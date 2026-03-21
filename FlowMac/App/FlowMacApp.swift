import SwiftUI
import AppKit
import UserNotifications

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
    var recordingOverlay: RecordingOverlayWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup notifications
        setupNotifications()
        
        // Initialize core services
        audioEngine = AudioEngine()
        recognitionService = RecognitionService()
        textInjector = TextInjector()
        recordingOverlay = RecordingOverlayWindow()
        
        // Setup audio level delegate for overlay
        audioEngine?.audioLevelDelegate = self
        
        // Initialize UI components
        statusBarController = StatusBarController(
            audioEngine: audioEngine!,
            recognitionService: recognitionService!,
            textInjector: textInjector!
        )
        
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
        
        print("Flow Mac initialized successfully")
        print("Default hotkey: Cmd+Shift+Space")
    }
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func checkPermissions() {
        // Check accessibility permission (required for text injection and hotkeys)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessibilityEnabled {
            print("Accessibility permission not granted. Text injection and hotkeys will not work.")
            showAccessibilityPrompt()
        } else {
            print("Accessibility permission granted")
        }
        
        // Check microphone permission
        audioEngine?.requestPermission { granted in
            if granted {
                print("Microphone permission granted")
            } else {
                print("Microphone permission denied")
                self.showMicrophonePrompt()
            }
        }
    }
    
    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Flow Mac needs accessibility permission to inject text into other applications and monitor global hotkeys. Please enable it in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    private func showMicrophonePrompt() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "Flow Mac needs microphone access to record your voice for transcription. Please enable it in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        hotkeyManager?.stopMonitoring()
        if audioEngine?.isRecording == true {
            _ = audioEngine?.stopRecording()
        }
    }
}

// MARK: - Audio Level Delegate

extension AppDelegate: AudioLevelDelegate {
    func audioLevelDidChange(_ level: Float) {
        recordingOverlay?.updateAudioLevel(level)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
