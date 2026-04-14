import Foundation
import AppKit

// MARK: - App Category Detection

enum AppCategory: String, CaseIterable, Identifiable {
    case terminal
    case coding
    case chat
    case email
    case writing
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .coding: return "Code Editor"
        case .chat: return "Chat / Messenger"
        case .email: return "Email"
        case .writing: return "Writing"
        case .general: return "General"
        }
    }

    var systemPrompt: String {
        switch self {
        case .terminal:
            return """
            Fix transcription errors in this terminal command dictation. Preserve CLI terms, flags, paths, and technical jargon exactly. \
            Common corrections: "suit oh" → "sudo", "see dee" → "cd", "el es" → "ls", "grip" → "grep". \
            Only fix obvious speech-to-text errors. Return corrected text only.
            """
        case .coding:
            return """
            Fix transcription errors in this code-related dictation. Apply correct casing: camelCase, PascalCase, snake_case as appropriate. \
            Common corrections: "a sink" → "async", "you state" → "useState", "con st" → "const". \
            Preserve code syntax and technical terms. Return corrected text only.
            """
        case .chat:
            return """
            Lightly fix transcription errors in this chat message. Preserve informal tone, slang, and casual style. \
            Fix only obvious speech recognition mistakes. Don't add formal punctuation. Return corrected text only.
            """
        case .email:
            return """
            Fix transcription errors in this email text. Apply proper grammar, punctuation, and professional tone. \
            Preserve greetings and sign-offs. Return corrected text only.
            """
        case .writing:
            return """
            Fix transcription errors in this text. Apply full grammar correction, proper punctuation, and capitalization. \
            Maintain the author's intended meaning and style. Return corrected text only.
            """
        case .general:
            return """
            Fix obvious transcription errors in this dictated text. Apply basic punctuation and capitalization. \
            Preserve the original meaning. Return corrected text only.
            """
        }
    }

    /// Detect category from frontmost app bundle identifier
    static func detect(bundleIdentifier: String?) -> AppCategory {
        guard let bid = bundleIdentifier?.lowercased() else { return .general }

        if bid.contains("terminal") || bid.contains("iterm") || bid.contains("warp")
            || bid.contains("alacritty") || bid.contains("kitty") || bid.contains("hyper") {
            return .terminal
        }
        if bid.contains("xcode") || bid.contains("vscode") || bid.contains("code")
            || bid.contains("jetbrains") || bid.contains("intellij") || bid.contains("sublime")
            || bid.contains("textmate") || bid.contains("nova") || bid.contains("cursor")
            || bid.contains("zed") {
            return .coding
        }
        if bid.contains("slack") || bid.contains("telegram") || bid.contains("discord")
            || bid.contains("whatsapp") || bid.contains("messages") || bid.contains("signal")
            || bid.contains("skype") || bid.contains("teams") {
            return .chat
        }
        if bid.contains("mail") || bid.contains("outlook") || bid.contains("gmail")
            || bid.contains("spark") || bid.contains("airmail") {
            return .email
        }
        if bid.contains("pages") || bid.contains("word") || bid.contains("docs")
            || bid.contains("notion") || bid.contains("bear") || bid.contains("ulysses")
            || bid.contains("ia-writer") || bid.contains("obsidian") {
            return .writing
        }
        return .general
    }
}

// MARK: - Semantic Correction Service

final class SemanticCorrectionService {
    static let shared = SemanticCorrectionService()

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "semanticCorrectionEnabled")
    }

    /// Correct text using LLM with category-specific prompt
    func correct(text: String, category: AppCategory, completion: @escaping (String) -> Void) {
        guard isEnabled else {
            completion(text)
            return
        }

        let provider = TranscriptionProvider.current
        guard provider.isConfigured else {
            NSLog("[FlowMac] Semantic correction skipped — no API key")
            completion(text)
            return
        }

        // Build chat completion request
        let baseURL: String
        let model: String
        switch provider {
        case .openai:
            baseURL = "https://api.openai.com/v1/chat/completions"
            model = "gpt-4o-mini"
        case .groq:
            baseURL = "https://api.groq.com/openai/v1/chat/completions"
            model = "llama-3.1-8b-instant"
        }

        guard let url = URL(string: baseURL) else {
            completion(text)
            return
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": category.systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1,
            "max_tokens": 1024
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                NSLog("[FlowMac] Semantic correction request failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { completion(text) }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let corrected = message["content"] as? String else {
                NSLog("[FlowMac] Semantic correction: failed to parse response")
                DispatchQueue.main.async { completion(text) }
                return
            }

            let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

            // safeMerge: reject if too many changes (hallucination protection)
            let merged = Self.safeMerge(original: text, corrected: trimmed, maxChangeRatio: 0.25)
            DispatchQueue.main.async { completion(merged) }
        }.resume()
    }

    /// Reject LLM output if normalized edit distance exceeds threshold
    static func safeMerge(original: String, corrected: String, maxChangeRatio: Double) -> String {
        let distance = normalizedEditDistance(original.lowercased(), corrected.lowercased())
        if distance > maxChangeRatio {
            NSLog("[FlowMac] safeMerge: rejected correction (distance=\(String(format: "%.2f", distance)), max=\(maxChangeRatio))")
            return original
        }
        return corrected
    }

    /// Normalized Levenshtein edit distance (0.0 = identical, 1.0 = completely different)
    static func normalizedEditDistance(_ a: String, _ b: String) -> Double {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        guard m > 0 || n > 0 else { return 0 }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }

        return Double(prev[n]) / Double(max(m, n))
    }
}
