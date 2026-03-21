import Foundation
import Carbon
import CoreGraphics
import Combine

/// Manages global hotkeys using Carbon RegisterEventHotKey and CGEventTap
class HotkeyManager: NSObject, ObservableObject, HotkeyManagerProtocol {
    @Published var isRecording = false
    
    private var audioEngine: AudioEngine
    private var recognitionService: RecognitionService
    private var textInjector: TextInjector
    private var recordingOverlay: RecordingOverlayWindow
    
    // Carbon hotkey references
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    // CGEventTap as fallback
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Default hotkey: Cmd + Shift + Space
    private var hotkeyKeyCode: UInt32 = 49  // Space key
    private var hotkeyModifiers: UInt32 = cmdKey | shiftKey // Cmd + Shift
    
    weak var hotkeyDelegate: HotkeyDelegate?
    
    // Callback reference for Carbon event handler
    private static var sharedManager: HotkeyManager?
    
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
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleNotification),
            name: .toggleRecording,
            object: nil
        )
    }
    
    @objc private func handleToggleNotification() {
        toggleRecording()
    }
    
    private func loadSettings() {
        // Load saved hotkey settings from UserDefaults
        if let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? UInt32 {
            hotkeyKeyCode = savedKeyCode
        }
        
        if let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt32 {
            hotkeyModifiers = savedModifiers
        } else {
            // Default: Cmd + Shift + Space
            hotkeyModifiers = cmdKey | shiftKey
            UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
            UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
        }
    }
    
    /// Set up global hotkey monitoring using Carbon
    private func setupHotkey() {
        // Check for accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("Accessibility permission required for global hotkeys")
            // Fall back to CGEventTap which also requires accessibility
            setupCGEventTap()
            return
        }
        
        registerCarbonHotkey()
    }
    
    /// Register hotkey using Carbon Event Manager
    private func registerCarbonHotkey() {
        // Create event type spec for hotkey events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        // Install event handler
        let handlerUPP = NewEventHandlerUPP { _, eventRef, _ -> OSStatus in
            guard HotkeyManager.sharedManager != nil else { return noErr }
            
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    HotkeyManager.sharedManager?.toggleRecording()
                }
            }
            
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        
        guard status == noErr else {
            print("Failed to install event handler: \(status)")
            setupCGEventTap()
            return
        }
        
        // Register the hotkey
        let hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("FLMC")), id: 1)
        
        let regStatus = RegisterEventHotKey(
            hotkeyKeyCode,
            hotkeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if regStatus == noErr {
            print("Registered hotkey: Cmd+Shift+Space (keyCode: \(hotkeyKeyCode), modifiers: \(hotkeyModifiers))")
        } else {
            print("Failed to register hotkey: \(regStatus)")
            setupCGEventTap()
        }
    }
    
    /// Fall back to CGEventTap for hotkey monitoring
    private func setupCGEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: cgEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        
        // Start monitoring in background thread
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            CFRunLoopRun()
        }
        
        print("CGEventTap hotkey monitoring started")
    }
    
    /// Start monitoring for global hotkey events
    func startMonitoring() {
        // Already started in setup
    }
    
    /// Stop monitoring hotkey events
    func stopMonitoring() {
        // Unregister Carbon hotkey
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        // Remove event handler
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        
        // Stop CGEventTap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    /// Check if hotkey is pressed
    func isHotkeyPressed(event: CGEvent) -> Bool {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Convert CGEventFlags to Carbon modifiers
        var carbonModifiers: UInt32 = 0
        if flags.contains(.maskCommand) { carbonModifiers |= cmdKey }
        if flags.contains(.maskShift) { carbonModifiers |= shiftKey }
        if flags.contains(.maskAlternate) { carbonModifiers |= optionKey }
        if flags.contains(.maskControl) { carbonModifiers |= controlKey }
        
        return keyCode == hotkeyKeyCode && carbonModifiers == hotkeyModifiers
    }
    
    /// Handle hotkey event from CGEventTap
    func handleCGEvent(_ event: CGEvent) -> Bool {
        guard isHotkeyPressed(event: event) else {
            return false // Event not handled
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecording()
        }
        hotkeyDelegate?.hotkeyDidTrigger()
        
        return true // Event handled
    }
    
    /// Toggle recording state
    @objc func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Start recording and transcription
    private func startRecording() {
        // Request microphone permission first
        audioEngine.requestPermission { [weak self] granted in
            guard let self = self else { return }
            
            guard granted else {
                self.showErrorNotification(message: "Microphone permission required")
                return
            }
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingOverlay.show()
                self.audioEngine.startRecording()
                self.hotkeyDelegate?.hotkeyDidTrigger()
                
                // Play start sound
                self.playStartSound()
            }
        }
    }
    
    /// Stop recording and process transcription
    private func stopRecording() {
        isRecording = false
        recordingOverlay.hide()
        hotkeyDelegate?.hotkeyDidRelease()
        
        guard let audioData = audioEngine.stopRecording() else {
            print("No audio data captured")
            return
        }
        
        // Play stop sound
        playStopSound()
        
        // Validate audio data size
        guard audioData.count > 100 else {
            showErrorNotification(message: "Audio too short, please try again")
            return
        }
        
        // Send to recognition service
        recognitionService.transcribe(audioData: audioData) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    guard !text.isEmpty else {
                        self?.showErrorNotification(message: "No speech detected")
                        return
                    }
                    self?.textInjector.insertText(text)
                case .failure(let error):
                    print("Transcription error: \(error)")
                    self?.showErrorNotification(error: error)
                }
            }
        }
    }
    
    /// Update hotkey configuration
    func updateHotkey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        // Convert CGKeyCode to Carbon key code
        hotkeyKeyCode = UInt32(keyCode)
        
        // Convert CGEventFlags to Carbon modifiers
        hotkeyModifiers = 0
        if modifiers.contains(.maskCommand) { hotkeyModifiers |= cmdKey }
        if modifiers.contains(.maskShift) { hotkeyModifiers |= shiftKey }
        if modifiers.contains(.maskAlternate) { hotkeyModifiers |= optionKey }
        if modifiers.contains(.maskControl) { hotkeyModifiers |= controlKey }
        
        // Save to UserDefaults
        UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        
        // Re-register hotkey
        stopMonitoring()
        setupHotkey()
    }
    
    /// Get current hotkey configuration
    func getCurrentHotkey() -> (keyCode: CGKeyCode, modifiers: CGEventFlags) {
        var cgModifiers: CGEventFlags = []
        if (hotkeyModifiers & cmdKey) != 0 { cgModifiers.insert(.maskCommand) }
        if (hotkeyModifiers & shiftKey) != 0 { cgModifiers.insert(.maskShift) }
        if (hotkeyModifiers & optionKey) != 0 { cgModifiers.insert(.maskAlternate) }
        if (hotkeyModifiers & controlKey) != 0 { cgModifiers.insert(.maskControl) }
        
        return (CGKeyCode(hotkeyKeyCode), cgModifiers)
    }
    
    /// Get current hotkey as readable string
    func getHotkeyString() -> String {
        var parts: [String] = []
        
        if (hotkeyModifiers & cmdKey) != 0 { parts.append("⌘") }
        if (hotkeyModifiers & shiftKey) != 0 { parts.append("⇧") }
        if (hotkeyModifiers & optionKey) != 0 { parts.append("⌥") }
        if (hotkeyModifiers & controlKey) != 0 { parts.append("⌃") }
        
        let keyNames: [UInt32: String] = [
            49: "Space",
            36: "↵",
            51: "⌫",
            53: "Esc",
            48: "⇥",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
        ]
        
        if let keyName = keyNames[hotkeyKeyCode] {
            parts.append(keyName)
        } else if hotkeyKeyCode >= 0 && hotkeyKeyCode <= 25 {
            let letter = Character(UnicodeScalar(hotkeyKeyCode + 65)!)
            parts.append(String(letter))
        }
        
        return parts.joined(separator: "+")
    }
    
    // MARK: - Sound Feedback
    
    private func playStartSound() {
        // Use system sound or custom sound
        NSSound.beep()
    }
    
    private func playStopSound() {
        // Use system sound or custom sound
        NSSound.beep()
    }
    
    // MARK: - Notifications
    
    private func showErrorNotification(message: String) {
        let notification = UNMutableNotificationContent()
        notification.title = "Flow Mac"
        notification.body = message
        notification.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notification,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func showErrorNotification(error: Error) {
        showErrorNotification(message: error.localizedDescription)
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
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
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }
    
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    
    let handled = manager.handleCGEvent(event)
    
    if handled {
        return nil // Consume event
    } else {
        return Unmanaged.passRetained(event) // Pass through
    }
}

// MARK: - Helper Functions

private func fourCharCode(_ string: String) -> Int {
    guard string.count == 4 else { return 0 }
    var result: Int = 0
    for char in string.utf16 {
        result = (result << 8) + Int(char)
    }
    return result
}
