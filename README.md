# Flow Mac — AI Voice Dictation for macOS

Конкурент Wispr Flow. Голосовой диктовщик с AI-обработкой для macOS.

## Концепция
- Глобальный hotkey для активации голосового ввода
- AI-транскрипция в реальном времени
- Автоматическая вставка текста в активное поле ввода
- Поддержка русского и английского языков
- Локальная обработка + облачный fallback

## Технологии
- **Язык:** Swift + Objective-C (для API macOS)
- **UI:** SwiftUI
- **AI:** Whisper (OpenAI) или локальная модель
- **Распознавание:** Speech Recognition API + Whisper API

## Архитектура
```
Flow Mac/
├── FlowMac/                    # Основное приложение
│   ├── App/                    # AppDelegate, главный цикл
│   ├── Core/                   # Ядро системы
│   │   ├── Audio/              # Захват аудио
│   │   ├── Recognition/        # Распознавание речи
│   │   ├── Injection/          # Вставка текста
│   │   └── Hotkey/             # Глобальные хоткеи
│   ├── UI/                     # Интерфейс
│   ├── Models/                 # Модели данных
│   └── Resources/              # Ассеты
├── FlowMacHelper/              # Helper app (для sandbox)
├── Shared/                     # Общий код
└── Tests/
```

## Roadmap
См. Linear: team NeonPoison, префикс FLOW
