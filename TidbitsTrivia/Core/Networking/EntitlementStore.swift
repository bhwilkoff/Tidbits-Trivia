import Foundation

/// Is this player a Tidbits Club member? The one gate every Club feature checks
/// (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION §7). Reference implementation — the
/// Kotlin / JS / C# stores mirror this exact logic.
///
/// Two independent sources, per Decision 047:
///  - **Class A (local store):** StoreKit `Transaction.currentEntitlements`, verified on
///    device, authoritative, works offline. Provided by the StoreKit adapter (Phase 1) via
///    `localCheck` so Core never imports StoreKit.
///  - **Class B (remote):** a web purchase the Worker wrote to `entitlements/{accountKey}`.
///    Read-only for the client; requires a verified-email sign-in (the rule enforces it).
///
/// `isClub = localStoreEntitled || remoteEntitled`.
///
/// **Fail OPEN.** A transient network miss or an empty-but-still-syncing local store must
/// never *revoke* Club — that would punish a paying member for being on a plane. We cache
/// the last-known-good answer and only lower it on a CLEAN negative from a reachable source.
@Observable @MainActor
final class EntitlementStore {
    static let shared = EntitlementStore()

    private let db: FirebaseRTDB
    private let identity: PlayerIdentityStore
    private static let cacheKey = "tidbits.entitlement.isClub"
    private static let sourceKey = "tidbits.entitlement.source"

    /// The gate. Seeded from the cached last-known-good so a returning member is Club
    /// instantly, before any network or store round-trip.
    private(set) var isClub: Bool = UserDefaults.standard.bool(forKey: EntitlementStore.cacheKey)
    /// Where the current entitlement came from ("apple" / "web" / nil) — for display + debug.
    private(set) var source: String? = UserDefaults.standard.string(forKey: EntitlementStore.sourceKey)

    /// The StoreKit adapter installs this in Phase 1. Returns the locally-proven state:
    ///  - `true`  — a verified local transaction grants Club.
    ///  - `false` — the store definitively reports no entitlement.
    ///  - `nil`   — unknown (sync hasn't completed) → treat as "no clean signal", never revoke.
    /// Default `nil` on every platform until the store layer lands.
    var localCheck: (@MainActor () async -> Bool?) = { nil }

    init(db: FirebaseRTDB = .shared, identity: PlayerIdentityStore = .shared) {
        self.db = db
        self.identity = identity
    }

    /// Recompute Club status. Safe to call at launch, after sign-in, and after a purchase.
    /// Never throws; the worst case is "keep the cached answer".
    func refresh() async {
        // Class A — local store, authoritative and offline. A clean YES wins immediately.
        let local = await localCheck()
        if local == true { set(true, source: source == "web" ? "web" : "apple"); return }

        // Class B — the web purchase. Only possible when signed in with a verified email
        // (the accountKey is the sha256 of that email, and the rule checks emailOwners).
        if identity.signedIn, let key = identity.profileId {
            do {
                let ent = try await db.get(Entitlement.path(key), as: Entitlement.self)
                if let ent, ent.grantsClub {
                    set(true, source: "web"); return
                }
                // A clean read that found nothing, AND the local store cleanly said no →
                // this is a definitive negative. Lower the gate.
                if local == false { set(false, source: nil); return }
                // else: local was unknown (nil) — no clean negative, keep cached.
            } catch {
                // Transient RTDB error → fail open, keep the cached answer.
            }
            return
        }

        // Not signed in. A local `false` with no remote possibility is a clean negative;
        // a local `nil` (unknown) keeps the cached answer (fail open).
        if local == false { set(false, source: nil) }
    }

    private func set(_ club: Bool, source: String?) {
        isClub = club
        self.source = source
        UserDefaults.standard.set(club, forKey: EntitlementStore.cacheKey)
        UserDefaults.standard.set(source, forKey: EntitlementStore.sourceKey)
    }

    /// Sign-out clears the cached Club state (the next person on this device isn't you).
    /// A local store purchase re-asserts itself on the next `refresh()`.
    func clearOnSignOut() { set(false, source: nil) }
}

/// The `entitlements/{sha256(email)}` wire record (MONETIZATION §7). Written ONLY by the
/// Worker; read-only for clients. Additive. `nonisolated` so the RTDB actor can decode it.
nonisolated struct Entitlement: Codable, Sendable {
    let tier: String            // "club"
    var sources: [String] = []  // ["web", "apple", …]
    var since: Int? = nil       // epoch ms
    var until: Int? = nil       // epoch ms; nil = lifetime / non-expiring
    var ver: Int? = nil

    static func path(_ key: String) -> String { "entitlements/\(key)" }

    /// True when this record grants an active Club membership. A subscription past `until`
    /// no longer grants; a lifetime (`until == nil`) always does.
    var grantsClub: Bool {
        guard tier == "club" else { return false }
        guard let until else { return true }
        return Int(Date().timeIntervalSince1970 * 1000) < until
    }
}
