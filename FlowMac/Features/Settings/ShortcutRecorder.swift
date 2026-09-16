import SwiftUI
import AppKit
import CoreAudio
import Carbon

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
    @Binding var modifierSides: UInt32

    func makeNSView(context: Context) -> ShortcutRecorder {
        let recorder = ShortcutRecorder()
        recorder.setShortcut(keyCode: keyCode, modifiers: modifiers, modifierSides: modifierSides)
        recorder.onShortcutChanged = { code, mods, sides in
            keyCode = code
            modifiers = mods
            modifierSides = sides
            NotificationCenter.default.post(
                name: .hotkeyDidChange,
                object: nil,
                userInfo: [
                    "keyCode": code,
                    "modifiers": mods.rawValue,
                    "modifierSides": sides,
                    "mode": mode.rawValue,
                ]
            )
        }
        return recorder
    }

    func updateNSView(_ nsView: ShortcutRecorder, context: Context) {
        if !nsView.isRecordingActive {
            nsView.setShortcut(keyCode: keyCode, modifiers: modifiers, modifierSides: modifierSides)
        }
    }
}

// MARK: - Shortcut Recorder NSView

class ShortcutRecorder: NSView {
    var onShortcutChanged: ((UInt16, NSEvent.ModifierFlags, UInt32) -> Void)?
    var isRecordingActive: Bool { isRecording }

    private var currentKeyCode: UInt16 = 49
    private var currentModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var currentModifierSides: UInt32 = 0
    private var currentKeyDisplay: String = "Space"
    private var isRecording = false

