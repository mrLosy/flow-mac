import SwiftUI
import AppKit
import Combine

/// Floating overlay window showing recording status with audio visualization
class RecordingOverlayWindow: NSObject, ObservableObject {
    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    
    @Published var audioLevel: Float = 0.0
    @Published var isRecording = false
    
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupWindow()
    }
    
    private func setupWindow() {
        let contentView = RecordingOverlayView(
            audioLevel: $audioLevel,
            isRecording: $isRecording
        )
        
        hostingView = NSHostingView(rootView: contentView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window?.contentView = hostingView
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = .floating
        window?.ignoresMouseEvents = true
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Position window at center of screen
        positionWindow()
    }
    
    private func positionWindow() {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        
        let windowSize: CGFloat = 200
        let x = screenFrame.midX - windowSize / 2
        let y = screenFrame.midY - windowSize / 2
        
        window?.setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: false)
    }
    
    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.positionWindow() // Recenter on current screen
            self?.window?.orderFrontRegardless()
            self?.isRecording = true
        }
    }
    
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil)
            self?.isRecording = false
            self?.audioLevel = 0.0
        }
    }
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
    }
}

// MARK: - SwiftUI Overlay View

struct RecordingOverlayView: View {
    @Binding var audioLevel: Float
    @Binding var isRecording: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Background blur effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Circle())
            
            // Outer pulsing ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.red.opacity(0.4), .orange.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .animation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Middle pulsing ring
            Circle()
                .stroke(Color.red.opacity(0.15), lineWidth: 8)
                .scaleEffect(pulseScale * 0.85)
                .opacity(pulseOpacity * 0.7)
            
            // Audio level rings - dynamic visualization
            ForEach(0..<5) { index in
                Circle()
                    .stroke(
                        audioLevelColor(for: index)
                            .opacity(0.3 + Double(index) * 0.1),
                        lineWidth: 2 + CGFloat(index) * 0.5
                    )
                    .scaleEffect(scaleForRing(index))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
            
            // Center main circle with gradient
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.red, .red.opacity(0.8)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .red.opacity(0.4), radius: 20, x: 0, y: 0)
                
                // Microphone icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, isActive: isRecording)
            }
            
            // Recording indicator pill at bottom
            VStack {
                Spacer()
                
                HStack(spacing: 6) {
                    // Animated recording dot
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulseOpacity)
                            .scaleEffect(pulseScale)
                    }
                    
                    Text("Recording...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.6))
                        .background(
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.bottom, 20)
            }
            
            // Audio level bars visualization
            HStack(spacing: 3) {
                ForEach(0..<7) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(audioLevel > Float(index) / 7 ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 4, height: barHeight(for: index))
                        .animation(.easeOut(duration: 0.05), value: audioLevel)
                }
            }
            .offset(y: 45)
        }
        .frame(width: 200, height: 200)
        .onAppear {
            // Start pulse animation
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.25
                pulseOpacity = 0.2
            }
        }
    }
    
    private func audioLevelColor(for ringIndex: Int) -> Color {
        if audioLevel < 0.3 {
            return .green
        } else if audioLevel < 0.6 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func scaleForRing(_ index: Int) -> CGFloat {
        let baseScale = 0.5 + (CGFloat(index) * 0.08)
        let levelScale = CGFloat(audioLevel) * (0.15 + CGFloat(index) * 0.02)
        return baseScale + levelScale
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [8, 14, 20, 24, 20, 14, 8]
        let baseHeight = heights[index]
        let levelMultiplier = 0.5 + CGFloat(audioLevel) * 0.5
        return baseHeight * levelMultiplier
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 100
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview

struct RecordingOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RecordingOverlayView(
                audioLevel: .constant(0.3),
                isRecording: .constant(true)
            )
            .frame(width: 200, height: 200)
            .background(Color.black)
            .previewDisplayName("Low Level")
            
            RecordingOverlayView(
                audioLevel: .constant(0.7),
                isRecording: .constant(true)
            )
            .frame(width: 200, height: 200)
            .background(Color.black)
            .previewDisplayName("High Level")
        }
    }
}
