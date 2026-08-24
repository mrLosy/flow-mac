# Экономическая модель FlowMac

Дата: 2026-04-17
Статус: действующая модель, основана на фактическом тесте Groq API (97 запросов)

## 1. TL;DR

| Провайдер (STT + LLM) | Cost/мин | Basic маржа (120мин) | Pro маржа (500мин) | Latency p50 |
|---|---|---|---|---|
| **Groq Whisper + Llama 8B** ⭐ | **$0.000677** | **98.1%** | **96.0%** | **444ms** |
| Deepgram Nova-3 + Gemini Flash-Lite | $0.006614 | 81.1% | 60.6% | ~600ms* |
| OpenAI gpt-4o-mini-transcribe + GPT-5 Nano | $0.003062 | 91.2% | 81.8% | ~800ms* |
| OpenAI whisper-1 + GPT-4o-mini | $0.006126 | 82.5% | 63.5% | ~1200ms* |
| AssemblyAI + Claude Haiku | $0.004459 | 87.2% | 73.4% | ~700ms* |

*Latency других провайдеров — оценка, не тестировали.

**Вывод:** Groq — оптимум. При недоступности — OpenAI gpt-4o-mini-transcribe сохраняет маржу >80% на всех тарифах.

---

## 2. Формула себестоимости

### Базовая формула на минуту аудио

```
cost_per_minute = transcription_cost_per_min + llm_cost_per_min

где:
    transcription_cost_per_min = <ставка провайдера за минуту>
    llm_cost_per_min = (avg_input_tokens × price_input_per_1M
                       + avg_output_tokens × price_output_per_1M) / 1_000_000
```

**Допущение:** 1 запрос в LLM на каждую транскрипцию (1:1 ratio, подтверждено кодом SemanticCorrectionService.swift).

### Фактические токены (из теста 97 запросов)

```
avg_input_tokens  = 110    (system prompt ~90 + user text ~20)
avg_output_tokens = 25     (LLM возвращает исправленный текст)
```

### Месячная себестоимость на пользователя

```
monthly_cost_per_user = quota_minutes × cost_per_minute
```

### Маржа тарифа

```
revenue_after_apple = price × (1 - apple_commission)
margin_pct = (revenue_after_apple - monthly_cost_per_user) / revenue_after_apple × 100
```

**Константы:**
- `apple_commission = 0.30` (Small Business Program даёт 0.15 при доходе <$1M/год)
- `quota_free = 15 мин`, `quota_basic = 120 мин`, `quota_pro = 500 мин`

---

## 3. Фактические данные теста (Groq)

Тест: 97 запросов через TTS-генерированный корпус, 7.8 мин аудио.
Файл отчёта: `scripts/economics_report_20260417_200656.json`

### Transcription (Whisper large-v3-turbo)

| Метрика | Значение |
|---|---|
| Success rate | 56% (54/97) — из-за Free tier rate limits |
| Latency p50 | 281 ms |
| Latency p95 | 704 ms |
| Latency p99 | 1035 ms |
| Ставка | $0.04/час = $0.000667/мин |

### LLM (llama-3.1-8b-instant)

| Метрика | Значение |
|---|---|
| Avg input tokens | 110 |
| Avg output tokens | 25 |
| Cost per request | $0.0000075 |
| Cost per audio minute | $0.0000075 (1:1 ratio) |
| Latency p50 | ~150 ms |

### End-to-end pipeline

| Метрика | Значение |
|---|---|
| E2E latency p50 | 444 ms |
| E2E latency p95 | 1059 ms |
| **Combined cost/min** | **$0.000677** |
| vs документированная $0.00173 | **−60.9%** |

### ⚠ Расхождение с первоначальной моделью

Документ `docs/07-economics-validation.md` считал LLM по Llama 3.3 70B ($0.59/$0.79 per 1M) = $0.001064/мин.
Код использует `llama-3.1-8b-instant` ($0.05/$0.08 per 1M) = $0.0000075/мин.
**Реальная LLM стоимость в ~140 раз ниже изначальной модели.**

---

## 4. Каталог провайдеров (на 2026-04-17)

### 4.1 Speech-to-Text (STT)

