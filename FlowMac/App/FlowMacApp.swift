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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?
    var audioEngine: AudioEngine?
    var recognitionService: RecognitionService?
    var textInjector: TextInjector?
    var recordingOverlay: RecordingOverlayWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
    }

    /// Quit immediately if another FlowMac is already running, activating that one instead.
    /// Prevents two copies (e.g. installed Desktop build + dev build from DerivedData) from
    /// competing for the global hotkey and microphone.
    private func enforceSingleInstance() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.flowmac.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        guard let existing = others.first else { return }

        NSLog("[FlowMac] Another instance is already running (PID \(existing.processIdentifier)) — terminating self")
        DistributedNotificationCenter.default().postNotificationName(
            StatusBarController.showRequestNotification,
            object: nil,
            deliverImmediately: true
        )
        existing.activate(options: [])
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.clear()
        DebugLog.printLocation()
        DebugLog.log("1. applicationDidFinishLaunching CALLED")
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app")

        UserDefaults.standard.register(defaults: [
            "soundFeedbackEnabled": false
        ])

        setupNotifications()

        DebugLog.log("2. Initializing core services")
        // Quota & subscription (singletons, init on first access)
        _ = QuotaService.shared
        _ = SubscriptionService.shared

        audioEngine = AudioEngine()
        recognitionService = RecognitionService()
        textInjector = TextInjector()
        recordingOverlay = RecordingOverlayWindow()

        audioEngine?.audioLevelDelegate = self

        DebugLog.log("3. Setting up status bar")
        statusBarController = StatusBarController(
            audioEngine: audioEngine!,
            recognitionService: recognitionService!,
            textInjector: textInjector!
        )

        DebugLog.log("4. Checking permissions")
        checkPermissions()

        DebugLog.log("5. Setting up hotkey manager")
        hotkeyManager = HotkeyManager(
            audioEngine: audioEngine!,
            recognitionService: recognitionService!,
            textInjector: textInjector!,
            recordingOverlay: recordingOverlay!
        )

        NSApp.setActivationPolicy(.accessory)

        DebugLog.log("6. Initialization COMPLETE")
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.shared.requestPermission()
    }

    private func checkPermissions() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(
            [promptKey: false] as CFDictionary
        )
        DebugLog.log("4a. Accessibility=\(accessibilityEnabled)")

        if !accessibilityEnabled {
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }

        audioEngine?.requestPermission { granted in
            DebugLog.log("4b. Microphone=\(granted)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let urlString = response.notification.request.content.userInfo["actionURL"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
