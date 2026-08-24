# Task 2: StoreKit Configuration и тестирование покупок

## Цель

Создать StoreKit Configuration файл для локального тестирования in-app purchases в Xcode без подключения к App Store Connect. Настроить все 6 продуктов, триал, и протестировать полный purchase flow.

## Контекст

В приложении реализован `SubscriptionService.swift` с StoreKit 2 API. Он загружает продукты, обрабатывает покупки и обновляет entitlements. Но без StoreKit Configuration файла в Xcode тестировать невозможно — `Product.products(for:)` возвращает пустой массив.

## Что нужно создать

### StoreKit Configuration File

Файл: `FlowMac/Resources/FlowMacProducts.storekit`

Формат — JSON, создаётся через Xcode: File → New → StoreKit Configuration File. Но можно создать вручную.

### Продукты (6 штук)

**Auto-Renewable Subscriptions (1 группа: "Flow Mac Subscriptions"):**

| Product ID | Reference Name | Price | Duration | Free Trial |
|---|---|---|---|---|
| com.flowmac.basic.monthly | Basic Monthly | $4.99 | 1 month | 7 days |
| com.flowmac.basic.annual | Basic Annual | $39.99 | 1 year | 14 days |
| com.flowmac.pro.monthly | Pro Monthly | $9.99 | 1 month | 7 days |
| com.flowmac.pro.annual | Pro Annual | $79.99 | 1 year | 14 days |

Subscription Group ID: `com.flowmac.subscriptions`

Upgrade/Downgrade rules внутри группы:
- Pro Annual > Pro Monthly > Basic Annual > Basic Monthly (по уровню)

**Non-Consumable:**

| Product ID | Reference Name | Price |
|---|---|---|
| com.flowmac.lifetime | Lifetime (BYOK) | $29.99 |

**Consumable:**

| Product ID | Reference Name | Price |
|---|---|---|
| com.flowmac.topup.60min | Top-Up 60 Minutes | $1.99 |

### Настройка в Xcode

1. Создать файл `FlowMacProducts.storekit` в `FlowMac/Resources/`
2. В Scheme settings (Product → Scheme → Edit Scheme → Run → Options):
   - StoreKit Configuration: выбрать `FlowMacProducts.storekit`
3. Это позволит тестировать покупки в Simulator и на device без App Store Connect

## Существующий код

### SubscriptionService.swift (FlowMac/Core/Subscription/SubscriptionService.swift)

```swift
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var currentPlan: SubscriptionPlan = .free
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    func loadProducts() async {
        products = try await Product.products(for: SubscriptionProductID.all)
            .sorted { $0.price < $1.price }
    }

    func purchase(_ product: Product) async -> Bool { ... }
    func restorePurchases() async { ... }
    func refreshEntitlements() async { ... }
}
```

### Product IDs (FlowMac/Core/Subscription/SubscriptionProducts.swift)

```swift
enum SubscriptionProductID {
    static let basicMonthly = "com.flowmac.basic.monthly"
    static let basicAnnual = "com.flowmac.basic.annual"
    static let proMonthly = "com.flowmac.pro.monthly"
    static let proAnnual = "com.flowmac.pro.annual"
    static let lifetime = "com.flowmac.lifetime"
    static let topUp60min = "com.flowmac.topup.60min"

    static let all: Set<String> = [
        basicMonthly, basicAnnual, proMonthly, proAnnual,
        lifetime, topUp60min
    ]
}
```

## Тестовые сценарии (чеклист)

### Покупка подписки
- [ ] Загрузка всех 6 продуктов: `products.count == 6`
- [ ] Покупка Basic Monthly → `currentPlan == .basic`
- [ ] Покупка Pro Monthly → `currentPlan == .pro`
- [ ] Upgrade Basic → Pro (автоматический upgrade внутри группы)
- [ ] Downgrade Pro → Basic (действует с конца текущего периода)

### Lifetime
- [ ] Покупка Lifetime → `currentPlan == .lifetime`
- [ ] Lifetime отменяет подписку (non-consumable + subscription = lifetime побеждает)
- [ ] После покупки Lifetime: BYOK логика активна, backend не используется

### Top-Up
- [ ] Покупка Top-Up → `QuotaService.shared.state.bonusSeconds += 3600`
- [ ] Повторная покупка Top-Up: бонус складывается
- [ ] Бонус не сгорает при сбросе периода

### Квота
- [ ] Free plan → quota 15 min → после исчерпания блокировка
- [ ] Basic plan → quota 120 min
- [ ] Pro plan → quota 500 min
- [ ] При смене плана → quota сбрасывается

### Restore
- [ ] `AppStore.sync()` восстанавливает purchases
- [ ] Entitlements обновляются корректно

### Trial
- [ ] При первой покупке → 7/14 days free trial
- [ ] После отмены trial → fallback на Free

### Edge cases
- [ ] Покупка при отсутствии сети → graceful error
- [ ] Отмена покупки пользователем → `userCancelled`
- [ ] Pending покупка (Ask to Buy) → `pending`

## Критерии готовности

- [ ] StoreKit Configuration файл создан и подключен к схеме
- [ ] Все 6 продуктов загружаются при запуске
- [ ] PaywallView показывает все продукты с ценами
- [ ] Покупка любого продукта меняет план в QuotaService
- [ ] AccountView отображает текущий план и квоту