    func setShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, modifierSides: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        currentModifierSides = modifierSides
        if keyCode == 0 {
            currentKeyDisplay = ""
        } else {
            currentKeyDisplay = Self.displayName(for: keyCode)
        }
        setNeedsDisplay(bounds)
    }

    // Recording session state
    private var liveModifiers: NSEvent.ModifierFlags = []
    private var maxModifiersSeen: NSEvent.ModifierFlags = []
    private var sidesSeen: UInt32 = 0
    private var keyPressedWhileRecording = false
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var flagsMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

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
            cancelRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        liveModifiers = []
        maxModifiersSeen = []
        sidesSeen = 0
        keyPressedWhileRecording = false
        // The global hotkeys must not fire while we capture their replacement.
        HotkeyManager.sharedManager?.isCapturingShortcut = true
        setNeedsDisplay(bounds)

        if let window {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.cancelRecording()
            }
        }

        let handleKey: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isRecording else { return }
            self.handleKeyEvent(event)
        }

        let handleFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isRecording else { return }
            self.handleFlagsEvent(event)
        }

        // Local monitors: when Settings window is focused
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKey(event)
            return nil
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            handleFlags(event)
            return nil
        }

        // Global monitors: when another window is focused (Cmd+key bypasses local)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handleKey)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: handleFlags)
    }

    private func handleFlagsEvent(_ event: NSEvent) {
        let curr = event.modifierFlags.intersection([.command, .option, .control, .shift])
        liveModifiers = curr

        if !curr.isEmpty {
            maxModifiersSeen.formUnion(curr)
            sidesSeen = Self.accumulateSides(
                fromRawFlags: UInt64(event.modifierFlags.rawValue),
                mods: curr,
                into: sidesSeen
            )
            setNeedsDisplay(bounds)
            return
        }

        // Every modifier is up again. If a regular key was pressed in between, that combo
        // has already been committed; otherwise the user meant a modifier-only shortcut.
        // Committing on release (rather than after a hold timeout) keeps it deterministic:
        // press the combo, let go, done.
        guard !keyPressedWhileRecording, !maxModifiersSeen.isEmpty else {
            setNeedsDisplay(bounds)
            return
        }
        commit(keyCode: 0, modifiers: maxModifiersSeen, sides: sidesSeen)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Physical modifier keycodes (54-63) shouldn't arrive via .keyDown on macOS,
        // but guard anyway — they'd confuse the combo commit.
        if event.keyCode >= 54 && event.keyCode <= 63 {
            return
        }

        // Esc with no modifiers cancels recording
        if event.keyCode == 53 && maxModifiersSeen.isEmpty && liveModifiers.isEmpty {
            cancelRecording()
            return
        }

        let eventMods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let finalMods = maxModifiersSeen.union(eventMods)

        // A bare letter or digit as a global hotkey would swallow that key everywhere,
        // so ignore it and keep waiting. Function keys are fine on their own.
        guard !finalMods.isEmpty || Self.isStandaloneKey(event.keyCode) else { return }

        keyPressedWhileRecording = true
        let finalSides = Self.accumulateSides(
            fromRawFlags: UInt64(event.modifierFlags.rawValue),
            mods: eventMods,
            into: sidesSeen
        )

        let displayCode = event.keyCode
        currentKeyDisplay = Self.displayName(for: displayCode, event: event)
        commit(keyCode: displayCode, modifiers: finalMods, sides: finalSides)
    }

    private func commit(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, sides: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        currentModifierSides = sides
        if keyCode == 0 {
            currentKeyDisplay = Self.modifierOnlyDisplayName(modifiers, sides: sides)
        }
        stopRecording()
        onShortcutChanged?(keyCode, modifiers, sides)
    }

    private func cancelRecording() {
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        liveModifiers = []
        maxModifiersSeen = []
        sidesSeen = 0
        keyPressedWhileRecording = false
        removeAllMonitors()
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        HotkeyManager.sharedManager?.isCapturingShortcut = false
        setNeedsDisplay(bounds)
    }

    /// Keys that carry no meaning while typing, so they are safe to bind on their own.
    private static func isStandaloneKey(_ keyCode: UInt16) -> Bool {
        let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113]
        return functionKeys.contains(keyCode)
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
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
        // Closing Settings mid-capture must not leave the hotkeys muted.
        if isRecording {
            HotkeyManager.sharedManager?.isCapturingShortcut = false
        }
    }

    // MARK: - Side Extraction

    /// Updates `existing` with side info for each modifier currently present in `mods`.
    /// Once a side has been recorded for a modifier (left/right), it is NOT overwritten —
    /// the first physical side seen in the session wins. This prevents accidental
    /// flipping when a subsequent event happens to have different side bits set.
    static func accumulateSides(fromRawFlags rawFlags: UInt64, mods: NSEvent.ModifierFlags, into existing: UInt32) -> UInt32 {
        var result = existing

        func updateSlot(modPresent: Bool, slot: UInt32, leftMask: UInt64, rightMask: UInt64) {
            guard modPresent else { return }
            let currentSide = ModifierSide(rawValue: (result >> slot) & ModifierSideSlot.mask) ?? .any
            guard currentSide == .any else { return } // already recorded — keep it

            let hasLeft = (rawFlags & leftMask) != 0
            let hasRight = (rawFlags & rightMask) != 0
            let side: ModifierSide
            if hasLeft && !hasRight { side = .left }
            else if hasRight && !hasLeft { side = .right }
            else { side = .any } // both or neither → no info; leave as any
            if side != .any {
                result = HotkeyConfig.encodeSide(side, at: slot, into: result)
            }
        }

        updateSlot(modPresent: mods.contains(.command), slot: ModifierSideSlot.cmd,
                   leftMask: DeviceModifierMask.leftCommand, rightMask: DeviceModifierMask.rightCommand)
        updateSlot(modPresent: mods.contains(.shift), slot: ModifierSideSlot.shift,
                   leftMask: DeviceModifierMask.leftShift, rightMask: DeviceModifierMask.rightShift)
        updateSlot(modPresent: mods.contains(.option), slot: ModifierSideSlot.option,
                   leftMask: DeviceModifierMask.leftOption, rightMask: DeviceModifierMask.rightOption)
        updateSlot(modPresent: mods.contains(.control), slot: ModifierSideSlot.control,
                   leftMask: DeviceModifierMask.leftControl, rightMask: DeviceModifierMask.rightControl)

        return result
    }

    // MARK: - Display

    private func shortcutString() -> String {
        if isRecording {
            if liveModifiers.isEmpty && maxModifiersSeen.isEmpty {
                return "Press shortcut..."
            }
            let snapshot = maxModifiersSeen.union(liveModifiers)
            var text = Self.modifierOnlyDisplayName(snapshot, sides: sidesSeen)
            if text.isEmpty { text = "Press shortcut..." }
            else { text += "…" }
            return text
        }

        let modsPart = Self.modifierOnlyDisplayName(currentModifiers, sides: currentModifierSides)
        // keyCode == 0 means modifier-only shortcut
        if currentKeyCode == 0 {
            return modsPart
        }
        if modsPart.isEmpty {
            return currentKeyDisplay
        }
        return modsPart + currentKeyDisplay
    }

    static func modifierOnlyDisplayName(_ mods: NSEvent.ModifierFlags, sides: UInt32 = 0) -> String {
        var parts: [String] = []
        if mods.contains(.command) {
            parts.append("⌘" + sideSuffix(for: ModifierSideSlot.cmd, sides: sides))
        }
        if mods.contains(.option) {
            parts.append("⌥" + sideSuffix(for: ModifierSideSlot.option, sides: sides))
        }
        if mods.contains(.control) {
            parts.append("⌃" + sideSuffix(for: ModifierSideSlot.control, sides: sides))
        }
        if mods.contains(.shift) {
            parts.append("⇧" + sideSuffix(for: ModifierSideSlot.shift, sides: sides))
        }
        return parts.joined()
    }

    private static func sideSuffix(for slot: UInt32, sides: UInt32) -> String {
        let side = ModifierSide(rawValue: (sides >> slot) & ModifierSideSlot.mask) ?? .any
        switch side {
        case .left: return "L"
        case .right: return "R"
        case .any: return ""
        }
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
