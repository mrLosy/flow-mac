import Foundation
import AVFoundation
import CoreAudio
import os.lock

/// CoreAudio device lookup by UID.
///
/// `AudioDeviceID` is a runtime handle: CoreAudio hands out a fresh one every time a
/// device reconnects, so it must never be persisted. The device UID is stable across
/// reconnects and reboots, and is what we store in UserDefaults instead.
enum AudioDeviceLookup {
    static let selectionKey = "selectedAudioDevice"
    static let systemDefault = "default"

    /// Stored selection, migrating the legacy numeric `AudioDeviceID` form to the system
    /// default — an old numeric value refers to whatever device happens to hold that id
    /// now, which is worse than no selection at all.
    static func selectedDeviceUID() -> String {
        let stored = UserDefaults.standard.string(forKey: selectionKey) ?? systemDefault
        guard stored != systemDefault else { return systemDefault }
        guard stored.allSatisfy(\.isNumber) else { return stored }

        UserDefaults.standard.set(systemDefault, forKey: selectionKey)
        NSLog("[FlowMac] Migrated legacy numeric input-device selection '\(stored)' to system default")
        return systemDefault
    }

    /// Stable UID of a device, or nil if it does not expose one.
    static func uid(of deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid) == noErr else { return nil }
        return uid as String
    }

    /// Current `AudioDeviceID` for a UID, or nil if that device is not connected.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    /// The device's actual capture format. AVAudioEngine can misreport this for devices
    /// whose input and output rates differ (Bluetooth headsets); CoreAudio does not.
    static func inputFormat(of deviceID: AudioDeviceID) -> AudioStreamBasicDescription? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &asbd) == noErr,
              asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else { return nil }
        return asbd
    }

    /// Whether the device still exists and exposes input streams.
    static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: 0
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr && size > 0
    }
}

