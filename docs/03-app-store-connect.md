# Task 3: App Store Connect — регистрация продуктов

## Цель

Зарегистрировать все 6 in-app purchase продуктов в App Store Connect, настроить subscription group, pricing, триалы и подготовить метаданные для review.

## Контекст

Приложение Flow Mac — macOS menu bar app для голосовой диктовки. Монетизация через подписку с backend (транскрипция + LLM) и one-time purchase (Lifetime BYOK). Все продукты уже реализованы в коде с конкретными product IDs.

## Предварительные требования

- Apple Developer Program ($99/год) — активна
- App Store Connect аккаунт с доступом к приложению Flow Mac
- Bundle ID зарегистрирован (проверить в Certificates, Identifiers & Profiles)
- Заявка на Small Business Program (15% комиссия вместо 30%) — **подать до релиза**

## Продукты для регистрации

### Subscription Group: "Flow Mac Subscriptions"

Group ID (Reference Name): `com.flowmac.subscriptions`

**Уровни внутри группы (от высшего к низшему):**
1. Pro Annual
2. Pro Monthly
3. Basic Annual
4. Basic Monthly

#### Product 1: Basic Monthly

| Поле | Значение |
|---|---|
| Reference Name | Basic Monthly |
| Product ID | `com.flowmac.basic.monthly` |
| Type | Auto-Renewable Subscription |
| Duration | 1 Month |
| Price | $4.99 (Tier 5) |
| Introductory Offer | Free Trial, 7 days |
| Subscription Group Level | 4 (lowest) |

#### Product 2: Basic Annual

| Поле | Значение |
|---|---|
| Reference Name | Basic Annual |
| Product ID | `com.flowmac.basic.annual` |
| Type | Auto-Renewable Subscription |
| Duration | 1 Year |
| Price | $39.99 (Tier 35) |
| Introductory Offer | Free Trial, 14 days |
| Subscription Group Level | 3 |

Маркетинговый акцент: "Save 33%" ($39.99/год vs $59.88/год при месячной оплате).

#### Product 3: Pro Monthly

| Поле | Значение |
|---|---|
| Reference Name | Pro Monthly |
| Product ID | `com.flowmac.pro.monthly` |
| Type | Auto-Renewable Subscription |
| Duration | 1 Month |
| Price | $9.99 (Tier 9) |
| Introductory Offer | Free Trial, 7 days |
| Subscription Group Level | 2 |

#### Product 4: Pro Annual

| Поле | Значение |
|---|---|
| Reference Name | Pro Annual |
| Product ID | `com.flowmac.pro.annual` |
| Type | Auto-Renewable Subscription |
| Duration | 1 Year |
| Price | $79.99 (Tier 60) |
| Introductory Offer | Free Trial, 14 days |
| Subscription Group Level | 1 (highest) |

### Non-Consumable

#### Product 5: Lifetime

| Поле | Значение |
|---|---|
| Reference Name | Lifetime (BYOK) |
| Product ID | `com.flowmac.lifetime` |
| Type | Non-Consumable |
| Price | $29.99 (Tier 27) |

### Consumable

#### Product 6: Top-Up 60 Minutes

| Поле | Значение |
|---|---|
| Reference Name | Top-Up 60 Minutes |
| Product ID | `com.flowmac.topup.60min` |
| Type | Consumable |
| Price | $1.99 (Tier 2) |

## Локализация (Display Names)

Для каждого продукта нужно указать Display Name и Description на **English** (обязательно) и **Russian** (опционально):

| Product | EN Display Name | EN Description |
|---|---|---|
| Basic Monthly | Basic — 120 min/month | 2 hours of voice dictation per month with AI text enhancement |
| Basic Annual | Basic Annual — 120 min/month | 2 hours of voice dictation per month. Save 33% with annual billing |
| Pro Monthly | Pro — 500 min/month | 8+ hours of dictation, custom vocabulary, all hotkey modes |
| Pro Annual | Pro Annual — 500 min/month | Full Pro features. Save 33% with annual billing |
| Lifetime | Lifetime (Bring Your Own Key) | One-time purchase. Use your own API keys, unlimited dictation |
| Top-Up 60 min | 60 Extra Minutes | Add 60 minutes to your quota. Minutes don't expire |

## App Store Server Notifications V2

Настроить webhook URL в App Store Connect:
- URL: `https://api.flowmac.app/v1/webhook/appstore`
- Version: V2
- Environment: Production + Sandbox

Нотификации которые нужно обработать:
- `SUBSCRIBED` — новая подписка
- `DID_RENEW` — автопродление
- `DID_FAIL_TO_RENEW` — проблема с оплатой
- `EXPIRED` — подписка истекла
- `REVOKE` — refund
- `GRACE_PERIOD_EXPIRED` — grace period закончился
- `CONSUMPTION_REQUEST` — Apple запрашивает info для refund

## Review Information

**App Review Notes (текст для ревьюеров Apple):**

```
Flow Mac is a macOS menu bar voice dictation app. Press a hotkey to start recording,
speak, and the transcribed text is automatically inserted at the cursor position.

Subscriptions:
- Free: 15 minutes/month of AI-powered dictation
- Basic ($4.99/mo): 120 minutes/month
- Pro ($9.99/mo): 500 minutes/month with custom vocabulary
- Lifetime ($29.99): Bring-your-own API keys, no limits

The app requires:
- Microphone access (for voice recording)
- Accessibility access (for text insertion at cursor)
- Network access (for cloud transcription)

Test account credentials: [provide sandbox test account]
```

## Чеклист

- [ ] Apple Developer Program активна
- [ ] Bundle ID зарегистрирован
- [ ] Small Business Program заявка подана
- [ ] Subscription Group создана с 4 уровнями
- [ ] 4 subscription продукта зарегистрированы с ценами и триалами
- [ ] Lifetime (non-consumable) зарегистрирован
- [ ] Top-Up (consumable) зарегистрирован
- [ ] Локализация заполнена (EN обязательно)
- [ ] App Store Server Notifications V2 webhook настроен
- [ ] Sandbox тестовый аккаунт создан
- [ ] Все продукты в статусе "Ready to Submit"
