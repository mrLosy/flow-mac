# Task 1: Flow Mac Backend

## Цель

Создать backend-сервер для Flow Mac — macOS приложения голосовой диктовки. Сервер проксирует запросы к Groq API (транскрипция + LLM пост-обработка), управляет квотами пользователей и валидирует подписки.

## Контекст

Flow Mac — menu bar приложение: пользователь нажимает хоткей, диктует текст, получает транскрипцию с AI-улучшением прямо в курсор. Ранее пользователи вводили свои API ключи (BYOK). Теперь мы добавляем подписочную модель, где транскрипция идёт через наш сервер.

**Монетизация:**
- Free: 15 мин/мес (через наш backend)
- Basic $4.99/мес: 120 мин/мес
- Pro $9.99/мес: 500 мин/мес
- Lifetime $29.99: BYOK, без backend (обрабатывается на клиенте)

## API, который ожидает клиент

Клиент уже реализован в `FlowMac/Core/Backend/BackendAPIService.swift`. Вот контракт:

### POST /v1/transcribe

**Описание:** Принимает аудио, транскрибирует через Groq Whisper, улучшает через Groq LLM, возвращает финальный текст. Одним запросом — транскрипция + пост-обработка.

**Headers:**
```
Authorization: Bearer {jwt_token}
Content-Type: multipart/form-data; boundary={boundary}
```

**Multipart fields:**
| Field | Type | Required | Description |
|---|---|---|---|
| file | binary | да | WAV аудио (16kHz, mono, 16-bit PCM) |
| language | string | нет | ISO код языка ("en", "ru", ...). Если отсутствует — auto-detect |
| prompt | string | нет | Подсказка для Whisper (пользовательский контекст) |
| app_context | string | нет | Категория приложения: "terminal", "coding", "chat", "email", "writing", "general" |

**Response 200:**
```json
{
  "text": "Финальный текст после LLM обработки",
  "raw_text": "Оригинальный текст от Whisper",
  "duration_seconds": 15,
  "remaining_seconds": 7185
}
```

**Error responses:**
| HTTP Code | Значение |
|---|---|
| 401 | Невалидный или отсутствующий JWT |
| 402 | Квота исчерпана |
| 429 | Rate limit |
| 500+ | Ошибка сервера / Groq API |

### POST /v1/auth/apple

**Описание:** Обмен Apple Sign In identity token на JWT.

**Body:**
```json
{
  "identity_token": "eyJ...",
  "user_id": "000123.abc..."
}
```

**Response 200:**
```json
{
  "token": "jwt_token_here",
  "expires_at": "2026-05-16T00:00:00Z"
}
```

### GET /v1/quota

**Описание:** Текущее состояние квоты пользователя.

**Headers:** `Authorization: Bearer {jwt}`

**Response 200:**
```json
{
  "plan": "basic",
  "used_seconds": 3600,
  "total_seconds": 7200,
  "remaining_seconds": 3600,
  "period_end": "2026-05-16T00:00:00Z",
  "bonus_seconds": 0
}
```

## Внешние API для проксирования

### Groq Whisper (транскрипция)

```
POST https://api.groq.com/openai/v1/audio/transcriptions
Authorization: Bearer {GROQ_API_KEY}
Content-Type: multipart/form-data

Fields:
  file: audio.wav
  model: whisper-large-v3-turbo
  language: (опционально)
  response_format: json
  prompt: (опционально)
```

Response: `{"text": "transcribed text"}`

**Стоимость:** $0.04/час = $0.000667/мин

### Groq LLM (пост-обработка)

```
POST https://api.groq.com/openai/v1/chat/completions
Authorization: Bearer {GROQ_API_KEY}
Content-Type: application/json

{
  "model": "llama-3.3-70b-versatile",
  "messages": [
    {"role": "system", "content": "{system_prompt_по_категории}"},
    {"role": "user", "content": "{raw_transcription}"}
  ],
  "temperature": 0.1,
  "max_tokens": 1024
}
```

**Стоимость:** ~$0.000532/запрос

### System prompts по категориям app_context

| Категория | System prompt |
|---|---|
| terminal | Fix transcription errors in this terminal command dictation. Preserve CLI terms, flags, paths. Common corrections: "suit oh" → "sudo", "see dee" → "cd". Only fix obvious speech-to-text errors. Return corrected text only. |
| coding | Fix transcription errors in this code-related dictation. Apply correct casing: camelCase, PascalCase, snake_case. Preserve code syntax and technical terms. Return corrected text only. |
| chat | Lightly fix transcription errors in this chat message. Preserve informal tone, slang, casual style. Don't add formal punctuation. Return corrected text only. |
| email | Fix transcription errors in this email text. Apply proper grammar, punctuation, professional tone. Return corrected text only. |
| writing | Fix transcription errors in this text. Apply full grammar correction, proper punctuation, capitalization. Return corrected text only. |
| general | Fix obvious transcription errors in this dictated text. Apply basic punctuation and capitalization. Preserve original meaning. Return corrected text only. |

## Логика квоты

1. **Перед транскрипцией:** проверить `remaining_seconds >= estimated_duration`. Если нет — вернуть 402.
2. **После успешной транскрипции:** списать `duration_seconds` (реальная длительность аудио, посекундно).
3. **При ошибке API:** НЕ списывать квоту.
4. **Сброс периода:** автоматический по `period_end`. При сбросе `used_seconds = 0`, `bonus_seconds` сохраняются.
5. **Top-up:** при получении уведомления от App Store (webhook) — добавить 3600 сек (60 мин) к `bonus_seconds`. Максимум 30000 сек (500 мин) накопления.

## Валидация подписки

Использовать **App Store Server API v2** для валидации:
- При каждом `/transcribe` запросе: проверить JWT, затем план из БД.
- Периодически (cron каждые 6 часов): пулить App Store Server Notifications V2 для обновления статусов (renewal, cancellation, refund).
- Webhook endpoint `POST /v1/webhook/appstore` для real-time нотификаций от Apple.

## Технический стек (рекомендуемый)

- **Язык:** Python (FastAPI)
- **БД:** SQLite (до 1000 юзеров) → PostgreSQL (выбери лучшее решение сразу)
- **Хостинг:** Hetzner CX22 (~€5/мес) или Fly.io
- **Auth:** Apple Sign In → JWT (RS256)
- **Secrets:** env vars для GROQ_API_KEY, JWT_SECRET

## Схема БД

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,           -- Apple user ID
  email TEXT,
  plan TEXT DEFAULT 'free',      -- free, basic, pro
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT REFERENCES users(id),
  used_seconds INTEGER DEFAULT 0,
  bonus_seconds INTEGER DEFAULT 0,
  period_start TIMESTAMP,
  period_end TIMESTAMP
);

CREATE TABLE subscriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT REFERENCES users(id),
  product_id TEXT,               -- com.flowmac.basic.monthly, etc.
  original_transaction_id TEXT,
  status TEXT,                   -- active, expired, revoked
  expires_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Rate limiting

- Free: 10 req/min
- Basic: 30 req/min
- Pro: 60 req/min
- По IP: 100 req/min (защита от абуза)

## Критерии готовности

- [ ] POST /v1/transcribe работает end-to-end (аудио → Groq → LLM → ответ)
- [ ] POST /v1/auth/apple выдаёт JWT
- [ ] GET /v1/quota возвращает актуальное состояние
- [ ] Квота списывается корректно
- [ ] 402 при исчерпании квоты
- [ ] Rate limiting работает
- [ ] App Store webhook принимает нотификации
- [ ] Нагрузочный тест: 50 concurrent запросов
