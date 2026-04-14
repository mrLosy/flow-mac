import CoreGraphics
import Carbon
import AppKit

// MARK: - CGEvent Dispatch & Matching

extension HotkeyManager {

    /// Main event handler — dispatches to toggle or PTT logic
    func handleCGEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DebugLog.log("EV. tap disabled by system — re-enabling")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        if type == .flagsChanged {
            let mods = currentCarbonModifiers(from: event)
            DebugLog.log("EV. flagsChanged mods=\(mods)")
        }

        // Express has top priority, then toggle, then PTT
        if let consumed = handleExpressEvent(event, type: type), consumed { return true }
        if let consumed = handleToggleEvent(event, type: type), consumed { return true }
        if let consumed = handlePTTEvent(event, type: type), consumed { return true }

        return false
    }

    func eventMatchesConfig(_ event: CGEvent, config: HotkeyConfig) -> Bool {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let eventMods = currentCarbonModifiers(from: event)
        return keyCode == config.keyCode && eventMods == config.modifiers
    }

    func currentCarbonModifiers(from event: CGEvent) -> UInt32 {
        let flags = event.flags
        var mods: UInt32 = 0
        if flags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { mods |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        if flags.contains(.maskControl) { mods |= UInt32(controlKey) }
        return mods
    }
}

// MARK: - Express Hotkey

extension HotkeyManager {

    func handleExpressEvent(_ event: CGEvent, type: CGEventType) -> Bool? {
        // Express hotkey disabled if keyCode == 0 and modifiers == 0
        guard expressHotkey.keyCode != 0 || expressHotkey.modifiers != 0 else { return nil }

        guard type == .keyDown else { return nil }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat { return nil }
        guard eventMatchesConfig(event, config: expressHotkey) else { return nil }

        DispatchQueue.main.async { [weak self] in self?.toggleExpressRecording() }
        return true
    }
}

// MARK: - Toggle Hotkey

extension HotkeyManager {

    /// Returns nil if irrelevant, true if consumed, false if passed through
    func handleToggleEvent(_ event: CGEvent, type: CGEventType) -> Bool? {
        if toggleHotkey.keyCode == 0 {
            return handleToggleModifierOnly(event, type: type)
        }

        guard type == .keyDown else { return nil }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat { return nil }
        guard eventMatchesConfig(event, config: toggleHotkey) else { return nil }

        DispatchQueue.main.async { [weak self] in self?.toggleRecording() }
        return true
    }

    private func handleToggleModifierOnly(_ event: CGEvent, type: CGEventType) -> Bool? {
        if type == .keyDown {
            if toggleModOnlyPending { toggleModOnlyKeyWasPressed = true }
            return nil
        }
        guard type == .flagsChanged else { return nil }

        let currentMods = currentCarbonModifiers(from: event)

        if currentMods == toggleHotkey.modifiers {
            toggleModOnlyPending = true
            toggleModOnlyKeyWasPressed = false
        } else if currentMods == 0 && toggleModOnlyPending && !toggleModOnlyKeyWasPressed {
            toggleModOnlyPending = false
            DispatchQueue.main.async { [weak self] in self?.toggleRecording() }
        } else if toggleModOnlyPending && currentMods != 0 && (currentMods & toggleHotkey.modifiers) == currentMods {
            // Partial release of multi-modifier combo — keep pending
        } else {
            toggleModOnlyPending = false
        }

        return false
    }
}

// MARK: - Push-to-Talk Hotkey

extension HotkeyManager {

