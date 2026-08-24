# Task 4: Переключение приложения на backend

## Цель

Переключить RecognitionService и SemanticCorrectionService с прямых вызовов Groq/OpenAI API на наш backend (`api.flowmac.app`). Для Lifetime (BYOK) юзеров — сохранить прямые вызовы.

## Контекст

Сейчас приложение напрямую обращается к Groq/OpenAI API, используя API ключи пользователя (BYOK). Нужно сделать так:
- **Подписчики (Free/Basic/Pro):** транскрипция и LLM идут через наш backend. API ключи не нужны. Backend сам проксирует к Groq.
- **Lifetime (BYOK):** сохранить текущее поведение — прямые вызовы с ключами пользователя.

## Текущая архитектура (что менять)

### RecognitionService.swift

Путь: `FlowMac/Core/Recognition/RecognitionService.swift`

Сейчас:
```swift
private var provider: TranscriptionProvider {
    TranscriptionProvider.current
}
private var apiKey: String { provider.apiKey }
private var apiURL: String { provider.apiURL }
```

Метод `transcribe(audioData:completion:)` строит multipart запрос к `provider.apiURL` с `provider.apiKey`.

**Что нужно:** Если план = Free/Basic/Pro (usesBackend = true), вызывать `BackendAPIService.shared.transcribe(...)` вместо прямого API. Если Lifetime — оставить как есть.

### SemanticCorrectionService.swift

Путь: `FlowMac/Core/PostProcessing/SemanticCorrectionService.swift`

Сейчас:
```swift
switch provider {
case .openai:
    baseURL = "https://api.openai.com/v1/chat/completions"
    model = "gpt-4o-mini"
case .groq:
    baseURL = "https://api.groq.com/openai/v1/chat/completions"
    model = "llama-3.1-8b-instant"
}
```

**Что нужно:** Для подписчиков — LLM обработка уже включена в `/v1/transcribe` ответ backend'а (поле `text` содержит улучшенный текст). Отдельный вызов LLM не нужен. Для Lifetime — оставить как есть.

### HotkeyManager.swift (stopRecording)

Путь: `FlowMac/Core/Hotkey/HotkeyManager.swift`, метод `stopRecording()`

Текущий flow:
```
audioData → RecognitionService.transcribe → cleanedText → SemanticCorrectionService.correct → TextInjector.insertText
```

**Новый flow для подписчиков:**
```
audioData → BackendAPIService.transcribe (включает и Whisper и LLM) → TextInjector.insertText
```
Пропускается отдельный шаг SemanticCorrection, т.к. backend уже это делает.

**Новый flow для Lifetime (BYOK):**
```
audioData → RecognitionService.transcribe → cleanedText → SemanticCorrectionService.correct → TextInjector.insertText
```
Как сейчас, без изменений.

## BackendAPIService (уже создан)

Путь: `FlowMac/Core/Backend/BackendAPIService.swift`

```swift
func transcribe(
    audioData: Data,
    language: String,
    prompt: String?,
    appContext: String?,
    completion: @escaping (Result<TranscribeResponse, BackendError>) -> Void
)
```

Response:
```swift
struct TranscribeResponse: Codable {
    let text: String             // Финальный текст (уже с LLM)
    let rawText: String?         // Оригинал от Whisper
    let durationSeconds: Int
    let remainingSeconds: Int
}
```

## Ключевая проверка: план пользователя

```swift
QuotaService.shared.state.plan.usesBackend  // true для Free/Basic/Pro, false для Lifetime
```

## План изменений

### 1. HotkeyManager.swift — разветвление flow

В методе `stopRecording()`, после валидации аудио и проверки квоты, добавить ветвление:

```swift
if QuotaService.shared.state.plan.usesBackend {
    // Backend flow: один запрос, всё включено
    let language = UserDefaults.standard.string(forKey: "recognitionLanguage") ?? "auto"
    let prompt = UserDefaults.standard.string(forKey: "transcriptionPrompt")
    let category = AppCategory.detect(bundleIdentifier: previousApp?.bundleIdentifier)
    
    BackendAPIService.shared.transcribe(
        audioData: audioData,
        language: language,
        prompt: prompt,
        appContext: category.rawValue
    ) { result in
        // Обработать result.text → TextInjector
        // Обновить quota из result.remainingSeconds
    }
} else {
    // BYOK flow: как сейчас
    recognitionService.transcribe(audioData: audioData) { ... }
}
```

### 2. RecognitionService.swift — без изменений

Оставить как есть — используется только в BYOK flow.

### 3. SemanticCorrectionService.swift — без изменений

Оставить как есть — используется только в BYOK flow. Для backend flow LLM уже встроен в ответ.

### 4. SettingsView — условный показ API key настроек

Показывать секцию "Provider / API Key" только для Lifetime:

```swift
if QuotaService.shared.state.plan == .lifetime {
    // Показать провайдер настройки, API ключи
} else {
    // Показать "Managed by Flow Mac" badge
}
```

### 5. Обработка ошибки 402 (Quota Exhausted)

Когда backend возвращает 402:
```swift
case .failure(.quotaExhausted):
    // Показать PaywallView
    NotificationService.shared.notifyQuotaExhausted()
```

### 6. Обработка offline/backend down

Если backend недоступен для подписчика:
```swift
case .failure(.network(_)):
    NotificationService.shared.notifyRecordingError(
        "Server unavailable. Check your internet connection."
    )
```

Не фоллбечить на BYOK (у подписчика нет API ключей).

## Тестовые сценарии

- [ ] Free юзер: диктовка → backend → текст вставлен
- [ ] Basic юзер: 120 мин квота уменьшается после каждой диктовки
- [ ] Pro юзер: app_context передаётся корректно (email/chat/code)
- [ ] Lifetime юзер: диктовка → Groq API напрямую → SemanticCorrection → текст вставлен
- [ ] Free юзер без сети: показывает ошибку, не крашится
- [ ] Квота 0: 402 → PaywallView
- [ ] Backend вернул raw_text + text: используется text (улучшенный)

## Файлы для изменения

| Файл | Что менять |
|---|---|
| `FlowMac/Core/Hotkey/HotkeyManager.swift` | Ветвление usesBackend в stopRecording() |
| `FlowMac/Features/Settings/SettingsView.swift` | Скрыть API key настройки для подписчиков |
| `FlowMac/Features/Settings/SettingsTabContent.swift` | Условный показ provider секции |

## Файлы НЕ трогать

| Файл | Почему |
|---|---|
| RecognitionService.swift | Используется Lifetime, не менять |
| SemanticCorrectionService.swift | Используется Lifetime, не менять |
| BackendAPIService.swift | Уже готов |
| QuotaService.swift | Уже готов |
