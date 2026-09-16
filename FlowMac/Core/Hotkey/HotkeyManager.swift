import Foundation
import Carbon
import CoreGraphics
import Combine
import AppKit

/// Manages two global hotkeys via CGEventTap:
/// - Toggle: press to start, press again to stop
/// - Push-to-Talk: hold to record, release to stop
class HotkeyManager: NSObject, ObservableObject, HotkeyManagerProtocol {
    @Published var isRecording = false

    private(set) var audioEngine: AudioEngine
    private(set) var recognitionService: RecognitionService
    private(set) var textInjector: TextInjector
    private(set) var recordingOverlay: RecordingOverlayWindow

    // CGEventTap
    var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Accessibility permission re-check timer
    private var accessibilityCheckTimer: Timer?

    // Three hotkey configs
    var toggleHotkey = HotkeyConfig(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey))
    var pttHotkey = HotkeyConfig(keyCode: 2, modifiers: UInt32(cmdKey | shiftKey))
    var expressHotkey = HotkeyConfig(keyCode: 0, modifiers: 0) // Disabled by default

    // PTT state
    var pttActive = false

    // Express mode state
    private var expressActive = false
    private var expressTimer: Timer?
    private let expressMaxDuration: TimeInterval = 300 // 5 min safety limit

    /// True while the Settings shortcut recorder is capturing a new combo. The event tap
    /// must stay installed (removing it mid-capture races with the recorder's monitors),
    /// but it must not act on or swallow anything: otherwise pressing the combo you are
    /// about to assign fires the *current* hotkey, and a matching key is consumed before
    /// the recorder ever sees it.
    var isCapturingShortcut = false

    // Modifier-only detection state
    var toggleModOnlyPending = false
    var toggleModOnlyKeyWasPressed = false
    var pttModOnlyPending = false
    var pttModOnlyKeyWasPressed = false

    // NSEvent fallback monitors (used when CGEventTap unavailable)
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var hasPromptedAccessibility = false

    // Focus restoration
    private var previousApp: NSRunningApplication?

    // Metrics tracking
    private var recordingStartTime: Date?

    weak var hotkeyDelegate: HotkeyDelegate?
    static var sharedManager: HotkeyManager?

    init(
        audioEngine: AudioEngine,
        recognitionService: RecognitionService,
        textInjector: TextInjector,
        recordingOverlay: RecordingOverlayWindow
    ) {
        self.audioEngine = audioEngine
        self.recognitionService = recognitionService
        self.textInjector = textInjector
        self.recordingOverlay = recordingOverlay
        super.init()

        HotkeyManager.sharedManager = self
        loadSettings()
        setupHotkey()
        setupNotificationObserver()
    }

    // MARK: - Notification Observers

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleNotification),
            name: .toggleRecording, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHotkeyChangeNotification(_:)),
            name: .hotkeyDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRetryNotification(_:)),
            name: .retryTranscription, object: nil
        )

        // System sleep/wake — CGEventTap can be silently invalidated across these
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self, selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(handleSystemWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(handleSystemWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil
        )

        // Screen lock/unlock (no sleep) — only delivered via distributed center
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleSystemWake),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil
        )
    }

    @objc private func handleSystemWake() {
        DebugLog.log("WAKE. system wake/unlock — restoring hotkey + audio")
        // Tap can be present but disabled, or completely invalidated. Cheapest
        // fix is to fully recreate it; setupHotkey() also handles the fallback path.
        setupHotkey()
        audioEngine.restartIfNeeded()
    }

    @objc private func handleToggleNotification() { toggleRecording() }

    @objc private func handleRetryNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let entryID = userInfo["entryID"] as? UUID else { return }
        retryTranscription(entryID: entryID)
    }

    @objc private func handleHotkeyChangeNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyCode = userInfo["keyCode"] as? UInt16,
              let modifiersRaw = userInfo["modifiers"] as? UInt else { return }

        let modeRaw = userInfo["mode"] as? String ?? RecordingMode.toggle.rawValue
        let mode = RecordingMode(rawValue: modeRaw) ?? .toggle
        let modifiers = NSEvent.ModifierFlags(rawValue: modifiersRaw)
        let modifierSides = userInfo["modifierSides"] as? UInt32 ?? 0
        updateHotkey(mode: mode, keyCode: keyCode, modifiers: modifiers, modifierSides: modifierSides)
    }

    // MARK: - Mode Enable Flags

    /// User-controlled enable toggles from Shortcuts settings. Defaults match
    /// SettingsView's @State initializers: toggle/PTT default on, express off.
    var isToggleEnabled: Bool {
        UserDefaults.standard.object(forKey: "toggleModeEnabled") as? Bool ?? true
    }
    var isPTTEnabled: Bool {
        UserDefaults.standard.object(forKey: "pttModeEnabled") as? Bool ?? true
    }
    var isExpressEnabled: Bool {
        UserDefaults.standard.bool(forKey: "expressModeEnabled")
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        // Migration from old single-hotkey keys
        if UserDefaults.standard.object(forKey: "toggleHotkeyKeyCode") == nil,
           let oldKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? UInt32 {
            let oldMods = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt32 ?? UInt32(cmdKey | shiftKey)
            UserDefaults.standard.set(oldKeyCode, forKey: "toggleHotkeyKeyCode")
            UserDefaults.standard.set(oldMods, forKey: "toggleHotkeyModifiers")
            UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
            UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
        }

        if let kc = UserDefaults.standard.object(forKey: "toggleHotkeyKeyCode") as? UInt32 { toggleHotkey.keyCode = kc }
        if let m = UserDefaults.standard.object(forKey: "toggleHotkeyModifiers") as? UInt32 { toggleHotkey.modifiers = m }
        if let s = UserDefaults.standard.object(forKey: "toggleHotkeyModifierSides") as? UInt32 { toggleHotkey.modifierSides = s }
        if let kc = UserDefaults.standard.object(forKey: "pttHotkeyKeyCode") as? UInt32 { pttHotkey.keyCode = kc }
        if let m = UserDefaults.standard.object(forKey: "pttHotkeyModifiers") as? UInt32 { pttHotkey.modifiers = m }
        if let s = UserDefaults.standard.object(forKey: "pttHotkeyModifierSides") as? UInt32 { pttHotkey.modifierSides = s }
        if let kc = UserDefaults.standard.object(forKey: "expressHotkeyKeyCode") as? UInt32 { expressHotkey.keyCode = kc }
        if let m = UserDefaults.standard.object(forKey: "expressHotkeyModifiers") as? UInt32 { expressHotkey.modifiers = m }
        if let s = UserDefaults.standard.object(forKey: "expressHotkeyModifierSides") as? UInt32 { expressHotkey.modifierSides = s }
    }

    private func saveHotkey(_ config: HotkeyConfig, mode: RecordingMode) {
        let prefix: String
        switch mode {
        case .toggle: prefix = "toggleHotkey"
        case .pushToTalk: prefix = "pttHotkey"
        case .express: prefix = "expressHotkey"
        }
        UserDefaults.standard.set(config.keyCode, forKey: "\(prefix)KeyCode")
        UserDefaults.standard.set(config.modifiers, forKey: "\(prefix)Modifiers")
        UserDefaults.standard.set(config.modifierSides, forKey: "\(prefix)ModifierSides")
    }

    // MARK: - Hotkey Setup

    private func setupHotkey() {
        let shouldPrompt = !hasPromptedAccessibility
        hasPromptedAccessibility = true

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        DebugLog.log("HK1. setupHotkey: trusted=\(trusted), prompted=\(shouldPrompt)")

        if trusted {
            accessibilityCheckTimer?.invalidate()
            accessibilityCheckTimer = nil
            removeNSEventFallback()
            setupCGEventTap()
        } else {
            NSLog("[FlowMac] Accessibility not granted — installing NSEvent fallback monitors")
            setupNSEventFallback()
            startAccessibilityCheckTimer()
        }
    }

    private func startAccessibilityCheckTimer() {
        guard accessibilityCheckTimer == nil else { return }
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            if AXIsProcessTrustedWithOptions(opts) {
                DispatchQueue.main.async {
                    self?.accessibilityCheckTimer?.invalidate()
                    self?.accessibilityCheckTimer = nil
                    self?.setupHotkey()
                }
            }
        }
    }

    private func setupCGEventTap() {
        // Clean up any existing tap first
        if let oldTap = eventTap {
            CGEvent.tapEnable(tap: oldTap, enable: false)
        }
        if let oldSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), oldSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: eventMask,
            callback: cgEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            DebugLog.log("HK2. FAILED to create CGEventTap — fallback to NSEvent")
            setupNSEventFallback()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        DebugLog.log("HK3. CGEventTap OK — toggle=\(HotkeyManager.hotkeyDisplayString(toggleHotkey)), PTT=\(HotkeyManager.hotkeyDisplayString(pttHotkey))")
    }

    // MARK: - NSEvent Fallback

    private func setupNSEventFallback() {
        guard globalKeyDownMonitor == nil else { return }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSKeyEvent(event, isDown: true)
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleNSKeyEvent(event, isDown: false)
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsEvent(event)
        }
        NSLog("[FlowMac] NSEvent global monitors installed as fallback")
    }

    private func removeNSEventFallback() {
        for monitor in [globalKeyDownMonitor, globalKeyUpMonitor, globalFlagsMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalKeyDownMonitor = nil
        globalKeyUpMonitor = nil
        globalFlagsMonitor = nil
    }

    func startMonitoring() {}

    func stopMonitoring() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
        removeNSEventFallback()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Recording Control

    @objc func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    func startRecording(showOverlay: Bool = true) {
        DebugLog.log("REC1. startRecording called, isRecording=\(isRecording)")
        guard !isRecording else { return }

        // Pre-flight: проверяем всё до начала записи
        if let error = NotificationService.shared.preflightCheck() {
            DebugLog.log("REC2. PREFLIGHT FAILED: \(error)")
            NotificationService.shared.notifyError(error)
            return
        }
        DebugLog.log("REC3. preflight OK")

        // Save the frontmost app for focus restoration after injection
        previousApp = NSWorkspace.shared.frontmostApplication
        NSLog("[FlowMac] Saved previous app: \(previousApp?.localizedName ?? "none")")
        audioEngine.requestPermission { [weak self] granted in
            guard let self else { return }
            NSLog("[FlowMac] Mic permission callback: granted=\(granted)")
            guard granted else {
                NotificationService.shared.notifyError(.microphoneDenied)
                return
            }
            Task { @MainActor in
                self.isRecording = true
                // Clear any stale error from a previous failed attempt so it
                // doesn't linger in the menu while a new recording is underway.
                self.recognitionService.errorMessage = nil
                if showOverlay { self.recordingOverlay.show() }
                self.recordingStartTime = Date()
                MicVolumeManager.shared.boostIfEnabled()

                if let startError = self.audioEngine.startRecordingSafe() {
                    NSLog("[FlowMac] AudioEngine start failed: \(startError)")
                    NotificationService.shared.notifyRecordingError(startError)
                    self.isRecording = false
                    if showOverlay { self.recordingOverlay.hide() }
                    MicVolumeManager.shared.restoreIfNeeded()
                    return
                }

                self.hotkeyDelegate?.hotkeyDidTrigger()
                self.playStartSound()
                NSLog("[FlowMac] Recording started, overlay=\(showOverlay)")
            }
        }
    }

    func stopRecording() {
        NSLog("[FlowMac] stopRecording called, isRecording=\(isRecording)")
        guard isRecording else { return }
        isRecording = false
        expressTimer?.invalidate()
        expressTimer = nil
        Task { @MainActor in recordingOverlay.hide() }
        hotkeyDelegate?.hotkeyDidRelease()

        guard let audioData = audioEngine.stopRecording() else {
            NSLog("[FlowMac] No audio data captured")
            NotificationService.shared.notifyRecordingError("Не удалось записать аудио — данные пусты")
            MicVolumeManager.shared.restoreIfNeeded()
            return
        }
        MicVolumeManager.shared.restoreIfNeeded()
        playStopSound()

        // Validate audio before sending to API
        if case .failure(let error) = AudioValidator.validate(audioData) {
            switch error {
            case .silentRecording:
                NotificationService.shared.notifyNoSpeech()
            default:
                NotificationService.shared.notifyRecordingError(error.localizedDescription)
            }
            return
        }

        // Check quota before sending to API (backend plans only)
        let estimatedSeconds = Int(ceil(recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0))
        if !QuotaService.shared.canTranscribe(audioDurationSeconds: max(1, estimatedSeconds)) {
            NotificationService.shared.notifyQuotaExhausted()
            return
        }

        // Save audio to disk before transcription so we can retry on failure
        let entryID = UUID()
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let audioFileName = AudioStorageService.shared.save(audioData: audioData, id: entryID)

        // Register the entry before the request goes out. If the process dies
        // mid-flight the audio is then referenced from history (so the orphan
        // sweep on next launch keeps it) and shows up as retryable.
        TranscriptionHistoryService.shared.add(PersistentTranscriptionEntry(
            failedWithID: entryID,
            duration: duration,
            provider: TranscriptionProvider.current.displayName,
            audioFileName: audioFileName,
            errorMessage: "Транскрипция прервана"
        ))

        recognitionService.transcribe(audioData: audioData) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    let cleanedText = TranscriptionCleaner.clean(text)
                    guard !cleanedText.isEmpty else {
                        NotificationService.shared.notifyNoSpeech()
                        TranscriptionHistoryService.shared.delete(id: entryID)
                        return
                    }
                    // Consume quota only when transcription produced usable text
                    QuotaService.shared.consumeSeconds(max(1, estimatedSeconds))
                    // The words are in hand — persist them now, before correction
                    // and injection get a chance to fail or crash.
                    TranscriptionHistoryService.shared.markAsSucceeded(id: entryID, text: cleanedText)
                    // Semantic correction (optional LLM post-processing)
                    let category = AppCategory.detect(bundleIdentifier: self?.previousApp?.bundleIdentifier)
                    SemanticCorrectionService.shared.correct(text: cleanedText, category: category) { finalText in
                        // Restore focus to the original app before injecting text
                        self?.restoreFocus {
                            let result = self?.textInjector.insertText(finalText) ?? .failed(.insertionFailed)
                            switch result {
                            case .injected:
                                NSLog("[FlowMac] Text injected into focused field")
                                self?.recordSuccessMetrics(text: finalText)
                            case .copiedToClipboard:
                                NSLog("[FlowMac] No text field focused — copied to clipboard")
                                let accessibilityOK = AXIsProcessTrustedWithOptions(
                                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
                                )
                                if !accessibilityOK {
                                    NotificationService.shared.notifyAccessibilityHint()
                                } else {
                                    NotificationService.shared.notifyClipboard()
                                }
                                self?.recordSuccessMetrics(text: finalText)
                            case .failed(let error):
                                NSLog("[FlowMac] Text injection failed: \(error.localizedDescription)")
                                NotificationService.shared.notifyInjectionError(error.localizedDescription)
                            }
                            // Keep the corrected text in history even if injection failed —
                            // the user can still copy it from the menu.
                            TranscriptionHistoryService.shared.markAsSucceeded(id: entryID, text: finalText)
                            // Audio transcribed successfully — delete the saved file
                            if let fileName = audioFileName { AudioStorageService.shared.delete(fileName: fileName) }
                        }
                    }
                case .failure(let error):
                    NSLog("[FlowMac] Transcription error: \(error)")
                    NotificationService.shared.notifyTranscriptionError(error.localizedDescription)
                    self?.recordingStartTime = nil
                    TranscriptionHistoryService.shared.updateError(id: entryID, message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Update Hotkey

    func updateHotkey(mode: RecordingMode, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, modifierSides: UInt32 = 0) {
        var cgFlags: CGEventFlags = []
        if modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        if modifiers.contains(.shift) { cgFlags.insert(.maskShift) }
        if modifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
        if modifiers.contains(.control) { cgFlags.insert(.maskControl) }
        updateHotkey(mode: mode, keyCode: CGKeyCode(keyCode), modifiers: cgFlags, modifierSides: modifierSides)
    }

    func updateHotkey(mode: RecordingMode, keyCode: CGKeyCode, modifiers: CGEventFlags) {
        updateHotkey(mode: mode, keyCode: keyCode, modifiers: modifiers, modifierSides: 0)
    }

    func updateHotkey(mode: RecordingMode, keyCode: CGKeyCode, modifiers: CGEventFlags, modifierSides: UInt32) {
        var carbonMods: UInt32 = 0
        if modifiers.contains(.maskCommand) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.maskShift) { carbonMods |= UInt32(shiftKey) }
        if modifiers.contains(.maskAlternate) { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.maskControl) { carbonMods |= UInt32(controlKey) }

        let config = HotkeyConfig(keyCode: UInt32(keyCode), modifiers: carbonMods, modifierSides: modifierSides)
        switch mode {
        case .toggle: toggleHotkey = config
        case .pushToTalk: pttHotkey = config
        case .express: expressHotkey = config
        }
        saveHotkey(config, mode: mode)
        stopMonitoring()
        setupHotkey()
    }

    func getCurrentHotkey(for mode: RecordingMode) -> (keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let config: HotkeyConfig
        switch mode {
        case .toggle: config = toggleHotkey
        case .pushToTalk: config = pttHotkey
        case .express: config = expressHotkey
        }
        var cgMods: CGEventFlags = []
        if (config.modifiers & UInt32(cmdKey)) != 0 { cgMods.insert(.maskCommand) }
        if (config.modifiers & UInt32(shiftKey)) != 0 { cgMods.insert(.maskShift) }
        if (config.modifiers & UInt32(optionKey)) != 0 { cgMods.insert(.maskAlternate) }
        if (config.modifiers & UInt32(controlKey)) != 0 { cgMods.insert(.maskControl) }
        return (CGKeyCode(config.keyCode), cgMods)
    }

    static func hotkeyDisplayString(_ config: HotkeyConfig) -> String {
        var parts: [String] = []
        if (config.modifiers & UInt32(cmdKey)) != 0 {
            parts.append("⌘" + sideSuffix(config.side(for: ModifierSideSlot.cmd)))
        }
        if (config.modifiers & UInt32(shiftKey)) != 0 {
            parts.append("⇧" + sideSuffix(config.side(for: ModifierSideSlot.shift)))
        }
        if (config.modifiers & UInt32(optionKey)) != 0 {
            parts.append("⌥" + sideSuffix(config.side(for: ModifierSideSlot.option)))
        }
        if (config.modifiers & UInt32(controlKey)) != 0 {
            parts.append("⌃" + sideSuffix(config.side(for: ModifierSideSlot.control)))
        }

        let keyNames: [UInt32: String] = [
            49: "Space", 36: "↵", 51: "⌫", 53: "Esc",
            48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        if let name = keyNames[config.keyCode] { parts.append(name) }
        else if config.keyCode > 0 && config.keyCode <= 25 {
            parts.append(String(Character(UnicodeScalar(config.keyCode + 65)!)))
        } else if config.keyCode > 25 { parts.append("Key\(config.keyCode)") }

        return parts.joined(separator: "+")
    }

    static func sideSuffix(_ side: ModifierSide) -> String {
        switch side {
        case .left: return "L"
        case .right: return "R"
        case .any: return ""
        }
    }

    // MARK: - Metrics

    private func recordSuccessMetrics(text: String) {
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        UsageMetricsService.shared.recordSession(duration: duration, text: text)
        recordingStartTime = nil
    }

    // MARK: - Retry

    func retryTranscription(entryID: UUID) {
        guard !recognitionService.isProcessing else {
            NSLog("[FlowMac] Retry skipped — transcription already in progress")
            return
        }
        guard let entry = TranscriptionHistoryService.shared.entry(withID: entryID),
              entry.status == .failed,
              let audioFileName = entry.audioFileName,
              let audioData = AudioStorageService.shared.load(fileName: audioFileName) else {
            NSLog("[FlowMac] Retry failed: entry not found or audio missing for %@", entryID.uuidString)
            return
        }

        NSLog("[FlowMac] Retrying transcription for entry %@", entryID.uuidString)

        recognitionService.transcribe(audioData: audioData) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    let cleanedText = TranscriptionCleaner.clean(text)
                    guard !cleanedText.isEmpty else {
                        TranscriptionHistoryService.shared.updateError(id: entryID, message: "Речь не обнаружена")
                        return
                    }
                    // A retry lands on the pasteboard rather than a focused field, so
                    // there is no target app to categorise — correct as general text.
                    SemanticCorrectionService.shared.correct(text: cleanedText, category: .general) { finalText in
                        TranscriptionHistoryService.shared.markAsSucceeded(id: entryID, text: finalText)
                        AudioStorageService.shared.delete(fileName: audioFileName)
                        UsageMetricsService.shared.recordSession(duration: entry.duration, text: finalText)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(finalText, forType: .string)
                        NotificationService.shared.notifyRetrySuccess()
                        NSLog("[FlowMac] Retry succeeded for entry %@", entryID.uuidString)
                    }
                case .failure(let error):
                    NSLog("[FlowMac] Retry failed for entry %@: %@", entryID.uuidString, error.localizedDescription)
                    TranscriptionHistoryService.shared.updateError(id: entryID, message: error.localizedDescription)
                    NotificationService.shared.notifyTranscriptionError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Express Mode

    func toggleExpressRecording() {
        if expressActive {
            expressActive = false
            stopRecording()
        } else {
            expressActive = true
            startRecording(showOverlay: false)
            // Safety timer: auto-stop after max duration
            expressTimer = Timer.scheduledTimer(withTimeInterval: expressMaxDuration, repeats: false) { [weak self] _ in
                guard let self, self.expressActive else { return }
                NSLog("[FlowMac] Express mode: auto-stop after \(self.expressMaxDuration)s")
                DispatchQueue.main.async { self.toggleExpressRecording() }
            }
        }
    }

    // MARK: - Focus Restoration

    private func restoreFocus(then action: @escaping () -> Void) {
        guard let app = previousApp, !app.isTerminated else {
            previousApp = nil
            action()
            return
        }
        NSLog("[FlowMac] Restoring focus to: \(app.localizedName ?? "unknown")")
        app.activate()
        previousApp = nil
        // Brief delay to let the target app become frontmost before injection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            action()
        }
    }

    // MARK: - Sound & Notifications

    private func playStartSound() {
        guard UserDefaults.standard.bool(forKey: "soundFeedbackEnabled") else { return }
        NSSound(named: "Ping")?.play()
    }

    private func playStopSound() {
        guard UserDefaults.standard.bool(forKey: "soundFeedbackEnabled") else { return }
        NSSound(named: "Glass")?.play()
    }


    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        HotkeyManager.sharedManager = nil
    }
}

// MARK: - CGEventTap Callback

private func cgEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handleCGEvent(event, type: type) ? nil : Unmanaged.passUnretained(event)
}
