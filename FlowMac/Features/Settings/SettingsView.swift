import SwiftUI
import AppKit
import AVFoundation

/// Settings view for the app
struct SettingsView: View {
    @State private var apiKey = ""
    @State private var selectedLanguage = "auto"
    @State private var hotkeyKeyCode: UInt16 = 49 // Space
    @State private var hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    @State private var showAccessibilityAlert = false
    @State private var hasAccessibilityPermission = false
    @State private var hasMicrophonePermission = false
    @State private var availableInputDevices: [AVAudioDevice] = []
    @State private var selectedDeviceID: String = "default"
    
    let languages = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ru", "Russian"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
    ]
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            audioTab
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            loadSettings()
            checkPermissions()
            loadAudioDevices()
        }
        .alert("Accessibility Permission Required", isPresented: $showAccessibilityAlert) {
            Button("Open System Settings") {
                openAccessibilitySettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Flow Mac needs accessibility permission to inject text into other applications. Please grant this permission in System Settings.")
        }
    }
    
    // MARK: - Tabs
    
    private var generalTab: some View {
        Form {
            Section(header: Text("API Configuration").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OpenAI API Key")
                        .font(.system(size: 13, weight: .medium))
                    
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: apiKey) { _ in
                            saveAPIKey()
                        }
                    
                    Text("Your API key is stored in UserDefaults (Keychain support coming soon).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recognition Language")
                        .font(.system(size: 13, weight: .medium))
                    
                    Picker("", selection: $selectedLanguage) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: selectedLanguage) { _ in
                        saveLanguage()
                    }
                    
                    Text("Select your primary language for better accuracy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Permissions").font(.headline)) {
                HStack {
                    Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(hasAccessibilityPermission ? .green : .orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Permission")
                            .font(.subheadline)
                        Text("Required for text injection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !hasAccessibilityPermission {
                        Button("Grant") {
                            showAccessibilityAlert = true
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }
                .padding(.vertical, 4)
                
                HStack {
                    Image(systemName: hasMicrophonePermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(hasMicrophonePermission ? .green : .orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone Permission")
                            .font(.subheadline)
                        Text("Required for voice recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !hasMicrophonePermission {
                        Button("Grant") {
                            openMicrophoneSettings()
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
    
    private var shortcutsTab: some View {
        Form {
            Section(header: Text("Global Shortcut").font(.headline)) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Press the key combination you want to use to activate Flow Mac:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Current shortcut:")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        ShortcutRecorderView(
                            keyCode: $hotkeyKeyCode,
                            modifiers: $hotkeyModifiers
                        )
                        .frame(width: 160, height: 36)
                    }
                    
                    Text("Default: ⌘ + ⇧ + Space (Command + Shift + Space)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("How to Use").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    stepView(number: 1, text: "Press the global shortcut to start recording")
                    stepView(number: 2, text: "Speak clearly into your microphone")
                    stepView(number: 3, text: "Press again or wait for silence to stop")
                    stepView(number: 4, text: "Text will be automatically inserted at cursor")
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
    }
    
    private func stepView(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
    
    private var audioTab: some View {
        Form {
            Section(header: Text("Audio Input").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Device")
                        .font(.system(size: 13, weight: .medium))
                    
                    // macOS audio device picker
                    Picker("", selection: $selectedDeviceID) {
                        Text("Default Microphone").tag("default")
                        ForEach(availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: selectedDeviceID) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "selectedAudioDevice")
                    }
                    
                    Text("Select the microphone you want to use for voice input.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Audio Quality").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sample Rate")
                        Spacer()
                        Text("16 kHz (Optimal for Whisper)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Format")
                        Spacer()
                        Text("16-bit PCM Mono")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Buffer Size")
                        Spacer()
                        Text("4096 samples")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Test").font(.headline)) {
                Button("Test Microphone") {
                    testMicrophone()
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .controlSize(.regular)
            }
        }
        .padding()
    }
    
    private var aboutTab: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)
            
            Text("Flow Mac")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("AI-powered voice dictation for macOS")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 10) {
                Link(destination: URL(string: "https://openai.com/whisper")!) {
                    Label("Powered by OpenAI Whisper", systemImage: "waveform")
                }
                
                Link(destination: URL(string: "https://github.com/flowmac/flow-mac")!) {
                    Label("GitHub Repository", systemImage: "curlybraces")
                }
                
                Link(destination: URL(string: "https://github.com/flowmac/flow-mac/issues")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.subheadline)
            
            Spacer()
            
            Text("© 2026 Flow Mac. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func loadSettings() {
        apiKey = UserDefaults.standard.string(forKey: "whisperAPIKey") ?? ""
        selectedLanguage = UserDefaults.standard.string(forKey: "recognitionLanguage") ?? "auto"
        selectedDeviceID = UserDefaults.standard.string(forKey: "selectedAudioDevice") ?? "default"
        
        if let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? UInt16 {
            hotkeyKeyCode = savedKeyCode
        }
        
        if let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiersRaw") as? UInt {
            hotkeyModifiers = NSEvent.ModifierFlags(rawValue: savedModifiers)
        }
    }
    
    private func saveAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: "whisperAPIKey")
    }
    
    private func saveLanguage() {
        UserDefaults.standard.set(selectedLanguage, forKey: "recognitionLanguage")
    }
    
    private func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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
    
    private func loadAudioDevices() {
        // Get available audio input devices using AVAudioEngine
        let audioSession = AVAudioEngine()
        let inputNode = audioSession.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Query available input devices using Core Audio
        var devices: [AVAudioDevice] = []
        
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var result = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &propertySize)
        
        if result == noErr {
            let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
            var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
            
            result = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &propertySize, &deviceIDs)
            
            if result == noErr {
                for deviceID in deviceIDs {
                    // Check if device is an input device
                    var inputAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyStreamConfiguration,
                        mScope: kAudioDevicePropertyScopeInput,
                        mElement: 0
                    )
                    
                    var streamConfigSize: UInt32 = 0
                    result = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &streamConfigSize)
                    
                    if result == noErr && streamConfigSize > 0 {
                        // Get device name
                        var nameAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioObjectPropertyName,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        
                        var deviceName: CFString = "" as CFString
                        var nameSize = UInt32(MemoryLayout<CFString>.size)
                        result = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &deviceName)
                        
                        if result == noErr {
                            let name = deviceName as String
                            devices.append(AVAudioDevice(id: String(deviceID), name: name, objectID: deviceID))
                        }
                    }
                }
            }
        }
        
        availableInputDevices = devices
    }
    
    private func testMicrophone() {
        // Request permission if needed
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if granted {
                    let alert = NSAlert()
                    alert.messageText = "Microphone Test"
                    alert.informativeText = "Microphone access granted. You can now use voice dictation."
                    alert.alertStyle = .informational
                    alert.runModal()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Microphone Access Denied"
                    alert.informativeText = "Please enable microphone access in System Settings to use Flow Mac."
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - Audio Device Model

struct AVAudioDevice: Identifiable {
    let id: String
    let name: String
    let objectID: AudioObjectID
}

// MARK: - Supporting Views

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags
    
    func makeNSView(context: Context) -> ShortcutRecorder {
        let recorder = ShortcutRecorder()
        recorder.onShortcutChanged = { code, mods in
            keyCode = code
            modifiers = mods
            
            // Save to UserDefaults
            UserDefaults.standard.set(code, forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(mods.rawValue, forKey: "hotkeyModifiersRaw")
        }
        return recorder
    }
    
    func updateNSView(_ nsView: ShortcutRecorder, context: Context) {}
}

class ShortcutRecorder: NSView {
    var onShortcutChanged: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    
    private var currentKeyCode: UInt16 = 49  // Space
    private var currentModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var isRecording = false
    
    override var acceptsFirstResponder: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw background
        if isRecording {
            NSColor.systemRed.withAlphaComponent(0.1).setFill()
            NSColor.systemRed.setStroke()
        } else {
            NSColor.controlBackgroundColor.setFill()
            NSColor.separatorColor.setStroke()
        }
        
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.fill()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()
        
        // Draw shortcut text
        let shortcutText = shortcutString()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: isRecording ? NSColor.systemRed : NSColor.label
        ]
        
        let size = shortcutText.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        
        shortcutText.draw(at: point, withAttributes: attributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        isRecording = !isRecording
        if isRecording {
            window?.makeFirstResponder(self)
        }
        setNeedsDisplay(bounds)
    }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        
        // Don't allow just modifiers
        let modifiersOnly: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function, .help]
        if modifiersOnly.contains(event.modifierFlags) && event.keyCode >= 54 && event.keyCode <= 63 {
            return // Just a modifier key, ignore
        }
        
        currentKeyCode = event.keyCode
        currentModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        
        onShortcutChanged?(currentKeyCode, currentModifiers)
        
        isRecording = false
        setNeedsDisplay(bounds)
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Handle modifier-only changes
    }
    
    private func shortcutString() -> String {
        if isRecording {
            return "Recording..."
        }
        
        var parts: [String] = []
        
        if currentModifiers.contains(.command) { parts.append("⌘") }
        if currentModifiers.contains(.option) { parts.append("⌥") }
        if currentModifiers.contains(.control) { parts.append("⌃") }
        if currentModifiers.contains(.shift) { parts.append("⇧") }
        
        let keyNames: [UInt16: String] = [
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
        
        if let keyName = keyNames[currentKeyCode] {
            parts.append(keyName)
        } else if currentKeyCode >= 0 && currentKeyCode <= 25 {
            let letter = Character(UnicodeScalar(currentKeyCode + 65)!)
            parts.append(String(letter))
        } else {
            // Try to get the character from keyCode
            parts.append("Key\(currentKeyCode)")
        }
        
        return parts.joined(separator: "")
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
