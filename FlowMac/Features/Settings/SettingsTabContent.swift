import SwiftUI

// MARK: - General Tab

extension SettingsView {
    var generalContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Providers") {
                if configuredProviders.isEmpty && !showAddKeyForm {
                    emptyProvidersCTA
                } else {
                    providersList
                }
            }

            settingsSection("Language") {
                Picker("", selection: $selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: selectedLanguage) { _ in saveLanguage() }
            }

            settingsSection("Feedback") {
                Toggle("Sound feedback", isOn: $soundFeedbackEnabled)
                    .onChange(of: soundFeedbackEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "soundFeedbackEnabled")
                    }
                Text("Play sounds when recording starts and stops")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            settingsSection("AI Correction") {
                Toggle("Enable semantic correction", isOn: $semanticCorrectionEnabled)
                    .onChange(of: semanticCorrectionEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "semanticCorrectionEnabled")
                    }
                Text("Fix grammar and transcription errors using LLM (uses same API key). Context-aware: adapts to Terminal, Code, Chat, Email.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            settingsSection("Permissions") {
                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    subtitle: "Required for hotkeys and text injection",
                    isGranted: hasAccessibilityPermission,
                    action: { showAccessibilityAlert = true }
                )
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Required for voice recording",
                    isGranted: hasMicrophonePermission,
                    action: { requestMicrophonePermission() }
                )
            }
        }
    }
}

// MARK: - Shortcuts Tab

extension SettingsView {
    var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Toggle Recording") {
                Toggle("Enabled", isOn: $toggleModeEnabled)
                    .onChange(of: toggleModeEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "toggleModeEnabled")
                    }
                if toggleModeEnabled {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Toggle Recording")
                                .font(.system(size: 13, weight: .medium))
                            Text("Press to start, press again to stop")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        ShortcutRecorderView(mode: .toggle, keyCode: $hotkeyKeyCode, modifiers: $hotkeyModifiers, modifierSides: $hotkeyModifierSides)
                            .frame(width: 140, height: 32)
                    }
                }
            }

            settingsSection("Push to Talk") {
                Toggle("Enabled", isOn: $pttModeEnabled)
                    .onChange(of: pttModeEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "pttModeEnabled")
                    }
                if pttModeEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Push to Talk")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Hold to record, release to stop")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            ShortcutRecorderView(mode: .pushToTalk, keyCode: $pttKeyCode, modifiers: $pttModifiers, modifierSides: $pttModifierSides)
                                .frame(width: 140, height: 32)
                        }

                        if shortcutConflict {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text("Both shortcuts use the same key combination")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }

            settingsSection("Express Mode") {
                Toggle("Enabled", isOn: $expressModeEnabled)
                    .onChange(of: expressModeEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "expressModeEnabled")
                    }
                if expressModeEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Express Mode")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Press to record (no overlay), press again to transcribe and paste")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            ShortcutRecorderView(mode: .express, keyCode: $expressKeyCode, modifiers: $expressModifiers, modifierSides: $expressModifierSides)
                                .frame(width: 140, height: 32)
                        }
                    }
                }
            }

            settingsSection("How It Works") {
                VStack(alignment: .leading, spacing: 14) {
                    stepRow(number: 1, text: "Toggle: press shortcut to start, press again to stop")
                    stepRow(number: 2, text: "Push to Talk: hold shortcut to record, release to stop")
                    stepRow(number: 3, text: "Express: press to record silently, press again to auto-paste")
                    stepRow(number: 4, text: "Speak clearly into your microphone")
                    stepRow(number: 5, text: "Text is automatically inserted at cursor")
                }
            }
        }
    }

    func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.85))
        }
    }
}

// MARK: - Audio Tab

extension SettingsView {
    var audioContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Input Device") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Microphone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedDeviceID) {
                        Text("System Default").tag("default")
                        ForEach(availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .onChange(of: selectedDeviceID) { newValue in
                        UserDefaults.standard.set(newValue, forKey: AudioDeviceLookup.selectionKey)
                    }
                }

                Button {
                    testMicrophone()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.badge.plus")
                            .font(.system(size: 12))
                        Text("Test Microphone")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            settingsSection("Microphone") {
                Toggle("Auto-boost microphone volume", isOn: $autoBoostMicVolume)
                    .onChange(of: autoBoostMicVolume) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "autoBoostMicVolume")
                    }
                Text("Temporarily set microphone to 100% during recording, restore after")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            settingsSection("Transcription Hint") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("e.g. technical terms, names, acronyms...", text: $transcriptionPrompt)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                        .onChange(of: transcriptionPrompt) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "transcriptionPrompt")
                        }
                    Text("Optional context hint sent to Whisper to improve accuracy for specific vocabulary")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            settingsSection("Audio Format") {
                HStack(spacing: 32) {
                    audioInfoItem(label: "Sample Rate", value: "16 kHz")
                    audioInfoItem(label: "Format", value: "16-bit PCM")
                    audioInfoItem(label: "Channels", value: "Mono")
                }
            }
        }
    }

    func audioInfoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }
}

// MARK: - About Tab

extension SettingsView {
    var aboutContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Flow Mac")
                        .font(.system(size: 18, weight: .bold))
                    Text("Version 1.0.0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("AI-powered voice dictation")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            settingsSection("Links") {
                VStack(alignment: .leading, spacing: 10) {
                    aboutLink(
                        icon: "waveform",
                        title: "Powered by Whisper via \(TranscriptionProvider.current.displayName)",
                        url: "https://openai.com/whisper"
                    )
                    aboutLink(icon: "curlybraces", title: "GitHub Repository", url: "https://github.com/flowmac/flow-mac")
                    aboutLink(icon: "exclamationmark.bubble", title: "Report an Issue", url: "https://github.com/flowmac/flow-mac/issues")
                }
            }

            Spacer()

            Text("\u{00A9} 2026 Flow Mac")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }

    func aboutLink(icon: String, title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Shared Components

extension SettingsView {
    func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(5)
            } else {
                Button("Grant Access") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