| Провайдер | Модель | Цена | Per-second billing | Latency |
|---|---|---|---|---|
| **Groq** | whisper-large-v3-turbo | $0.000667/мин | да | 281ms (p50) |
| Deepgram | Nova-3 (batch) | $0.0066/мин | да | ~400-600ms |
| Deepgram | Nova-3 (streaming) | $0.0077/мин | да | ~200-400ms |
| AssemblyAI | Universal | ~$0.0042/мин eff. | нет (session) | ~700ms |
| OpenAI | gpt-4o-mini-transcribe | $0.003/мин | да | ~600-800ms |
| OpenAI | whisper-1 | $0.006/мин | да | ~1000-1200ms |
| OpenAI | gpt-4o-transcribe | $0.006/мин | да | ~600-800ms |
| ElevenLabs | Scribe v2 | ~$0.0067/мин | да | ~500ms |

**Нюансы:**
- Deepgram: $200 бесплатных кредитов без карты (~26K минут)
- AssemblyAI биллит session duration — overhead ~65% на коротких клипах
- Groq — единственный с доступом к LLM на той же платформе (1 интеграция)

### 4.2 LLM для пост-обработки

Для расчёта: 110 input + 25 output токенов на запрос.

| Провайдер | Модель | Input $/1M | Output $/1M | Cost/req | Качество |
|---|---|---|---|---|---|
| **Groq** | llama-3.1-8b-instant | $0.05 | $0.08 | **$0.0000075** | хорошее |
| OpenAI | gpt-5-nano | $0.05 | $0.40 | $0.0000155 | хорошее |
| Gemini | 2.5 Flash-Lite | $0.10 | $0.40 | $0.000021 | хорошее |
| Groq | llama-3.3-70b-versatile | $0.59 | $0.79 | $0.0000847 | отличное |
| OpenAI | gpt-4o-mini | $0.15 | $0.60 | $0.0000315 | отличное |
| DeepSeek | V3.2 | $0.28 | $0.42 | $0.0000413 | отличное |
| Claude | Haiku | $0.25 | $1.25 | $0.0000588 | отличное |

**Рекомендации:**
- Для MVP: Groq 8B или Gemini Flash-Lite — достаточно для правки транскрипций
- Для премиум-качества: Groq 70B или Claude Haiku
- **Кэш промптов:** DeepSeek и Claude дают 90% скидку на повторяющиеся system prompts — для нашего use case с 6 фиксированными промптами это снижает стоимость в ~10x

---

## 5. Себестоимость по комбинациям провайдеров

Формула: `cost_per_min = STT_price + (110×input + 25×output) / 1_000_000`

| STT | LLM | STT/мин | LLM/мин | Total/мин |
|---|---|---|---|---|
| Groq Whisper | Groq Llama 8B | $0.000667 | $0.0000075 | **$0.000675** |
| Groq Whisper | Gemini Flash-Lite | $0.000667 | $0.000021 | $0.000688 |
| OpenAI gpt-4o-mini-trans | GPT-5 Nano | $0.003 | $0.0000155 | $0.003016 |
| OpenAI gpt-4o-mini-trans | GPT-4o-mini | $0.003 | $0.0000315 | $0.003032 |
| Deepgram Nova-3 batch | Gemini Flash-Lite | $0.0066 | $0.000021 | $0.006621 |
| Deepgram Nova-3 batch | Groq Llama 8B | $0.0066 | $0.0000075 | $0.006608 |
| AssemblyAI | Gemini Flash-Lite | $0.0042 | $0.000021 | $0.004221 |
| OpenAI whisper-1 | GPT-4o-mini | $0.006 | $0.0000315 | $0.006032 |
| ElevenLabs Scribe v2 | Groq Llama 8B | $0.0067 | $0.0000075 | $0.006708 |

---

## 6. Модель подписки

### 6.1 Тарифы

| Тариф | Квота (мин/мес) | Цена USD | Apple 30% | Выручка чистая |
|---|---|---|---|---|
| Free | 15 | $0 | — | $0 |
| Basic Monthly | 120 | $5.99 | −$1.80 | $4.19 |
| Basic Annual | 120×12=1440 | $59.99 | −$18.00 | $41.99 |
| Pro Monthly | 500 | $11.99 | −$3.60 | $8.39 |
| Pro Annual | 500×12=6000 | $119.99 | −$36.00 | $83.99 |
| Lifetime (BYOK) | 120 (их ключ) | $49.99 | −$15.00 | $34.99 |