    func handlePTTEvent(_ event: CGEvent, type: CGEventType) -> Bool? {
        if pttHotkey.keyCode == 0 {
            return handlePTTModifierOnly(event, type: type)
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if type == .keyDown {
            guard eventMatchesConfig(event, config: pttHotkey) else { return nil }
            if isRepeat { return true } // Consume repeats but don't restart

            if !pttActive {
                pttActive = true
                DispatchQueue.main.async { [weak self] in self?.startRecording() }
            }
            return true
        }

        if type == .keyUp {
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == pttHotkey.keyCode && pttActive else { return nil }

            pttActive = false
            DispatchQueue.main.async { [weak self] in self?.stopRecording() }
            return true
        }

        return nil
    }

    private func handlePTTModifierOnly(_ event: CGEvent, type: CGEventType) -> Bool? {
        guard type == .flagsChanged else { return nil }

        let currentMods = currentCarbonModifiers(from: event)
        DebugLog.log("PTT. modOnly check: currentMods=\(currentMods), pttMods=\(pttHotkey.modifiers), pttKeyCode=\(pttHotkey.keyCode), pttActive=\(pttActive)")

        if currentMods == pttHotkey.modifiers && !pttActive {
            DebugLog.log("PTT. MATCH — starting recording")
            pttActive = true
            DispatchQueue.main.async { [weak self] in self?.startRecording() }
        } else if currentMods == 0 && pttActive {
            NSLog("[FlowMac] PTT modifier-only: STOP (released)")
            pttActive = false
            DispatchQueue.main.async { [weak self] in self?.stopRecording() }
        } else if pttActive && currentMods != 0 && (currentMods & pttHotkey.modifiers) == currentMods {
            // Partial release of multi-modifier combo — keep recording
        } else if pttActive {
            NSLog("[FlowMac] PTT modifier-only: STOP (different mods=\(currentMods))")
            pttActive = false
            DispatchQueue.main.async { [weak self] in self?.stopRecording() }
        }

        return false // Never consume flagsChanged
    }
}

// MARK: - NSEvent Fallback Handlers

extension HotkeyManager {

    func handleNSKeyEvent(_ event: NSEvent, isDown: Bool) {
        let keyCode = UInt32(event.keyCode)
        let carbonMods = nsEventToCarbonModifiers(event.modifierFlags)

        if isDown {
            // Cancel modifier-only detection on key press
            if toggleModOnlyPending { toggleModOnlyKeyWasPressed = true }
            if pttModOnlyPending { pttModOnlyKeyWasPressed = true }

            // Express hotkey
            if expressHotkey.keyCode != 0 && keyCode == expressHotkey.keyCode
                && carbonMods == expressHotkey.modifiers && !event.isARepeat {
                DispatchQueue.main.async { [weak self] in self?.toggleExpressRecording() }
                return
            }

            // Toggle hotkey (key + modifiers)
            if toggleHotkey.keyCode != 0 && keyCode == toggleHotkey.keyCode
                && carbonMods == toggleHotkey.modifiers && !event.isARepeat {
                DispatchQueue.main.async { [weak self] in self?.toggleRecording() }
                return
            }

            // PTT hotkey (key down = start)
            if pttHotkey.keyCode != 0 && keyCode == pttHotkey.keyCode
                && carbonMods == pttHotkey.modifiers && !event.isARepeat && !pttActive {
                pttActive = true
                DispatchQueue.main.async { [weak self] in self?.startRecording() }
                return
            }
        } else {
            // PTT key up = stop
            if pttHotkey.keyCode != 0 && keyCode == pttHotkey.keyCode && pttActive {
                pttActive = false
                DispatchQueue.main.async { [weak self] in self?.stopRecording() }
            }
        }
    }

    func handleNSFlagsEvent(_ event: NSEvent) {
        let carbonMods = nsEventToCarbonModifiers(event.modifierFlags)

        // Toggle modifier-only
        if toggleHotkey.keyCode == 0 {
            if carbonMods == toggleHotkey.modifiers {
                toggleModOnlyPending = true
                toggleModOnlyKeyWasPressed = false
            } else if carbonMods == 0 && toggleModOnlyPending && !toggleModOnlyKeyWasPressed {
                toggleModOnlyPending = false
                DispatchQueue.main.async { [weak self] in self?.toggleRecording() }
            } else if toggleModOnlyPending && carbonMods != 0 && (carbonMods & toggleHotkey.modifiers) == carbonMods {
                // Partial release of multi-modifier combo — keep pending
            } else {
                toggleModOnlyPending = false
            }
        }

        // PTT modifier-only
        if pttHotkey.keyCode == 0 {
            if carbonMods == pttHotkey.modifiers && !pttActive {
                NSLog("[FlowMac] PTT modifier-only (NSEvent fallback): START")
                pttActive = true
                DispatchQueue.main.async { [weak self] in self?.startRecording() }
            } else if carbonMods == 0 && pttActive {
                NSLog("[FlowMac] PTT modifier-only (NSEvent fallback): STOP")
                pttActive = false
                DispatchQueue.main.async { [weak self] in self?.stopRecording() }
            } else if pttActive && carbonMods != 0 && (carbonMods & pttHotkey.modifiers) == carbonMods {
                // Partial release of multi-modifier combo — keep recording
            } else if pttActive {
                NSLog("[FlowMac] PTT modifier-only (NSEvent fallback): STOP (different mods)")
                pttActive = false
                DispatchQueue.main.async { [weak self] in self?.stopRecording() }
            }
        }
    }

    func nsEventToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }
}
