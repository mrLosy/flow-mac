import Foundation

// MARK: - Subscription Plan

enum SubscriptionPlan: String, Codable, CaseIterable, Identifiable {
    case free
    case basic
    case pro
    case lifetime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic"
        case .pro: return "Pro"
        case .lifetime: return "Lifetime"
        }
    }

    /// Monthly quota in seconds of audio
    var monthlyQuotaSeconds: Int {
        switch self {
        case .free: return 15 * 60       // 15 min
        case .basic: return 120 * 60     // 120 min (2 hrs)
        case .pro: return 500 * 60       // 500 min (8.3 hrs)
        case .lifetime: return 120 * 60  // 120 min (same as Basic)
        }
    }

    var monthlyQuotaMinutes: Int { monthlyQuotaSeconds / 60 }

    /// Maximum history entries visible in menu
    var historyLimit: Int {
        switch self {
        case .free: return 2
        case .basic, .pro, .lifetime: return 20
        }
    }

    var hasFullHistory: Bool { self != .free }
    var hasFileTranscription: Bool { self != .free }
    var hasAllLanguages: Bool { self != .free }
    var hasMetrics: Bool { self != .free }
    var hasCustomVocabulary: Bool { self == .pro }
    var hasExpressMode: Bool { self == .pro }
    var hasPushToTalk: Bool { self != .free }

    /// Whether this plan uses our backend (vs BYOK)
    var usesBackend: Bool { self != .lifetime }

    var color: String {
        switch self {
        case .free: return "secondary"
        case .basic: return "blue"
        case .pro: return "purple"
        case .lifetime: return "orange"
        }
    }
}

// MARK: - Quota State

struct QuotaState: Codable {
    var plan: SubscriptionPlan
    var usedSeconds: Int
    var periodStart: Date
    var periodEnd: Date
    var bonusSeconds: Int  // top-up or referral bonus

    var totalAvailableSeconds: Int {
        plan.monthlyQuotaSeconds + bonusSeconds
    }

    var remainingSeconds: Int {
        max(0, totalAvailableSeconds - usedSeconds)
    }

    var remainingMinutes: Int {
        remainingSeconds / 60
    }

    var usageRatio: Double {
        guard totalAvailableSeconds > 0 else { return 0 }
        return Double(usedSeconds) / Double(totalAvailableSeconds)
    }

    var isExhausted: Bool {
        remainingSeconds <= 0
    }

    var usedMinutes: Int { usedSeconds / 60 }
    var totalMinutes: Int { totalAvailableSeconds / 60 }

    /// Days until period reset
    var daysUntilReset: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: periodEnd).day ?? 0
        return max(0, days)
    }

    /// Threshold alerts
    var thresholdLevel: QuotaThreshold {
        if isExhausted { return .exhausted }
        if usageRatio >= 0.9 { return .ninety }
        if usageRatio >= 0.8 { return .eighty }
        return .normal
    }

    static func initial() -> QuotaState {
        let now = Date()
        let periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: now)!
        return QuotaState(
            plan: .free,
            usedSeconds: 0,
            periodStart: now,
            periodEnd: periodEnd,
            bonusSeconds: 0
        )
    }
}

// MARK: - Quota Threshold

enum QuotaThreshold {
    case normal
    case eighty
    case ninety
    case exhausted
}

// MARK: - Top-Up Pack

struct TopUpPack {
    let seconds: Int
    let productID: String

    var minutes: Int { seconds / 60 }

    static let standard = TopUpPack(seconds: 60 * 60, productID: "com.flowmac.topup.60min")
}
