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
    /// True while `loadProducts()` is in flight (including its retries) so the paywall can
    /// show a spinner instead of flashing the failure copy at a store that just hasn't
    /// answered yet.
    private(set) var loading = false
    /// The last real StoreKit failure, in Apple's own words. Shown verbatim to the player —
    /// a generic "that didn't go through" is indistinguishable from a broken app (App Review
    /// 2.1(a): "an error message displayed when we attempted to purchase the plans").
    private(set) var lastError: String?
    /// Whether this device/account is allowed to buy at all (parental controls, managed
    /// devices). Not an error — a different, explanatory state.
    var canMakePayments: Bool { StoreKit.AppStore.canMakePayments }
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
    ///
    /// **Retried.** `Product.products(for:)` is documented to fail transiently, and on a cold
    /// launch it can return an EMPTY array (not an error) before the store finishes its first
    /// sync — most visibly on tvOS, where the paywall is often the first App Store traffic the
    /// process makes. One attempt is why App Review saw an error message where a price list
    /// belonged; three attempts with a short backoff is the documented remedy.
    /// Set when the store answered SUCCESSFULLY with an empty list. That is a
    /// different failure from an error and has different causes, and the paywall
    /// showed the same sentence for both — so the one signal that tells you which
    /// problem you have was the one thing the screen did not say.
    private(set) var returnedEmpty = false

    /// The renewal terms, built from the plans ACTUALLY on screen rather than from the
    /// three we hope are there.
    ///
    /// Apple requires the terms beside the purchase controls, so this text used to be a
    /// static sentence naming all three plans. That is wrong whenever the store returns a
    /// subset — and it does: an IAP bound to an in-flight review submission is not served
    /// in the sandbox while its subscriptions, which are submitted by a different
    /// mechanism, are. On 2026-08-05 the real store returned Monthly and Yearly but not
    /// Founding Member, so the screen described a plan with no button. A plan a reviewer
    /// can read about but cannot buy, on a purchase screen, is the exact shape of the
    /// 2.1(b) rejection this came from. The sentence now follows the buttons.
    ///
    /// Empty when nothing loaded — there are no terms to state for nothing.
    var legalDisclosure: String {
        let ids = Set(products.map(\.id))
        let subs = [
            ids.contains(Product.monthly.rawValue) ? "Monthly" : nil,
            ids.contains(Product.annual.rawValue) ? "Yearly" : nil,
        ].compactMap { $0 }

        var parts: [String] = []
        if !subs.isEmpty {
            let one = subs.count == 1
            parts.append("""
            \(subs.joined(separator: " and ")) \(one ? "is an auto-renewable subscription" : "are auto-renewable subscriptions") \
            at the \(one ? "price" : "prices") shown above. Payment is charged to your Apple Account at purchase \
            confirmation. \(one ? "It renews" : "Each renews") automatically unless auto-renewal is turned off at least \
            24 hours before the current period ends; manage or cancel anytime in your Apple Account settings.
            """)
        }
        if ids.contains(Product.lifetime.rawValue) {
            parts.append("Founding Member is a one-time purchase for lifetime access — it does not renew.")
        }
        return parts.joined(separator: " ")
    }

    func loadProducts() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        lastError = nil
        returnedEmpty = false
        for attempt in 0..<3 {
            do {
                let loaded = try await StoreKit.Product.products(for: Self.clubProductIDs)
                if !loaded.isEmpty {
                    let order: [String: Int] = [Product.lifetime.rawValue: 0, Product.annual.rawValue: 1, Product.monthly.rawValue: 2]
                    products = loaded.sorted { (order[$0.id] ?? 9) < (order[$1.id] ?? 9) }
                    loadFailed = false
                    return
                }
                returnedEmpty = true
                // An EMPTY result is not an error: StoreKit reached the App Store
                // and the App Store had nothing to return for these ids. On a
                // build that is not running under Xcode's StoreKit configuration
                // (TestFlight, or any device build launched outside Xcode) the
                // causes are all App Store Connect side. Printed in full because
                // the difference is invisible from the UI.
                print("""
                [StoreKit] products(for:) returned 0 of \(Self.clubProductIDs.count) \
                — attempt \(attempt + 1). NOT an error: the store answered with an \
                empty list. Check, in order:
                  1. Agreements, Tax, and Banking — the PAID APPLICATIONS agreement \
                     must be Active. Until it is, App Store Connect returns NOTHING \
                     for every product, which looks exactly like this.
                  2. Each product's state — "Ready to Submit" or approved. \
                     "Missing Metadata" products are not returned.
                  3. The ids match App Store Connect exactly: \
                     \(Self.clubProductIDs.joined(separator: ", "))
                  4. Xcode's StoreKit configuration file only applies when the app \
                     is launched BY Xcode. TestFlight always uses App Store Connect.
                """)
            } catch {
                lastError = Self.describe(error)
                print("[StoreKit] products(for:) failed on attempt \(attempt + 1): \(error)")
            }
            if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(600_000_000 << attempt)) }
        }
        loadFailed = products.isEmpty
    }

    enum PurchaseOutcome { case success, pending, cancelled, failed }

    /// Buy a Club product. On success the transaction is finished and the entitlement gate
    /// refreshes, so the UI lights up immediately.
    ///
    /// Any failure records `lastError` in StoreKit's own words. The paywall shows it verbatim
    /// so "can't connect to the App Store" reads as what it is instead of as a broken app.
    func purchase(_ product: StoreKit.Product) async -> PurchaseOutcome {
        lastError = nil
        guard canMakePayments else {
            lastError = "Purchases are turned off for this Apple Account (Screen Time or a device restriction)."
            return .failed
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await EntitlementStore.shared.refresh()
                    return .success
                }
                lastError = "The App Store couldn't verify that purchase. No charge was made."
                return .failed                        // unverified — do not grant
            case .pending: return .pending            // e.g. Ask to Buy — grant later via updates
            case .userCancelled: return .cancelled
            @unknown default:
                lastError = "The App Store returned an unexpected result. No charge was made."
                return .failed
            }
        } catch {
            lastError = Self.describe(error)
            print("[StoreKit] purchase(\(product.id)) failed: \(error)")
            return .failed
        }
    }

    /// StoreKit's own wording where it has some, plus the two cases whose raw text is useless
    /// to a player. Never returns an empty string.
    private static func describe(_ error: Error) -> String {
        if let skError = error as? StoreKitError {
            switch skError {
            case .networkError:
                return "Couldn't reach the App Store. Check your connection and try again."
            case .userCancelled:
                return "Purchase cancelled."
            case .notAvailableInStorefront:
                return "Tidbits Club isn't available in your App Store region yet."
            case .notEntitled:
                return "This Apple Account isn't able to make this purchase."
            default:
                break
            }
        }
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? "The App Store couldn't complete that. No charge was made." : message
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
