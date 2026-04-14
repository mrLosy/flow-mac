import Foundation
import AVFoundation
import CoreAudio
import os.lock

/// Audio capture engine using AVAudioEngine with proper 16kHz PCM mono format for Whisper
class AudioEngine: NSObject, ObservableObject, AudioCaptureServiceProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0

    private let audioEngine = AVAudioEngine()
    private var audioBuffer: Data = Data()
    private let bufferSize: UInt32 = 4096
    private let targetSampleRate: Double = 16000.0 // Whisper optimal sample rate
    private var converter: AVAudioConverter?
    private var lastAppliedDeviceID: String = ""

    /// Atomic flag checked in the always-on tap callback
    private var capturing = false
    private let captureLock = NSLock()

    var onAudioBuffer: ((Data) -> Void)?
    weak var audioLevelDelegate: AudioLevelDelegate?

    /// Accumulated audio data for the current recording session
    private var recordedAudioData: Data = Data()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        installPermanentTap()
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

    /// Install tap and start engine once; never tear down during normal operation
    private func installPermanentTap() {
        applySelectedAudioDeviceIfNeeded()

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            NSLog("[FlowMac] Input format sampleRate is 0 at init — will retry on first recording")
            return
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!

        setupConverter(inputFormat: inputFormat)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.captureLock.lock()
            let isCapturing = self.capturing
            self.captureLock.unlock()

            if isCapturing {
                self.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: targetFormat)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            NSLog("[FlowMac] Audio engine started with permanent tap")
        } catch {
            NSLog("[FlowMac] Failed to start audio engine: \(error)")
        }
    }

    private func setupConverter(inputFormat: AVAudioFormat) {
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!

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
        }

        captureLock.lock()
        recordedAudioData = Data()
        capturing = true
        captureLock.unlock()

        DispatchQueue.main.async {
            self.isRecording = true
        }
        NSLog("[FlowMac] Audio recording started at 16kHz PCM mono")
        return nil
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
            DispatchQueue.main.async { [weak self] in
                self?.onAudioBuffer?(data)
            }
        }
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // If no conversion needed, extract data directly
        if buffer.format.sampleRate == targetSampleRate && buffer.format.channelCount == 1 {
            return buffer
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
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Calculate RMS
        let sum = samples.map { $0 * $0 }.reduce(0, +)
        let rms = sqrt(sum / Float(frameLength))

        // Normalize with logarithmic scaling for better visualization
        let db = 20 * log10(max(rms, 0.00001))
        let normalizedLevel = min(max((db + 60) / 60, 0), 1) // Map -60dB to 0dB range

        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalizedLevel
            self?.audioLevelDelegate?.audioLevelDidChange(normalizedLevel)
        }
    }

    // MARK: - Device Management

    /// Set the audio engine's input device based on user selection (skips if unchanged)
    private func applySelectedAudioDeviceIfNeeded() {
        let deviceIDString = UserDefaults.standard.string(forKey: "selectedAudioDevice") ?? "default"

        guard deviceIDString != lastAppliedDeviceID else { return }
        lastAppliedDeviceID = deviceIDString

        guard deviceIDString != "default", let deviceID = AudioDeviceID(deviceIDString) else { return }

        let inputNode = audioEngine.inputNode
        let inputUnit = inputNode.audioUnit!
        var selectedDevice = deviceID
        let status = AudioUnitSetProperty(inputUnit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &selectedDevice,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        if status == noErr {
            NSLog("[FlowMac] Set audio input device to \(deviceID)")
        } else {
            NSLog("[FlowMac] Failed to set audio device \(deviceID), status=\(status) — using default")
        }
    }

    @objc private func handleConfigurationChange(_ notification: Notification) {
        NSLog("[FlowMac] Audio engine configuration changed (device plugged/unplugged)")
        lastAppliedDeviceID = ""
        converter = nil
        // Engine auto-stops on config change; reinstall everything
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
