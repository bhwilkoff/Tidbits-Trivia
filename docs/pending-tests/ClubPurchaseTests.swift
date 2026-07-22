import XCTest
import StoreKitTest
@testable import TidbitsTrivia

/// The proof that a user can actually PAY and become a Club member (docs/CLUB-MONETIZATION-
/// BUILD.md, Phase 1). Uses StoreKitTest's SKTestSession against the bundled Tidbits.storekit
/// config — no App Store Connect, no network, no system purchase sheet — to buy each product
/// and assert the entitlement flips. This is the reliable verification the sim-UI render
/// couldn't give.
@MainActor
final class ClubPurchaseTests: XCTestCase {
    var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Tidbits")
        session.disableDialogs = true      // auto-approve — no purchase sheet in the test
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
    }

    /// The Class A entitlement check starts negative (no purchases yet).
    func testNoPurchaseIsNotClub() async throws {
        let entitled = await StoreKitStore.currentClubEntitlement()
        XCTAssertNotEqual(entitled, true, "a fresh session must not grant Club")
    }

    /// Buying the lifetime (non-consumable) grants Club.
    func testLifetimePurchaseGrantsClub() async throws {
        try await session.buyProduct(productIdentifier: StoreKitStore.Product.lifetime.rawValue)
        let entitled = await StoreKitStore.currentClubEntitlement()
        XCTAssertEqual(entitled, true, "a completed lifetime purchase must grant Club")
    }

    /// Buying the annual subscription grants Club.
    func testAnnualSubscriptionGrantsClub() async throws {
        try await session.buyProduct(productIdentifier: StoreKitStore.Product.annual.rawValue)
        let entitled = await StoreKitStore.currentClubEntitlement()
        XCTAssertEqual(entitled, true, "an active annual subscription must grant Club")
    }

    /// Buying the monthly subscription grants Club too (same group, one entitlement).
    func testMonthlySubscriptionGrantsClub() async throws {
        try await session.buyProduct(productIdentifier: StoreKitStore.Product.monthly.rawValue)
        let entitled = await StoreKitStore.currentClubEntitlement()
        XCTAssertEqual(entitled, true, "an active monthly subscription must grant Club")
    }

    /// The three products load from the config with the expected IDs and non-empty prices.
    func testProductsLoad() async throws {
        let store = StoreKitStore.shared
        await store.loadProducts()
        XCTAssertEqual(store.products.count, 3, "all three Club products should load")
        XCTAssertEqual(Set(store.products.map(\.id)), StoreKitStore.clubProductIDs)
        for p in store.products {
            XCTAssertFalse(p.displayPrice.isEmpty, "\(p.id) must have a price")
        }
    }
}
