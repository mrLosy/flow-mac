import SwiftUI
import AppKit
import Combine

private let kExpandedWidth: CGFloat = 128
private let kExpandedHeight: CGFloat = 36
private let kIdleWidth: CGFloat = 40
private let kIdleHeight: CGFloat = 4
private let kWindowPadding: CGFloat = 24
private let kWindowWidth: CGFloat = kExpandedWidth + kWindowPadding * 2
private let kWindowHeight: CGFloat = kExpandedHeight + kWindowPadding * 2

/// Always-visible bottom-center pill: idle = tiny bar, recording = expanded with waveform
@MainActor
class RecordingOverlayWindow: NSObject, ObservableObject {
    private var window: NSWindow?
    private var screenTrackingTimer: Timer?
    private var lastScreenFrame: NSRect = .zero

    @Published var audioLevel: Float = 0.0
    @Published var isRecording = false {
        didSet {
            if isRecording {
                startScreenTracking()
            } else {
                stopScreenTracking()
            }
        }
    }

    override init() {
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let hosting = NSHostingView(rootView: RecordingOverlayView(overlay: self))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: kWindowWidth, height: kWindowHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = hosting
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .statusBar
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window = win
        positionWindow()
        win.orderFrontRegardless()
    }

    private func positionWindow() {
        guard let screen = activeScreen() else { return }
        let sf = screen.frame
        let x = sf.midX - kWindowWidth / 2
        let y = sf.minY + 20
        window?.setFrame(NSRect(x: x, y: y, width: kWindowWidth, height: kWindowHeight), display: false)
        lastScreenFrame = sf
    }

    private func startScreenTracking() {
        guard screenTrackingTimer == nil else { return }
        screenTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let screen = self.activeScreen() else { return }
                if screen.frame != self.lastScreenFrame {
                    self.positionWindow()
                }
            }
        }
    }

    private func stopScreenTracking() {
        screenTrackingTimer?.invalidate()
        screenTrackingTimer = nil
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    func show() {
        positionWindow()
        isRecording = true
    }

    func hide() {
        isRecording = false
        audioLevel = 0.0
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = level
    }

    deinit {
        screenTrackingTimer?.invalidate()
    }
}

// MARK: - SwiftUI Overlay View

struct RecordingOverlayView: View {
    @ObservedObject var overlay: RecordingOverlayWindow
    @State private var smoothedLevel: CGFloat = 0

    private var pillWidth: CGFloat {
        overlay.isRecording ? kExpandedWidth : kIdleWidth
    }

    private var pillHeight: CGFloat {
        overlay.isRecording ? kExpandedHeight : kIdleHeight
    }

    private var normalizedLevel: CGFloat {
        CGFloat(overlay.audioLevel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            ZStack {
                if overlay.isRecording {
                    subtleGlow
                        .transition(.opacity)
                }

                pillBackground

                if overlay.isRecording {
                    gradientBorder
                        .transition(.opacity.animation(.easeIn(duration: 0.25).delay(0.15)))

                    waveformBars
                        .transition(.opacity.animation(.easeIn(duration: 0.25).delay(0.15)))
                }
            }
            .frame(width: pillWidth, height: pillHeight)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: overlay.isRecording)
            .padding(.bottom, kWindowPadding)
        }
        .frame(width: kWindowWidth, height: kWindowHeight)
    }

    // MARK: - Subtle Glow

    private var subtleGlow: some View {
        Capsule()
            .fill(Color.white.opacity(0.05 + smoothedLevel * 0.1))
            .frame(width: pillWidth + 8, height: pillHeight + 8)
            .blur(radius: 8 + smoothedLevel * 4)
            .animation(.easeOut(duration: 0.1), value: smoothedLevel)
    }

    // MARK: - Background

    private var pillBackground: some View {
        Capsule()
            .fill(overlay.isRecording
                  ? Color.black.opacity(0.75)
                  : Color.white.opacity(0.15))
    }

    // MARK: - Rotating Gradient Border

    private var gradientBorder: some View {
        TimelineView(.animation) { timeline in
            let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 90)
            let lineWidth = 2.0 + smoothedLevel * 0.5

            Capsule()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.8),
                            .cyan.opacity(0.5),
                            .white.opacity(0.15),
                            .clear,
                            .clear,
                            .cyan.opacity(0.3),
                            .white.opacity(0.8)
                        ]),
                        center: .center,
                        angle: angle
                    ),
                    lineWidth: lineWidth
                )
        }
    }

    // MARK: - Waveform Bars

    private var waveformBars: some View {
        TimelineView(.animation) { timeline in
            let target = normalizedLevel
            let newSmoothed = smoothedLevel + (target - smoothedLevel) * 0.15
            let envelope: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 3, height: 4 + envelope[index] * newSmoothed * 16)
                }
            }
            .onChange(of: timeline.date) { _ in
                smoothedLevel = smoothedLevel + (normalizedLevel - smoothedLevel) * 0.15
            }
        }
    }
}
