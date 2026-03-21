# Flow Mac - Архитектура

## Обзор

Flow Mac — menu bar приложение для macOS, которое захватывает аудио с микрофона, 
отправляет его на OpenAI Whisper API для транскрипции и вставляет результат 
в активное текстовое поле.

## Структура проекта

```
FlowMac/
├── App/                          # Точка входа
│   ├── FlowMacApp.swift         # @main структура приложения
│   └── AppDelegate.swift        # Инициализация сервисов
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
│   ├── StatusBar/               # Menu bar
│   │   └── StatusBarController.swift
│   │
│   ├── Settings/                # Настройки
│   │   ├── SettingsWindow.swift
│   │   └── SettingsView.swift   # SwiftUI
│   │
│   └── Recording/               # Индикатор записи
│       ├── RecordingOverlay.swift
│       ├── StatusBarController.swift
│       └── StatusBarMenuView.swift
│
└── Resources/                    # Ресурсы
    ├── Assets.xcassets/         # Иконки
    ├── FlowMac.entitlements     # Разрешения
    └── Info.plist              # Конфигурация
```

## Поток данных

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Горячая    │────▶│   Запись     │────▶│   Аудио     │
│   клавиша   │     │   начата     │     │   буфер     │
└─────────────┘     └──────────────┘     └──────┬──────┘
                                                │
                                                ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Результат  │◀────│ Вставка текста │◀────│ Whisper API │
│  вставлен   │     │  в активное   │     │  ответ      │
└─────────────┘     └──────────────┘     └─────────────┘
```

## Ключевые компоненты

### AudioEngine
- Использует `AVAudioEngine` для захвата аудио
- Конвертирует в PCM 16-bit 16kHz (оптимально для Whisper)
- Реализует `AudioCaptureServiceProtocol`

### RecognitionService
- HTTP клиент для OpenAI Whisper API
- Поддержка multipart/form-data запросов
- Обработка ошибок и таймаутов

### TextInjector
- Три метода вставки текста:
  1. Accessibility API (самый надёжный)
  2. CGEvent keystroke simulation
  3. Pasteboard fallback (Cmd+V)

### HotkeyManager
- Carbon EventTap для глобальных событий
- Регистрация произвольных комбинаций
- Callback в main thread

### StatusBarController
- NSStatusBar для menu bar
- Анимация иконки при записи
- Dropdown меню

### RecordingOverlay
- Borderless NSWindow
- Пульсирующий индикатор записи
- Визуализация уровня звука

## Разрешения (Entitlements)

```xml
com.apple.security.app-sandbox           — App Sandbox
com.apple.security.device.microphone     — Микрофон
com.apple.security.automation.apple-events — Accessibility
com.apple.security.network.client        — Сеть (Whisper API)
```

## Зависимости

- **Внешние:** Нет (только системные фреймворки)
- **Встроенные:**
  - AVFoundation (аудио)
  - Carbon (хоткеи)
  - SwiftUI (UI)

## Минимальная версия

- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+
