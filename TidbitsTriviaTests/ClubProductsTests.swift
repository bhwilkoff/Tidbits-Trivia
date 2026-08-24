import Foundation
import Testing

// This bundle compiles Core INTO itself (no app dependency — see project.yml);
// the module to test against is the bundle's own, exactly like every sibling
// file. `@testable import TidbitsTrivia` broke the whole suite's build for
// three weeks of red CI (2026-08-05 → 2026-08-24).
@testable import TidbitsTriviaTests

/// Regression cover for the tvOS 2.1(b) rejection on 2026-08-05.
///
/// App Review's Apple TV showed "The App Store hasn't published the plans for this
/// build yet." — our own `returnedEmpty` copy — because `Product.products(for:)`
/// returned NOTHING. Both causes were account-side: the Paid Applications agreement
/// was not in effect, and `club.monthly` / `club.annual` had never been submitted
/// (they sat at READY_TO_SUBMIT, which reads like "ready" and means "never sent").
///
/// **What this file can and cannot prove.** Nothing local can verify App Store
/// Connect, and a live `products(for:)` needs `SKTestSession`, which needs a host
/// application — this target deliberately has none (hosting the app double-builds
/// the Core swiftmodule). So these tests pin the one half that lives in this repo
/// and would otherwise break silently: the IDs the paywall asks for are exactly the
/// products we ship a configuration for, with the right types. A typo or a renamed
/// product reproduces the identical empty-list symptom against a perfectly
/// configured account, and no other test in the suite would notice.
struct ClubProductsTests {

    private static let config: [String: Any] = {
        // The shipped file, read from source — the same one Xcode's StoreKit testing
        // and the simulator use. Bundling it as a test resource would let the copy
        // and the original drift.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TidbitsTriviaTests/
            .deletingLastPathComponent()   // repo root
        let url = root.appendingPathComponent("TidbitsTrivia/Resources/Tidbits.storekit")
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    private static var oneTimeIDs: Set<String> {
        Set((config["products"] as? [[String: Any]] ?? []).compactMap { $0["productID"] as? String })
    }

    private static var subscriptionIDs: Set<String> {
        let groups = config["subscriptionGroups"] as? [[String: Any]] ?? []
        return Set(groups.flatMap { g in
            (g["subscriptions"] as? [[String: Any]] ?? []).compactMap { $0["productID"] as? String }
        })
    }

    /// The rejection symptom as an assertion: every plan the paywall will ask for
    /// must be a product we actually offer.
    @Test func everyRequestedPlanExistsInTheStoreConfig() {
        let offered = Self.oneTimeIDs.union(Self.subscriptionIDs)
        let requested = StoreKitStore.clubProductIDs

        #expect(requested.subtracting(offered).isEmpty,
                "the paywall requests plans the store does not offer: \(requested.subtracting(offered).sorted()) — this is what renders an empty plan list")
        #expect(offered.subtracting(requested).isEmpty,
                "the store offers plans the paywall never asks for: \(offered.subtracting(requested).sorted())")
    }

    /// Three plans, no more and no fewer — a silently dropped plan is a paywall that
    /// quietly stops selling something.
    @Test func thereAreExactlyThreePlans() {
        #expect(StoreKitStore.clubProductIDs.count == 3)
        #expect(Self.oneTimeIDs.count + Self.subscriptionIDs.count == 3)
    }

    /// Lifetime must NOT renew and the other two must, because the paywall shows a
    /// renewal period for a subscription and a flat price for the one-time purchase.
    /// Getting this backwards is its own review rejection.
    @Test func planTypesMatchHowThePaywallPresentsThem() {
        #expect(Self.oneTimeIDs == [StoreKitStore.Product.lifetime.rawValue],
                "lifetime must be the only non-renewing product; got \(Self.oneTimeIDs.sorted())")
        #expect(Self.subscriptionIDs == [StoreKitStore.Product.annual.rawValue,
                                         StoreKitStore.Product.monthly.rawValue],
                "monthly and annual must be the auto-renewable pair; got \(Self.subscriptionIDs.sorted())")
    }

    /// Both subscriptions must sit in ONE group. Two groups would let a player hold
    /// monthly and annual simultaneously and be double-charged for one entitlement.
    @Test func bothSubscriptionsShareASingleGroup() {
        let groups = Self.config["subscriptionGroups"] as? [[String: Any]] ?? []
        #expect(groups.count == 1, "expected a single subscription group, found \(groups.count)")
    }
}

/// The disclosure must describe the plans that are on screen and no others.
///
/// It was a static sentence naming all three. On 2026-08-05 the real App Store
/// returned Monthly and Yearly but NOT Founding Member (a non-consumable bound to an
/// in-flight review submission is not served in the sandbox; its subscriptions, which
/// are submitted by a different mechanism, are). The screen therefore described a plan
/// with no button — a plan a reviewer can read about but cannot buy, on a purchase
/// screen, which is the exact shape of the 2.1(b) rejection this came from.
@MainActor
struct ClubDisclosureTests {

    /// Nothing to sell, nothing to disclaim.
    @Test func noPlansMeansNoTerms() {
        #expect(StoreKitStore.shared.legalDisclosure.isEmpty)
    }

    /// The wording is derived, so the pieces have to agree with each other. These assert
    /// the *shape* of the derivation without needing StoreKit to hand us real products.
    @Test func theSentenceNeverMentionsAPlanItIsNotShowing() {
        let d = StoreKitStore.shared.legalDisclosure
        // With no products loaded the store shows nothing, so no plan may be named.
        #expect(!d.contains("Founding Member"))
        #expect(!d.contains("Monthly"))
        #expect(!d.contains("Yearly"))
    }
}
