import Foundation

/// Protocol defining text injection service interface
protocol TextInjectionServiceProtocol: AnyObject, ObservableObject {
    var lastInjectedText: String { get }
    
    /// Insert text into the currently focused text field, or copy to clipboard if no field is focused
    @discardableResult
    func insertText(_ text: String) -> TextInsertionResult
    
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

/// Result of text insertion attempt
enum TextInsertionResult {
    case injected           // Текст вставлен в активное текстовое поле
    case copiedToClipboard  // Нет текстового поля — скопировано в буфер обмена
    case failed(TextInjectionError)
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
