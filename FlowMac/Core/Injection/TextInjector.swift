import Foundation
import Carbon
import AppKit
import CoreGraphics

/// Injects text into the active text field using CGEvent, Accessibility API, and Pasteboard fallback
class TextInjector: NSObject, ObservableObject, TextInjectionServiceProtocol {
    
    @Published var lastInjectedText = ""
    weak var injectionDelegate: TextInjectionDelegate?
    
    /// Insert text into the currently focused text field, or copy to clipboard if no field is focused
    @discardableResult
    func insertText(_ text: String) -> TextInsertionResult {
        guard !text.isEmpty else { return .failed(.insertionFailed) }

        let hasField = hasFocusedTextInput()

        if hasField {
            // Есть активное текстовое поле — пробуем нативные методы
            if insertViaAccessibility(text) {
                lastInjectedText = text
                injectionDelegate?.textInjectionDidSucceed(text)
                return .injected
            }

            if insertViaCGEventUnicode(text) {
                lastInjectedText = text
                injectionDelegate?.textInjectionDidSucceed(text)
                return .injected
            }
        }

        // Есть активное приложение — вставляем через Cmd+V (Electron, web-apps и т.д.)
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier.map({ !$0.hasPrefix("com.apple.finder") }) ?? false {
            pasteViaClipboard(text)
            lastInjectedText = text
            injectionDelegate?.textInjectionDidSucceed(text)
            return .injected
        }

        // Нет активного приложения / Finder — просто копируем в буфер
        copyToClipboard(text)
        lastInjectedText = text
        showClipboardNotification()
        return .copiedToClipboard
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

        guard let axElement = element as? AXUIElement else { return false }

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
            keyEvent.keyboardSetUnicodeString(stringLength: Int(length), unicodeString: buffer)
            keyEvent.post(tap: .cgAnnotatedSessionEventTap)
        }
        
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            keyUp.keyboardSetUnicodeString(stringLength: Int(length), unicodeString: buffer)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
    
    // MARK: - Focus Detection

    /// Проверяет, есть ли фокус на текстовом поле ввода
    private func hasFocusedTextInput() -> Bool {
        guard checkAccessibilityPermissions() else {
            NSLog("[FlowMac] hasFocusedTextInput: no accessibility permissions")
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?

        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let element = focusedElement else {
            NSLog("[FlowMac] hasFocusedTextInput: no focused element (result=\(result.rawValue))")
            return false
        }

        guard let axElement = element as? AXUIElement else { return false }

        // Проверяем роль элемента
        var roleValue: AnyObject?
        let roleResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXRoleAttribute as CFString,
            &roleValue
        )

        let role = (roleResult == .success) ? (roleValue as? String) : nil

        // Проверяем subrole
        var subroleValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = subroleValue as? String

        NSLog("[FlowMac] hasFocusedTextInput: role=\(role ?? "nil"), subrole=\(subrole ?? "nil")")

        if let role = role {
            let textInputRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
            ]
            if textInputRoles.contains(role) {
                return true
            }

            // Web-based editors: contenteditable divs appear as AXWebArea or AXGroup
            if role == "AXWebArea" || role == "AXGroup" {
                // Проверяем, можно ли установить значение — признак редактируемого элемента
                var isSettable: DarwinBoolean = false
                let settableResult = AXUIElementIsAttributeSettable(
                    axElement,
                    kAXValueAttribute as CFString,
                    &isSettable
                )
                if settableResult == .success && isSettable.boolValue {
                    NSLog("[FlowMac] hasFocusedTextInput: web area/group with settable value")
                    return true
                }
            }
        }

        // Проверяем subrole для edge cases
        if let subrole = subrole,
           subrole == "AXSearchField" || subrole == "AXSecureTextField" {
            return true
        }

        // Финальная эвристика: если значение элемента можно установить — он принимает текст
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            axElement,
            kAXValueAttribute as CFString,
            &isSettable
        )
        if settableResult == .success && isSettable.boolValue {
            NSLog("[FlowMac] hasFocusedTextInput: settable value attribute — treating as text input")
            return true
        }

        NSLog("[FlowMac] hasFocusedTextInput: not a text input")
        return false
    }

    // MARK: - Clipboard

    /// Копирует текст в буфер обмена и симулирует Cmd+V для вставки
    private func pasteViaClipboard(_ text: String) {
        copyToClipboard(text)

        // Используем .hidSystemState и .cghidEventTap чтобы обойти наш CGEventTap
        let source = CGEventSource(stateID: .hidSystemState)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    /// Просто копирует текст в буфер обмена (без вставки)
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Helper Methods
    
    /// Check if accessibility permissions are granted
    func checkAccessibilityPermissions() -> Bool {
        // Стандартная проверка
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        if AXIsProcessTrustedWithOptions(options as CFDictionary) {
            return true
        }

        // Fallback для debug-билдов: пробуем создать тестовый event tap
        let testTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        guard let tap = testTap else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
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
    
    /// Show notification that text was copied to clipboard
    private func showClipboardNotification() {
        NotificationService.shared.notifyClipboard()
    }

    /// Show failure notification
    private func showFailureNotification() {
        NotificationService.shared.notifyInjectionError("Не удалось вставить текст. Проверьте права Accessibility.")
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
