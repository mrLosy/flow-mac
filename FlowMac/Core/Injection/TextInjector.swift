import Foundation
import Carbon
import AppKit
import CoreGraphics

/// Injects text into the active text field using CGEvent, Accessibility API, and Pasteboard fallback
class TextInjector: NSObject, ObservableObject, TextInjectionServiceProtocol {
    
    @Published var lastInjectedText = ""
    weak var injectionDelegate: TextInjectionDelegate?
    
    /// Insert text into the currently focused text field with Unicode support
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Method 1: Use Accessibility API (most reliable for native apps)
        if insertViaAccessibility(text) {
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
            return
        }
        
        // Method 2: Use CGEvent with Unicode (good for most apps)
        if insertViaCGEventUnicode(text) {
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
            return
        }
        
        // Method 3: Fall back to pasteboard (works everywhere but modifies clipboard)
        if insertViaPasteboard(text) {
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
        } else {
            injectionDelegate?.textInjectionDidFail(with: .insertionFailed)
            showFailureNotification()
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
        
        let axElement = element as! AXUIElement
        
        // Try to get current value and append (for some text fields)
        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)
        
        var finalText = text
        if valueResult == .success, let existingText = currentValue as? String {
            // Check if we should append or replace
            // For now, we just set the value directly
            finalText = existingText + text
        }
        
        // Try to set value directly
        let axResult = AXUIElementSetAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            finalText as CFTypeRef
        )
        
        if axResult == .success {
            // Post notification that value changed
            AXUIElementPerformAction(axElement, kAXConfirmAction as CFString)
            return true
        }
        
        return false
    }
    
    // MARK: - Method 2: CGEvent with Unicode Support
    
    private func insertViaCGEventUnicode(_ text: String) -> Bool {
        guard NSWorkspace.shared.frontmostApplication != nil else {
            return false
        }
        
        // Use CGEventKeyboardSetUnicodeString for proper Unicode support
        for char in text {
            postUnicodeCharacter(char)
        }
        
        return true
    }
    
    private func postUnicodeCharacter(_ character: Character) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Convert character to UTF-16
        let utf16 = String(character).utf16
        let length = utf16.count
        
        guard length > 0 else { return }
        
        // Allocate buffer for unicode string
        let buffer = UnsafeMutablePointer<UniChar>.allocate(capacity: length)
        defer { buffer.deallocate() }
        
        for (index, codeUnit) in utf16.enumerated() {
            buffer[index] = codeUnit
        }
        
        // Create key event with unicode string
        if let keyEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            keyEvent.keyboardSetUnicodeString(stringLength: length, unicodeString: buffer)
            keyEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
        
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            keyUp.keyboardSetUnicodeString(stringLength: length, unicodeString: buffer)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
    
    // MARK: - Method 3: Pasteboard Fallback
    
    private func insertViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Save current pasteboard contents
        let oldTypes = pasteboard.types
        var oldContents: [NSPasteboard.PasteboardType: Any] = [:]
        
        for type in oldTypes ?? [] {
            if let data = pasteboard.data(forType: type) {
                oldContents[type] = data
            }
        }
        
        let oldString = pasteboard.string(forType: .string)
        
        // Set new content
        pasteboard.clearContents()
        
        // Set multiple representations for better compatibility
        guard pasteboard.setString(text, forType: .string) else {
            // Restore old contents on failure
            restorePasteboard(oldContents, oldString: oldString)
            return false
        }
        
        // Also set plain text format
        if let data = text.data(using: .utf8) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        }
        
        // Simulate Cmd+V
        postPasteCommand()
        
        // Restore original pasteboard content after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.restorePasteboard(oldContents, oldString: oldString)
        }
        
        return true
    }
    
    private func restorePasteboard(_ contents: [NSPasteboard.PasteboardType: Any], oldString: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Try to restore string first
        if let oldString = oldString {
            pasteboard.setString(oldString, forType: .string)
        }
        
        // Restore other contents
        for (type, data) in contents {
            if let data = data as? Data {
                pasteboard.setData(data, forType: type)
            }
        }
    }
    
    private func postPasteCommand() {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        vDown?.post(tap: .cgAnnotatedSessionEventTap)
        vUp?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
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
        
        // Open System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Show failure notification
    private func showFailureNotification() {
        let notification = UNMutableNotificationContent()
        notification.title = "Flow Mac"
        notification.body = "Failed to insert text. Please check accessibility permissions."
        notification.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notification,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    /// Type a single key (for special keys like Return, Tab, etc.)
    func typeKey(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        if !modifiers.isEmpty {
            keyDown?.flags = modifiers
            keyUp?.flags = modifiers
        }
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
    
    /// Type special keys after text insertion (e.g., Return to confirm)
    func typeReturn() {
        typeKey(keyCode: 36) // Return key
    }
    
    func typeTab() {
        typeKey(keyCode: 48) // Tab key
    }
    
    func typeEscape() {
        typeKey(keyCode: 53) // Escape key
    }
}

// MARK: - CGEvent Unicode Support Extension

extension CGEvent {
    func keyboardSetUnicodeString(stringLength: Int, unicodeString: UnsafePointer<UniChar>) {
        // Use the private API for setting unicode strings
        // This is the same mechanism used by Apple's Keyboard Viewer
        let sel = NSSelectorFromString("setUnicodeString:length:")
        if self.responds(to: sel) {
            self.perform(sel, with: unicodeString, with: stringLength as NSNumber)
        }
    }
}

// MARK: - Common Key Codes

enum KeyCode: CGKeyCode {
    case returnKey = 36
    case tab = 48
    case space = 49
    case delete = 51
    case escape = 53
    case command = 55
    case shift = 56
    case option = 58
    case control = 59
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126
}
