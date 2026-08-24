# Flow Mac — Launch Roadmap

Документация для запуска Flow Mac на рынок с подписочной моделью.

Каждый файл — самодостаточная задача для AI-агента или разработчика. Файлы содержат полный контекст, API контракты, схемы БД, чеклисты.

## Задачи

| # | Файл | Задача | Зависимости | Приоритет |
|---|---|---|---|---|
| 1 | [01-backend.md](01-backend.md) | Backend сервер: /transcribe, /auth, /quota, webhook | — | P0 |
| 2 | [02-storekit-testing.md](02-storekit-testing.md) | StoreKit Configuration файл + тестирование покупок | — | P0 |
| 3 | [03-app-store-connect.md](03-app-store-connect.md) | Регистрация 6 продуктов в App Store Connect | — | P0 |
| 4 | [04-backend-switchover.md](04-backend-switchover.md) | Переключение приложения на backend | #1 backend готов | P1 |
| 5 | [05-app-store-submission.md](05-app-store-submission.md) | Подготовка к App Store review | #2, #3, #4 | P1 |
| 6 | [06-onboarding.md](06-onboarding.md) | Онбординг + 7-day Pro trial | #2 | P1 |
| 7 | [07-economics-validation.md](07-economics-validation.md) | Тестирование реальных API costs | #1 | P0 |

## Граф зависимостей

```
[01-backend] ──────→ [04-switchover] ──→ [05-submission]
                                    ↗
[02-storekit] ─→ [06-onboarding] ──/
                                  ↗
[03-app-store-connect] ──────────/

[07-economics] (параллельно с #1)
```

## Параллельные треки

**Трек A (backend):** #1 → #7 → #4
**Трек B (app store):** #2 + #3 (параллельно) → #6 → #5
**Финальная сборка:** #4 + #6 → #5

## Ссылки

- Полный план экономики: `/.claude/plans/merry-munching-minsky.md`
- Текущий код: `FlowMac/Core/Quota/`, `FlowMac/Core/Subscription/`, `FlowMac/Core/Backend/`
- CLAUDE.md (архитектура проекта): `/CLAUDE.md`
