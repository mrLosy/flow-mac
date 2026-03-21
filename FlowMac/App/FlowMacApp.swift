import SwiftUI

@main
struct FlowMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?
    var audioEngine: AudioEngine?
    var recognitionService: RecognitionService?
    var textInjector: TextInjector?
    var recordingOverlay: RecordingOverlay?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize core services
        audioEngine = AudioEngine()
        recognitionService = RecognitionService()
        textInjector = TextInjector()
        
        // Initialize UI components
        statusBarController = StatusBarController(
            audioEngine: audioEngine!,
            recognitionService: recognitionService!,
            textInjector: textInjector!
        )
        
        recordingOverlay = RecordingOverlay()
        
        // Initialize hotkey manager
        hotkeyManager = HotkeyManager(
            audioEngine: audioEngine!,
            recognitionService: recognitionService!,
            textInjector: textInjector!,
            recordingOverlay: recordingOverlay!
        )
        
        // Check and request permissions
        checkPermissions()
        
        // Hide dock icon (menu bar app)
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func checkPermissions() {
        // Microphone permission will be requested when audio engine starts
        // Accessibility permission is required for text injection
        // Input monitoring permission is required for global hotkeys
        
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessibilityEnabled {
            print("Accessibility permission not granted. Text injection will not work.")
        }
    }
}
