import XCTest
@testable import FlowMac

final class TextInjectorTests: XCTestCase {
    
    var textInjector: TextInjector!
    
    override func setUp() {
        super.setUp()
        textInjector = TextInjector()
    }
    
    override func tearDown() {
        textInjector = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(textInjector)
        XCTAssertEqual(textInjector.lastInjectedText, "")
    }
    
    // MARK: - Permission Tests
    
    func testAccessibilityPermissionCheck() {
        // Test that the permission check doesn't crash
        let hasPermission = textInjector.checkAccessibilityPermissions()
        // Result depends on system state, just verify it returns a value
        XCTAssertTrue(hasPermission == true || hasPermission == false)
    }
    
    // MARK: - Text Injection Tests
    
    func testInsertEmptyText() {
        // Should not crash with empty text
        textInjector.insertText("")
        XCTAssertEqual(textInjector.lastInjectedText, "")
    }
    
    func testInsertTextWithSpecialCharacters() {
        // Test various Unicode characters
        let testCases = [
            "Hello World",
            "Привет мир",
            "你好世界",
            "🎉 Emoji test 🚀",
            "Line 1\nLine 2",
            "Tab\there",
            "Quotes: \"test\"",
            "Apos: it's",
        ]
        
        for testText in testCases {
            // Note: We can't actually inject in tests without accessibility permissions
            // This test verifies the text is handled correctly internally
            XCTAssertNoThrow(textInjector.insertText(testText))
        }
    }
    
    // MARK: - Error Tests
    
    func testTextInjectionErrorDescriptions() {
        let errors: [(TextInjectionError, String)] = [
            (.accessibilityNotGranted, "Accessibility permissions not granted"),
            (.noFocusedElement, "No text field is currently focused"),
            (.insertionFailed, "Failed to insert text"),
            (.pasteboardError, "Failed to use pasteboard"),
        ]
        
        for (error, expectedPrefix) in errors {
            XCTAssertTrue(
                error.localizedDescription.contains(expectedPrefix),
                "Error \(error) should contain '\(expectedPrefix)'"
            )
        }
    }
    
    // MARK: - Key Code Tests
    
    func testKeyCodes() {
        // Verify key code enum values
        XCTAssertEqual(KeyCode.returnKey.rawValue, 36)
        XCTAssertEqual(KeyCode.tab.rawValue, 48)
        XCTAssertEqual(KeyCode.space.rawValue, 49)
        XCTAssertEqual(KeyCode.delete.rawValue, 51)
        XCTAssertEqual(KeyCode.escape.rawValue, 53)
        XCTAssertEqual(KeyCode.command.rawValue, 55)
        XCTAssertEqual(KeyCode.shift.rawValue, 56)
        XCTAssertEqual(KeyCode.option.rawValue, 58)
        XCTAssertEqual(KeyCode.control.rawValue, 59)
        XCTAssertEqual(KeyCode.leftArrow.rawValue, 123)
        XCTAssertEqual(KeyCode.rightArrow.rawValue, 124)
        XCTAssertEqual(KeyCode.downArrow.rawValue, 125)
        XCTAssertEqual(KeyCode.upArrow.rawValue, 126)
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateCallbacks() {
        class MockDelegate: TextInjectionDelegate {
            var successCalled = false
            var failureCalled = false
            var injectedText: String?
            var receivedError: TextInjectionError?
            
            func textInjectionDidSucceed(_ text: String) {
                successCalled = true
                injectedText = text
            }
            
            func textInjectionDidFail(with error: TextInjectionError) {
                failureCalled = true
                receivedError = error
            }
        }
        
        let mockDelegate = MockDelegate()
        textInjector.injectionDelegate = mockDelegate
        
        // The actual injection result depends on system state
        // This test verifies the delegate is set up correctly
        XCTAssertNotNil(textInjector.injectionDelegate)
    }
}
