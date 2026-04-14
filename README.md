# Flow Mac

macOS menu bar приложение для голосовой диктовки с AI-транскрипцией.

Хоткей → запись → Whisper API → вставка текста в активное поле.

## Возможности

- Глобальный хоткей (Cmd+Shift+Space по умолчанию, настраивается)
- Транскрипция через OpenAI Whisper или Groq
- Вставка текста через Accessibility API / CGEvent / Pasteboard (fallback chain)
- Визуальный оверлей при записи с waveform-анимацией
- История транскрипций и статистика использования
- Хранение API ключей в Keychain
- Звуковая обратная связь

## Требования

- macOS 13.0+
- Xcode 15.0+
- API ключ OpenAI или Groq

## Сборка

```bash
# Debug
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -configuration Debug build

# Release
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -configuration Release build

# Или через скрипт (убивает старый процесс, собирает, копирует на Desktop)
./build.sh
```

## Использование

1. Запустить приложение — появится иконка в menu bar
2. Открыть Settings и ввести API ключ (OpenAI или Groq)
3. Дать разрешения: микрофон, Accessibility, Input Monitoring
4. Нажать Cmd+Shift+Space — начать запись, нажать снова — остановить и вставить текст

## Структура проекта

```
FlowMac/
├── App/
│   └── FlowMacApp.swift          # @main, AppDelegate как inner class
├── Core/
│   ├── Audio/
│   │   ├── AudioEngine.swift     # AVAudioEngine → 16kHz PCM mono WAV
│   │   ├── AudioValidator.swift  # Проверки перед записью
│   │   └── MicVolumeManager.swift # Управление громкостью микрофона
│   ├── Recognition/
│   │   ├── RecognitionService.swift      # Whisper API клиент, retry 3x
│   │   ├── TranscriptionProvider.swift   # Enum провайдеров (OpenAI/Groq)
│   │   ├── TranscriptionCleaner.swift    # Нормализация текста
│   │   └── FileTranscriptionService.swift # Транскрипция файлов
│   ├── Injection/
│   │   └── TextInjector.swift    # Accessibility → CGEvent → Pasteboard
│   ├── Hotkey/
│   │   ├── HotkeyManager.swift   # Carbon RegisterEventHotKey
│   │   └── HotkeyManager+EventHandling.swift
│   ├── Security/
│   │   └── KeychainService.swift # Хранение API ключей
│   ├── Notifications/
│   │   └── NotificationService.swift
│   ├── History/
│   │   └── TranscriptionHistoryService.swift
│   ├── Metrics/
│   │   └── UsageMetricsService.swift
│   ├── PostProcessing/
│   │   └── SemanticCorrectionService.swift
│   └── DebugLog.swift
├── Features/
│   ├── Recording/
│   │   ├── StatusBarController.swift
│   │   ├── StatusBarMenuView.swift
│   │   └── RecordingOverlay.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── SettingsTabContent.swift
│   │   ├── ProviderSettingsView.swift
│   │   └── ShortcutRecorder.swift
│   └── Metrics/
│       └── UsageMetricsView.swift
└── Resources/
    ├── Assets.xcassets/
    ├── FlowMac.entitlements
    └── Info.plist
```

## Разрешения

| Разрешение | Назначение |
|------------|-----------|
| Microphone | Запись голоса |
| Accessibility | Вставка текста в приложения |
| Input Monitoring | Глобальный хоткей |
| Network | Запросы к API транскрипции |

## Тесты

```bash
xcodebuild test -project FlowMac.xcodeproj -scheme FlowMac -destination 'platform=macOS'
```

## Лицензия

MIT
