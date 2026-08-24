import Foundation
import StoreKit
import Combine

/// Manages StoreKit 2 subscriptions, lifetime purchase, and top-up packs.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var currentPlan: SubscriptionPlan = .free
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: SubscriptionProductID.all)
                .sorted { $0.price < $1.price }
            DebugLog.log("StoreKit: loaded \(products.count) products")
        } catch {
            DebugLog.log("StoreKit: failed to load products — \(error.localizedDescription)")
        }
        isLoading = false
    }

    /// Get products filtered by type
    func subscriptionProducts() -> [Product] {
        products.filter { SubscriptionProductID.subscriptions.contains($0.id) }
    }

    func lifetimeProduct() -> Product? {
        products.first { $0.id == SubscriptionProductID.lifetime }
    }

    func topUpProduct() -> Product? {
        products.first { $0.id == SubscriptionProductID.topUp60min }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handleTransaction(transaction)
                await transaction.finish()
                DebugLog.log("StoreKit: purchase success — \(product.id)")
                return true

            case .userCancelled:
                DebugLog.log("StoreKit: user cancelled purchase")
                return false

            case .pending:
                DebugLog.log("StoreKit: purchase pending approval")
                return false

            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            DebugLog.log("StoreKit: purchase failed — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            DebugLog.log("StoreKit: purchases restored")
        } catch {
            purchaseError = error.localizedDescription
            DebugLog.log("StoreKit: restore failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var newPlan: SubscriptionPlan = .free

        // Check for active subscription
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if transaction.productID == SubscriptionProductID.lifetime {
                // Lifetime trumps everything
                newPlan = .lifetime
                break
            }

            let plan = SubscriptionProductID.plan(for: transaction.productID)
            if plan.monthlyQuotaSeconds > newPlan.monthlyQuotaSeconds {
                newPlan = plan
            }
        }

        if currentPlan != newPlan {
            currentPlan = newPlan
            QuotaService.shared.updatePlan(newPlan)
            DebugLog.log("StoreKit: entitlement updated to \(newPlan.rawValue)")
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { break }
                if let transaction = try? Self.checkVerifiedStatic(result) {
                    await self.handleTransaction(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    private func handleTransaction(_ transaction: Transaction) async {
        let productID = transaction.productID

        if productID == SubscriptionProductID.topUp60min {
            // Consumable: add bonus minutes
            QuotaService.shared.addBonusSeconds(TopUpPack.standard.seconds)
            return
        }

        // Subscription or lifetime — refresh entitlements
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        try Self.checkVerifiedStatic(result)
    }

    private nonisolated static func checkVerifiedStatic<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
