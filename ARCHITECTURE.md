# Архитектура Flow Mac

## Обзор

Menu bar приложение: хоткей → запись микрофона → Whisper API → вставка текста в активное поле.

## Поток данных

```
Hotkey (Cmd+Shift+Space)
  → AudioEngine.startRecording()     # AVAudioEngine, 16kHz PCM mono
  → AudioEngine.stopRecording()      # → WAV Data
  → RecognitionService.transcribe()  # multipart POST → OpenAI/Groq
  → TranscriptionCleaner.clean()     # нормализация текста
  → TextInjector.insertText()        # Accessibility → CGEvent → Pasteboard
```

## Компоненты

### App/

**FlowMacApp.swift** — `@main` точка входа. Содержит `AppDelegate` как inner class с `@MainActor`. AppDelegate — DI-координатор: создаёт все сервисы и связывает их.

### Core/Audio/

- **AudioEngine** — AVAudioEngine, захват с inputNode, конвертация в 16kHz Int16 PCM mono, генерация WAV с RIFF-заголовками. Audio level delegate для UI.
- **AudioValidator** — проверка микрофона и разрешений перед записью.
- **MicVolumeManager** — управление системной громкостью микрофона.

### Core/Recognition/

- **RecognitionService** — HTTP клиент для Whisper API. Multipart/form-data, retry 3x с exponential backoff.
- **TranscriptionProvider** — enum OpenAI/Groq с endpoint и model конфигурацией. Центральная точка добавления новых провайдеров.
- **TranscriptionCleaner** — пост-обработка текста (пробелы, пунктуация).
- **FileTranscriptionService** — транскрипция аудиофайлов.

### Core/Injection/

- **TextInjector** — вставка текста с fallback chain: Accessibility API → CGEvent Unicode → NSPasteboard (Cmd+V). Сохраняет/восстанавливает буфер обмена. Звуковая обратная связь.

### Core/Hotkey/

- **HotkeyManager** — Carbon `RegisterEventHotKey` + CGEventTap fallback. Toggle recording, настраиваемые комбинации клавиш.
- **HotkeyManager+EventHandling** — расширение с логикой обработки событий.

### Core/ (вспомогательные сервисы)

- **KeychainService** — безопасное хранение API ключей в macOS Keychain.
- **NotificationService** — пользовательские уведомления об ошибках и статусе.
- **TranscriptionHistoryService** — логирование транскрипций.
- **UsageMetricsService** — статистика использования.
- **SemanticCorrectionService** — контекстная коррекция текста.
- **DebugLog** — логирование в Console.app через NSLog.

### Features/Recording/

- **StatusBarController** — NSStatusBar, анимация иконки при записи, popover.
- **StatusBarMenuView** — SwiftUI меню с информацией о провайдере и quick actions.
- **RecordingOverlay** — borderless NSWindow с waveform-визуализацией.

### Features/Settings/

- **SettingsView** — TabView (General, Shortcuts, Audio, About).
- **SettingsTabContent** — содержимое табов.
- **ProviderSettingsView** — настройка провайдеров транскрипции.
- **ShortcutRecorder** — визуальный recorder для назначения хоткея.

### Features/Metrics/

- **UsageMetricsView** — отображение статистики транскрипций.

## Паттерны

- `@MainActor` на AppDelegate и UI-обновлениях
- `@Published` + `ObservableObject` на сервисах для SwiftUI binding
- `weak var delegate` для audio level callbacks
- Completion handlers (не async/await)
- Protocol + конкретный класс для каждого сервиса

## Зависимости

Только системные фреймворки: AVFoundation, Carbon, CoreGraphics, SwiftUI, UserNotifications.

## Разрешения (Entitlements)

```
com.apple.security.device.audio-input
com.apple.security.network.client
com.apple.security.automation.apple-events
```

Для App Store: Hardened Runtime + App Sandbox (ограничивает CGEventTap).
