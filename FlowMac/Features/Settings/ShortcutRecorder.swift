import SwiftUI
import AppKit
import CoreAudio

// MARK: - Audio Device Model

struct AVAudioDevice: Identifiable {
    let id: String
    let name: String
    let objectID: AudioObjectID
}

// MARK: - Shortcut Recorder Bridge

struct ShortcutRecorderView: NSViewRepresentable {
    let mode: RecordingMode
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags

    func makeNSView(context: Context) -> ShortcutRecorder {
        let recorder = ShortcutRecorder()
        recorder.setShortcut(keyCode: keyCode, modifiers: modifiers)
        recorder.onShortcutChanged = { code, mods in
            keyCode = code
            modifiers = mods
            NotificationCenter.default.post(
                name: .hotkeyDidChange,
                object: nil,
                userInfo: ["keyCode": code, "modifiers": mods.rawValue, "mode": mode.rawValue]
            )
        }
        return recorder
    }

    func updateNSView(_ nsView: ShortcutRecorder, context: Context) {
        if !nsView.isRecordingActive {
            nsView.setShortcut(keyCode: keyCode, modifiers: modifiers)
        }
    }
}

// MARK: - Shortcut Recorder NSView

class ShortcutRecorder: NSView {
    var onShortcutChanged: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var isRecordingActive: Bool { isRecording }

    private var currentKeyCode: UInt16 = 49
    private var currentModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var currentKeyDisplay: String = "Space"
    private var isRecording = false

    func setShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        if keyCode == 0 {
            currentKeyDisplay = ""
        } else {
            currentKeyDisplay = Self.displayName(for: keyCode)
        }
        setNeedsDisplay(bounds)
    }
    private var liveModifiers: NSEvent.ModifierFlags = []
    private var keyPressedWhileRecording = false
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var flagsMonitor: Any?
    private var globalFlagsMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bgColor: NSColor
        let borderColor: NSColor

        if isRecording {
            bgColor = NSColor.systemBlue.withAlphaComponent(0.08)
            borderColor = NSColor.systemBlue.withAlphaComponent(0.5)
        } else {
            bgColor = NSColor.controlBackgroundColor
            borderColor = NSColor.separatorColor
        }

        bgColor.setFill()
        borderColor.setStroke()

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        path.fill()
        path.lineWidth = 1
        path.stroke()

        let shortcutText = shortcutString()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.systemBlue : NSColor.labelColor
        ]

        let size = shortcutText.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        shortcutText.draw(at: point, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        liveModifiers = []
        keyPressedWhileRecording = false
        setNeedsDisplay(bounds)

        let handleKey: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isRecording else { return }
            self.keyPressedWhileRecording = true
            _ = self.handleKeyEvent(event)
        }

        let handleFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isRecording else { return }
            let prev = self.liveModifiers
            let curr = event.modifierFlags.intersection([.command, .option, .control, .shift])
            self.liveModifiers = curr
            self.setNeedsDisplay(self.bounds)

            if !prev.isEmpty && curr.isEmpty && !self.keyPressedWhileRecording {
                self.currentKeyCode = 0
                self.currentModifiers = prev
                self.currentKeyDisplay = Self.modifierOnlyDisplayName(prev)
                self.onShortcutChanged?(0, prev)
                self.stopRecording()
            }
        }

        // Local monitors: when Settings window is focused
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKey(event)
            return nil
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            handleFlags(event)
            return event
        }

        // Global monitors: when another window is focused (Cmd+key bypasses local)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handleKey)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: handleFlags)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Esc cancels
        if event.keyCode == 53 && mods.isEmpty {
            stopRecording()
            return true
        }

        // Ignore modifier-only keys (keyCodes 54-63)
        if event.keyCode >= 54 && event.keyCode <= 63 {
            return true
        }

        currentKeyCode = event.keyCode
        currentModifiers = mods
        currentKeyDisplay = Self.displayName(for: event.keyCode, event: event)
        onShortcutChanged?(currentKeyCode, currentModifiers)
        stopRecording()
        return true
    }

    private func stopRecording() {
        isRecording = false
        liveModifiers = []
        removeAllMonitors()
        setNeedsDisplay(bounds)
    }

    private func removeAllMonitors() {
        for monitor in [keyMonitor, globalKeyMonitor, flagsMonitor, globalFlagsMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        globalKeyMonitor = nil
        flagsMonitor = nil
        globalFlagsMonitor = nil
    }

    deinit {
        removeAllMonitors()
    }

    // MARK: - Display

    private func shortcutString() -> String {
        if isRecording {
            if liveModifiers.isEmpty {
                return "Press shortcut..."
            }
            var parts: [String] = []
            if liveModifiers.contains(.command) { parts.append("⌘") }
            if liveModifiers.contains(.option) { parts.append("⌥") }
            if liveModifiers.contains(.control) { parts.append("⌃") }
            if liveModifiers.contains(.shift) { parts.append("⇧") }
            parts.append("+ key")
            return parts.joined(separator: "")
        }

        var parts: [String] = []
        if currentModifiers.contains(.command) { parts.append("⌘") }
        if currentModifiers.contains(.option) { parts.append("⌥") }
        if currentModifiers.contains(.control) { parts.append("⌃") }
        if currentModifiers.contains(.shift) { parts.append("⇧") }
        // keyCode == 0 means modifier-only shortcut
        if currentKeyCode != 0 {
            parts.append(currentKeyDisplay)
        }
        return parts.joined(separator: "")
    }

    static func modifierOnlyDisplayName(_ mods: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if mods.contains(.command) { parts.append("⌘") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.shift) { parts.append("⇧") }
        return parts.joined()
    }

    static func displayName(for keyCode: UInt16, event: NSEvent? = nil) -> String {
        // Special keys with standard macOS symbols
        let specialKeys: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
            53: "⎋", 71: "⌧", 76: "⌅",
            115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            // F-keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15",
        ]

        if let name = specialKeys[keyCode] { return name }

        // Use charactersIgnoringModifiers from the event for real keyboard layout
        if let chars = event?.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }

        // Fallback: derive from keyCode for common keys
        return "Key\(keyCode)"
    }
}
