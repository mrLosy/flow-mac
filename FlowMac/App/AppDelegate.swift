import SwiftUI
import AppKit
import AVFoundation

/// Main app entry point
@main
struct FlowMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsWindow()
        }
    }
}

/// App delegate for lifecycle management and service initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?
    var audioEngine: AudioEngine?
    var recognitionService: RecognitionService?
    var textInjector: TextInjector?
    var recordingOverlay: RecordingOverlayWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        requestNotificationPermissions()
        
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
        
        // Initialize recording overlay
        recordingOverlay = RecordingOverlayWindow()
        
        // Initialize hotkey manager
        hotkeyManager = HotkeyManager(
            audioEngine: audioEngine!,
            recognitionService: recognitionService!,
            textInjector: textInjector!,
            recordingOverlay: recordingOverlay!
        )
        
        // Check permissions
        checkPermissions()
        
        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
        
        print("Flow Mac initialized successfully")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        hotkeyManager?.stopMonitoring()
        if audioEngine?.isRecording == true {
            audioEngine?.stopRecording()
        }
    }
    
    // MARK: - Permissions
    
    private func checkPermissions() {
        // Check microphone permission
        checkMicrophonePermission()
        
        // Check accessibility permission (required for text injection)
        checkAccessibilityPermission()
        
        // Check input monitoring permission (required for global hotkeys)
        checkInputMonitoringPermission()
    }
    
    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    print("Microphone permission granted")
                } else {
                    print("Microphone permission denied")
                }
            }
        case .restricted, .denied:
            print("Microphone permission not granted")
        case .authorized:
            print("Microphone permission already granted")
        @unknown default:
            break
        }
    }
    
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessibilityEnabled {
            print("Accessibility permission not granted. Text injection will not work.")
        }
    }
    
    private func checkInputMonitoringPermission() {
        // Input monitoring requires CGEventTap which needs accessibility
        // The prompt will appear when we try to create the event tap
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
