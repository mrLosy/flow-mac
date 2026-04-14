import Foundation

struct PersistentTranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval
    let wordCount: Int
    let provider: String

    init(text: String, duration: TimeInterval = 0, provider: String = "") {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.wordCount = text.split(separator: " ").count
        self.provider = provider
    }
}

final class TranscriptionHistoryService {
    static let shared = TranscriptionHistoryService()

    private var entries: [PersistentTranscriptionEntry] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.flowmac.history", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("history.json")
        loadFromDisk()
        cleanupOldEntries()
    }

    // MARK: - Public API

    func add(_ entry: PersistentTranscriptionEntry) {
        entries.insert(entry, at: 0)
        scheduleSave()
    }

    func add(text: String, provider: String = "") {
        add(PersistentTranscriptionEntry(text: text, provider: provider))
    }

    func recentEntries(limit: Int = 20) -> [PersistentTranscriptionEntry] {
        Array(entries.prefix(limit))
    }

    func search(_ query: String) -> [PersistentTranscriptionEntry] {
        let lowered = query.lowercased()
        return entries.filter { $0.text.lowercased().contains(lowered) }
    }

    func deleteAll() {
        entries.removeAll()
        scheduleSave()
    }

    var totalCount: Int { entries.count }

    // MARK: - Persistence

    private func loadFromDisk() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                entries = try JSONDecoder().decode([PersistentTranscriptionEntry].self, from: data)
                NSLog("[FlowMac] Loaded \(entries.count) history entries")
            } catch {
                NSLog("[FlowMac] Failed to load history: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveToDisk()
        }
        saveWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[FlowMac] Failed to save history: \(error.localizedDescription)")
        }
    }

    private func cleanupOldEntries() {
        let retentionDays = UserDefaults.standard.integer(forKey: "historyRetentionDays")
        guard retentionDays > 0 else { return } // 0 = keep forever
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        let before = entries.count
        entries.removeAll { $0.timestamp < cutoff }
        if entries.count != before {
            NSLog("[FlowMac] Cleaned up \(before - entries.count) old history entries")
            scheduleSave()
        }
    }
}
