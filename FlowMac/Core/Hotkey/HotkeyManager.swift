import Foundation
import Carbon
import Combine

/// Manages global hotkeys using Carbon EventTap
class HotkeyManager: NSObject, ObservableObject, HotkeyManagerProtocol {
    @Published var isRecording = false
    
    private var audioEngine: AudioEngine
    private var recognitionService: RecognitionService
    private var textInjector: TextInjector
    private var recordingOverlay: RecordingOverlayWindow
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Default hotkey: Option + Space
    private var hotkeyKeyCode: CGKeyCode = 49 // Space
    private var hotkeyModifiers: CGEventFlags = [.maskAlternate]
    
    weak var hotkeyDelegate: HotkeyDelegate?
    
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
        if let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? CGKeyCode {
            hotkeyKeyCode = savedKeyCode
        }
        
        if let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt64 {
            hotkeyModifiers = CGEventFlags(rawValue: savedModifiers)
        }
    }
    
    /// Set up global hotkey monitoring
    private func setupHotkey() {
        startMonitoring()
    }
    
    /// Start monitoring for global hotkey events
    func startMonitoring() {
        // Check for accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("Accessibility permission required for global hotkeys")
            return
        }
        
        // Create event tap for key events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
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
        DispatchQueue.global(qos: .userInteractive).async {
            CFRunLoopRun()
        }
    }
    
    /// Stop monitoring hotkey events
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    /// Handle hotkey event
    func handleHotkey(eventType: CGEventType, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Check if our hotkey combination is pressed
        let modifiersMatch = flags.contains(hotkeyModifiers)
        let keyCodeMatch = keyCode == Int64(hotkeyKeyCode)
        
        guard modifiersMatch && keyCodeMatch else {
            return false // Event not handled
        }
        
        if eventType == .keyDown {
            DispatchQueue.main.async { [weak self] in
                self?.toggleRecording()
            }
            hotkeyDelegate?.hotkeyDidTrigger()
        } else {
            hotkeyDelegate?.hotkeyDidRelease()
        }
        
        return true // Event handled, don't propagate
    }
    
    /// Toggle recording state
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Start recording and transcription
    private func startRecording() {
        isRecording = true
        recordingOverlay.show()
        audioEngine.startRecording()
        
        // Play start sound (optional)
        playSound(named: "start")
    }
    
    /// Stop recording and process transcription
    private func stopRecording() {
        isRecording = false
        recordingOverlay.hide()
        
        guard let audioData = audioEngine.stopRecording() else {
            print("No audio data captured")
            return
        }
        
        // Play stop sound (optional)
        playSound(named: "stop")
        
        // Send to recognition service
        recognitionService.transcribe(audioData: audioData) { [weak self] result in
            switch result {
            case .success(let text):
                self?.textInjector.insertText(text)
            case .failure(let error):
                print("Transcription error: \(error)")
                // Show error notification
                self?.showErrorNotification(error: error)
            }
        }
    }
    
    /// Update hotkey configuration
    func updateHotkey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        
        // Save to UserDefaults
        UserDefaults.standard.set(keyCode, forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(modifiers.rawValue, forKey: "hotkeyModifiers")
    }
    
    /// Get current hotkey configuration
    func getCurrentHotkey() -> (keyCode: CGKeyCode, modifiers: CGEventFlags) {
        return (hotkeyKeyCode, hotkeyModifiers)
    }
    
    private func playSound(named: String) {
        // Implement sound feedback
        NSSound.beep()
    }
    
    private func showErrorNotification(error: Error) {
        let notification = UNMutableNotificationContent()
        notification.title = "Flow Mac"
        notification.body = error.localizedDescription
        notification.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notification,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - C Callback

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }
    
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    
    let handled = manager.handleHotkey(eventType: type, event: event)
    
    if handled {
        return nil // Consume event
    } else {
        return Unmanaged.passRetained(event) // Pass through
    }
}
