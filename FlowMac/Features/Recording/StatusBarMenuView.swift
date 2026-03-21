import SwiftUI
import Combine

/// SwiftUI view for the status bar popover menu
struct StatusBarMenuView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var recognitionService: RecognitionService
    @ObservedObject var textInjector: TextInjector
    
    var openSettings: () -> Void
    var quitApp: () -> Void
    
    @State private var showingPermissionsAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerView
            
            Divider()
            
            // Recording status
            recordingStatusView
            
            Divider()
            
            // Quick actions
            actionsView
            
            Divider()
            
            // Bottom buttons
            bottomButtonsView
        }
        .padding()
        .frame(width: 280)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Flow Mac")
                    .font(.headline)
                Text("Voice Dictation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var recordingStatusView: some View {
        VStack(spacing: 12) {
            // Audio level indicator
            AudioLevelView(level: audioEngine.audioLevel, isRecording: audioEngine.isRecording)
                .frame(height: 40)
            
            // Status text
            HStack {
                Circle()
                    .fill(audioEngine.isRecording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: audioEngine.isRecording)
                
                Text(audioEngine.isRecording ? "Recording..." : "Ready")
                    .font(.subheadline)
                
                Spacer()
            }
            
            // Processing indicator
            if recognitionService.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            // Last transcribed text preview
            if !recognitionService.transcribedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last transcription:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(recognitionService.transcribedText)
                        .font(.caption)
                        .lineLimit(3)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            // Error message
            if let errorMessage = recognitionService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var actionsView: some View {
        VStack(spacing: 8) {
            Button {
                NotificationCenter.default.post(name: .toggleRecording, object: nil)
            } label: {
                HStack {
                    Image(systemName: audioEngine.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    Text(audioEngine.isRecording ? "Stop Recording" : "Start Recording")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(audioEngine.isRecording ? .red : .accentColor)
            
            HStack(spacing: 8) {
                PermissionStatusView(
                    title: "Microphone",
                    isGranted: checkMicrophonePermission()
                )
                
                PermissionStatusView(
                    title: "Accessibility",
                    isGranted: textInjector.checkAccessibilityPermissions()
                )
            }
        }
    }
    
    private var bottomButtonsView: some View {
        HStack {
            Button("Settings...") {
                openSettings()
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Button("Quit") {
                quitApp()
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Helpers
    
    private func checkMicrophonePermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float
    let isRecording: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                
                // Level indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(gradient)
                    .frame(width: max(0, CGFloat(level) * geometry.size.width))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
    
    private var gradient: some View {
        LinearGradient(
            colors: isRecording ? [.green, .yellow, .red] : [.gray],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Permission Status View

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
