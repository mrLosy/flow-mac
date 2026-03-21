import Foundation

/// Protocol defining text injection service interface
protocol TextInjectionServiceProtocol: AnyObject, ObservableObject {
    var lastInjectedText: String { get }
    
    /// Insert text into the currently focused text field
    /// - Parameter text: Text to insert
    func insertText(_ text: String)
    
    /// Check if accessibility permissions are granted
    /// - Returns: True if accessibility is enabled
    func checkAccessibilityPermissions() -> Bool
    
    /// Request accessibility permissions from user
    func requestAccessibilityPermissions()
}

/// Protocol for text injection delegates
protocol TextInjectionDelegate: AnyObject {
    func textInjectionDidSucceed(_ text: String)
    func textInjectionDidFail(with error: TextInjectionError)
}

/// Errors that can occur during text injection
enum TextInjectionError: Error, LocalizedError {
    case accessibilityNotGranted
    case noFocusedElement
    case insertionFailed
    case pasteboardError
    
    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permissions not granted. Please enable in System Settings."
        case .noFocusedElement:
            return "No text field is currently focused."
        case .insertionFailed:
            return "Failed to insert text into the focused field."
        case .pasteboardError:
            return "Failed to use pasteboard for text insertion."
        }
    }
}
