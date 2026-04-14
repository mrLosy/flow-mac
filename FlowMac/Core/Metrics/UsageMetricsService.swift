import Foundation

struct SessionMetric: Codable {
    let timestamp: Date
    let duration: TimeInterval
    let wordCount: Int
    let characterCount: Int
}

struct UsageMetrics: Codable {
    var sessions: [SessionMetric] = []
    var totalSessions: Int = 0
    var totalDuration: TimeInterval = 0
    var totalWords: Int = 0
    var totalCharacters: Int = 0
}

final class UsageMetricsService: ObservableObject {
    static let shared = UsageMetricsService()

    @Published private(set) var metrics = UsageMetrics()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.flowmac.metrics", qos: .utility)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("metrics.json")
        loadFromDisk()
    }

    // MARK: - Recording

    func recordSession(duration: TimeInterval, text: String) {
        let words = text.split(separator: " ").count
        let chars = text.count
        let session = SessionMetric(timestamp: Date(), duration: duration, wordCount: words, characterCount: chars)

        metrics.sessions.append(session)
        metrics.totalSessions += 1
        metrics.totalDuration += duration
        metrics.totalWords += words
        metrics.totalCharacters += chars

        // Keep only last 90 days of individual sessions
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        metrics.sessions.removeAll { $0.timestamp < cutoff }

        saveToDisk()
    }

    // MARK: - Computed Stats

    var wordsPerMinute: Double {
        guard metrics.totalDuration > 0 else { return 0 }
        return Double(metrics.totalWords) / (metrics.totalDuration / 60)
    }

    /// Estimated time saved vs typing at 45 WPM
    var estimatedTimeSaved: TimeInterval {
        let typingWPM: Double = 45
        let typingTime = Double(metrics.totalWords) / typingWPM * 60
        return max(0, typingTime - metrics.totalDuration)
    }

    /// Keystrokes saved (avg 5 chars per word)
    var keystrokesSaved: Int {
        metrics.totalCharacters
    }

    /// Current daily streak
    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        let sessionDays = Set(metrics.sessions.map { calendar.startOfDay(for: $0.timestamp) })

        while sessionDays.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    /// Sessions per day for last N days
    func dailyActivity(days: Int = 30) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var result: [(Date, Int)] = []
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let count = metrics.sessions.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }.count
            result.append((date, count))
        }
        return result
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                metrics = try JSONDecoder().decode(UsageMetrics.self, from: data)
            } catch {
                NSLog("[FlowMac] Failed to load metrics: \(error.localizedDescription)")
            }
        }
    }

    private func saveToDisk() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONEncoder().encode(self.metrics)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                NSLog("[FlowMac] Failed to save metrics: \(error.localizedDescription)")
            }
        }
    }
}