**Small Business Program Apple:** при доходе <$1M/год комиссия 15% вместо 30%. На старте маржи ниже считаем при 30%, после перехода на 15% маржи будут +~18% лучше.

### 6.2 Top-up пакет

| Пакет | Минут | Цена | Apple 30% | Выручка чистая |
|---|---|---|---|---|
| 60 min | 60 | $2.99 | −$0.90 | $2.09 |

---

## 7. Маржа по комбинациям (Apple 30%)

Формула маржи: `margin = (revenue_after_apple - quota × cost_per_min) / revenue_after_apple × 100`

### Basic Monthly (120 min, $4.19 чистых)

| Комбинация | Cost | Маржа |
|---|---|---|
| **Groq Whisper + Groq 8B** | $0.08 | **98.1%** |
| OpenAI gpt-4o-mini-trans + GPT-5 Nano | $0.36 | **91.4%** |
| AssemblyAI + Gemini Flash-Lite | $0.51 | 87.9% |
| OpenAI whisper-1 + GPT-4o-mini | $0.72 | 82.7% |
| Deepgram Nova-3 + Groq 8B | $0.79 | 81.1% |

### Pro Monthly (500 min, $8.39 чистых)

| Комбинация | Cost | Маржа |
|---|---|---|
| **Groq Whisper + Groq 8B** | $0.34 | **96.0%** |
| OpenAI gpt-4o-mini-trans + GPT-5 Nano | $1.51 | **82.0%** |
| AssemblyAI + Gemini Flash-Lite | $2.11 | 74.8% |
| OpenAI whisper-1 + GPT-4o-mini | $3.02 | 64.0% |
| Deepgram Nova-3 + Groq 8B | $3.30 | 60.6% |

---

## 8. Прогноз затрат по сценариям

**Допущения:** 30 диктовок × 15 сек × 30 дней = 225 мин/мес на активного пользователя.

### 8.1 Launch (500 активных пользователей)

```
Общий объём аудио/мес = 500 × 225 = 112,500 мин
```

| Провайдер | Месячные расходы API |
|---|---|
| **Groq Whisper + Groq 8B** | **$76** |
| OpenAI gpt-4o-mini-trans + GPT-5 Nano | $339 |
| AssemblyAI + Gemini Flash-Lite | $475 |
| Deepgram Nova-3 + Groq 8B | $744 |
| OpenAI whisper-1 + GPT-4o-mini | $679 |

### 8.2 Growth (2,000 пользователей)

```
Объём = 450,000 мин/мес
```

| Провайдер | Месячные расходы |
|---|---|
| **Groq Whisper + Groq 8B** | **$304** |
| OpenAI gpt-4o-mini-trans + GPT-5 Nano | $1,357 |
| Deepgram Nova-3 + Groq 8B | $2,974 |

### 8.3 Scale (10,000 пользователей)

```
Объём = 2,250,000 мин/мес
```

| Провайдер | Месячные расходы |
|---|---|
| **Groq Whisper + Groq 8B** | **$1,519** |
| OpenAI gpt-4o-mini-trans + GPT-5 Nano | $6,786 |
| Deepgram Nova-3 + Groq 8B | $14,868 |

---

## 9. Прогноз выручки (Apple 30%)

**Допущения conversion rate:**
- Free → Basic: 5%
- Free → Pro: 2%
- Остальные 93% остаются на Free (не приносят денег, но генерируют costs)

### 500 пользователей

```
Free:   465 × 0 мин → $0 выручка, но 15 мин × 465 = 6,975 мин costs
Basic:  25 × 120 мин → $104.75/мес, 3,000 мин costs
Pro:    10 × 500 мин → $83.90/мес, 5,000 мин costs

Общий объём: 14,975 мин (НЕ 112,500 — 225 мин это power user)
MRR: $189
API costs (Groq): 14,975 × $0.000677 = $10.14
Gross margin: $178.86 (94.6%)
```

### 2,000 пользователей

```
MRR: ~$755
API costs (Groq): ~$40
Gross margin: ~$715 (94.7%)
```

### 10,000 пользователей

```
MRR: ~$3,775
API costs (Groq): ~$203
Gross margin: ~$3,572 (94.6%)
```

