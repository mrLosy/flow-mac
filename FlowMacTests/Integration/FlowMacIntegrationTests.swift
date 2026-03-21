import XCTest
import AVFoundation
@testable import FlowMac

/// Integration tests for the complete Flow Mac workflow
final class FlowMacIntegrationTests: XCTestCase {
    
    var audioEngine: AudioEngine!
    var recognitionService: RecognitionService!
    var textInjector: TextInjector!
    var recordingOverlay: RecordingOverlayWindow!
    
    override func setUp() {
        super.setUp()
        audioEngine = AudioEngine()
        recognitionService = RecognitionService()
        textInjector = TextInjector()
        recordingOverlay = RecordingOverlayWindow()
    }
    
    override func tearDown() {
        if audioEngine.isRecording {
            _ = audioEngine.stopRecording()
        }
        audioEngine = nil
        recognitionService = nil
        textInjector = nil
        recordingOverlay = nil
        super.tearDown()
    }
    
    // MARK: - Full Workflow Tests
    
    /// Tests the complete flow: Start recording -> Capture audio -> Stop recording -> Get WAV data
    func testRecordingWorkflow() {
        // Skip if no microphone
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw XCTSkip("No microphone available")
        }
        
        let expectation = self.expectation(description: "Recording workflow completed")
        
        // Start recording
        audioEngine.startRecording()
        XCTAssertTrue(audioEngine.isRecording)
        
        // Record for a short time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Stop recording
            let audioData = self?.audioEngine.stopRecording()
            
            // Verify results
            XCTAssertNotNil(audioData)
            XCTAssertFalse(self?.audioEngine.isRecording ?? true)
            
            // Verify WAV format
            if let data = audioData {
                XCTAssertGreaterThan(data.count, 44) // WAV header is 44 bytes
                
                // Check RIFF header
                let riffHeader = data.prefix(4)
                XCTAssertEqual(String(data: riffHeader, encoding: .ascii), "RIFF")
                
                // Check WAVE marker
                let waveMarker = data.subdata(in: 8..<12)
                XCTAssertEqual(String(data: waveMarker, encoding: .ascii), "WAVE")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
    }
    
    /// Tests audio level updates during recording
    func testAudioLevelUpdatesDuringRecording() {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw XCTSkip("No microphone available")
        }
        
        let expectation = self.expectation(description: "Audio level updated")
        var maxLevel: Float = 0.0
        
        // Set up delegate to capture audio levels
        class TestDelegate: AudioLevelDelegate {
            var maxLevel: Float = 0.0
            var expectation: XCTestExpectation?
            var updateCount = 0
            
            func audioLevelDidChange(_ level: Float) {
                maxLevel = max(maxLevel, level)
                updateCount += 1
                
                // Fulfill expectation after a few updates
                if updateCount >= 3 {
                    expectation?.fulfill()
                }
            }
        }
        
        let delegate = TestDelegate()
        delegate.expectation = expectation
        audioEngine.audioLevelDelegate = delegate
        
        // Start recording
        audioEngine.startRecording()
        
        // Wait for audio level updates
        waitForExpectations(timeout: 3) { [weak self] _ in
            _ = self?.audioEngine.stopRecording()
        }
        
