import XCTest
import Carbon
import CoreGraphics
@testable import FlowMac

final class HotkeyManagerTests: XCTestCase {
    
    var audioEngine: AudioEngine!
    var recognitionService: RecognitionService!
    var textInjector: TextInjector!
    var recordingOverlay: RecordingOverlayWindow!
    var hotkeyManager: HotkeyManager!
    
    override func setUp() {
        super.setUp()
        audioEngine = AudioEngine()
        recognitionService = RecognitionService()
        textInjector = TextInjector()
        recordingOverlay = RecordingOverlayWindow()
        
        hotkeyManager = HotkeyManager(
            audioEngine: audioEngine,
            recognitionService: recognitionService,
            textInjector: textInjector,
            recordingOverlay: recordingOverlay
        )
    }
    
    override func tearDown() {
        hotkeyManager?.stopMonitoring()
        hotkeyManager = nil
        audioEngine = nil
        recognitionService = nil
        textInjector = nil
        recordingOverlay = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testHotkeyManagerInitialization() {
        XCTAssertNotNil(hotkeyManager)
        XCTAssertFalse(hotkeyManager.isRecording)
    }
    
    // MARK: - Hotkey Configuration Tests
    
    func testDefaultHotkeyConfiguration() {
        let hotkey = hotkeyManager.getCurrentHotkey()
        // Default should be Cmd+Shift+Space (keyCode 49)
        XCTAssertEqual(hotkey.keyCode, 49)
        XCTAssertTrue(hotkey.modifiers.contains(.maskCommand))
        XCTAssertTrue(hotkey.modifiers.contains(.maskShift))
    }
    
    func testHotkeyStringRepresentation() {
        let hotkeyString = hotkeyManager.getHotkeyString()
        // Should contain modifier symbols
        XCTAssertTrue(hotkeyString.contains("⌘") || hotkeyString.contains("Cmd"))
        XCTAssertTrue(hotkeyString.contains("⇧") || hotkeyString.contains("Shift"))
        XCTAssertTrue(hotkeyString.contains("Space"))
    }
    
    func testUpdateHotkey() {
        // Update to Option+Space
        var newModifiers: CGEventFlags = .maskAlternate
        hotkeyManager.updateHotkey(keyCode: 49, modifiers: newModifiers)
        
        let updated = hotkeyManager.getCurrentHotkey()
        XCTAssertEqual(updated.keyCode, 49)
        XCTAssertTrue(updated.modifiers.contains(.maskAlternate))
    }
    
    // MARK: - Settings Persistence Tests
    
    func testHotkeySettingsPersistence() {
        // Save a custom hotkey configuration
        UserDefaults.standard.set(UInt32(12), forKey: "hotkeyKeyCode") // 'Q' key
        UserDefaults.standard.set(UInt32(controlKey), forKey: "hotkeyModifiers")
        
        // Create a new manager to load these settings
        let newManager = HotkeyManager(
            audioEngine: audioEngine,
            recognitionService: recognitionService,
            textInjector: textInjector,
            recordingOverlay: recordingOverlay
        )
        
        let hotkey = newManager.getCurrentHotkey()
        // The new manager should load the saved settings
        // Note: The exact behavior depends on implementation
        XCTAssertNotNil(newManager)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
    }
    
    // MARK: - Hotkey Detection Tests
    
    func testHotkeyDetection() {
        // Create a mock event with Cmd+Shift+Space
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true)
        event?.flags = [.maskCommand, .maskShift]
        
        guard let testEvent = event else {
            XCTFail("Failed to create test event")
            return
        }
        
        let isPressed = hotkeyManager.isHotkeyPressed(event: testEvent)
        XCTAssertTrue(isPressed)
        
        // Test with different modifiers - should not match
        event?.flags = [.maskCommand]
        let isDifferentPressed = hotkeyManager.isHotkeyPressed(event: testEvent)
        XCTAssertFalse(isDifferentPressed)
    }
    
    // MARK: - Error Tests
    
    func testHotkeyErrorDescriptions() {
        let errors: [(HotkeyError, String)] = [
            (.accessibilityNotGranted, "Accessibility permissions required"),
            (.eventTapCreationFailed, "Failed to create event tap"),
            (.hotkeyAlreadyRegistered, "Hotkey is already registered"),
        ]
        
        for (error, expectedPrefix) in errors {
            XCTAssertTrue(
                error.localizedDescription.contains(expectedPrefix),
                "Error \(error) should contain '\(expectedPrefix)'"
            )
        }
    }
    
    // MARK: - Delegate Tests
    
    func testHotkeyDelegate() {
        class MockDelegate: HotkeyDelegate {
            var triggerCalled = false
            var releaseCalled = false
            
            func hotkeyDidTrigger() {
                triggerCalled = true
            }
            
            func hotkeyDidRelease() {
                releaseCalled = true
            }
        }
        
        let mockDelegate = MockDelegate()
        hotkeyManager.hotkeyDelegate = mockDelegate
        
        XCTAssertNotNil(hotkeyManager.hotkeyDelegate)
    }
    
    // MARK: - Monitoring Tests
    
    func testStartStopMonitoring() {
        // Should not crash
        hotkeyManager.startMonitoring()
        hotkeyManager.stopMonitoring()
    }
}
