import SwiftUI
import Combine
import AVFoundation

/// SwiftUI view for the status bar popover menu
struct StatusBarMenuView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var recognitionService: RecognitionService
    @ObservedObject var textInjector: TextInjector
    @ObservedObject var historyService: TranscriptionHistoryService
    @ObservedObject var quotaService = QuotaService.shared
    @State private var showPaywall = false

    var openSettings: () -> Void
    var quitApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().padding(.horizontal, 12)

            // Main content
            VStack(spacing: 12) {
                if shouldShowQuotaBanner {
                    quotaBanner.padding(.top, 12)
                }

                // Recording button
                recordingButton
                    .padding(.top, shouldShowQuotaBanner ? 0 : 12)

                // Status
                if audioEngine.isRecording {
                    audioLevelBar
                }

                if recognitionService.isProcessing {
                    processingView
                }

                if let error = recognitionService.errorMessage {
                    errorView(error)
                }
            }
            .padding(.horizontal, 16)

            // History
            if !historyService.entries.isEmpty {
                Divider().padding(.horizontal, 12).padding(.top, 12)
                historyView
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            Divider().padding(.horizontal, 12).padding(.top, 12)

            // Footer
            footerView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Flow Mac")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            quotaIndicator
        }
    }

    private var statusText: String {
        if audioEngine.isRecording { return "Recording..." }
        if recognitionService.isProcessing { return "Transcribing..." }
        return "Ready"
    }

    // MARK: - Recording Button

    private var recordingButton: some View {
        Button {
            NotificationCenter.default.post(name: .toggleRecording, object: nil)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(audioEngine.isRecording ? Color.red : Color.blue)
                        .frame(width: 28, height: 28)

                    Image(systemName: audioEngine.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(audioEngine.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                if audioEngine.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(audioEngine.isRecording ? Color.red.opacity(0.12) : Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Audio Level

    private var audioLevelBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, CGFloat(audioEngine.audioLevel) * geo.size.width))
                    .animation(.easeOut(duration: 0.08), value: audioEngine.audioLevel)
            }
        }
        .frame(height: 4)
        .cornerRadius(2)
    }

    // MARK: - Processing

    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Transcribing...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - History

    private var historyView: some View {
        let plan = quotaService.state.plan
        let limit = min(5, plan.historyLimit)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if !plan.hasFullHistory {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("See all in Pro")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(historyService.recentEntries(limit: limit)) { entry in
                        if entry.status == .failed {
                            failedHistoryRow(entry)
                        } else {
                            historyRow(entry)
                        }
                    }
                }
            }
            .frame(maxHeight: 130)
        }
    }

    private func historyRow(_ entry: PersistentTranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .textSelection(.enabled)

                Text(entry.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    private func failedHistoryRow(_ entry: PersistentTranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ошибка транскрипции")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)

                if let errorMsg = entry.errorMessage {
                    Text(errorMsg)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(entry.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            Button {
                NotificationCenter.default.post(
                    name: .retryTranscription,
                    object: nil,
                    userInfo: ["entryID": entry.id]
                )
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .disabled(recognitionService.isProcessing)
            .help("Повторить")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Quota Indicator

    private var shouldShowQuotaBanner: Bool {
        let state = quotaService.state
        return state.plan.usesBackend && (state.isExhausted || state.usageRatio >= 0.8)
    }

    private var quotaBanner: some View {
        let state = quotaService.state
        let exhausted = state.isExhausted
        let title = exhausted ? "Quota exhausted" : "Quota nearly used"
        let subtitle = exhausted
            ? "Resets \(formattedReset). Upgrade for more minutes."
            : "\(state.remainingMinutes) min left of \(state.totalMinutes). Resets \(formattedReset)."

        return Button {
            showPaywall = true
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: exhausted ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(exhausted ? .red : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(exhausted ? .red : .primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((exhausted ? Color.red : Color.orange).opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var formattedReset: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: quotaService.state.periodEnd)
    }

    private var quotaIndicator: some View {
        let state = quotaService.state
        guard state.plan.usesBackend else { return AnyView(EmptyView()) }

        return AnyView(
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 6) {
                    // Mini progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: CGFloat(1.0 - state.usageRatio))
                            .stroke(quotaColor(state), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 14, height: 14)

                    Text("\(state.remainingMinutes) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(state.isExhausted ? .red : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(state.isExhausted ? Color.red.opacity(0.08) : Color.secondary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        )
    }

    private func quotaColor(_ state: QuotaState) -> Color {
        if state.isExhausted { return .red }
        if state.usageRatio >= 0.9 { return .orange }
        if state.usageRatio >= 0.8 { return .yellow }
        return .blue
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    openSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .font(.system(size: 11))
                        Text("Settings")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Permission dots
                HStack(spacing: 6) {
                    permissionDot("Mic", isGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
                    permissionDot("A11y", isGranted: textInjector.checkAccessibilityPermissions())
                }

                Spacer()

                Button {
                    quitApp()
                } label: {
                    Text("Quit")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func permissionDot(_ label: String, isGranted: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - Audio Level View (kept for compatibility)

struct AudioLevelView: View {
    let level: Float
    let isRecording: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(gradient)
                    .frame(width: max(0, CGFloat(level) * geometry.size.width))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: isRecording ? [.green, .yellow, .red] : [.gray],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Permission Status View (kept for compatibility)

struct PermissionStatusView: View {
    let title: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isGranted ? .green : .orange)
                .font(.caption)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
    }
}
