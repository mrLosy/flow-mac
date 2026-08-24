import SwiftUI
import StoreKit

/// Shown when quota is exhausted or user taps upgrade
struct PaywallView: View {
    @ObservedObject var quotaService = QuotaService.shared
    @ObservedObject var subscriptionService = SubscriptionService.shared
    @State private var purchasing: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Plans
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(subscriptionService.subscriptionProducts(), id: \.id) { product in
                        planCard(product)
                    }

                    // Lifetime
                    if let lifetime = subscriptionService.lifetimeProduct() {
                        lifetimeCard(lifetime)
                    }

                    // Top-up (only for paid users)
                    if quotaService.state.plan != .free, let topUp = subscriptionService.topUpProduct() {
                        topUpCard(topUp)
                    }
                }
                .padding(24)
            }

            // Footer
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(width: 420, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            if quotaService.state.isExhausted {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                Text("Minutes exhausted")
                    .font(.system(size: 18, weight: .semibold))

                Text("\(quotaService.state.usedMinutes) / \(quotaService.state.totalMinutes) min used. Resets in \(quotaService.state.daysUntilReset) days.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Upgrade Flow Mac")
                    .font(.system(size: 18, weight: .semibold))

                Text("Unlock more dictation minutes and premium features")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Plan Card

    private func planCard(_ product: Product) -> some View {
        let plan = SubscriptionProductID.plan(for: product.id)
        let isAnnual = SubscriptionProductID.isAnnual(product.id)
        let isCurrent = subscriptionService.currentPlan == plan && !isAnnual

        return Button {
            Task { await purchaseProduct(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.displayName)
                            .font(.system(size: 14, weight: .semibold))
                        if isAnnual {
                            Text("Annual")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(3)
                        }
                        if isCurrent {
                            Text("Current")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                        }
                    }

                    Text("\(plan.monthlyQuotaMinutes) min/month")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if purchasing == product.id {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(product.displayPrice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil || isCurrent)
    }

    // MARK: - Lifetime Card

    private func lifetimeCard(_ product: Product) -> some View {
        let isCurrent = subscriptionService.currentPlan == .lifetime

        return Button {
            Task { await purchaseProduct(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Lifetime")
                            .font(.system(size: 14, weight: .semibold))
                        Text("BYOK")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(3)
                    }
                    Text("Your API keys, no limits, pay once")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if purchasing == product.id {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(product.displayPrice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil || isCurrent)
    }

    // MARK: - Top-Up Card

    private func topUpCard(_ product: Product) -> some View {
        Button {
            Task { await purchaseProduct(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top-Up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("+\(TopUpPack.standard.minutes) min (doesn't expire)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if purchasing == product.id {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(product.displayPrice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let error = subscriptionService.purchaseError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Button("Restore Purchases") {
                    Task { await subscriptionService.restorePurchases() }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)

                Spacer()

                Button("Close") { dismiss() }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Purchase

    private func purchaseProduct(_ product: Product) async {
        purchasing = product.id
        let success = await subscriptionService.purchase(product)
        purchasing = nil
        if success {
            dismiss()
        }
    }
}
