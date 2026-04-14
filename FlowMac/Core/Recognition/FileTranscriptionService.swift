import Foundation
import AppKit
import UserNotifications
import UniformTypeIdentifiers

/// Transcribes existing audio files using the same recognition pipeline
final class FileTranscriptionService {
    static let shared = FileTranscriptionService()

    static let supportedTypes = ["m4a", "mp3", "wav", "flac", "aiff", "caf", "ogg", "webm"]

    private init() {}

    /// Show file picker and transcribe selected audio file
    func transcribeFromFilePicker(using recognitionService: RecognitionService) {
        let panel = NSOpenPanel()
        panel.title = "Select Audio File to Transcribe"
        panel.allowedContentTypes = Self.supportedTypes.compactMap {
            .init(filenameExtension: $0)
        }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        transcribeFile(at: url, using: recognitionService)
    }

    func transcribeFile(at url: URL, using recognitionService: RecognitionService) {
        NSLog("[FlowMac] Transcribing file: \(url.lastPathComponent)")

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                showNotification(title: "Error", body: "File is empty")
                return
            }

            recognitionService.transcribe(audioData: data) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        let cleaned = TranscriptionCleaner.clean(text)
                        guard !cleaned.isEmpty else {
                            self?.showNotification(title: "No Speech", body: "No speech detected in the file")
                            return
                        }
                        // Copy to clipboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cleaned, forType: .string)
                        // Save to history
                        TranscriptionHistoryService.shared.add(text: cleaned, provider: TranscriptionProvider.current.displayName)
                        self?.showNotification(title: "Transcription Complete", body: "Text copied to clipboard (\(cleaned.split(separator: " ").count) words)")
                    case .failure(let error):
                        self?.showNotification(title: "Transcription Failed", body: error.localizedDescription)
                    }
                }
            }
        } catch {
            showNotification(title: "Error", body: "Could not read file: \(error.localizedDescription)")
        }
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
