import Foundation

enum EntryStatus: String, Codable {
    case success, failed
}

struct PersistentTranscriptionEntry: Codable, Identifiable {
    let id: UUID
    var text: String
    let timestamp: Date
    let duration: TimeInterval
    var wordCount: Int
    let provider: String
    var status: EntryStatus
    var errorMessage: String?
    var audioFileName: String?

    init(text: String, duration: TimeInterval = 0, provider: String = "") {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.wordCount = text.split(separator: " ").count
        self.provider = provider
        self.status = .success
        self.errorMessage = nil
        self.audioFileName = nil
    }

    init(failedWithID id: UUID, duration: TimeInterval, provider: String, audioFileName: String, errorMessage: String) {
        self.id = id
        self.text = ""
        self.timestamp = Date()
        self.duration = duration
        self.wordCount = 0
        self.provider = provider
        self.status = .failed
        self.errorMessage = errorMessage
        self.audioFileName = audioFileName
    }

    // Backward-compatible decoder: old entries without status/errorMessage/audioFileName parse as .success
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        provider = try container.decode(String.self, forKey: .provider)
        status = try container.decodeIfPresent(EntryStatus.self, forKey: .status) ?? .success
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
    }
}

final class TranscriptionHistoryService: ObservableObject {
    static let shared = TranscriptionHistoryService()

    @Published private(set) var entries: [PersistentTranscriptionEntry] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.flowmac.history", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private let maxFailedEntries = 10

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("history.json")
        loadFromDisk()
        cleanupOldEntries()
        cleanupOrphanedAudio()
    }

    // MARK: - Public API

    func add(_ entry: PersistentTranscriptionEntry) {
        dispatchPrecondition(condition: .onQueue(.main))
        entries.insert(entry, at: 0)
        // Enforce failed entries limit
        if entry.status == .failed {
            enforceFailedLimit()
        }
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

    func entry(withID id: UUID) -> PersistentTranscriptionEntry? {
        entries.first { $0.id == id }
    }

    func markAsSucceeded(id: UUID, text: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].text = text
        entries[idx].wordCount = text.split(separator: " ").count
        entries[idx].status = .success
        entries[idx].errorMessage = nil
        entries[idx].audioFileName = nil
        scheduleSave()
    }

    func updateError(id: UUID, message: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].errorMessage = message
        scheduleSave()
    }

    func delete(id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let entry = entries.first(where: { $0.id == id }), let fileName = entry.audioFileName {
            AudioStorageService.shared.delete(fileName: fileName)
        }
        entries.removeAll { $0.id == id }
        scheduleSave()
    }

    func deleteAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        for entry in entries {
            if let fileName = entry.audioFileName {
                AudioStorageService.shared.delete(fileName: fileName)
            }
        }
        entries.removeAll()
        scheduleSave()
    }

    var totalCount: Int { entries.count }

    // MARK: - Private

    private func enforceFailedLimit() {
        let failedEntries = entries.enumerated().filter { $0.element.status == .failed }
        guard failedEntries.count > maxFailedEntries else { return }
        // Remove oldest failed entries (they're at higher indices since newest is at 0)
        let toRemove = failedEntries.suffix(failedEntries.count - maxFailedEntries)
        for (_, entry) in toRemove {
            if let fileName = entry.audioFileName {
                AudioStorageService.shared.delete(fileName: fileName)
            }
        }
        let idsToRemove = Set(toRemove.map { $0.element.id })
        entries.removeAll { idsToRemove.contains($0.id) }
    }

    private func cleanupOrphanedAudio() {
        let validFileNames = Set(entries.compactMap { $0.audioFileName })
        AudioStorageService.shared.cleanupOrphans(validFileNames: validFileNames)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                entries = try JSONDecoder().decode([PersistentTranscriptionEntry].self, from: data)
                NSLog("[FlowMac] Loaded %d history entries", entries.count)
            } catch {
                NSLog("[FlowMac] Failed to load history: %@", error.localizedDescription)
            }
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = entries
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveToDisk(snapshot)
        }
        saveWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func saveToDisk(_ snapshot: [PersistentTranscriptionEntry]) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[FlowMac] Failed to save history: %@", error.localizedDescription)
        }
    }

    private func cleanupOldEntries() {
        let retentionDays = UserDefaults.standard.integer(forKey: "historyRetentionDays")
        guard retentionDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        let toRemove = entries.filter { $0.timestamp < cutoff }
        guard !toRemove.isEmpty else { return }
        for entry in toRemove {
            if let fileName = entry.audioFileName {
                AudioStorageService.shared.delete(fileName: fileName)
            }
        }
        entries.removeAll { $0.timestamp < cutoff }
        NSLog("[FlowMac] Cleaned up %d old history entries", toRemove.count)
        scheduleSave()
    }
}
