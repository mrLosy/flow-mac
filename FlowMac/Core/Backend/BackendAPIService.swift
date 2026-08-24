import Foundation

/// HTTP client for the Flow Mac backend.
/// Proxies transcription and LLM enhancement requests.
final class BackendAPIService {
    static let shared = BackendAPIService()

    // TODO: replace with production URL before release
    private let baseURL = "https://api.flowmac.app/v1"
    private var authToken: String?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - Auth

    func setAuthToken(_ token: String) {
        authToken = token
    }

    // MARK: - Transcription

    /// Transcribe audio through our backend (includes LLM enhancement)
    func transcribe(
        audioData: Data,
        language: String,
        prompt: String?,
        appContext: String?,
        completion: @escaping (Result<TranscribeResponse, BackendError>) -> Void
    ) {
        guard let token = authToken else {
            completion(.failure(.notAuthenticated))
            return
        }

        guard let url = URL(string: "\(baseURL)/transcribe") else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Audio file
        body.appendMultipart(name: "file", fileName: "audio.wav", mimeType: "audio/wav", data: audioData, boundary: boundary)

        // Language
        if language != "auto" {
            body.appendMultipart(name: "language", value: language, boundary: boundary)
        }

        // Prompt
        if let prompt = prompt, !prompt.isEmpty {
            body.appendMultipart(name: "prompt", value: prompt, boundary: boundary)
        }

        // App context for LLM enhancement
        if let context = appContext {
            body.appendMultipart(name: "app_context", value: context, boundary: boundary)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            guard let data = data else {
                completion(.failure(.noData))
                return
            }

            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let result = try JSONDecoder().decode(TranscribeResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(.parsing(error.localizedDescription)))
                }
            case 401:
                completion(.failure(.notAuthenticated))
            case 402:
                completion(.failure(.quotaExhausted))
            case 429:
                completion(.failure(.rateLimited))
            default:
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(.server(message)))
            }
        }.resume()
    }
}

// MARK: - Response Models

struct TranscribeResponse: Codable {
    let text: String             // Final enhanced text
    let rawText: String?         // Original Whisper output (before LLM)
    let durationSeconds: Int     // Audio duration consumed
    let remainingSeconds: Int    // Remaining quota

    enum CodingKeys: String, CodingKey {
        case text
        case rawText = "raw_text"
        case durationSeconds = "duration_seconds"
        case remainingSeconds = "remaining_seconds"
    }
}

// MARK: - Errors

enum BackendError: Error, LocalizedError {
    case notAuthenticated
    case quotaExhausted
    case rateLimited
    case invalidURL
    case invalidResponse
    case noData
    case network(String)
    case server(String)
    case parsing(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in."
        case .quotaExhausted:
            return "Minutes exhausted. Upgrade or wait for reset."
        case .rateLimited:
            return "Too many requests. Please wait."
        case .invalidURL:
            return "Invalid server URL."
        case .invalidResponse:
            return "Invalid server response."
        case .noData:
            return "No data from server."
        case .network(let msg):
            return "Network error: \(msg)"
        case .server(let msg):
            return "Server error: \(msg)"
        case .parsing(let msg):
            return "Parse error: \(msg)"
        }
    }
}

// MARK: - Data Multipart Helper

private extension Data {
    mutating func appendMultipart(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(name: String, fileName: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
