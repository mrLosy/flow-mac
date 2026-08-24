import Foundation

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case groq = "groq"
    case openai = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        }
    }

    /// Custom base URL stored in UserDefaults per provider (e.g. for Azure or proxies)
    var customBaseURL: String? {
        get { UserDefaults.standard.string(forKey: "customBaseURL_\(rawValue)") }
        nonmutating set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: "customBaseURL_\(rawValue)")
            } else {
                UserDefaults.standard.removeObject(forKey: "customBaseURL_\(rawValue)")
            }
        }
    }

    var isAzure: Bool {
        customBaseURL?.contains(".openai.azure.com") == true
    }

    var apiURL: String {
        if let custom = customBaseURL, !custom.isEmpty {
            // For Azure: user provides full deployment URL
            return custom.hasSuffix("/") ? custom + "audio/transcriptions" : custom + "/audio/transcriptions"
        }
        switch self {
        case .openai: return "https://api.openai.com/v1/audio/transcriptions"
        case .groq: return "https://api.groq.com/openai/v1/audio/transcriptions"
        }
    }

    var validationURL: String {
        if let custom = customBaseURL, !custom.isEmpty {
            return custom.hasSuffix("/") ? custom + "models" : custom + "/models"
        }
        switch self {
        case .openai: return "https://api.openai.com/v1/models"
        case .groq: return "https://api.groq.com/openai/v1/models"
        }
    }

    /// Auth header name: "api-key" for Azure, "Authorization" for standard
    var authHeaderName: String {
        isAzure ? "api-key" : "Authorization"
    }

    /// Auth header value
    var authHeaderValue: String {
        isAzure ? apiKey : "Bearer \(apiKey)"
    }

    var modelName: String {
        switch self {
        case .openai: return "whisper-1"
        // large-v3, not turbo: the distilled decoder in turbo drops word
        // endings and agreement in inflected languages (ru/de/pl).
        case .groq: return "whisper-large-v3"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain"
        case .groq: return "bolt.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .openai: return "High accuracy, reliable"
        case .groq: return "Ultra-fast transcription"
        }
    }

    var description: String {
        switch self {
        case .openai: return "OpenAI Whisper API. Reliable and accurate speech recognition with broad language support."
        case .groq: return "Groq-powered Whisper. Extremely fast inference on custom LPU hardware. OpenAI-compatible API."
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .groq: return "gsk_..."
        }
    }

    var apiKeyDefaultsKey: String {
        "apiKey_\(rawValue)"
    }

    // MARK: - Persistence

    static var selectedProviderKey: String { "selectedTranscriptionProvider" }

    static var current: TranscriptionProvider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedProviderKey),
                  let provider = TranscriptionProvider(rawValue: raw) else {
                return .groq
            }
            return provider
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedProviderKey)
        }
    }

    var apiKey: String {
        get {
            // Keychain first, fallback to UserDefaults for migration
            if let keychainKey = KeychainService.shared.load(account: apiKeyDefaultsKey) {
                return keychainKey
            }
            // Migrate from UserDefaults if present
            if let legacyKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey), !legacyKey.isEmpty {
                let saved = KeychainService.shared.save(key: legacyKey, account: apiKeyDefaultsKey)
                if saved {
                    UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
                    NSLog("[FlowMac] Migrated API key for \(rawValue) from UserDefaults to Keychain")
                } else {
                    NSLog("[FlowMac] Keychain save failed for \(rawValue) — keeping in UserDefaults")
                }
                return legacyKey
            }
            return ""
        }
        nonmutating set {
            if newValue.isEmpty {
                KeychainService.shared.delete(account: apiKeyDefaultsKey)
            } else {
                KeychainService.shared.save(key: newValue, account: apiKeyDefaultsKey)
            }
            // Clean up UserDefaults if still there
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        }
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Validation

    /// Validate API key by calling the lightweight /models endpoint
    static func validate(provider: TranscriptionProvider, key: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let url = URL(string: provider.validationURL) else {
            completion(.failure(ValidationError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if provider.isAzure {
            request.setValue(key, forHTTPHeaderField: "api-key")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(ValidationError.invalidResponse)) }
                return
            }

            DispatchQueue.main.async {
                switch httpResponse.statusCode {
                case 200:
                    completion(.success(true))
                case 401:
                    completion(.failure(ValidationError.invalidKey))
                case 429:
                    // Rate limited but key is valid
                    completion(.success(true))
                default:
                    completion(.failure(ValidationError.serverError(httpResponse.statusCode)))
                }
            }
        }.resume()
    }

    enum ValidationError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case invalidKey
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid validation URL"
            case .invalidResponse: return "Could not reach server"
            case .invalidKey: return "Invalid API key"
            case .serverError(let code): return "Server error (\(code))"
            }
        }
    }

    // MARK: - Migration

    static func migrateIfNeeded() {
        let migrated = UserDefaults.standard.bool(forKey: "apiKeyMigrated")
        guard !migrated else { return }

        if let legacyKey = UserDefaults.standard.string(forKey: "whisperAPIKey"), !legacyKey.isEmpty {
            if legacyKey.hasPrefix("gsk_") {
                TranscriptionProvider.groq.apiKey = legacyKey
                TranscriptionProvider.current = .groq
            } else {
                TranscriptionProvider.openai.apiKey = legacyKey
                TranscriptionProvider.current = .openai
            }
        }

        UserDefaults.standard.set(true, forKey: "apiKeyMigrated")
    }
}
