# Task 7: Валидация экономической модели

## Цель

Провести реальный тест API costs, замерить фактическую стоимость транскрипции + LLM обработки, сверить с расчётной моделью, и нагрузочно протестировать Groq rate limits.

## Контекст

Вся экономика подписки построена на расчётной себестоимости **$0.00173/мин аудио** (Groq Whisper $0.000667/мин + Groq LLM $0.001064/мин). Если реальные цифры отличаются — нужно пересмотреть квоты или цены до запуска.

## Расчётная модель (baseline)

| Компонент | Стоимость | Источник |
|---|---|---|
| Groq Whisper v3 Turbo | $0.04/час = $0.000667/мин | groq.com/pricing |
| Groq Llama 3.3 70B (input 500 tok) | $0.000295/req | $0.59/1M tokens |
| Groq Llama 3.3 70B (output 300 tok) | $0.000237/req | $0.79/1M tokens |
| LLM per request | $0.000532/req | input + output |
| LLM per minute (2 req/min worst case) | $0.001064/мин | |
| **Total per minute** | **$0.00173/мин** | |

## Тест 1: Реальная стоимость транскрипции

### Методика

1. Создать тестовый аккаунт на console.groq.com
2. Записать начальный баланс / usage
3. Выполнить 100 транскрипций с реальной речью:
   - 50 коротких (5-15 сек) — типичная диктовка
   - 30 средних (15-30 сек) — параграф
   - 20 длинных (30-60 сек) — развёрнутая мысль
4. Для каждой: замерить длительность аудио, время ответа, размер response
5. Проверить Groq billing dashboard: реальные charges

### Что замерить

| Метрика | Как |
|---|---|
| API cost per minute | Groq dashboard: total charges / total audio minutes |
| Latency (p50, p95, p99) | Timestamps в коде |
| Error rate | Count 4xx/5xx responses |
| Minimum billable duration | Groq bills min 10 sec — проверить |

### Ожидаемый результат

100 транскрипций × ~20 сек среднее = ~33 мин аудио.
Ожидаемый cost: 33 × $0.000667 = **$0.022**

Если реальный cost > $0.05 — модель нужно пересмотреть.

## Тест 2: Реальная стоимость LLM обработки

### Методика

1. Взять 100 транскрипций из Теста 1
2. Для каждой отправить в Groq Llama 3.3 70B chat completion:
   - System prompt: ~200 tokens (по категории)
   - User message: реальный текст транскрипции
3. Замерить: input tokens, output tokens, cost в Groq dashboard

### Что замерить

| Метрика | Как |
|---|---|
| Avg input tokens per request | Response headers или usage field |
| Avg output tokens per request | Response headers или usage field |
| Actual cost per request | Dashboard |
| Latency | Timestamps |

### Ожидаемый результат

100 запросов × $0.000532 = **$0.053**

Если реальный > $0.10 — проверить: может tokens больше чем оценка 500+300.

## Тест 3: Combined pipeline cost

### Методика

Прогнать полный pipeline как на production:
1. Запись аудио → Groq Whisper → Groq LLM → финальный текст
2. 100 раз, разные длительности

### Что замерить

| Метрика | Ожидание | Red flag |
|---|---|---|
| Cost per minute audio | $0.00173 | > $0.005 |
| Total pipeline latency | < 3 сек | > 5 сек |
| Error rate | < 1% | > 5% |

## Тест 4: Rate limits и concurrent load

### Groq Free Tier limits

| Resource | Limit |
|---|---|
| Audio (Whisper) | 7,200 сек/час, 28,800 сек/день |
| LLM requests | 30 req/min, 14,400 req/day |
| LLM tokens | 6,000 tok/min |

### Тест

1. **Burst test:** 20 concurrent transcription requests → все проходят?
2. **Sustained load:** 5 req/sec в течение 1 минуты → rate limits?
3. **Daily limit test:** приблизиться к 28,800 сек/день → что происходит?

### Что замерить

| Сценарий | Ожидание |
|---|---|
| 20 concurrent | Все проходят (Groq Whisper burst OK) |
| 5 req/sec sustained | Может начать 429 → нужен retry с backoff |
| LLM 30 req/min | Ограничение → нужна очередь или paid tier |

### Важно: Paid Tier

Для production нужен **Groq paid tier** (не free). Проверить:
- Paid tier rate limits
- Pricing остаётся тем же?
- SLA guarantees

## Тест 5: Экономика по тарифам

### Simulation: средний пользователь

**Профиль:** 30 диктовок/день, 15 сек каждая = 7.5 мин/день = 225 мин/мес

| Тариф | Квота | Хватит? | Наш cost | Доход (после Apple) | Маржа |
|---|---|---|---|---|---|
| Free (15 мин) | 15 мин | Нет (2 дня) | $0.026 | $0 | -$0.026 |
| Basic (120 мин) | 120 мин | ~16 дней | $0.208 | $4.24 | 95% |
| Pro (500 мин) | 500 мин | Да, с запасом | $0.865 | $8.49 | 90% |

### Simulation: power user

**Профиль:** 80 диктовок/день, 20 сек каждая = 26.7 мин/день = 800 мин/мес

| Тариф | Квота | Хватит? | Наш cost | Маржа |
|---|---|---|---|---|
| Basic (120 мин) | 120 мин | ~4.5 дня | $0.208 | 95% (capped) |
| Pro (500 мин) | 500 мин | ~18.7 дней | $0.865 | 90% (capped) |

Power user упирается в квоту → покупает top-up или апгрейдит.

## Результаты (заполнить после тестирования)

```
### Фактические данные

Дата тестирования: ___
Groq API tier: free / paid

Transcription:
- 100 requests, total audio: ___ min
- Groq dashboard charge: $___
- Actual cost per minute: $___
- Avg latency: ___ ms
- P95 latency: ___ ms
- Error rate: ___%

LLM Post-processing:
- 100 requests
- Avg input tokens: ___
- Avg output tokens: ___
- Groq dashboard charge: $___
- Actual cost per request: $___
- Avg latency: ___ ms

Combined pipeline:
- Actual cost per minute: $___
- vs calculated $0.00173 → difference: ___%

Rate limit test:
- 20 concurrent: pass / fail
- Sustained 5 req/sec: ___ before 429
- Daily limit hit at: ___ seconds

Conclusion:
- Model accurate: yes / no
- Adjustments needed: ___
```

## Чеклист

- [ ] Groq аккаунт с billing доступом
- [ ] 100 транскрипций выполнены
- [ ] 100 LLM запросов выполнены
- [ ] Dashboard charges записаны
- [ ] Latency замерена (p50, p95, p99)
- [ ] Rate limit тест пройден
- [ ] Фактические данные заполнены в шаблоне выше
- [ ] Вывод: модель точна / требует корректировки
