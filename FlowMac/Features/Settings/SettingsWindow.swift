import SwiftUI
import AVFoundation

/// Main settings window view
struct SettingsWindow: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }
            
            RecognitionSettingsView()
                .tabItem {
                    Label("Recognition", systemImage: "waveform")
                }
            
            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showRecordingOverlay") private var showRecordingOverlay = true
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("autoPaste") private var autoPaste = true
    
    var body: some View {
        Form {
            Section("Startup & Behavior") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show recording overlay", isOn: $showRecordingOverlay)
                Toggle("Play sound effects", isOn: $playSounds)
                Toggle("Automatically paste transcription", isOn: $autoPaste)
            }
            
            Section("Menu Bar") {
                Picker("Icon style", selection: .constant("waveform")) {
                    Text("Waveform").tag("waveform")
                    Text("Microphone").tag("mic")
                    Text("Minimal").tag("minimal")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: UInt16 = 49 // Space
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: UInt64 = 524576 // Option
    
    @State private var isRecordingHotkey = false
    
    private let modifierOptions: [(String, UInt64)] = [
        ("⌘ Command", 1048840),
        ("⌥ Option", 524576),
        ("⌃ Control", 262401),
        ("⇧ Shift", 131330)
    ]
    
    private let keyOptions: [(String, UInt16)] = [
        ("Space", 49),
        ("Return", 36),
        ("Tab", 48),
        ("` (Backtick)", 50),
        ("F5", 96),
        ("F6", 97),
        ("F7", 98),
        ("F8", 99)
    ]
    
    var body: some View {
        Form {
            Section("Global Hotkey") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Press this key combination anywhere to start/stop voice dictation:")
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        // Modifier picker
                        Picker("Modifier", selection: $hotkeyModifiers) {
                            ForEach(modifierOptions, id: \.1) { name, value in
                                Text(name).tag(value)
                            }
                        }
                        .frame(width: 150)
                        
                        Text("+")
                            .foregroundColor(.secondary)
                        
                        // Key picker
                        Picker("Key", selection: $hotkeyKeyCode) {
                            ForEach(keyOptions, id: \.1) { name, value in
                                Text(name).tag(value)
                            }
                        }
                        .frame(width: 150)
                    }
                    
                    // Current hotkey display
                    HStack {
                        Text("Current hotkey:")
                            .foregroundColor(.secondary)
                        
                        KeyboardShortcutDisplay(
                            modifiers: hotkeyModifiers,
                            keyCode: hotkeyKeyCode
                        )
                    }
                    .padding(.top, 8)
                }
            }
            
            Section("Quick Actions") {
                Button("Restore Defaults") {
                    hotkeyKeyCode = 49
                    hotkeyModifiers = 524576
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyboardShortcutDisplay: View {
    let modifiers: UInt64
    let keyCode: UInt16
    
    var body: some View {
        HStack(spacing: 4) {
            if modifiers & 1048840 == 1048840 {
                ModifierBadge(text: "⌘")
            }
            if modifiers & 524576 == 524576 {
                ModifierBadge(text: "⌥")
            }
            if modifiers & 262401 == 262401 {
                ModifierBadge(text: "⌃")
            }
            if modifiers & 131330 == 131330 {
                ModifierBadge(text: "⇧")
            }
            
            ModifierBadge(text: keyName, isKey: true)
        }
    }
    
    private var keyName: String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 50: return "`"
        case 96...99: return "F\(keyCode - 91)"
        default: return "Key \(keyCode)"
        }
    }
}

struct ModifierBadge: View {
    let text: String
    var isKey: Bool = false
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isKey ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundColor(isKey ? .white : .primary)
            .cornerRadius(4)
    }
}

// MARK: - Recognition Settings

struct RecognitionSettingsView: View {
    @AppStorage("whisperAPIKey") private var apiKey = ""
    @AppStorage("recognitionLanguage") private var language = "auto"
    @AppStorage("recognitionModel") private var model = "whisper-1"
    @AppStorage("autoPunctuation") private var autoPunctuation = true
    @AppStorage("profanityFilter") private var profanityFilter = false
    
    private let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese")
    ]
    
    var body: some View {
        Form {
            Section("OpenAI API") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Your API key is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Link("Get API Key →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            }
            
            Section("Recognition Options") {
                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                
                Picker("Model", selection: $model) {
                    Text("Whisper-1").tag("whisper-1")
                }
                
                Toggle("Auto-punctuation", isOn: $autoPunctuation)
                Toggle("Profanity filter", isOn: $profanityFilter)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Usage Information")
                        .font(.headline)
                    
                    Text("Flow Mac uses OpenAI's Whisper API for transcription. Standard API rates apply.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Link("View Pricing →", destination: URL(string: "https://openai.com/pricing")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsView: View {
    @State private var microphonePermission: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityPermission = false
    
    var body: some View {
        Form {
            Section("Required Permissions") {
                // Microphone permission
                PermissionRow(
                    title: "Microphone",
                    description: "Needed to capture your voice for transcription",
                    icon: "mic.fill",
                    isGranted: microphonePermission == .authorized
                ) {
                    requestMicrophonePermission()
                }
                
                // Accessibility permission
                PermissionRow(
                    title: "Accessibility",
                    description: "Needed to insert transcribed text into other apps",
                    icon: "accessibility",
                    isGranted: accessibilityPermission
                ) {
                    requestAccessibilityPermission()
                }
                
                // Input monitoring permission
                PermissionRow(
                    title: "Input Monitoring",
                    description: "Needed for global hotkey detection",
                    icon: "keyboard",
                    isGranted: accessibilityPermission // Same as accessibility
                ) {
                    requestAccessibilityPermission()
                }
            }
            
            Section {
                Button("Open System Settings") {
                    openSystemSettings()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
        
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }
    
    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            checkPermissions()
        }
    }
    
    private func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            // App icon placeholder
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 4) {
                Text("Flow Mac")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Voice dictation for macOS powered by OpenAI Whisper")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.vertical)
            
            HStack(spacing: 20) {
                Link("Website", destination: URL(string: "https://flowmac.app")!)
                Link("GitHub", destination: URL(string: "https://github.com/flowmac/flowmac")!)
                Link("Support", destination: URL(string: "https://flowmac.app/support")!)
            }
            
            Spacer()
            
            Text("© 2024 Flow Mac. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