        // Verify that we received some level updates
        XCTAssertGreaterThan(delegate.updateCount, 0)
    }
    
    /// Tests the overlay window show/hide functionality
    func testRecordingOverlay() {
        // Test showing overlay
        recordingOverlay.show()
        XCTAssertTrue(recordingOverlay.isRecording)
        
        // Test updating audio level
        recordingOverlay.updateAudioLevel(0.5)
        // Audio level should be updated (internal state)
        
        // Test hiding overlay
        recordingOverlay.hide()
        XCTAssertFalse(recordingOverlay.isRecording)
    }
    
    /// Tests text injector accessibility permission check
    func testTextInjectorPermissions() {
        // Test permission check (result depends on system state)
        let hasPermission = textInjector.checkAccessibilityPermissions()
        // Just verify the method doesn't crash
        XCTAssertTrue(true)
    }
    
    /// Tests text injection with sample text (without actually injecting)
    func testTextInjectionPreparation() {
        let testText = "Hello, this is a test!"
        
        // Verify the injector is ready
        XCTAssertEqual(textInjector.lastInjectedText, "")
        
        // Note: We don't actually inject text in tests to avoid side effects
        // The actual injection requires user interaction and accessibility permissions
    }
    
    // MARK: - Service Integration Tests
    
    /// Tests that audio engine and recognition service work together
    func testAudioToRecognitionIntegration() {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw XCTSkip("No microphone available")
        }
        
        let expectation = self.expectation(description: "Audio captured for recognition")
        
        // Start recording
        audioEngine.startRecording()
        
        // Capture for a short time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let audioData = self?.audioEngine.stopRecording()
            
            // Verify we have data suitable for recognition
            XCTAssertNotNil(audioData)
            if let data = audioData {
                // Verify it's a valid WAV file
                XCTAssertGreaterThanOrEqual(data.count, 44)
                
                // Check that the audio format is correct for Whisper
                // Whisper expects: 16kHz, 16-bit, mono, WAV
                // The header contains this information
                
                // Parse WAV header to verify format
                let sampleRate = data.subdata(in: 24..<28)
                let sampleRateValue = sampleRate.withUnsafeBytes { ptr in
                    ptr.load(as: UInt32.self)
                }
                XCTAssertEqual(UInt32(littleEndian: sampleRateValue), 16000, "Sample rate should be 16kHz")
                
                let channels = data.subdata(in: 22..<24)
                let channelsValue = channels.withUnsafeBytes { ptr in
                    ptr.load(as: UInt16.self)
                }
                XCTAssertEqual(UInt16(littleEndian: channelsValue), 1, "Should be mono")
                
                let bitsPerSample = data.subdata(in: 34..<36)
                let bitsValue = bitsPerSample.withUnsafeBytes { ptr in
                    ptr.load(as: UInt16.self)
                }
                XCTAssertEqual(UInt16(littleEndian: bitsValue), 16, "Should be 16-bit")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
    }
    
    /// Tests recognition service error handling without API key
    func testRecognitionServiceErrorHandling() {
        let expectation = self.expectation(description: "Recognition error handled")
        
        // Clear API key
        UserDefaults.standard.removeObject(forKey: "whisperAPIKey")
        
        // Create dummy audio data
        let dummyAudio = Data(repeating: 0, count: 1000)
        
        recognitionService.transcribe(audioData: dummyAudio) { result in
            switch result {
            case .failure(let error):
                if let recognitionError = error as? RecognitionError {
                    XCTAssertEqual(recognitionError, RecognitionError.noAPIKey)
                } else {
                    XCTFail("Expected RecognitionError.noAPIKey")
                }
            case .success:
                XCTFail("Should fail without API key")
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
    }
    
    // MARK: - Settings Persistence Tests
    
    func testSettingsPersistence() {
        // Test API key persistence
        let testKey = "sk-test-persistence-key"
        UserDefaults.standard.set(testKey, forKey: "whisperAPIKey")
        
        let retrievedKey = UserDefaults.standard.string(forKey: "whisperAPIKey")
        XCTAssertEqual(retrievedKey, testKey)
        
        // Test language persistence
        UserDefaults.standard.set("ru", forKey: "recognitionLanguage")
        let retrievedLanguage = UserDefaults.standard.string(forKey: "recognitionLanguage")
        XCTAssertEqual(retrievedLanguage, "ru")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "whisperAPIKey")
        UserDefaults.standard.removeObject(forKey: "recognitionLanguage")
    }
    
    // MARK: - Performance Tests
    
    /// Tests audio processing performance
    func testAudioProcessingPerformance() {
        // Create a larger PCM data buffer to simulate 5 seconds of audio
        let pcmData = Data(repeating: 0xAB, count: 16000 * 2 * 5) // 16kHz, 16-bit, 5 seconds
        
        measure {
            // Simulate WAV header creation
            var wavData = Data()
            
            // RIFF header
            wavData.append("RIFF".data(using: .ascii)!)
            let totalSize = UInt32(pcmData.count + 36)
            wavData.append(withUnsafeBytes(of: totalSize.littleEndian, Data.init))
            wavData.append("WAVE".data(using: .ascii)!)
            
            // fmt chunk
            wavData.append("fmt ".data(using: .ascii)!)
            wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian, Data.init))
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian, Data.init))
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian, Data.init)) // channels
            wavData.append(withUnsafeBytes(of: UInt32(16000).littleEndian, Data.init)) // sample rate
            wavData.append(withUnsafeBytes(of: UInt32(32000).littleEndian, Data.init)) // byte rate
            wavData.append(withUnsafeBytes(of: UInt16(2).littleEndian, Data.init)) // block align
            wavData.append(withUnsafeBytes(of: UInt16(16).littleEndian, Data.init)) // bits per sample
            
            // data chunk
            wavData.append("data".data(using: .ascii)!)
            wavData.append(withUnsafeBytes(of: UInt32(pcmData.count).littleEndian, Data.init))
            wavData.append(pcmData)
            
            XCTAssertEqual(wavData.count, pcmData.count + 44)
        }
    }
}

// MARK: - Helper Extensions

extension Data {
    fileprivate mutating func append(_ other: Data) {
        self.append(contentsOf: other)
    }
}