/// Audio capture engine using AVAudioEngine with proper 16kHz PCM mono format for Whisper
class AudioEngine: NSObject, ObservableObject, AudioCaptureServiceProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    private var audioEngine = AVAudioEngine()
    private let bufferSize: UInt32 = 4096
    private let targetSampleRate: Double = 16000.0 // Whisper optimal sample rate
    private lazy var targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var lastAppliedDeviceID: String = ""

    /// Bluetooth input devices report an invalid format for a few hundred ms after
    /// connecting; bounded retries let the engine recover instead of staying dead.
    private var installRetryCount = 0
    private let maxInstallRetries = 10

    /// Atomic flag checked in the always-on tap callback
    private var capturing = false
    private let captureLock = NSLock()

    /// Timestamp of the last buffer the tap delivered (any source), guarded by captureLock.
    /// Used by the record-start watchdog to detect a running-but-dead engine.
    private var lastTapBufferTime: CFAbsoluteTime = 0
    /// How long after capture start to confirm buffers are actually flowing.
    private let bufferWatchdogDelay: CFAbsoluteTime = 0.4

    /// Coalesces overlapping device-change triggers into a single reinstall (main-thread only).
    private var reconfigurePending = false
    private let reconfigureDebounce: TimeInterval = 0.15

    /// Starting the engine emits AVAudioEngineConfigurationChange itself. Without a
    /// suppression window each reinstall schedules the next one and the engine loops
    /// forever, stopping and starting several times per second.
    private var lastReinstallTime: CFAbsoluteTime = 0
    private let reinstallSuppressionWindow: CFAbsoluteTime = 0.75

    /// CoreAudio listener block for default-input-device changes; removed in deinit.
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?

    /// Throttle audioLevel main-thread dispatches to ~20 FPS — 60/sec contends with BT output stream
    private var lastLevelPublishTime: CFAbsoluteTime = 0
    private let levelPublishInterval: CFAbsoluteTime = 1.0 / 20.0
    var onAudioBuffer: ((Data) -> Void)?
    weak var audioLevelDelegate: AudioLevelDelegate?

    /// Accumulated audio data for the current recording session
    private var recordedAudioData: Data = Data()

    override init() {
        super.init()
        observeConfigurationChange()
        installDefaultInputListener()
        installPermanentTap()
    }

    private func observeConfigurationChange() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
    }

    deinit {
        removeDefaultInputListener()
    }

    /// Request microphone permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Engine & Tap Lifecycle (one-time setup)

    /// Discard the current engine and build a fresh one.
    ///
    /// Reinstalling a tap happens exactly when the graph is least trustworthy: a device
    /// switch, a wake, a dead tap. Stop/reset leaves the old engine's cached device
    /// binding and node formats in place; a new instance resolves both from scratch.
    private func rebuildEngine() {
        NotificationCenter.default.removeObserver(
            self, name: .AVAudioEngineConfigurationChange, object: audioEngine
        )
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine = AVAudioEngine()
        // The fresh engine is bound to the system default, whatever we applied before.
        lastAppliedDeviceID = ""
        observeConfigurationChange()
    }

    /// Make the input node emit the format the microphone actually captures.
    ///
    /// On a device whose input and output rates differ — AirPods capture at 24 kHz while
    /// playing at 48 kHz — AVAudioEngine reports the *output* rate on the input node, so
    /// the tap goes on at 48 kHz while the graph initializes the hardware at 24 kHz and
    /// `start()` fails with -10868 ("formats don't match"), forever. CoreAudio reports the
    /// capture format correctly, so we take it from the device and write it onto the
    /// AUHAL's output scope, which is what the node and the tap read back.
    private func alignInputNodeToHardware(_ inputNode: AVAudioInputNode) {
        guard let deviceID = resolvedInputDevice(),
              let hwFormat = AudioDeviceLookup.inputFormat(of: deviceID) else { return }
        let nodeRate = inputNode.outputFormat(forBus: 0).sampleRate
        guard nodeRate != hwFormat.mSampleRate else { return }
        guard let inputUnit = inputNode.audioUnit else { return }

        var asbd = hwFormat
        let status = AudioUnitSetProperty(
            inputUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1, // input element of the AUHAL
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        DebugLog.log("AUD. realign \(nodeRate) -> \(hwFormat.mSampleRate) Hz status=\(status) now=\(inputNode.outputFormat(forBus: 0).sampleRate)")
    }

    /// Install tap and start engine once; never tear down during normal operation
    private func installPermanentTap() {
        rebuildEngine()
        _ = applySelectedAudioDeviceIfNeeded()

        let inputNode = audioEngine.inputNode
        alignInputNodeToHardware(inputNode)
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // installTap raises unless both are non-zero. A device mid-switch, or a default
        // input with no input streams, reports zero channels at a valid sample rate.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            scheduleInstallRetry(
                reason: "input format not ready (sampleRate \(inputFormat.sampleRate), channels \(inputFormat.channelCount))"
            )
            return
        }

        setupConverter(inputFormat: inputFormat)

        let targetFormat = self.targetFormat
        // format: nil means "whatever this bus actually outputs". Pinning a format here
        // makes installTap assert that it equals the hardware format, and the value we
        // just read goes stale the moment the device switches or the machine wakes —
        // which is exactly when this runs. The buffer carries its own format instead.
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.captureLock.lock()
            self.lastTapBufferTime = CFAbsoluteTimeGetCurrent()
            let isCapturing = self.capturing
            self.captureLock.unlock()

            if isCapturing {
                self.processAudioBuffer(buffer, inputFormat: buffer.format, targetFormat: targetFormat)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            installRetryCount = 0
            lastReinstallTime = CFAbsoluteTimeGetCurrent()
            NSLog("[FlowMac] Audio engine started with permanent tap")
        } catch {
            lastReinstallTime = CFAbsoluteTimeGetCurrent()
            NSLog("[FlowMac] Failed to start audio engine: \(error)")
            scheduleInstallRetry(reason: "engine start failed: \(error.localizedDescription)")
        }
    }

    /// Retry installing the tap shortly after a failed attempt. Without this, a single
    /// early return on an invalid format (common right after a Bluetooth device connects)
    /// leaves the engine permanently stopped until the next manual recording attempt.
    /// Delay grows mildly so a slow Bluetooth HFP settle is still caught within the budget.
    private func scheduleInstallRetry(reason: String) {
        guard installRetryCount < maxInstallRetries else {
            NSLog("[FlowMac] Audio engine reinstall gave up after \(maxInstallRetries) retries (\(reason))")
            installRetryCount = 0
            return
        }
        installRetryCount += 1
        let delay = min(0.3 + 0.15 * Double(installRetryCount), 1.5)
        NSLog("[FlowMac] Audio engine reinstall retry \(installRetryCount)/\(maxInstallRetries) in \(delay)s: \(reason)")
        // Force device re-resolution on retry — the new default device may have just settled.
        lastAppliedDeviceID = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.installPermanentTap()
        }
    }

    private func setupConverter(inputFormat: AVAudioFormat) {
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            if converter == nil {
                NSLog("[FlowMac] Failed to create audio converter from \(inputFormat) to \(targetFormat)")
            }
        } else {
            converter = nil
        }
    }

    // MARK: - Recording (flip the flag, no HAL changes)

    /// Start recording audio with 16kHz PCM mono format
    func startRecording() {
        _ = startRecordingSafe()
    }

    /// Start recording, returning an error message on failure or nil on success
    func startRecordingSafe() -> String? {
        guard !isRecording else { return nil }

        // If engine isn't running (e.g. mic was unavailable at init), try again
        if !audioEngine.isRunning {
            installPermanentTap()
            guard audioEngine.isRunning else {
                return "Не удалось запустить аудио-движок"
            }
        } else if selectedInputDeviceChanged() {
            // The default input changed while the engine kept running on the old binding
            // (a config-change can be missed or raced) — rebind to the current device.
            installPermanentTap()
        }

        captureLock.lock()
        recordedAudioData = Data()
        capturing = true
        let captureStart = CFAbsoluteTimeGetCurrent()
        captureLock.unlock()

        DispatchQueue.main.async {
            self.isRecording = true
        }
        armBufferFlowWatchdog(captureStart: captureStart)
        NSLog("[FlowMac] Audio recording started at 16kHz PCM mono")
        return nil
    }

    /// Detect a running-but-dead engine: if no buffer arrived shortly after capture
    /// started, the tap is attached to a stale graph — force a full reinstall while
    /// keeping `capturing` true so recording resumes on the healthy tap.
    private func armBufferFlowWatchdog(captureStart: CFAbsoluteTime) {
        DispatchQueue.main.asyncAfter(deadline: .now() + bufferWatchdogDelay) { [weak self] in
            guard let self, self.isRecording else { return }
            self.captureLock.lock()
            let lastBuffer = self.lastTapBufferTime
            self.captureLock.unlock()
            guard lastBuffer < captureStart else { return } // buffers flowing — healthy

            NSLog("[FlowMac] No audio buffers \(self.bufferWatchdogDelay)s after record start — forcing engine reinstall")
            self.lastAppliedDeviceID = ""
            self.converter = nil
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
            }
            self.installPermanentTap()
        }
    }

    /// Stop recording audio and return accumulated data as WAV
    func stopRecording() -> Data? {
        guard isRecording else { return nil }

        captureLock.lock()
        capturing = false
        let capturedData = recordedAudioData
        recordedAudioData = Data()
        captureLock.unlock()

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }

        NSLog("[FlowMac] Audio recording stopped, captured \(capturedData.count) bytes")

        let wavData = createWAVFile(from: capturedData)

        return wavData
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        // Calculate audio level from the buffer
        calculateAudioLevel(buffer)

        // Convert buffer to target format (16kHz, mono, Int16)
        if let convertedBuffer = convertBuffer(buffer, to: targetFormat) {
            // Extract Int16 data
            let channelData = convertedBuffer.int16ChannelData![0]
            let frameLength = Int(convertedBuffer.frameLength)
            let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Int16>.size)

            self.captureLock.lock()
            self.recordedAudioData.append(data)
            self.captureLock.unlock()

            // Stream buffer for real-time processing if needed
            if let onAudioBuffer = self.onAudioBuffer {
                DispatchQueue.main.async {
                    onAudioBuffer(data)
                }
            }
        }
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // If no conversion needed, extract data directly
        if buffer.format.sampleRate == targetSampleRate && buffer.format.channelCount == 1 {
            return buffer
        }

        // The tap is not pinned to a format, so the hardware can start delivering a
        // different one after a device switch or a wake — rebuild the converter to match.
        if converter?.inputFormat != buffer.format {
            setupConverter(inputFormat: buffer.format)
        }

        guard let converter = self.converter else { return nil }

        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            NSLog("[FlowMac] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Normalize with logarithmic scaling for better visualization
        let db = 20 * log10(max(rms, 0.00001))
        let normalizedLevel = min(max((db + 60) / 60, 0), 1) // Map -60dB to 0dB range

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelPublishTime >= levelPublishInterval else { return }
        lastLevelPublishTime = now

        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalizedLevel
            self?.audioLevelDelegate?.audioLevelDidChange(normalizedLevel)
        }
    }

    // MARK: - Device Management

    /// Device to bind the input unit to: the explicit selection while it is still
    /// connected, otherwise the current system default. A selection whose device is gone
    /// is cleared, so Settings stops offering something that no longer exists and every
    /// reconfigure stops failing with -10851.
    private func resolvedInputDevice() -> AudioDeviceID? {
        let selection = AudioDeviceLookup.selectedDeviceUID()
        if selection != AudioDeviceLookup.systemDefault {
            if let deviceID = AudioDeviceLookup.deviceID(forUID: selection),
               AudioDeviceLookup.hasInputStreams(deviceID) {
                return deviceID
            }
            NSLog("[FlowMac] Selected input device '\(selection)' is not connected — using system default")
            UserDefaults.standard.set(AudioDeviceLookup.systemDefault, forKey: AudioDeviceLookup.selectionKey)
        }
        return systemDefaultInputDevice()
    }

    /// Whether the resolved input device differs from the one the engine is bound to.
    /// Split out from `applySelectedAudioDeviceIfNeeded` so callers can stop the engine
    /// before rebinding — rebinding a running input unit is what raises.
    private func selectedInputDeviceChanged() -> Bool {
        guard let deviceID = resolvedInputDevice() else { return false }
        return String(deviceID) != lastAppliedDeviceID
    }

    /// Bind the engine's input unit to the desired device (explicit selection, or the
    /// current system default). On macOS AVAudioEngine does NOT automatically follow the
    /// system default input device when it changes — e.g. when headphones connect — so for
    /// "default" we resolve and apply the current default device explicitly. Returns true
    /// if the binding actually changed (so the caller can reinstall the tap), false if the
    /// resolved device is unchanged or could not be applied.
    @discardableResult
    private func applySelectedAudioDeviceIfNeeded() -> Bool {
        guard let deviceID = resolvedInputDevice() else {
            NSLog("[FlowMac] No input device to apply")
            return false
        }

        // Compare resolved IDs, not the "default" string — the underlying device changes.
        let resolvedKey = String(deviceID)
        guard resolvedKey != lastAppliedDeviceID else { return false }

        let inputNode = audioEngine.inputNode
        guard let inputUnit = inputNode.audioUnit else {
            NSLog("[FlowMac] Input node has no audio unit — cannot set device")
            return false
        }
        var selectedDevice = deviceID
        let status = AudioUnitSetProperty(inputUnit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &selectedDevice,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            // Deliberately leave lastAppliedDeviceID alone: recording a device we failed
            // to bind would hide the failure and keep the unit on a stale device.
            NSLog("[FlowMac] Failed to set audio device \(deviceID), status=\(status)")
            return false
        }
        lastAppliedDeviceID = resolvedKey
        NSLog("[FlowMac] Set audio input device to \(deviceID)")
        return true
    }

    /// Current system default input device, or nil if none is available
    private func systemDefaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Listen for system-default-input-device changes. This is the canonical CoreAudio
    /// signal for "headphones connected / default mic switched" and fires reliably even
    /// when the AVAudioEngineConfigurationChange notification is missed. The callback is
    /// delivered on the main queue and coalesced via scheduleReconfigure.
    private func installDefaultInputListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // Only follow the default when the user hasn't pinned an explicit device.
            guard AudioDeviceLookup.selectedDeviceUID() == AudioDeviceLookup.systemDefault else { return }
            self.scheduleReconfigure(reason: "default input device changed")
        }
        defaultInputListenerBlock = block
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block
        )
        if status != noErr {
            NSLog("[FlowMac] Failed to add default-input listener, status=\(status)")
        }
    }

    private func removeDefaultInputListener() {
        guard let block = defaultInputListenerBlock else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block
        )
        defaultInputListenerBlock = nil
    }

    /// Coalesce all device-change triggers (config-change notification, default-input
    /// listener) onto the main thread so engine-graph reinstalls never interleave.
    /// Without this, the off-main config-change handler raced the main-queue retry and
    /// could leave the engine running-but-dead (tap attached to a stale graph).
    private func scheduleReconfigure(reason: String) {
        if Thread.isMainThread {
            scheduleReconfigureOnMain(reason: reason)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleReconfigureOnMain(reason: reason)
            }
        }
    }

    private func scheduleReconfigureOnMain(reason: String) {
        guard !reconfigurePending else { return }
        guard CFAbsoluteTimeGetCurrent() - lastReinstallTime >= reinstallSuppressionWindow else {
            NSLog("[FlowMac] Reconfigure ignored — emitted by our own reinstall (\(reason))")
            return
        }
        reconfigurePending = true
        NSLog("[FlowMac] Reconfigure scheduled: \(reason)")
        DispatchQueue.main.asyncAfter(deadline: .now() + reconfigureDebounce) { [weak self] in
            guard let self else { return }
            self.reconfigurePending = false
            self.lastAppliedDeviceID = ""
            self.converter = nil
            self.installPermanentTap()
        }
    }

    @objc private func handleConfigurationChange(_ notification: Notification) {
        NSLog("[FlowMac] Audio engine configuration changed (device plugged/unplugged)")
        scheduleReconfigure(reason: "AVAudioEngineConfigurationChange")
    }

    /// Called after system wake/screen unlock. AVAudioEngine can keep `isRunning == true`
    /// while the underlying HAL device has gone away, so we always reinstall.
    /// Safe to call while a recording session is active — the capture flag is preserved.
    func restartIfNeeded() {
        guard !isRecording else {
            NSLog("[FlowMac] Skipping audio restart — recording in progress")
            return
        }
        lastAppliedDeviceID = ""
        converter = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        installPermanentTap()
    }

    // MARK: - WAV

    /// Create WAV file header and data for Whisper API
    private func createWAVFile(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let totalSize = dataSize + 36

        var wavData = Data()

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: totalSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // Subchunk1Size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // AudioFormat (PCM)
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)

        return wavData
    }
}
