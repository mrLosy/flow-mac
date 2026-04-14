# Flow Mac

macOS menu bar приложение для голосовой диктовки: хоткей → запись → Whisper API → вставка текста.
Цель: рабочий MVP → App Store.
Платформа: macOS 13.0+, Swift 5.9, Xcode 15+.

## Стек

SwiftUI + AppKit (hybrid), AVFoundation, Carbon, CoreGraphics, UserNotifications.
Провайдеры транскрипции: OpenAI Whisper, Groq (whisper-large-v3-turbo).

## Команды (VS Code)

```bash
# Сборка
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -configuration Debug build

# Тесты
xcodebuild test -project FlowMac.xcodeproj -scheme FlowMac -destination 'platform=macOS'

# Release сборка
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -configuration Release build
```

## Архитектура

AppDelegate (inner class в FlowMacApp.swift) — DI-координатор: создаёт все сервисы и передаёт зависимости вручную.

```
FlowMac/
├── App/              # FlowMacApp.swift (@main + AppDelegate inner class)
├── Core/
│   ├── Audio/        # AudioEngine, AudioValidator, MicVolumeManager
│   ├── Recognition/  # RecognitionService, TranscriptionProvider, TranscriptionCleaner
│   ├── Injection/    # TextInjector: Accessibility → CGEvent → Pasteboard
│   ├── Hotkey/       # HotkeyManager + EventHandling extension
│   ├── Security/     # KeychainService
│   ├── Notifications/# NotificationService
│   ├── History/      # TranscriptionHistoryService
│   ├── Metrics/      # UsageMetricsService
│   ├── PostProcessing/# SemanticCorrectionService
│   └── DebugLog.swift
└── Features/
    ├── Recording/    # StatusBarController, StatusBarMenuView, RecordingOverlay
    ├── Settings/     # SettingsView, SettingsTabContent, ProviderSettingsView, ShortcutRecorder
    └── Metrics/      # UsageMetricsView
```

Каждый сервис: Protocol + конкретный класс. Мокай через Protocol в тестах.

## Ключевые паттерны

- `@MainActor` на AppDelegate и всех UI-обновлениях
- `@Published` + `ObservableObject` на сервисах для SwiftUI binding
- `weak var delegate` для audio level callbacks (избегай retain cycle)
- Completion handlers — не async/await (не ломай существующие контракты без необходимости)
- `TranscriptionProvider` enum — добавление нового провайдера только через него
- `UserDefaults` ключи — не переименовывай существующие (migration logic зависит от них)

## Разрешения macOS

Три обязательных права для работы приложения:
- **Microphone** — `NSMicrophoneUsageDescription` в Info.plist
- **Accessibility** — `AXIsProcessTrustedWithOptions` для text injection
- **Input Monitoring** — для глобального hotkey через CGEventTap

Для App Store потребуется Hardened Runtime + entitlements:
- `com.apple.security.device.audio-input`
- `com.apple.security.automation.apple-events`
- App Sandbox включает ограничения на CGEventTap — проверь перед сабмитом

## Правила

- Никогда не хардкодь API ключи — только `UserDefaults` через `TranscriptionProvider`
- `guard let` вместо `if let` для ранних возвратов
- Избегай `!` force unwrap — только там где сбой невозможен по контракту
- Логирование: `DebugLog.log(...)` — обёртка над NSLog, не `print()`
- После изменений в entitlements или Info.plist — пересобирай clean build
- Не трогай `AudioEngine` формат: 16kHz, mono, Int16 — Whisper требует именно это

## Текущий статус MVP

Реализовано: UI, настройки, hotkey, аудио, транскрипция (OpenAI/Groq), вставка текста, история, метрики, keychain.
Core workflow собран: `HotkeyManager → AudioEngine → RecognitionService → TextInjector`.

Приоритет: тестирование полного пайплайна на реальном использовании, подготовка к App Store.
