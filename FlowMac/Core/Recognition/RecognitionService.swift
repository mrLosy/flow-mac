import Foundation
import Combine

/// Whisper API client for speech recognition with retry logic and error handling
class RecognitionService: NSObject, ObservableObject, WhisperRecognitionServiceProtocol {
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var partialText = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    
    private var provider: TranscriptionProvider {
        TranscriptionProvider.current
    }

    private var apiKey: String {
        provider.apiKey
    }

    private var apiURL: String {
        provider.apiURL
    }
    private var urlSession: URLSession
    private var streamingTask: URLSessionDataTask?
    private var retryCount = 0
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    /// Hard upper bound on a whole transcription (across all retries) so the UI
    /// never stays stuck on "Transcribing…" when the network silently stalls.
    private let overallTimeout: TimeInterval = 40
    private var watchdog: DispatchWorkItem?

    weak var streamingDelegate: StreamingTranscriptionDelegate?

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        // Fail fast when offline instead of silently waiting for connectivity —
        // retries with backoff already cover brief drops, and the watchdog caps
        // the overall time.
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)
        super.init()

        TranscriptionProvider.migrateIfNeeded()
    }
    
    /// Transcribe audio data using Whisper API with retry logic
    func transcribe(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            let error = RecognitionError.noAPIKey
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            completion(.failure(error))
            return
        }
        
        guard !audioData.isEmpty else {
            let error = RecognitionError.emptyAudio
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            completion(.failure(error))
            return
        }
        
        // Reset retry count for new transcription
        retryCount = 0

        // Fire the caller's completion exactly once — from the network path or
        // the watchdog, whichever happens first — so the UI never stays stuck
        // on "Transcribing…" if the request stalls.
        let guarded = makeGuardedCompletion(completion)
        scheduleWatchdog(firing: guarded)
        performTranscription(audioData: audioData, completion: guarded)
    }

    private func makeGuardedCompletion(
        _ completion: @escaping (Result<String, Error>) -> Void
    ) -> (Result<String, Error>) -> Void {
        let lock = NSLock()
        var fired = false
        return { [weak self] result in
            lock.lock()
            let alreadyFired = fired
            fired = true
            lock.unlock()
            guard !alreadyFired else { return }
            self?.cancelWatchdog()
            completion(result)
        }
    }

    /// If the whole transcription (including retries) hasn't finished within
    /// `overallTimeout`, surface a clear error instead of spinning forever.
    private func scheduleWatchdog(firing completion: @escaping (Result<String, Error>) -> Void) {
        cancelWatchdog()
        let item = DispatchWorkItem { [weak self] in
            self?.isProcessing = false
            self?.errorMessage = RetryReason.connectionFailed.userMessage
            completion(.failure(RecognitionError.maxRetriesExceeded(.connectionFailed)))
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + overallTimeout, execute: item)
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }
    
    private func performTranscription(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.errorMessage = nil
        }
        
        guard let url = URL(string: apiURL) else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.errorMessage = "Invalid API URL"
            }
            completion(.failure(RecognitionError.invalidURL))
            return
        }
        
        DebugLog.log("API: url=\(apiURL), key=\(String(apiKey.prefix(15)))..., provider=\(provider.rawValue)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(provider.authHeaderValue, forHTTPHeaderField: provider.authHeaderName)
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let body = createMultipartBody(audioData: audioData, boundary: boundary)
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            
            // Handle network errors
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                
                // Retry on network errors
                if self.shouldRetry(error: error) {
                    let reason: RetryReason = (error as NSError).code == NSURLErrorNotConnectedToInternet
                        ? .noInternet : .connectionFailed
                    self.retryTranscription(audioData: audioData, reason: reason, completion: completion)
                    return
                }

                completion(.failure(error))
                return
            }
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid response"
                }
                completion(.failure(RecognitionError.invalidResponse))
                return
            }
            
            // Handle HTTP errors
            if !(200...299).contains(httpResponse.statusCode) {
                let serverMessage = self.parseErrorResponse(data: data) ?? "HTTP \(httpResponse.statusCode)"
                DebugLog.log("API ERROR: HTTP \(httpResponse.statusCode) — \(serverMessage)")

                // Retry on server errors (5xx) and rate limiting (429)
                if (500...599).contains(httpResponse.statusCode) || httpResponse.statusCode == 429 {
                    let reason: RetryReason = httpResponse.statusCode == 429 ? .rateLimit : .serverError
                    self.retryTranscription(audioData: audioData, reason: reason, completion: completion)
                    return
                }

                // 403: Groq geo-blocks some regions (e.g. RU) at the Cloudflare
                // edge, before auth — a VPN or our own backend proxy is required.
                let displayMessage = httpResponse.statusCode == 403
                    ? "Service unavailable in your region. Connect via VPN or use the built-in service."
                    : serverMessage
                DispatchQueue.main.async {
                    self.errorMessage = displayMessage
                }
                completion(.failure(RecognitionError.apiError(displayMessage)))
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No data received"
                }
                completion(.failure(RecognitionError.noData))
                return
            }
            
            do {
                let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
                DispatchQueue.main.async {
                    self.transcribedText = result.text
                    self.partialText = ""
                    self.transcriptionHistory.insert(
                        TranscriptionEntry(text: result.text, timestamp: Date()),
                        at: 0
                    )
                }
                completion(.success(result.text))
            } catch {
                // Try to extract error message (OpenAI-compatible format)
                if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.errorMessage = errorResponse.error.message
                    }
                    completion(.failure(RecognitionError.apiError(errorResponse.error.message)))
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to parse response"
                    }
                    completion(.failure(RecognitionError.parsingError))
                }
            }
        }
        
        task.resume()
    }
    
    private func retryTranscription(audioData: Data, reason: RetryReason, completion: @escaping (Result<String, Error>) -> Void) {
        guard retryCount < maxRetries else {
            DispatchQueue.main.async {
                self.errorMessage = reason.userMessage
            }
            completion(.failure(RecognitionError.maxRetriesExceeded(reason)))
            return
        }

        retryCount += 1

        DispatchQueue.main.async {
            self.errorMessage = "Retrying... (\(self.retryCount)/\(self.maxRetries))"
        }

        // Exponential backoff
        let delay = retryDelay * pow(2.0, Double(retryCount - 1))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performTranscription(audioData: audioData, completion: completion)
        }
    }
    
    private func shouldRetry(error: Error) -> Bool {
        let nsError = error as NSError
        // Retry on common network errors
        return nsError.domain == NSURLErrorDomain &&
            (nsError.code == NSURLErrorNotConnectedToInternet ||
             nsError.code == NSURLErrorTimedOut ||
             nsError.code == NSURLErrorNetworkConnectionLost)
    }
    
    private func createMultipartBody(audioData: Data, boundary: String) -> Data {
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(provider.modelName)\r\n".data(using: .utf8)!)
        
        // Add language parameter
        let language = UserDefaults.standard.string(forKey: "recognitionLanguage") ?? "auto"
        if language != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // Add prompt for better accuracy (optional)
        if let prompt = UserDefaults.standard.string(forKey: "transcriptionPrompt"), !prompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    private func parseErrorResponse(data: Data?) -> String? {
        guard let data = data else { return nil }
        
        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return errorResponse.error.message
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Start streaming transcription using chunked approach
    func startStreamingTranscription(onResult: @escaping (String) -> Void) {
        // For real-time streaming, we use a chunked approach
        // sending audio every N seconds for transcription
        NSLog("[FlowMac] Streaming transcription started")
    }
    
    /// Stop streaming transcription
    func stopStreamingTranscription() {
        streamingTask?.cancel()
        streamingTask = nil
        NSLog("[FlowMac] Streaming transcription stopped")
    }
    
    /// Process audio chunk for streaming transcription
    func processAudioChunk(_ audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard !audioData.isEmpty else {
            completion(.failure(RecognitionError.emptyAudio))
            return
        }
        
        // For streaming, we process smaller chunks
        performTranscription(audioData: audioData, completion: completion)
    }
}

// MARK: - Transcription History

struct TranscriptionEntry: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

// MARK: - Models

struct WhisperResponse: Codable {
    let text: String
}

struct APIErrorResponse: Codable {
    let error: ErrorDetail
}

@available(*, deprecated, renamed: "APIErrorResponse")
typealias OpenAIError = APIErrorResponse

struct ErrorDetail: Codable {
    let message: String
    let type: String
    let code: String?
}

// MARK: - Errors

/// Why a transcription request was retried — drives the user-facing message
/// shown once all retry attempts are exhausted.
enum RetryReason {
    case noInternet
    case connectionFailed
    case rateLimit
    case serverError

    var userMessage: String {
        switch self {
        case .noInternet:
            return "No internet connection. Check your network and try again."
        case .connectionFailed:
            return "Couldn't reach the server. Check your connection and try again."
        case .rateLimit:
            return "Rate limit reached. Try again in a moment."
        case .serverError:
            return "Service temporarily unavailable. Try again later."
        }
    }
}

enum RecognitionError: Error, LocalizedError {
    case noAPIKey
    case emptyAudio
    case noData
    case invalidURL
    case invalidResponse
    case parsingError
    case apiError(String)
    case maxRetriesExceeded(RetryReason)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not configured. Please add it in Settings."
        case .emptyAudio:
            return "No audio data to transcribe."
        case .noData:
            return "No response from server."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .invalidResponse:
            return "Invalid response from server."
        case .parsingError:
            return "Failed to parse server response."
        case .apiError(let message):
            return "API Error: \(message)"
        case .maxRetriesExceeded(let reason):
            return reason.userMessage
        case .networkError(let message):
            return "Network Error: \(message)"
        }
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}
