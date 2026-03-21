# Flow Mac - Архитектура

## Обзор

Flow Mac — menu bar приложение для macOS, которое захватывает аудио с микрофона, 
отправляет его на OpenAI Whisper API для транскрипции и вставляет результат 
в активное текстовое поле.

**Статус**: ✅ Полностью реализовано

## Структура проекта

```
FlowMac/
├── App/                          # Точка входа
│   ├── FlowMacApp.swift         # @main структура приложения
│   └── AppDelegate.swift        # Делегат приложения
│
├── Core/                         # Основные сервисы
│   ├── Audio/                   # Захват аудио
│   │   ├── AudioCaptureServiceProtocol.swift
│   │   └── AudioEngine.swift    # AVAudioEngine реализация
│   │
│   ├── Recognition/             # Распознавание речи
│   │   ├── WhisperRecognitionServiceProtocol.swift
│   │   └── RecognitionService.swift  # OpenAI API клиент
│   │
│   ├── Injection/               # Вставка текста
│   │   ├── TextInjectionServiceProtocol.swift
│   │   └── TextInjector.swift   # CGEvent + Accessibility
│   │
│   └── Hotkey/                  # Глобальные хоткеи
│       ├── HotkeyManagerProtocol.swift
│       └── HotkeyManager.swift  # Carbon EventTap
│
├── Features/                     # UI компоненты
│   ├── Recording/               # Запись и индикаторы
│   │   ├── StatusBarController.swift
│   │   ├── StatusBarMenuView.swift
│   │   └── RecordingOverlay.swift
│   │
│   └── Settings/                # Настройки
│       ├── SettingsWindow.swift
│       └── SettingsView.swift
│
├── Resources/                    # Ресурсы
│   ├── Assets.xcassets/         # Иконки
│   ├── FlowMac.entitlements     # Разрешения
│   └── Info.plist              # Конфигурация
│
└── Tests/                        # Тесты
    ├── Core/                    # Unit тесты сервисов
    └── Integration/             # Интеграционные тесты
```

## Поток данных

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

## Ключевые компоненты

### AudioEngine

**Файл**: `Core/Audio/AudioEngine.swift`

**Возможности**:
- Использует `AVAudioEngine` для захвата аудио
- Конвертирует в PCM 16-bit 16kHz (оптимально для Whisper)
- Реализует `AudioCaptureServiceProtocol`
- Предоставляет уровень громкости для UI
- Генерирует WAV файлы с правильными заголовками

**API**:
```swift
func startRecording()                    // Начать запись
func stopRecording() -> Data?           // Остановить и получить WAV
func requestPermission(completion:)      // Запросить разрешение микрофона
```

### RecognitionService

**Файл**: `Core/Recognition/RecognitionService.swift`

**Возможности**:
- HTTP клиент для OpenAI Whisper API
- Поддержка multipart/form-data запросов
- Обработка ошибок и retry logic (3 попытки)
- Поддержка выбора языка
- API key из UserDefaults

**API**:
```swift
func transcribe(audioData:completion:)   // Транскрибировать аудио
func startStreamingTranscription(onResult:)  // Для будущего streaming
func stopStreamingTranscription()
```

### TextInjector

**Файл**: `Core/Injection/TextInjector.swift`

**Возможности**:
- Три метода вставки текста с fallback chain:
  1. Accessibility API (самый надёжный для native apps)
  2. CGEvent keystroke simulation с Unicode
  3. Pasteboard fallback (Cmd+V)
- Поддержка Unicode и эмодзи
- Сохранение и восстановление буфера обмена

**API**:
```swift
func insertText(_ text: String)          // Вставить текст
func checkAccessibilityPermissions() -> Bool
func requestAccessibilityPermissions()
```

### HotkeyManager

**Файл**: `Core/Hotkey/HotkeyManager.swift`

**Возможности**:
- Carbon RegisterEventHotKey для глобальных событий
- CGEventTap как fallback
- Регистрация произвольных комбинаций
- Callback в main thread
- Toggle recording функционал

**API**:
```swift
func startMonitoring()                   // Начать мониторинг
func stopMonitoring()                    // Остановить мониторинг
func updateHotkey(keyCode:modifiers:)    // Изменить хоткей
func getCurrentHotkey() -> (keyCode: CGKeyCode, modifiers: CGEventFlags)
func getHotkeyString() -> String         // Человекочитаемое представление
```

### StatusBarController

**Файл**: `Features/Recording/StatusBarController.swift`

**Возможности**:
- NSStatusBar для menu bar
- Анимация иконки при записи
- Dropdown меню
- Popover с информацией о статусе

### RecordingOverlay

**Файл**: `Features/Recording/RecordingOverlay.swift`

**Возможности**:
- Borderless NSWindow
- Пульсирующий индикатор записи
- Визуализация уровня звука
- SwiftUI анимации

### SettingsView

**Файл**: `Features/Settings/SettingsView.swift`

**Возможности**:
- TabView с 4 табами: General, Shortcuts, Audio, About
- Настройка API ключа
- Выбор языка
- Настройка хоткея с визуальным recorder
- Список аудио устройств
- Информация о разрешениях

## Разрешения (Entitlements)

```xml
com.apple.security.app-sandbox           — App Sandbox
com.apple.security.device.audio-input    — Микрофон
com.apple.security.network.client        — Сеть (Whisper API)
com.apple.security.automation.apple-events — Accessibility
```

## Зависимости

- **Внешние**: Нет (только системные фреймворки)
- **Встроенные**:
  - AVFoundation (аудио)
  - Carbon (хоткеи)
  - CoreGraphics (CGEvent)
  - SwiftUI (UI)
  - UserNotifications (уведомления)

## Минимальная версия

- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

## Тестирование

### Unit Tests
- `AudioEngineTests` - Тесты аудио захвата
- `RecognitionServiceTests` - Тесты API клиента
- `TextInjectorTests` - Тесты вставки текста
- `HotkeyManagerTests` - Тесты хоткеев

### Integration Tests
- `FlowMacIntegrationTests` - Полный workflow:
  - Запись аудио
  - Генерация WAV
  - Формат данных
  - Интеграция сервисов

## Производительность

- Аудио буфер: 4096 семплов (~256ms при 16kHz)
- Конвертация формата: realtime через AVAudioConverter
- Отправка на API: async с retry
- Вставка текста: < 100ms

## Безопасность

- API key хранится в UserDefaults (в будущем Keychain)
- Аудио не сохраняется локально
- HTTPS для всех API запросов
- Sandboxing включён

## Известные ограничения

1. Требуется интернет для работы Whisper API
2. Нет офлайн режима (требуется локальная модель)
3. Первый запуск требует множества разрешений
4. API key хранится в UserDefaults (не Keychain)

## Roadmap

- [ ] Streaming transcription для real-time результата
- [ ] Локальная Whisper модель для офлайн режима
- [ ] Keychain для хранения API key
- [ ] История транскрипций
- [ ] Голосовые команды (пунктуация)
- [ ] Поддержка других провайдеров (Google, Azure)
