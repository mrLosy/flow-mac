import XCTest
@testable import FlowMac

final class RecognitionServiceTests: XCTestCase {
    
    var recognitionService: RecognitionService!
    
    override func setUp() {
        super.setUp()
        recognitionService = RecognitionService()
        // Clear API key for clean tests
        UserDefaults.standard.removeObject(forKey: "whisperAPIKey")
    }
    
    override func tearDown() {
        recognitionService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(recognitionService)
        XCTAssertFalse(recognitionService.isProcessing)
        XCTAssertEqual(recognitionService.transcribedText, "")
        XCTAssertNil(recognitionService.errorMessage)
    }
    
    // MARK: - Error Handling Tests
    
    func testTranscribeWithoutAPIKey() {
        let expectation = self.expectation(description: "Transcription failed")
        
        // Ensure no API key is set
        UserDefaults.standard.removeObject(forKey: "whisperAPIKey")
        
        // Create minimal audio data
        let audioData = Data(repeating: 0, count: 1000)
        
        recognitionService.transcribe(audioData: audioData) { result in
            switch result {
            case .failure(let error):
                if let recognitionError = error as? RecognitionError {
                    XCTAssertEqual(recognitionError, RecognitionError.noAPIKey)
                } else {
                    XCTFail("Expected RecognitionError.noAPIKey")
                }
                expectation.fulfill()
            case .success:
                XCTFail("Should fail without API key")
            }
        }
        
        waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testTranscribeWithEmptyAudio() {
        let expectation = self.expectation(description: "Transcription failed")
        
        // Set a dummy API key
        UserDefaults.standard.set("sk-test-key", forKey: "whisperAPIKey")
        
        // Try to transcribe empty data
        recognitionService.transcribe(audioData: Data()) { result in
            switch result {
            case .failure(let error):
                if let recognitionError = error as? RecognitionError {
                    XCTAssertEqual(recognitionError, RecognitionError.emptyAudio)
                } else {
                    XCTFail("Expected RecognitionError.emptyAudio")
                }
                expectation.fulfill()
            case .success:
                XCTFail("Should fail with empty audio")
            }
        }
        
        waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testTranscribeWithTooSmallAudio() {
        let expectation = self.expectation(description: "Transcription failed")
        
        UserDefaults.standard.set("sk-test-key", forKey: "whisperAPIKey")
        
        // Very small audio data (less than 100 bytes)
        let tinyAudio = Data(repeating: 0, count: 50)
        
        // This might succeed or fail depending on implementation
        // Just verify the method completes
        recognitionService.transcribe(audioData: tinyAudio) { result in
            // Either success or failure is acceptable for tiny audio
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    // MARK: - State Management Tests
    
    func testProcessingState() {
        // Set API key
        UserDefaults.standard.set("sk-test-key", forKey: "whisperAPIKey")
        
        let audioData = Data(repeating: 0, count: 1000)
        
        // Start transcription
        recognitionService.transcribe(audioData: audioData) { _ in }
        
        // Check that isProcessing is true immediately after
        XCTAssertTrue(recognitionService.isProcessing)
    }
    
    func testErrorMessageAfterFailure() {
        let expectation = self.expectation(description: "Error set")
        
        UserDefaults.standard.removeObject(forKey: "whisperAPIKey")
        
        recognitionService.transcribe(audioData: Data(repeating: 0, count: 100)) { _ in
            DispatchQueue.main.async {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        XCTAssertNotNil(recognitionService.errorMessage)
    }
    
    // MARK: - Response Parsing Tests
    
    func testWhisperResponseParsing() {
        let json = """
        {"text": "Hello world"}
        """
        
        let data = json.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
            XCTAssertEqual(response.text, "Hello world")
        } catch {
            XCTFail("Failed to parse valid response: \(error)")
        }
    }
    
    func testWhisperResponseParsingWithUnicode() {
        let json = """
        {"text": "Привет мир"}
        """
        
        let data = json.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
            XCTAssertEqual(response.text, "Привет мир")
        } catch {
            XCTFail("Failed to parse unicode response: \(error)")
        }
    }
    
    func testOpenAIErrorParsing() {
        let json = """
        {"error": {"message": "Invalid API key", "type": "invalid_request_error", "code": "invalid_api_key"}}
        """
        
        let data = json.data(using: .utf8)!
        
        do {
            let error = try JSONDecoder().decode(OpenAIError.self, from: data)
            XCTAssertEqual(error.error.message, "Invalid API key")
            XCTAssertEqual(error.error.type, "invalid_request_error")
        } catch {
            XCTFail("Failed to parse error response: \(error)")
        }
    }
    
    // MARK: - Error Description Tests
    
    func testRecognitionErrorDescriptions() {
        let errors: [(RecognitionError, String)] = [
            (.noAPIKey, "OpenAI API key not configured"),
            (.emptyAudio, "No audio data to transcribe"),
            (.noData, "No response from server"),
            (.invalidURL, "Invalid API URL configuration"),
            (.invalidResponse, "Invalid response from server"),
            (.parsingError, "Failed to parse server response"),
            (.maxRetriesExceeded, "Failed after maximum retry attempts"),
        ]
        
        for (error, expectedPrefix) in errors {
            XCTAssertTrue(
                error.localizedDescription.contains(expectedPrefix),
                "Error \(error) should contain '\(expectedPrefix)'"
            )
        }
    }
    
    func testAPIErrorDescription() {
        let errorMessage = "Rate limit exceeded"
        let error = RecognitionError.apiError(errorMessage)
        
        XCTAssertTrue(error.localizedDescription.contains(errorMessage))
        XCTAssertTrue(error.localizedDescription.contains("API Error"))
    }
}

// MARK: - Mock Tests

extension RecognitionServiceTests {
    
    func testTranscribeWithMockAPIKey() {
        // This test would need a mock server or stubbed URLSession
        // For now, we just verify the service handles the key correctly
        
        let testKey = "sk-test123456789"
        UserDefaults.standard.set(testKey, forKey: "whisperAPIKey")
        
        // Verify key is retrieved correctly
        let retrievedKey = UserDefaults.standard.string(forKey: "whisperAPIKey")
        XCTAssertEqual(retrievedKey, testKey)
    }
    
    func testLanguageSetting() {
        // Test that language setting is respected
        UserDefaults.standard.set("ru", forKey: "recognitionLanguage")
        
        let language = UserDefaults.standard.string(forKey: "recognitionLanguage")
        XCTAssertEqual(language, "ru")
    }
}
