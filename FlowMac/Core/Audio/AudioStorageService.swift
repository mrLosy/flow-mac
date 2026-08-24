import Foundation

final class AudioStorageService {
    static let shared = AudioStorageService()

    let audioDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowMac", isDirectory: true)
        audioDirectory = appDir.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    func save(audioData: Data, id: UUID) -> String? {
        let fileName = "\(id.uuidString).wav"
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        do {
            try audioData.write(to: fileURL, options: .atomic)
            NSLog("[FlowMac] Saved audio to %@ (%d bytes)", fileName, audioData.count)
            return fileName
        } catch {
            NSLog("[FlowMac] Failed to save audio: %@", error.localizedDescription)
            return nil
        }
    }

    func load(fileName: String) -> Data? {
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            NSLog("[FlowMac] Failed to load audio %@: %@", fileName, error.localizedDescription)
            return nil
        }
    }

    func delete(fileName: String) {
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.removeItem(at: fileURL)
            NSLog("[FlowMac] Deleted audio file: %@", fileName)
        } catch {
            NSLog("[FlowMac] Failed to delete audio %@: %@", fileName, error.localizedDescription)
        }
    }

    func cleanupOrphans(validFileNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: audioDirectory.path) else { return }
        for file in files where file.hasSuffix(".wav") && !validFileNames.contains(file) {
            delete(fileName: file)
        }
    }
}
