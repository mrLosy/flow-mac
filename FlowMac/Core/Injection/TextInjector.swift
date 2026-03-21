import Foundation
import Carbon
import AppKit

/// Injects text into the active text field using CGEvent and Accessibility API
class TextInjector: NSObject, ObservableObject, TextInjectionServiceProtocol {
    
    @Published var lastInjectedText = ""
    weak var injectionDelegate: TextInjectionDelegate?
    
    /// Insert text into the currently focused text field
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Method 1: Use Accessibility API (most reliable)
        if insertViaAccessibility(text) {
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
            return
        }
        
        // Method 2: Use CGEvent keystroke simulation
        if insertViaCGEvent(text) {
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
            return
        }
        
        // Method 3: Fall back to pasteboard
        if insertViaPasteboard(text) {
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
        } else {
            injectionDelegate?.textInjectionDidFail(with: .insertionFailed)
        }
    }
    
    // MARK: - Method 1: Accessibility API
    
    private func insertViaAccessibility(_ text: String) -> Bool {
        guard checkAccessibilityPermissions() else { return false }
        
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return false
        }
        
        // Check if element supports text input
        var supportedActions: CFArray?
        AXUIElementCopyActionNames(element as! AXUIElement, &supportedActions)
        
        // Try to set value directly
        let axResult = AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        
        return axResult == .success
    }
    
    // MARK: - Method 2: CGEvent Keystroke Simulation
    
    private func insertViaCGEvent(_ text: String) -> Bool {
        // Get the current foreground app
        guard NSWorkspace.shared.frontmostApplication != nil else {
            return false
        }
        
        // Convert text to keystrokes
        for character in text {
            if let keyEvent = createKeyEvent(character: character) {
                keyEvent.post(tap: .cgSessionEventTap)
            }
        }
        
        return true
    }
    
    private func createKeyEvent(character: Character) -> CGEvent? {
        // Map character to key code and modifiers
        guard let (keyCode, shift) = characterToKeyCode(character) else {
            return nil
        }
        
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Key down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        if shift {
            keyDown?.flags = .maskShift
        }
        
        // Key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        if shift {
            keyUp?.flags = .maskShift
        }
        
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
        
        return keyDown
    }
    
    private func characterToKeyCode(_ character: Character) -> (CGKeyCode, Bool)? {
        // Basic character mapping
        let char = String(character)
        let lower = char.lowercased()
        
        // Letters
        if lower >= "a" && lower <= "z" {
            let keyCode: CGKeyCode = CGKeyCode(lower.first!.asciiValue! - 97 + 0)
            let needsShift = char != lower
            return (keyCode, needsShift)
        }
        
        // Numbers
        if char >= "0" && char <= "9" {
            let keyCode: CGKeyCode = CGKeyCode(char.first!.asciiValue! - 48 + 29)
            return (keyCode, false)
        }
        
        // Special characters (simplified mapping)
        let specialChars: [String: (CGKeyCode, Bool)] = [
            " ": (49, false),      // Space
            "\n": (36, false),     // Return
            "\t": (48, false),     // Tab
            ".": (47, false),      // Period
            ",": (43, false),      // Comma
            ";": (41, false),      // Semicolon
            "=": (24, false),      // Equals
            "-": (27, false),      // Minus
            "/": (44, false),      // Slash
            "'": (39, false),      // Quote
            "[": (33, false),      // Left bracket
            "]": (30, false),      // Right bracket
            "\\": (42, false),     // Backslash
            "`": (50, false),      // Grave
        ]
        
        return specialChars[char]
    }
    
    // MARK: - Method 3: Pasteboard Fallback
    
    private func insertViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Save current pasteboard contents
        let oldString = pasteboard.string(forType: .string)
        
        // Set new content
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return false
        }
        
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)  // Command
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)      // V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cgSessionEventTap)
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)
        cmdUp?.post(tap: .cgSessionEventTap)
        
        // Restore original pasteboard content after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let oldString = oldString {
                pasteboard.setString(oldString, forType: .string)
            }
        }
        
        return true
    }
    
    // MARK: - Helper Methods
    
    /// Check if accessibility permissions are granted
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Request accessibility permissions
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Open System Preferences
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
