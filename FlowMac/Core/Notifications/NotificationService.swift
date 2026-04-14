import Foundation
import UserNotifications
import AVFoundation
import AppKit

/// Централизованный сервис уведомлений для критических ошибок записи и транскрипции
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    // MARK: - Setup

    /// Запросить разрешение на уведомления при запуске
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("[FlowMac] Notification permission error: \(error)")
            }
            NSLog("[FlowMac] Notification permission granted: \(granted)")
        }
    }

    // MARK: - Pre-flight Checks

    /// Проверяет все условия перед началом записи. Возвращает nil если всё ок, или описание проблемы.
    func preflightCheck() -> PreflightError? {
        // 1. Микрофон
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            return .microphoneDenied
        }

        // 2. API ключ
        let provider = TranscriptionProvider.current
        if !provider.isConfigured {
            return .noAPIKey(provider: provider.displayName)
        }

        return nil
    }

    // MARK: - Notification Sending

    func notifyError(_ error: PreflightError) {
        let (title, body, actionURL) = error.notificationContent
        send(title: title, body: body, category: "PREFLIGHT_ERROR", actionURL: actionURL)
    }

    func notifyRecordingError(_ message: String) {
        send(
            title: "Ошибка записи",
            body: message,
            category: "RECORDING_ERROR"
        )
    }

    func notifyTranscriptionError(_ message: String) {
        send(
            title: "Ошибка транскрипции",
            body: message,
            category: "TRANSCRIPTION_ERROR"
        )
    }

    func notifyInjectionError(_ message: String) {
        send(
            title: "Ошибка вставки текста",
            body: message,
            category: "INJECTION_ERROR"
        )
    }

    func notifyClipboard() {
        send(
            title: "Flow Mac",
            body: "Текст скопирован в буфер обмена (нет активного текстового поля)",
            category: "INFO"
        )
    }

    func notifyAccessibilityHint() {
        send(
            title: "Текст скопирован в буфер обмена",
            body: "Включите Accessibility для прямой вставки текста",
            category: "INFO",
            actionURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func notifyNoSpeech() {
        send(
            title: "Речь не распознана",
            body: "Попробуйте говорить громче или ближе к микрофону",
            category: "RECORDING_WARNING"
        )
    }

    func notifyRetrySuccess() {
        send(
            title: "Повторная транскрипция",
            body: "Текст скопирован в буфер обмена",
            category: "INFO"
        )
    }

    // MARK: - Private

    private func send(title: String, body: String, category: String, actionURL: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        if let url = actionURL {
            content.userInfo["actionURL"] = url
        }

        let request = UNNotificationRequest(
            identifier: "\(category)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[FlowMac] Failed to deliver notification: \(error)")
            }
        }
    }
}

// MARK: - PreflightError

enum PreflightError {
    case microphoneDenied
    case noAPIKey(provider: String)
    case accessibilityDenied

    var notificationContent: (title: String, body: String, actionURL: String?) {
        switch self {
        case .microphoneDenied:
            return (
                "Нет доступа к микрофону",
                "Разрешите доступ к микрофону в Системных настройках → Конфиденциальность → Микрофон",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
        case .noAPIKey(let provider):
            return (
                "API ключ не настроен",
                "Добавьте ключ для \(provider) в настройках Flow Mac (⌘,)",
                nil
            )
        case .accessibilityDenied:
            return (
                "Нет доступа к Accessibility",
                "Без Accessibility текст не будет вставлен в активное поле. Разрешите в Системных настройках.",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        }
    }
}
