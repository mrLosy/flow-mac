# Flow Mac

AI-powered voice dictation for macOS — конкурент Wispr Flow.
**Stack**: Swift 5.9+, SwiftUI, AVAudioEngine, OpenAI Whisper API, Carbon Hotkeys

## Команды

```bash
# Сборка
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -configuration Release build

# Тесты
xcodebuild test -project FlowMac.xcodeproj -scheme FlowMac

# Архивирование для распространения
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac -archivePath FlowMac.xcarchive archive
```

## Архитектура

```
FlowMac/
├── App/                          # Entry point
│   ├── FlowMacApp.swift         # @main app structure
│   └── AppDelegate.swift        # Lifecycle events
│
├── Core/                         # Core services
│   ├── Audio/                   # Audio capture
│   │   ├── AudioCaptureServiceProtocol.swift
│   │   └── AudioEngine.swift    # AVAudioEngine implementation
│   │
│   ├── Recognition/             # Speech recognition
│   │   ├── WhisperRecognitionServiceProtocol.swift
│   │   └── RecognitionService.swift  # OpenAI API client
│   │
│   ├── Injection/               # Text injection
│   │   ├── TextInjectionServiceProtocol.swift
│   │   └── TextInjector.swift   # CGEvent + Accessibility
│   │
│   └── Hotkey/                  # Global hotkeys
│       ├── HotkeyManagerProtocol.swift
│       └── HotkeyManager.swift  # Carbon EventTap
│
├── Features/                     # UI components
│   ├── Recording/               # Recording UI
│   │   ├── StatusBarController.swift
│   │   ├── StatusBarMenuView.swift
│   │   └── RecordingOverlay.swift
│   │
│   └── Settings/                # Settings window
│       ├── SettingsWindow.swift
│       └── SettingsView.swift
│
└── Resources/                    # Assets and configs
    ├── FlowMac.entitlements     # Sandbox permissions
    └── Info.plist              # App configuration
```

## Data Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Hotkey     │────▶│   Recording  │────▶│   Audio     │
│  (Cmd+Shift+│     │   Started    │     │   Buffer    │
│   Space)    │     └──────────────┘     └──────┬──────┘
└─────────────┘                                 │
                                                ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Result     │◀────│  Text        │◀────│  Whisper    │
│  Inserted   │     │  Injection   │     │  API        │
└─────────────┘     └──────────────┘     └─────────────┘
```

## Технологии

### Audio Capture
- **Framework**: AVAudioEngine
- **Format**: 16kHz, 16-bit PCM, Mono
- **Buffer**: 4096 samples (real-time)
- **Output**: WAV для Whisper API

### Whisper API
- **Endpoint**: `https://api.openai.com/v1/audio/transcriptions`
- **Model**: whisper-1
- **Retry Logic**: 3 попытки с exponential backoff

### Text Injection
Три метода (fallback chain):
1. **Accessibility API** — Надёжный для native apps
2. **CGEvent Unicode** — Universal Unicode support
3. **Pasteboard** — Работает везде

### Global Hotkeys
- **Primary**: Carbon `RegisterEventHotKey`
- **Fallback**: CGEventTap
- **Default**: Cmd+Shift+Space

## App Sandbox & Entitlements

```xml
<!-- FlowMac.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.device.microphone</key>
<true/>
```

**Обязательные Permission Descriptions в Info.plist:**
- `NSMicrophoneUsageDescription` — Для записи голоса
- `NSAccessibilityUsageDescription` — Для вставки текста

## State Management

- **@StateObject** — Для сервисов уровня View
- **@AppStorage** — Для настроек пользователя
- **Combine** — Для реактивных потоков между сервисами
- **Async/await** — Для асинхронных операций

## Нейминг

- **Файлы**: `PascalCase.swift`
- **Протоколы**: `*ServiceProtocol`, `*ManagerProtocol`
- **Классы**: `PascalCase` (сервисы оканчиваются на Service/Manager)
- **Методы**: `camelCase`, глагол first (`startRecording`, `injectText`)
- **Свойства**: `camelCase`, private начинается с `_`

## Правила кода

- **Always use `self.`** — Явное указание для ясности
- **Mark closures with `@Sendable`** — Для concurrency safety
- **Use `MainActor`** — UI updates только на main thread
- **Force unwrap запрещён** — Использовать `guard let` или `if let`
- **Не игнорировать ошибки** — Всегда handle или log
- **Документировать public API** — Triple-slash comments

## DI и Services

```swift
// Service Locator pattern
class ServiceContainer {
    static let shared = ServiceContainer()
    
    lazy var audioEngine: AudioCaptureServiceProtocol = AudioEngine()
    lazy var recognitionService: WhisperRecognitionServiceProtocol = RecognitionService()
    lazy var textInjector: TextInjectionServiceProtocol = TextInjector()
    lazy var hotkeyManager: HotkeyManagerProtocol = HotkeyManager()
}
```

## Git

```
feat: Add feature    fix: Fix bug         refactor: Extract class
feature/recording-overlay    fix/hotkey-registration
```

## Тестирование

- **Unit tests**: XCTest для сервисов
- **Integration tests**: Полный workflow
- **UI tests**: SwiftUI View inspections

## Безопасность

- **API Key**: UserDefaults (временно), Keychain (production)
- **No hardcoded secrets**: Всегда через configuration
- **HTTPS only**: Для всех network calls
- **Sandbox**: Минимальные entitlements

## Документация

- Architecture: `ARCHITECTURE.md`
- Implementation: `IMPLEMENTATION_SUMMARY.md`
- PR Template: `PR_DESCRIPTION.md`
