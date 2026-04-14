import Foundation

enum TranscriptionCleaner {
    /// Strip Whisper artifacts like [music], (silence), [inaudible] and normalize whitespace
    static func clean(_ text: String) -> String {
        var result = text

        // Remove content in square brackets: [music], [inaudible], [silence], etc.
        while let range = result.range(of: #"\[.*?\]"#, options: .regularExpression) {
            result.removeSubrange(range)
        }

        // Remove content in round brackets: (silence), (background noise), etc.
        while let range = result.range(of: #"\(.*?\)"#, options: .regularExpression) {
            result.removeSubrange(range)
        }

        // Collapse multiple whitespace into single space
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
