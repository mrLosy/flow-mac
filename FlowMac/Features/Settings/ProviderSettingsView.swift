import SwiftUI

// MARK: - Provider Settings Components

extension SettingsView {

    // MARK: - Empty State CTA

    var emptyProvidersCTA: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold))

                Text("Add an API key to start using voice dictation.\nGroq is recommended for the fastest experience.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                openAddForm()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add Provider")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Providers List

    var providersList: some View {
        VStack(spacing: 0) {
            ForEach(Array(configuredProviders.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Divider().padding(.leading, 44)
                }
                providerRow(provider)
            }

            if showAddKeyForm {
                if !configuredProviders.isEmpty {
                    Divider().padding(.vertical, 4)
                }
                addKeyFormView
            }

            if !showAddKeyForm && !unconfiguredProviders.isEmpty {
                if !configuredProviders.isEmpty {
                    Divider().padding(.leading, 44)
                }
                addProviderButton
            }
        }
    }

    // MARK: - Provider Row

    func providerRow(_ provider: TranscriptionProvider) -> some View {
        let isActive = activeProvider == provider
        let key = providerAPIKeys[provider] ?? ""

        return Button {
            activateProvider(provider)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(providerGradient(for: provider))
                        .frame(width: 32, height: 32)

                    Image(systemName: provider.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if isActive {
                            Text("Active")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green))
                        }
                    }

                    HStack(spacing: 8) {
                        Text(maskedKey(key))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text("\u{2022}")
                            .font(.system(size: 6))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(provider.modelName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    removeProviderKey(provider)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? providerColor(for: provider).opacity(0.06) : Color.clear)
        )
    }

    // MARK: - Add Provider Button

    var addProviderButton: some View {
        Button {
            openAddForm()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Color.secondary.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text("Add Provider")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Key Form

    var addKeyFormView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Provider selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Provider")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: $addFormProvider) {
                    ForEach(unconfiguredProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Provider description
            HStack(spacing: 8) {
                Image(systemName: addFormProvider.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(providerColor(for: addFormProvider))

                Text(addFormProvider.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(providerColor(for: addFormProvider).opacity(0.06))
            )

            // API key field
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                SecureField(addFormProvider.keyPlaceholder, text: $addFormKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .disabled(addFormValidating)
                    .onSubmit { submitAddForm() }
            }

            // Custom endpoint (optional)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Custom Endpoint")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("(optional)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                TextField("https://your-proxy.com/v1/", text: Binding(
                    get: { addFormProvider.customBaseURL ?? "" },
                    set: { addFormProvider.customBaseURL = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                Text("For Azure OpenAI, proxies, or self-hosted endpoints")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // Error message
            if let error = addFormError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
            }

            // Actions
            HStack(spacing: 8) {
                Spacer()

                Button("Cancel") {
                    cancelAddForm()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(addFormValidating)

                Button {
                    submitAddForm()
                } label: {
                    HStack(spacing: 4) {
                        if addFormValidating {
                            ProgressIndicator()
                                .frame(width: 12, height: 12)
                        }
                        Text(addFormValidating ? "Checking..." : "Add Key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    addFormKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || addFormValidating
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Provider Colors

    func providerColor(for provider: TranscriptionProvider) -> Color {
        switch provider {
        case .openai: return Color(red: 0.29, green: 0.73, blue: 0.57)
        case .groq: return Color(red: 0.96, green: 0.52, blue: 0.15)
        }
    }

    func providerGradient(for provider: TranscriptionProvider) -> LinearGradient {
        switch provider {
        case .openai:
            return LinearGradient(
                colors: [
                    Color(red: 0.29, green: 0.73, blue: 0.57),
                    Color(red: 0.20, green: 0.55, blue: 0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .groq:
            return LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.52, blue: 0.15),
                    Color(red: 0.90, green: 0.35, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {}
}