**Ключевой вывод:** на Groq инфраструктурные расходы <6% от выручки на любом масштабе. На OpenAI gpt-4o-mini-transcribe — ~25% от выручки (всё ещё прибыльно).

---

## 10. Точка безубыточности одного пользователя

Вопрос: сколько минут может диктовать Basic пользователь, чтобы мы были в нуле?

```
breakeven_minutes = revenue_after_apple / cost_per_min
```

| Провайдер | Basic ($4.19) breakeven | Pro ($8.39) breakeven |
|---|---|---|
| Groq | **6,187 мин** | **12,397 мин** |
| OpenAI gpt-4o-mini-trans | 1,389 мин | 2,781 мин |
| Deepgram Nova-3 | 634 мин | 1,270 мин |
| OpenAI whisper-1 | 695 мин | 1,392 мин |

**Интерпретация:** на Groq Basic пользователь окупается даже если диктует **в 52 раза больше** своей квоты. Это даёт огромный буфер на:
- Переиспользование аккаунта (family sharing)
- Power users которые диктуют постоянно
- Бесплатные минуты в рамках промо

---

## 11. Риски

### Риск 1: Groq Developer tier недоступен
**Текущее состояние:** апгрейд до pay-as-you-go закрыт с ноября 2025.
**Impact:** Free tier даёт 30 req/min LLM, 7,200 сек/час Whisper — достаточно для <100 активных пользователей максимум.
**Mitigation:**
1. Outreach в Discord + Enterprise форма + support@ (см. `docs/groq-outreach.md`)
2. Fallback на OpenAI gpt-4o-mini-transcribe + GPT-5 Nano (маржа остаётся >80%)
3. Архитектурный: backend должен поддерживать переключение провайдера по флагу без деплоя

### Риск 2: Groq меняет цены
**Impact:** если цена Whisper удвоится ($0.08/час), cost станет $0.0014/мин — всё ещё лучше OpenAI.
**Mitigation:** формула расчёта модульная — замена константы в одном месте.

### Риск 3: Злоупотребление квотой
**Scenario:** один аккаунт используется несколькими людьми (family sharing, команда).
**Impact:** с маржой 96% на Groq даже 5x превышение квоты оставляет нас в прибыли.
**Mitigation:** rate limiting на бэкенде (max 10 min/час на аккаунт) если станет проблемой.

### Риск 4: App Store rejection
**Impact:** если Apple отклоняет subscription model — fallback на Lifetime + BYOK.
**Mitigation:** Lifetime тариф уже заложен в архитектуре (`QuotaModels.swift:lifetime`).

---

## 12. Чеклист по верификации модели

- [x] Фактические данные теста Groq собраны (97 запросов)
- [x] Исправлено расхождение по модели LLM (8B vs 70B)
- [x] Просчитаны 5+ комбинаций провайдеров
- [x] Тарифная сетка финализирована (Free/Basic/Pro/Lifetime)
- [ ] Groq Developer tier получен ИЛИ решение о переходе на OpenAI
- [ ] Backend конфигурация провайдера через env var
- [ ] Измерить реальный conversion rate Free → Paid (после запуска)
- [ ] Измерить реальный avg minutes/user/day (после запуска)
- [ ] Пересчитать модель после 30 дней реальной эксплуатации

---

## 13. Приложение: как обновлять модель

### Когда обновлять
- Изменилась цена провайдера → обновить таблицу в разделе 4
- Запустили новую комбинацию → добавить строку в раздел 5
- Получили реальные данные по conversion → обновить раздел 9
- Изменилась тарифная сетка → обновить раздел 6

### Инструмент
Скрипт `scripts/economics_validation.py` прогоняет фактический тест Groq и сохраняет JSON с результатами. Для сравнительных расчётов других провайдеров — формулы из раздела 2.

### Источники цен (актуально на 2026-04-17)
- Groq: https://groq.com/pricing
- OpenAI: https://developers.openai.com/api/docs/pricing
- Deepgram: https://deepgram.com/pricing
- AssemblyAI: https://www.assemblyai.com/pricing
- Gemini: https://ai.google.dev/pricing
- Claude: https://www.anthropic.com/pricing

Перепроверять каждые 90 дней.
