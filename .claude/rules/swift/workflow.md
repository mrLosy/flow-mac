# Swift Development Workflow

## Process

1. **Understand** — Прочитать требования, проверить существующий код
2. **Design** — Описать подход перед кодированием
3. **Implement** — Написать код согласно правилам
4. **Test** — Запустить тесты, проверить на устройстве
5. **Review** — Использовать code-reviewer агента

## Code Review Checklist

- [ ] Следует ли код style guide?
- [ ] Все ли optionals безопасно развёрнуты?
- [ ] Обрабатываются ли все ошибки?
- [ ] Используется ли self. явно?
- [ ] Есть ли документация для public API?
- [ ] Проверена ли работа на macOS 13+?

## Pre-Commit

```bash
# Сборка проекта
xcodebuild -project FlowMac.xcodeproj -scheme FlowMac build

# Запуск тестов
xcodebuild test -project FlowMac.xcodeproj -scheme FlowMac

# Проверка entitlements
codesign -d --entitlements :- FlowMac.app
```

## Debugging

```swift
// ✅ Использовать Logger вместо print
import OSLog

private let logger = Logger(subsystem: "com.flowmac.app", category: "AudioEngine")

logger.debug("Starting recording")
logger.error("Failed to start: \(error.localizedDescription)")
```
