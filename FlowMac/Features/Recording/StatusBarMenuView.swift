import SwiftUI
import Combine
import AVFoundation

/// SwiftUI view for the status bar popover menu
struct StatusBarMenuView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var recognitionService: RecognitionService
    @ObservedObject var textInjector: TextInjector

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
                // Recording button
                recordingButton
                    .padding(.top, 12)

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
            if !recognitionService.transcriptionHistory.isEmpty {
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

            // Hotkey badge
            HStack(spacing: 2) {
                Text("⌘⇧")
                    .font(.system(size: 10, weight: .medium))
                Text("Space")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(4)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(recognitionService.transcriptionHistory.prefix(5)) { entry in
                        historyRow(entry)
                    }
                }
            }
            .frame(maxHeight: 130)
        }
    }

    private func historyRow(_ entry: TranscriptionEntry) -> some View {
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

    // MARK: - Footer

    private var footerView: some View {
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
