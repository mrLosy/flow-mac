import Foundation

enum TranscriptionCleaner {
    /// Whisper artifact markers, matched case-insensitively against the inside
    /// of a bracketed group. Deliberately narrow: dictated parentheses are real
    /// text and must survive.
    private static let artifactKeywords = [
        "music", "музыка", "silence", "тишина", "inaudible", "неразборчиво",
        "applause", "аплодисменты", "laughter", "смех", "blank_audio", "no speech",
        "noise", "шум", "sound", "звук", "subtitle", "субтитр", "speaking",
        "foreign", "продолжение следует"
    ]

    /// Strip Whisper artifacts like [music], (тишина), ♪ and normalize whitespace
    static func clean(_ text: String) -> String {
        var result = removeArtifactGroups(in: text)

        // Music note runs Whisper emits over instrumental audio
        result = result.replacingOccurrences(of: #"[♪♫]+"#, with: "", options: .regularExpression)

        // Collapse multiple whitespace into single space
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove `[...]` / `(...)` groups whose contents look like a Whisper
    /// artifact rather than dictated speech.
    ///
    /// Builds a new string instead of mutating in place: `removeSubrange` invalidates
    /// the very indices the search loop would need to carry to the next iteration.
    private static func removeArtifactGroups(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[\[\(][^\[\]\(\)]*[\]\)]"#) else {
            return text
        }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let inner = source.substring(with: match.range)
                .dropFirst()
                .dropLast()
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard artifactKeywords.contains(where: { inner.contains($0) }) else { continue }

            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }
}
