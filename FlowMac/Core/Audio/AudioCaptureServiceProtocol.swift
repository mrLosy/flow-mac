import Foundation
import AVFoundation

/// Protocol defining audio capture service interface
protocol AudioCaptureServiceProtocol: AnyObject, ObservableObject {
    var isRecording: Bool { get }
    var audioLevel: Float { get }
    
    /// Called when audio buffer is ready for processing
    var onAudioBuffer: ((Data) -> Void)? { get set }
    
    /// Request microphone permission
    func requestPermission(completion: @escaping (Bool) -> Void)
    
    /// Start recording audio
    func startRecording()
    
    /// Stop recording and return accumulated audio data
    func stopRecording() -> Data?
}

/// Protocol for audio level monitoring
protocol AudioLevelDelegate: AnyObject {
    func audioLevelDidChange(_ level: Float)
}
