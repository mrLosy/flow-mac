import SwiftUI
import AppKit
import AVFoundation
import Carbon

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case audio = "Audio"
    case statistics = "Statistics"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .audio: return "waveform"
        case .statistics: return "chart.bar"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State var selectedTab: SettingsTab = .general

    // Provider state
    @State var activeProvider: TranscriptionProvider = .current
    @State var providerAPIKeys: [TranscriptionProvider: String] = [:]
    @State var showAddKeyForm = false
    @State var addFormProvider: TranscriptionProvider = .groq
    @State var addFormKey = ""
    @State var addFormValidating = false
    @State var addFormError: String?

    // Other settings
    @State var selectedLanguage = "auto"
    @State var hotkeyKeyCode: UInt16 = 49
    @State var hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    @State var pttKeyCode: UInt16 = 2  // D key
    @State var pttModifiers: NSEvent.ModifierFlags = [.command, .shift]
    @State var expressKeyCode: UInt16 = 0
    @State var expressModifiers: NSEvent.ModifierFlags = []
    @State var transcriptionPrompt: String = ""
    @State var showAccessibilityAlert = false
    @State var hasAccessibilityPermission = false
    @State var hasMicrophonePermission = false
    @State var toggleModeEnabled = UserDefaults.standard.object(forKey: "toggleModeEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "toggleModeEnabled")
    @State var pttModeEnabled = UserDefaults.standard.object(forKey: "pttModeEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "pttModeEnabled")
    @State var expressModeEnabled = UserDefaults.standard.bool(forKey: "expressModeEnabled")
    @State var soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
    @State var showMicTestAlert = false
    @State var micTestGranted = false
    @State var availableInputDevices: [AVAudioDevice] = []
    @State var selectedDeviceID: String = "default"
    @State var autoBoostMicVolume = UserDefaults.standard.bool(forKey: "autoBoostMicVolume")
    @State var semanticCorrectionEnabled = UserDefaults.standard.bool(forKey: "semanticCorrectionEnabled")

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

    var configuredProviders: [TranscriptionProvider] {
        TranscriptionProvider.allCases.filter { providerAPIKeys[$0]?.isEmpty == false }
    }

    var unconfiguredProviders: [TranscriptionProvider] {
        TranscriptionProvider.allCases.filter { providerAPIKeys[$0]?.isEmpty != false }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(width: 640, height: 460)
        .onAppear {
            loadSettings()
            loadAudioDevices()
            // Slight delay ensures the window is fully set up before TCC query
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                checkPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
        .alert("Accessibility Permission Required", isPresented: $showAccessibilityAlert) {
            Button("Open System Settings") { openAccessibilitySettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Flow Mac needs accessibility permission to inject text.")
        }
        .alert(micTestGranted ? "Microphone Test" : "Microphone Access Denied", isPresented: $showMicTestAlert) {
            if !micTestGranted {
                Button("Open System Settings") { openMicrophoneSettings() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(micTestGranted
                ? "Microphone access granted. You can now use voice dictation."
                : "Please enable microphone access in System Settings.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selectedTab == tab ? .white : .secondary)
                            .frame(width: 20)
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .background(.ultraThinMaterial)
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedTab.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.bottom, 20)

                switch selectedTab {
                case .general: generalContent
                case .shortcuts: shortcutsContent
                case .audio: audioContent
                case .statistics: UsageMetricsView()
                case .about: aboutContent
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Persistence

    func loadSettings() {
        TranscriptionProvider.migrateIfNeeded()
        activeProvider = .current
        providerAPIKeys = Dictionary(
            uniqueKeysWithValues: TranscriptionProvider.allCases.map { ($0, $0.apiKey) }
        )
        selectedLanguage = UserDefaults.standard.string(forKey: "recognitionLanguage") ?? "auto"
        selectedDeviceID = UserDefaults.standard.string(forKey: "selectedAudioDevice") ?? "default"
        // Toggle hotkey (migrated keys or new keys)
        if let savedKeyCode = UserDefaults.standard.object(forKey: "toggleHotkeyKeyCode") as? UInt32 {
            hotkeyKeyCode = UInt16(savedKeyCode)
        } else if let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? UInt32 {
            hotkeyKeyCode = UInt16(savedKeyCode)
        }
        if let savedModifiers = UserDefaults.standard.object(forKey: "toggleHotkeyModifiers") as? UInt32 {
            hotkeyModifiers = carbonToNSEventModifiers(savedModifiers)
        } else if let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt32 {
            hotkeyModifiers = carbonToNSEventModifiers(savedModifiers)
        }
        // PTT hotkey
        if let savedKeyCode = UserDefaults.standard.object(forKey: "pttHotkeyKeyCode") as? UInt32 {
            pttKeyCode = UInt16(savedKeyCode)
        }
        if let savedModifiers = UserDefaults.standard.object(forKey: "pttHotkeyModifiers") as? UInt32 {
            pttModifiers = carbonToNSEventModifiers(savedModifiers)
        }
        // Express hotkey
        if let savedKeyCode = UserDefaults.standard.object(forKey: "expressHotkeyKeyCode") as? UInt32 {
            expressKeyCode = UInt16(savedKeyCode)
        }
        if let savedModifiers = UserDefaults.standard.object(forKey: "expressHotkeyModifiers") as? UInt32 {
            expressModifiers = carbonToNSEventModifiers(savedModifiers)
        }
        // Transcription prompt
        transcriptionPrompt = UserDefaults.standard.string(forKey: "transcriptionPrompt") ?? ""
    }

    func activateProvider(_ provider: TranscriptionProvider) {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeProvider = provider
            TranscriptionProvider.current = provider
        }
    }

    func removeProviderKey(_ provider: TranscriptionProvider) {
        withAnimation(.easeInOut(duration: 0.2)) {
            provider.apiKey = ""
            providerAPIKeys[provider] = ""
            if activeProvider == provider {
                if let first = configuredProviders.first {
                    activateProvider(first)
                }
            }
        }
    }

    func openAddForm() {
        let firstUnconfigured = unconfiguredProviders.first ?? .groq
        addFormProvider = firstUnconfigured
        addFormKey = ""
        addFormError = nil
        addFormValidating = false
        withAnimation(.easeInOut(duration: 0.25)) {
            showAddKeyForm = true
        }
    }

    func cancelAddForm() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showAddKeyForm = false
            addFormKey = ""
            addFormError = nil
        }
    }

    func submitAddForm() {
        let key = addFormKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            addFormError = "Enter an API key"
            return
        }

        addFormValidating = true
        addFormError = nil

        TranscriptionProvider.validate(provider: addFormProvider, key: key) { result in
            addFormValidating = false
            switch result {
            case .success:
                addFormProvider.apiKey = key
                providerAPIKeys[addFormProvider] = key
                if configuredProviders.count == 1 || activeProvider == addFormProvider {
                    activateProvider(addFormProvider)
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAddKeyForm = false
                    addFormKey = ""
                }
            case .failure(let error):
                addFormError = error.localizedDescription
            }
        }
    }

    func saveLanguage() {
        UserDefaults.standard.set(selectedLanguage, forKey: "recognitionLanguage")
    }

    func checkPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let a11y = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[FlowMac Settings] checkPermissions — Accessibility: \(a11y), Mic status: \(micStatus.rawValue)")
        hasAccessibilityPermission = a11y
        hasMicrophonePermission = micStatus == .authorized
    }

    func requestMicrophonePermission() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.checkPermissions() }
            }
        } else {
            openMicrophoneSettings()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func loadAudioDevices() {
        var devices: [AVAudioDevice] = []
        var propSize: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sysID = AudioObjectID(kAudioObjectSystemObject)
        var res = AudioObjectGetPropertyDataSize(sysID, &addr, 0, nil, &propSize)
        guard res == noErr else { return }

        let count = Int(propSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        res = AudioObjectGetPropertyData(sysID, &addr, 0, nil, &propSize, &ids)
        guard res == noErr else { return }

        for devID in ids {
            var inAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: 0
            )
            var streamSize: UInt32 = 0
            res = AudioObjectGetPropertyDataSize(devID, &inAddr, 0, nil, &streamSize)
            guard res == noErr, streamSize > 0 else { continue }

            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            res = AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &nameSize, &name)
            if res == noErr {
                devices.append(AVAudioDevice(id: String(devID), name: name as String, objectID: devID))
            }
        }
        availableInputDevices = devices
    }

    func testMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.micTestGranted = granted
                self.hasMicrophonePermission = granted
                self.showMicTestAlert = true
            }
        }
    }

    // MARK: - Helpers

    var shortcutConflict: Bool {
        hotkeyKeyCode == pttKeyCode && hotkeyModifiers == pttModifiers
    }

    func carbonToNSEventModifiers(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbon & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        if (carbon & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbon & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbon & UInt32(controlKey)) != 0 { flags.insert(.control) }
        return flags
    }

    func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "\u{2022}", count: 8) }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\(suffix)"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
