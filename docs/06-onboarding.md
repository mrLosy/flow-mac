# Task 6: Онбординг и триал

## Цель

Создать onboarding flow для новых пользователей: welcome screen → permissions → trial activation → first dictation. Цель — привести юзера к первому WOW-моменту за 60 секунд.

## Контекст

Сейчас у приложения нет онбординга. При первом запуске юзер видит пустой menu bar popover и должен сам разобраться. Конкуренты (Wispr Flow, Superwhisper) имеют guided setup. Онбординг критичен для retention — без него юзеры уходят не попробовав.

Онбординг должен:
1. Объяснить что делает приложение (3 секунды)
2. Запросить разрешения (Microphone, Accessibility)
3. Активировать 7-day Pro trial
4. Провести через первую диктовку

## Архитектура

### Новый файл

`FlowMac/Features/Onboarding/OnboardingView.swift`

Директория уже создана: `FlowMac/Features/Onboarding/`

### Показ онбординга

В `FlowMacApp.swift` → `AppDelegate.applicationDidFinishLaunching`:

```swift
let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
if !hasCompletedOnboarding {
    // Показать OnboardingView в отдельном NSWindow
}
```

UserDefaults ключ: `"hasCompletedOnboarding"` (Bool, default: false)

### Триал

При первом запуске — активировать 7-day Pro trial через StoreKit introductory offer (если подключен к App Store) или локально:

```swift
// Если StoreKit ещё не настроен — локальный триал
let trialEndDate = UserDefaults.standard.object(forKey: "trialEndDate") as? Date
if trialEndDate == nil {
    let endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    UserDefaults.standard.set(endDate, forKey: "trialEndDate")
    QuotaService.shared.updatePlan(.pro)
}
```

UserDefaults ключ: `"trialEndDate"` (Date)

## Шаги онбординга (4 экрана)

### Step 1: Welcome

```
┌──────────────────────────────────────┐
│                                      │
│         [App Icon / Waveform]        │
│                                      │
│          Welcome to Flow Mac         │
│                                      │
│    Voice dictation with AI.          │
│    Press a shortcut, speak,          │
│    text appears at your cursor.      │
│                                      │
│          [Get Started →]             │
│                                      │
└──────────────────────────────────────┘
```

### Step 2: Permissions

```
┌──────────────────────────────────────┐
│                                      │
│      Flow Mac needs two things:      │
│                                      │
│  🎤 Microphone                       │
│     To hear your voice               │
│     [Grant Access]  ✅ / ⏳          │
│                                      │
│  ⌨️ Accessibility                    │
│     To type text for you             │
│     [Grant Access]  ✅ / ⏳          │
│                                      │
│          [Continue →]                │
│     (active only when both ✅)       │
│                                      │
└──────────────────────────────────────┘
```

Логика:
- "Grant Access" для микрофона: `AVCaptureDevice.requestAccess(for: .audio)`
- "Grant Access" для Accessibility: `AXIsProcessTrustedWithOptions([prompt: true])`
- Polling каждые 2 секунды для Accessibility (оно требует переход в System Settings)
- Кнопка "Continue" активна только когда оба ✅

### Step 3: Trial Activation

```
┌──────────────────────────────────────┐
│                                      │
│         🎉 7-day Pro Trial           │
│                                      │
│    You get full Pro access:          │
│                                      │
│    ✓ 500 minutes/month               │
│    ✓ AI text enhancement             │
│    ✓ All languages                   │
│    ✓ Push-to-Talk & Express modes    │
│    ✓ Full transcription history      │
│                                      │
│     No credit card required.         │
│     After trial: Free (15 min/mo)    │
│                                      │
│        [Activate Trial →]            │
│                                      │
└──────────────────────────────────────┘
```

При нажатии:
- Установить `trialEndDate`
- `QuotaService.shared.updatePlan(.pro)`

### Step 4: First Dictation

```
┌──────────────────────────────────────┐
│                                      │
│         Try it now!                  │
│                                      │
│    Press  ⌘⇧Space  to start.        │
│    Speak anything.                   │
│    Press again to stop.              │
│                                      │
│    [animated waveform preview]       │
│                                      │
│    Text will appear at your cursor.  │
│                                      │
│          [Done ✓]                    │
│                                      │
└──────────────────────────────────────┘
```

При нажатии "Done":
- `UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")`
- Закрыть окно онбординга
- Показать menu bar popover

## Триал management

### Проверка триала при каждом запуске

В `AppDelegate.applicationDidFinishLaunching`, после инициализации сервисов:

```swift
if let trialEnd = UserDefaults.standard.object(forKey: "trialEndDate") as? Date {
    if Date() < trialEnd {
        // Триал активен
        QuotaService.shared.updatePlan(.pro)
    } else {
        // Триал закончился — downgrade на free (если нет подписки)
        if SubscriptionService.shared.currentPlan == .free {
            QuotaService.shared.updatePlan(.free)
        }
    }
}
```

### Нотификация за 2 дня до конца триала

День 5 триала: локальная нотификация:
```
Title: "Trial ending soon"
Body: "Your Pro trial ends in 2 days. Upgrade to keep all features."
```

### Статистика после триала

При окончании триала показать:
```
"During your trial you dictated X minutes and saved Y minutes of typing."
```

Данные берутся из `UsageMetricsService.shared`.

## Существующие сервисы для интеграции

| Сервис | Использование |
|---|---|
| `QuotaService.shared` | `updatePlan(.pro)` при активации триала |
| `SubscriptionService.shared` | Проверка есть ли реальная подписка (не перезаписывать) |
| `NotificationService.shared` | Нотификации о конце триала |
| `UsageMetricsService.shared` | Статистика за триал |

## Файлы для создания/изменения

| Файл | Действие |
|---|---|
| `FlowMac/Features/Onboarding/OnboardingView.swift` | Создать — 4-step onboarding UI |
| `FlowMac/App/FlowMacApp.swift` | Добавить проверку + показ онбординга |
| `FlowMac.xcodeproj/project.pbxproj` | Добавить OnboardingView.swift в проект |

## Чеклист

- [ ] OnboardingView с 4 шагами
- [ ] Permissions запрос работает (Mic + A11y)
- [ ] Polling для Accessibility (юзер переходит в System Settings и возвращается)
- [ ] Trial активируется при нажатии кнопки
- [ ] Trial проверяется при каждом запуске
- [ ] Downgrade на Free после истечения триала
- [ ] Нотификация за 2 дня до конца
- [ ] Онбординг показывается только один раз
- [ ] "Done" закрывает онбординг и показывает popover
