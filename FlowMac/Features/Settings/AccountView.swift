import SwiftUI

/// Account tab in Settings — shows current plan, quota usage, and upgrade options
struct AccountView: View {
    @ObservedObject var quotaService = QuotaService.shared
    @ObservedObject var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Current plan
            planSection

            Divider()

            // Quota usage
            if quotaService.state.plan.usesBackend {
                quotaSection
                Divider()
            }

            // Actions
            actionsSection

            Spacer()
        }
    }

    // MARK: - Plan Section

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Plan")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(planGradient)
                        .frame(width: 40, height: 40)

                    Image(systemName: planIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(quotaService.state.plan.displayName)
                        .font(.system(size: 15, weight: .semibold))

                    Text(planDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if quotaService.state.plan == .free {
                    Button("Upgrade") { showPaywall = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private var planGradient: LinearGradient {
        switch quotaService.state.plan {
        case .free:
            return LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .basic:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pro:
            return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lifetime:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var planIcon: String {
        switch quotaService.state.plan {
        case .free: return "person"
        case .basic: return "star"
        case .pro: return "star.fill"
        case .lifetime: return "infinity"
        }
    }

    private var planDescription: String {
        switch quotaService.state.plan {
        case .free: return "15 min/month, limited features"
        case .basic: return "120 min/month, full history"
        case .pro: return "500 min/month, all features"
        case .lifetime: return "Unlimited (your API keys)"
        }
    }

    // MARK: - Quota Section

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage This Period")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.12))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(quotaBarColor)
                            .frame(width: max(0, CGFloat(quotaService.state.usageRatio) * geo.size.width))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(quotaService.state.usedMinutes) / \(quotaService.state.totalMinutes) min")
                        .font(.system(size: 12, weight: .medium))

                    Spacer()

                    Text("Resets in \(quotaService.state.daysUntilReset) days")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if quotaService.state.bonusSeconds > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "gift")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("Includes \(quotaService.state.bonusSeconds / 60) bonus min")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
        }
    }

    private var quotaBarColor: LinearGradient {
        let ratio = quotaService.state.usageRatio
        if ratio >= 0.9 {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        } else if ratio >= 0.8 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if quotaService.state.plan != .pro && quotaService.state.plan != .lifetime {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 12))
                        Text("Upgrade Plan")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }

            Button {
                Task { await subscriptionService.restorePurchases() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("Restore Purchases")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
}
