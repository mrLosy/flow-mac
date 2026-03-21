import SwiftUI
import AppKit
import Combine

/// Floating overlay window showing recording status
class RecordingOverlayWindow: NSObject, ObservableObject {
    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    
    @Published var audioLevel: Float = 0.0
    @Published var isRecording = false
    
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
        if let screenFrame = NSScreen.main?.visibleFrame {
            let windowSize: CGFloat = 200
            let x = screenFrame.midX - windowSize / 2
            let y = screenFrame.midY - windowSize / 2
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderFrontRegardless()
            self?.isRecording = true
        }
    }
    
    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil)
            self?.isRecording = false
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
    @State private var pulseOpacity: Double = 0.5
    
    var body: some View {
        ZStack {
            // Background blur effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(Circle())
            
            // Pulsing ring
            Circle()
                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .animation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Audio level rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        Color.red.opacity(0.3 - Double(index) * 0.1),
                        lineWidth: 2
                    )
                    .scaleEffect(scaleForRing(index))
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
            }
            
            // Center icon
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
            
            // Recording indicator
            VStack {
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                            value: isRecording
                        )
                    
                    Text("Recording...")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 200, height: 200)
        .onAppear {
            pulseScale = 1.2
            pulseOpacity = 0.0
        }
    }
    
    private func scaleForRing(_ index: Int) -> CGFloat {
        let baseScale = 0.6 + (CGFloat(index) * 0.15)
        let levelScale = CGFloat(audioLevel) * 0.3
        return baseScale + levelScale
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
        RecordingOverlayView(
            audioLevel: .constant(0.5),
            isRecording: .constant(true)
        )
        .frame(width: 200, height: 200)
        .background(Color.black)
    }
}
