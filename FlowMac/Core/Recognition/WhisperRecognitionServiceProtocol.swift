import Foundation

/// Protocol defining Whisper recognition service interface
protocol WhisperRecognitionServiceProtocol: AnyObject, ObservableObject {
    var isProcessing: Bool { get }
    var transcribedText: String { get }
    var errorMessage: String? { get }
    
    /// Transcribe audio data using Whisper API
    /// - Parameters:
    ///   - audioData: Raw audio data to transcribe
    ///   - completion: Callback with transcription result
    func transcribe(audioData: Data, completion: @escaping (Result<String, Error>) -> Void)
    
    /// Start streaming transcription for real-time recognition
    /// - Parameter onResult: Called when partial or final transcription is available
    func startStreamingTranscription(onResult: @escaping (String) -> Void)
    
    /// Stop streaming transcription
    func stopStreamingTranscription()
}

/// Protocol for real-time transcription streaming
protocol StreamingTranscriptionDelegate: AnyObject {
    func transcriptionDidUpdate(_ text: String, isFinal: Bool)
    func transcriptionDidFail(with error: Error)
}
