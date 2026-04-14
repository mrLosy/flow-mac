import Foundation
import CoreGraphics

/// Recording mode for global hotkeys
enum RecordingMode: String, CaseIterable {
    case toggle
    case pushToTalk
    case express
}

/// Hotkey key code + modifier pair
struct HotkeyConfig {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier format
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
