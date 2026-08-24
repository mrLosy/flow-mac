# Groq Outreach

## 1. Enterprise Form (groq.com/enterprise-access)

Subject: Production API access — macOS dictation app, App Store launch

We're shipping FlowMac — a macOS menu bar voice dictation app going to the App Store. The entire pipeline runs on Groq: Whisper large-v3-turbo for transcription, Llama 3.1 8B for semantic post-processing. User speaks → we hit Groq → corrected text appears at cursor in under 500ms.

We chose Groq because latency is the product. We benchmarked the full pipeline on Free tier — here are actual numbers from our test suite (97 requests, real audio):

    Whisper p50 latency:    281 ms
    End-to-end p50:         444 ms
    Transcription cost:     $0.000667/min
    LLM cost (8b):          $0.000010/min
    Combined:               $0.000677/min

No other provider gets close on latency. OpenAI Whisper is our fallback, but it's 3-9x more expensive and 2-3x slower.

Projected usage (first 6 months, conservative):

    Active users:           500 → 2,000
    Dictations/user/day:    ~30 × 15 sec = 7.5 min/day
    Daily audio volume:     3,750 → 15,000 min/day
    Whisper requests:       15K → 60K/day
    LLM requests:           15K → 60K/day (1:1)
    Monthly spend:          $75 → $300 (scaling with users)

The app is feature-complete. We need Developer tier (pay-as-you-go) to go to production — Free tier rate limits don't work for a shipping product. The billing page says upgrades are temporarily unavailable.

Questions:
1. Is there a path to get Developer access now for a production app?
2. If not — what's the expected timeline?
3. Should we be looking at Enterprise instead given our volume?

Happy to do a call or share a build.

Daniil Stashkevich
daniil@flowmac.app

---

## 2. Discord (#api-support)

Hey! Building a macOS voice dictation app (FlowMac, heading to App Store). Full pipeline on Groq — Whisper large-v3-turbo + Llama 3.1 8B for semantic correction.

Benchmarked on Free tier: Whisper p50=281ms, end-to-end p50=444ms, cost $0.000677/min audio. The speed is why we chose Groq over OpenAI (which is our fallback at 9x the cost).

App is ready to ship but we need Developer tier for production rate limits. Billing page says upgrades are unavailable. Is there a way to get access for a production app, or a timeline for when it reopens?

Projected ~60K Whisper + 60K LLM requests/day at scale.

---

## 3. Email (support@groq.com)

Subject: Developer tier access for production app (macOS App Store)

Hi,

I need Developer tier access for a production app that's ready to ship to the Mac App Store. Billing page shows upgrades are temporarily unavailable.

FlowMac — macOS menu bar voice dictation. Full pipeline on Groq:
- whisper-large-v3-turbo for transcription
- llama-3.1-8b-instant for semantic post-processing

We benchmarked on Free tier (97 requests, real audio):
- Whisper p50: 281ms, p95: 704ms
- End-to-end pipeline p50: 444ms
- Cost: $0.000677/min audio
- Projected spend: $75-300/month (scaling 500→2K users)

Free tier rate limits (30 req/min LLM) won't work for production. We have OpenAI as fallback but strongly prefer Groq — no one else gives us sub-500ms transcription.

Is there a way to get Developer access now, or should I apply through Enterprise?

Daniil Stashkevich

---

## Просчитанная экономика (приложение к письмам)

### Сравнение провайдеров — фактические данные

| | Groq (тест 97 req) | OpenAI gpt-4o-mini-transcribe | OpenAI whisper-1 |
|---|---|---|---|
| Транскрипция | $0.000667/мин | $0.003/мин | $0.006/мин |
| LLM пост-обработка | $0.000010/мин | $0.000032/мин | $0.000032/мин |
| **Итого/мин** | **$0.000677** | **$0.003032** | **$0.006032** |
| Множитель vs Groq | 1x | 4.5x | 8.9x |
| Whisper p50 latency | 281ms | ~600-800ms* | ~1000-1200ms* |
| E2E p50 latency | 444ms | ~800-1000ms* | ~1200-1500ms* |

*OpenAI latency — оценка по публичным бенчмаркам, не тестировали.

### Маржа по тарифам

| Тариф | Квота | Выручка (−30% Apple) | Groq cost | Groq маржа | OpenAI Mini cost | OpenAI Mini маржа | OpenAI Whisper-1 cost | Whisper-1 маржа |
|---|---|---|---|---|---|---|---|---|
| Free | 15 мин | $0 | $0.01 | — | $0.05 | — | $0.09 | — |
| Basic $5.99 | 120 мин | $4.19 | $0.08 | **98.1%** | $0.36 | **91.4%** | $0.72 | **82.8%** |
| Pro $11.99 | 500 мин | $8.39 | $0.34 | **96.0%** | $1.52 | **82.1%** | $3.02 | **64.2%** |

### Месячные расходы на API по сценариям

| Сценарий | Пользователей | Мин/мес | Groq | OpenAI Mini | OpenAI Whisper-1 |
|---|---|---|---|---|---|
| Launch | 500 | 112,500 | **$76** | $341 | $679 |
| Growth | 2,000 | 450,000 | **$305** | $1,364 | $2,714 |
| Scale | 10,000 | 2,250,000 | **$1,523** | $6,822 | $13,572 |

Расчёт: 30 диктовок/день × 15 сек × 30 дней = 225 мин/мес на пользователя.

### Вывод

Groq — оптимальный провайдер: минимальная стоимость + минимальная latency.
OpenAI gpt-4o-mini-transcribe — рабочий fallback с маржой >82% на всех тарифах.
OpenAI whisper-1 — крайний fallback, маржа Pro падает до 64% но всё ещё прибыльно.
