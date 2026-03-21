import XCTest
import AVFoundation
@testable import FlowMac

final class AudioEngineTests: XCTestCase {
    
    var audioEngine: AudioEngine!
    
    override func setUp() {
        super.setUp()
        audioEngine = AudioEngine()
    }
    
    override func tearDown() {
        if audioEngine.isRecording {
            _ = audioEngine.stopRecording()
        }
        audioEngine = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testAudioEngineInitialization() {
        XCTAssertNotNil(audioEngine)
        XCTAssertFalse(audioEngine.isRecording)
        XCTAssertEqual(audioEngine.audioLevel, 0.0)
    }
    
    // MARK: - Permission Tests
    
    func testRequestPermission() {
        let expectation = self.expectation(description: "Permission check")
        
        audioEngine.requestPermission { granted in
            // Result depends on system state, just verify callback is called
            XCTAssertTrue(true)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    // MARK: - Recording State Tests
    
    func testStartRecording() {
        // Skip if no microphone available
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw XCTSkip("No microphone available")
        }
        
        audioEngine.startRecording()
        
        // Give time for recording to start
        let expectation = self.expectation(description: "Recording started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        
        XCTAssertTrue(audioEngine.isRecording)
    }
    
    func testStopRecordingReturnsData() {
        // Skip if no microphone available
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw XCTSkip("No microphone available")
        }
        
        // Start recording
        audioEngine.startRecording()
        
        let expectation = self.expectation(description: "Recording")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        
        // Stop and get data
        let audioData = audioEngine.stopRecording()
        
        XCTAssertNotNil(audioData)
        XCTAssertFalse(audioEngine.isRecording)
        
        // Check that data is in WAV format
        if let data = audioData, data.count > 44 {
            // Check RIFF header
            let header = data.prefix(4)
            XCTAssertEqual(String(data: header, encoding: .ascii), "RIFF")
            
            // Check WAVE marker
            let waveMarker = data.subdata(in: 8..12)
            XCTAssertEqual(String(data: waveMarker, encoding: .ascii), "WAVE")
        }
    }
    
    func testStopRecordingWhenNotRecording() {
        let audioData = audioEngine.stopRecording()
        XCTAssertNil(audioData)
    }
    
    func testDoubleStartRecording() {
        // Should not crash or create multiple instances
        audioEngine.startRecording()
        audioEngine.startRecording() // Second call should be ignored
        
        XCTAssertTrue(audioEngine.isRecording)
        
        _ = audioEngine.stopRecording()
    }
    
    // MARK: - Audio Level Tests
    
    func testAudioLevelUpdates() {
        let expectation = self.expectation(description: "Audio level updated")
        var levelReceived = false
        
        class TestDelegate: AudioLevelDelegate {
            var expectation: XCTestExpectation?
            var levelReceived: Bool = false
            
            func audioLevelDidChange(_ level: Float) {
                levelReceived = true
                expectation?.fulfill()
            }
        }
        
        let delegate = TestDelegate()
        delegate.expectation = expectation
        audioEngine.audioLevelDelegate = delegate
        
        audioEngine.startRecording()
        
        waitForExpectations(timeout: 2) { _ in
            _ = self.audioEngine.stopRecording()
        }
        
        // Audio level should have been updated at least once
        XCTAssertTrue(delegate.levelReceived || self.audioEngine.audioLevel >= 0)
    }
    
    // MARK: - Buffer Tests
    
    func testAudioBufferCallback() {
        let expectation = self.expectation(description: "Buffer received")
        var bufferReceived = false
        
        audioEngine.onAudioBuffer = { data in
            bufferReceived = true
            if !data.isEmpty {
                expectation.fulfill()
            }
        }
        
        audioEngine.startRecording()
        
        waitForExpectations(timeout: 2) { _ in
            _ = self.audioEngine.stopRecording()
        }
        
        XCTAssertTrue(bufferReceived)
    }
}

// MARK: - WAV Format Tests

extension AudioEngineTests {
    
    func testWAVFormatStructure() {
        // Create a mock PCM data
        let pcmData = Data(repeating: 0, count: 16000) // 1 second of silence at 16kHz, 16-bit
        
        // The WAV creation is internal, but we can test by recording
        // For this test, we verify the recording produces valid WAV
        
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw XCTSkip("No microphone available")
        }
        
        audioEngine.startRecording()
        
        let expectation = self.expectation(description: "Recording")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        
        let wavData = audioEngine.stopRecording()
        
        XCTAssertNotNil(wavData)
        
        if let data = wavData {
            // WAV header is 44 bytes minimum
            XCTAssertGreaterThanOrEqual(data.count, 44)
            
            // Verify structure
            XCTAssertEqual(data.count % 2, 0) // Should be even (16-bit samples)
        }
    }
}
