import Foundation
import CoreGraphics

/// Recording mode for global hotkeys
enum RecordingMode: String, CaseIterable {
    case toggle
    case pushToTalk
    case express
}

/// Side requirement for a modifier key.
/// Stored as 2 bits inside `HotkeyConfig.modifierSides`.
enum ModifierSide: UInt32 {
    case any = 0    // 00 — any side matches
    case left = 1   // 01 — only left physical key
    case right = 2  // 10 — only right physical key
}

/// Shift positions for each modifier inside `modifierSides` bitfield.
enum ModifierSideSlot {
    static let cmd: UInt32 = 0     // bits 0-1
    static let shift: UInt32 = 2   // bits 2-3
    static let option: UInt32 = 4  // bits 4-5
    static let control: UInt32 = 6 // bits 6-7

    static let mask: UInt32 = 0b11
}

/// Device-specific modifier masks from <IOKit/hidsystem/IOLLEvent.h>.
/// Found in both `NSEvent.modifierFlags.rawValue` and `CGEvent.flags.rawValue`.
enum DeviceModifierMask {
    static let leftControl: UInt64  = 0x00000001
    static let leftShift: UInt64    = 0x00000002
    static let rightShift: UInt64   = 0x00000004
    static let leftCommand: UInt64  = 0x00000008
    static let rightCommand: UInt64 = 0x00000010
    static let leftOption: UInt64   = 0x00000020
    static let rightOption: UInt64  = 0x00000040
    static let rightControl: UInt64 = 0x00002000
}

/// Hotkey key code + modifier pair
struct HotkeyConfig {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier format (side-agnostic)
    var modifierSides: UInt32 = 0 // 2 bits per modifier (see ModifierSideSlot)

    func side(for slot: UInt32) -> ModifierSide {
        let raw = (modifierSides >> slot) & ModifierSideSlot.mask
        return ModifierSide(rawValue: raw) ?? .any
    }

    static func encodeSide(_ side: ModifierSide, at slot: UInt32, into value: UInt32) -> UInt32 {
        let cleared = value & ~(ModifierSideSlot.mask << slot)
        return cleared | (side.rawValue << slot)
    }
}

/// Protocol defining hotkey manager interface
protocol HotkeyManagerProtocol: AnyObject, ObservableObject {
    var isRecording: Bool { get }

    /// Start monitoring for global hotkey events
    func startMonitoring()

    /// Stop monitoring hotkey events
    func stopMonitoring()

    /// Update hotkey configuration for a specific mode
    func updateHotkey(mode: RecordingMode, keyCode: CGKeyCode, modifiers: CGEventFlags)

    /// Get current hotkey configuration for a specific mode
    func getCurrentHotkey(for mode: RecordingMode) -> (keyCode: CGKeyCode, modifiers: CGEventFlags)
}

/// Protocol for hotkey event delegates
protocol HotkeyDelegate: AnyObject {
    func hotkeyDidTrigger()
    func hotkeyDidRelease()
}

/// Errors that can occur during hotkey setup
enum HotkeyError: Error, LocalizedError {
    case accessibilityNotGranted
    case eventTapCreationFailed
    case hotkeyAlreadyRegistered

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permissions required for global hotkeys."
        case .eventTapCreationFailed:
            return "Failed to create event tap for hotkey monitoring."
        case .hotkeyAlreadyRegistered:
            return "Hotkey is already registered by another application."
        }
    }
}
