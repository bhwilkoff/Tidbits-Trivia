import Foundation
import StoreKit

/// Tidbits Club purchases on Apple platforms (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION
/// §6/§7). StoreKit 2, one product set across iOS + iPadOS + macOS + tvOS via **Universal
/// Purchase** — the same bundle id + product ids restore across all four for free.
///
/// This is the **Class A** (local, offline, cryptographically-verified) source for
/// `EntitlementStore`. It installs `EntitlementStore.shared.localCheck` and drives it from
/// `Transaction.currentEntitlements`; the store never talks to our RTDB — a StoreKit
/// purchase is proven on-device, no server needed.
@Observable @MainActor
final class StoreKitStore {
    static let shared = StoreKitStore()

    /// The Club products. IDs are the contract App Store Connect (and the local .storekit)
    /// must match exactly. One entitlement — Club — is granted by ANY of them.
    enum Product: String, CaseIterable {
        case annual   = "com.learningischange.tidbitstrivia.club.annual"
        case monthly  = "com.learningischange.tidbitstrivia.club.monthly"
        case lifetime = "com.learningischange.tidbitstrivia.club.lifetime"
    }
    nonisolated static let clubProductIDs = Set(Product.allCases.map(\.rawValue))

    private(set) var products: [StoreKit.Product] = []
    private(set) var loadFailed = false
    private var updates: Task<Void, Never>?

    /// Wire the local entitlement check into the shared gate and start listening for
    /// renewals / external purchases. Call once at launch. The update listener runs for the
    /// process lifetime (this is a shared singleton), so there is no teardown.
    func start() {
        EntitlementStore.shared.localCheck = { await StoreKitStore.currentClubEntitlement() }
        if updates == nil {
            updates = Task.detached { await StoreKitStore.listenForTransactionUpdates() }
        }
    }

    /// Load the three products for display in the paywall. Sorted lifetime → annual → monthly
    /// so the best-value framing reads top-down.
    func loadProducts() async {
        do {
            let loaded = try await StoreKit.Product.products(for: Self.clubProductIDs)
            let order: [String: Int] = [Product.lifetime.rawValue: 0, Product.annual.rawValue: 1, Product.monthly.rawValue: 2]
            products = loaded.sorted { (order[$0.id] ?? 9) < (order[$1.id] ?? 9) }
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    enum PurchaseOutcome { case success, pending, cancelled, failed }

    /// Buy a Club product. On success the transaction is finished and the entitlement gate
    /// refreshes, so the UI lights up immediately.
    func purchase(_ product: StoreKit.Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await EntitlementStore.shared.refresh()
                    return .success
                }
                return .failed                        // unverified — do not grant
            case .pending: return .pending            // e.g. Ask to Buy — grant later via updates
            case .userCancelled: return .cancelled
            @unknown default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Restore Purchases — force a sync from the App Store, then re-check. Needed because
    /// `currentEntitlements` reads a local cache that may be empty on a fresh install.
    func restore() async {
        try? await StoreKit.AppStore.sync()   // qualify — the app has its own `AppStore` game type
        await EntitlementStore.shared.refresh()
    }

    // MARK: - Entitlement (Class A)

    /// The local, verified Club state for `EntitlementStore.localCheck`:
    ///  - `true`  — a verified, non-revoked Club transaction exists.
    ///  - `false` — the store returned entitlements but none are Club (definitive negative).
    ///  - `nil`   — the store returned NOTHING (a fresh install whose sync hasn't happened);
    ///              unknown, so the gate treats it as "no clean signal" and fails open.
    nonisolated static func currentClubEntitlement() async -> Bool? {
        var sawAny = false
        for await result in Transaction.currentEntitlements {
            sawAny = true
            if case .verified(let t) = result,
               clubProductIDs.contains(t.productID),
               t.revocationDate == nil {
                return true
            }
        }
        return sawAny ? false : nil
    }

    /// Renewals, family-sharing grants, and purchases made on another device arrive here.
    nonisolated static func listenForTransactionUpdates() async {
        for await update in Transaction.updates {
            if case .verified(let t) = update {
                await t.finish()
                await EntitlementStore.shared.refresh()
            }
        }
    }
}
