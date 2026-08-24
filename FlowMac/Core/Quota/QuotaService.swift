import Foundation
import Combine

/// Tracks audio usage quota per billing period.
/// Persists state to disk; syncs with backend when available.
final class QuotaService: ObservableObject {
    static let shared = QuotaService()

    @Published private(set) var state: QuotaState
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.flowmac.quota", qos: .utility)
    private var lastNotifiedThreshold: QuotaThreshold = .normal

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FlowMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("quota.json")

        // Load or create initial state
        if let loaded = Self.loadFromDisk(fileURL) {
            state = loaded
        } else {
            state = .initial()
        }
        resetPeriodIfNeeded()
    }

    // MARK: - Public API

    /// Whether quota tracking applies. BYOK (user provides their own API key) bypasses quota,
    /// since transcription billing happens at the provider directly.
    var isQuotaActive: Bool {
        if TranscriptionProvider.current.isConfigured { return false }
        return state.plan.usesBackend
    }

    /// Check if there's enough quota for a given audio duration
    func canTranscribe(audioDurationSeconds: Int) -> Bool {
        guard isQuotaActive else { return true }
        return state.remainingSeconds >= audioDurationSeconds
    }

    /// Consume quota after successful transcription
    func consumeSeconds(_ seconds: Int) {
        guard isQuotaActive else { return }
        state.usedSeconds += seconds
        checkThreshold()
        save()
        DebugLog.log("Quota: consumed \(seconds)s, remaining \(state.remainingSeconds)s")
    }

    /// Add bonus minutes (top-up purchase or referral)
    func addBonusSeconds(_ seconds: Int) {
        let maxBonus = 500 * 60 // cap at 500 min accumulation
        state.bonusSeconds = min(state.bonusSeconds + seconds, maxBonus)
        save()
        DebugLog.log("Quota: added \(seconds)s bonus, total bonus \(state.bonusSeconds)s")
    }

    /// Update plan (called when subscription changes)
    func updatePlan(_ plan: SubscriptionPlan) {
        let oldPlan = state.plan
        state.plan = plan

        // If upgrading, reset period to now
        if plan != oldPlan {
            let now = Date()
            state.periodStart = now
            state.periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: now)!
            state.usedSeconds = 0
            lastNotifiedThreshold = .normal
            DebugLog.log("Quota: plan changed \(oldPlan.rawValue) -> \(plan.rawValue)")
        }
        save()
    }

    /// Force reset period (for testing or manual refresh)
    func resetPeriod() {
        let now = Date()
        state.usedSeconds = 0
        state.periodStart = now
        state.periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: now)!
        // Bonus seconds carry over (they don't expire on reset)
        lastNotifiedThreshold = .normal
        save()
        DebugLog.log("Quota: period reset")
    }

    // MARK: - Period Management

    /// Check if the current period has expired and reset if needed
    private func resetPeriodIfNeeded() {
        guard Date() >= state.periodEnd else { return }
        resetPeriod()
    }

    // MARK: - Threshold Notifications

    private func checkThreshold() {
        let threshold = state.thresholdLevel
        guard threshold != lastNotifiedThreshold else { return }
        lastNotifiedThreshold = threshold

        switch threshold {
        case .eighty, .ninety:
            NotificationService.shared.notifyQuotaWarning(
                remainingMinutes: state.remainingMinutes,
                resetDate: formattedResetDate
            )
        case .exhausted:
            NotificationService.shared.notifyQuotaExhausted()
        case .normal:
            break
        }
    }

    private var formattedResetDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: state.periodEnd)
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = state
        queue.async { [fileURL] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                NSLog("[FlowMac] Failed to save quota: %@", error.localizedDescription)
            }
        }
    }

    private static func loadFromDisk(_ url: URL) -> QuotaState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(QuotaState.self, from: data)
        } catch {
            NSLog("[FlowMac] Failed to load quota: %@", error.localizedDescription)
            return nil
        }
    }
}
