import Foundation

/// StoreKit product identifiers and plan configuration
enum SubscriptionProductID {
    // Auto-renewable subscriptions (one subscription group)
    static let basicMonthly = "com.flowmac.basic.monthly"
    static let basicAnnual = "com.flowmac.basic.annual"
    static let proMonthly = "com.flowmac.pro.monthly"
    static let proAnnual = "com.flowmac.pro.annual"

    // Non-consumable (one-time purchase)
    static let lifetime = "com.flowmac.lifetime"

    // Consumable (top-up packs)
    static let topUp60min = "com.flowmac.topup.60min"

    /// All subscription product IDs
    static let subscriptions: Set<String> = [
        basicMonthly, basicAnnual, proMonthly, proAnnual
    ]

    /// All product IDs for StoreKit loading
    static let all: Set<String> = [
        basicMonthly, basicAnnual, proMonthly, proAnnual,
        lifetime, topUp60min
    ]

    /// Subscription group identifier
    static let subscriptionGroupID = "com.flowmac.subscriptions"

    /// Map product ID to plan
    static func plan(for productID: String) -> SubscriptionPlan {
        switch productID {
        case basicMonthly, basicAnnual:
            return .basic
        case proMonthly, proAnnual:
            return .pro
        case lifetime:
            return .lifetime
        default:
            return .free
        }
    }

    /// Whether this is an annual product
    static func isAnnual(_ productID: String) -> Bool {
        productID == basicAnnual || productID == proAnnual
    }
}
