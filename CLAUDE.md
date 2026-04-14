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

AppDelegate — DI-координатор: создаёт все сервисы и передаёт их зависимости вручную.

```
FlowMac/
├── App/            # FlowMacApp.swift (@main), AppDelegate (coordinator)
├── Core/
│   ├── Audio/      # AudioEngine: AVAudioEngine → 16kHz PCM mono WAV
│   ├── Recognition/# RecognitionService: multipart POST → Whisper API, retry 3x
│   ├── Injection/  # TextInjector: Accessibility → CGEvent → NSPasteboard fallback
│   └── Hotkey/     # HotkeyManager: Carbon RegisterEventHotKey + CGEventTap fallback
└── Features/
    ├── Recording/  # StatusBarController, RecordingOverlay
    └── Settings/   # SettingsView (TabView: General, Shortcuts, Audio, About)
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
- Логирование: `NSLog("[FlowMac] ...")` — не `print()` (NSLog попадает в Console.app)
- После изменений в entitlements или Info.plist — пересобирай clean build
- Не трогай `AudioEngine` формат: 16kHz, mono, Int16 — Whisper требует именно это

## Текущий статус MVP

Что работает: UI, настройки, hotkey registration.
Что не протестировано: реальная запись → транскрипция → вставка текста (core workflow).

Приоритет: довести до рабочего состояния `HotkeyManager → AudioEngine → RecognitionService → TextInjector`.
