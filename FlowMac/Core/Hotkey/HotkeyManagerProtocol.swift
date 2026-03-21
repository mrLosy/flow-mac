import Foundation
import CoreGraphics

/// Protocol defining hotkey manager interface
protocol HotkeyManagerProtocol: AnyObject, ObservableObject {
    var isRecording: Bool { get }
    
    /// Start monitoring for global hotkey events
    func startMonitoring()
    
    /// Stop monitoring hotkey events
    func stopMonitoring()
    
    /// Update hotkey configuration
    /// - Parameters:
    ///   - keyCode: Virtual key code
    ///   - modifiers: Modifier flags (Command, Option, Control, Shift)
    func updateHotkey(keyCode: CGKeyCode, modifiers: CGEventFlags)
    
    /// Get current hotkey configuration
    /// - Returns: Tuple of key code and modifiers
    func getCurrentHotkey() -> (keyCode: CGKeyCode, modifiers: CGEventFlags)
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
