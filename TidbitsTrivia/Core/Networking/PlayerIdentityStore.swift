import Foundation
#if canImport(GameKit)
import GameKit
#endif

/// The portable Tidbits player identity, live in the app. Bootstraps the shared
/// Firebase anonymous `uid` (the cross-platform profileId — now persisted across
/// launches via Keychain), loads or creates `players/{uid}`, and links the
/// platform-native identity (Game Center on Apple) into `playersPrivate/{uid}`.
/// The account feels native per platform (Game Center here) over ONE shared profile.
/// See `docs/PLAYER-IDENTITY-CONTRACT.md`.
@Observable
@MainActor
final class PlayerIdentityStore {
    static let shared = PlayerIdentityStore()

    private(set) var profileId: String?     // the shared Firebase anon uid
    private(set) var profile: PlayerIdentity.Profile?
    private(set) var loaded = false
    /// True once the account is promoted from anonymous via a federated sign-in — then
    /// records roam + survive session loss. Persisted so it's known at next launch.
    private(set) var signedIn = UserDefaults.standard.bool(forKey: "tidbits.identity.signedIn")

    private let db = FirebaseRTDB.shared

    /// Ensure identity: stable anon uid → load/create profile → link native ids.
    /// Idempotent; safe to call at launch and again after Game Center authenticates.
    func bootstrap() async {
        do {
            let uid = try await db.ensureAuth()
            profileId = uid
            if let existing = try? await db.get(PlayerIdentity.publicPath(uid), as: PlayerIdentity.Profile.self) {
                profile = existing
            } else {
                // Local-first: show the profile immediately, persist best-effort (works
                // offline and before the players/ rules are deployed).
                let fresh = Self.newProfile(name: Self.suggestedName())
                profile = fresh
                try? await db.put(PlayerIdentity.publicPath(uid), fresh)
            }
            await linkNativeIdentity()
            loaded = true
        } catch {
            // Even offline (no auth) show a local profile so the UI always works.
            if profile == nil { profile = Self.newProfile(name: Self.suggestedName()) }
            print("[Identity] bootstrap degraded: \(error)")
        }
    }

    /// Apple-native link: record the Game Center player id (owner-only) and adopt the
    /// GC alias as the display name while the profile still has its default name.
    /// Called from bootstrap AND from GameCenterManager once auth completes (async).
    func linkNativeIdentity() async {
        #if canImport(GameKit)
        guard let uid = profileId, GameCenterManager.shared.isAuthenticated else { return }
        let gc = GKLocalPlayer.local
        let gcID = gc.gamePlayerID
        guard !gcID.isEmpty else { return }
        var priv = (try? await db.get(PlayerIdentity.privatePath(uid), as: PlayerIdentity.Private.self)) ?? PlayerIdentity.Private()
        if priv.gameCenterID != gcID {
            priv.gameCenterID = gcID
            try? await db.put(PlayerIdentity.privatePath(uid), priv)
        }
        if let p = profile, p.name.hasPrefix("Player "), !gc.alias.isEmpty {
            await rename(gc.alias)
        }
        #endif
    }

    /// Record a finished game into the portable profile (rating + streak + stats) and
    /// persist best-effort. Called on every solo game; live games flow via the claim flow.
    func recordGame(correct: Int, total: Int, live: Bool = false) async {
        guard var p = profile, let uid = profileId, total > 0 else { return }
        p.rating = p.rating.updated(accuracy: Double(correct) / Double(total), weight: live ? 1.5 : 1.0)
        p.streak = p.streak.played(today: PlayerIdentity.todayString(), liveNight: live)
        p.stats.gamesPlayed += 1
        p.stats.questionsAnswered += total
        p.stats.correct += correct
        if live { p.stats.liveNights += 1 }
        profile = p
        try? await db.put(PlayerIdentity.publicPath(uid), p)
    }

    /// Record a finished LIVE game — the bridge that makes "solo AND live feed one
    /// identity" real. Advances the cross-context streak (a live night, which also grants
    /// a freeze), counts the night, and nudges the rating from MCQ accuracy when available.
    func recordLiveGame(correct: Int, answered: Int) async {
        guard var p = profile, let uid = profileId else { return }
        if answered > 0 {
            p.rating = p.rating.updated(accuracy: Double(correct) / Double(answered), weight: 1.5)
            p.stats.questionsAnswered += answered
            p.stats.correct += correct
        }
        p.streak = p.streak.played(today: PlayerIdentity.todayString(), liveNight: true)
        p.stats.gamesPlayed += 1
        p.stats.liveNights += 1
        profile = p
        try? await db.put(PlayerIdentity.publicPath(uid), p)
    }

    /// Sign in with Apple → promote the anon account so records roam + survive session
    /// loss. On a conflict (the Apple id already has an account), lossless-merge into it.
    /// Called from the SignInWithAppleButton completion with the identity token + raw nonce.
    func linkApple(idToken: String, rawNonce: String) async {
        do {
            let local = profile
            let res = try await db.linkWithApple(identityToken: idToken, rawNonce: rawNonce)
            profileId = res.uid
            if res.merged {
                let account = (try? await db.get(PlayerIdentity.publicPath(res.uid), as: PlayerIdentity.Profile.self)) ?? Self.newProfile(name: Self.suggestedName())
                let merged = PlayerIdentity.merge(local: local ?? account, account: account)
                profile = merged
                try? await db.put(PlayerIdentity.publicPath(res.uid), merged)
            } else if let local {
                try? await db.put(PlayerIdentity.publicPath(res.uid), local)   // promoted in place
            }
            signedIn = true
            UserDefaults.standard.set(true, forKey: "tidbits.identity.signedIn")
        } catch {
            print("[Identity] Apple sign-in failed: \(error)")
        }
    }

    /// Update the public display name.
    func rename(_ name: String) async {
        guard let uid = profileId, var p = profile else { return }
        let t = String(name.trimmingCharacters(in: .whitespaces).prefix(24))
        guard !t.isEmpty else { return }
        p.name = t
        do { try await db.put(PlayerIdentity.publicPath(uid), p); profile = p }
        catch { print("[Identity] rename failed: \(error)") }
    }

    // MARK: New profile

    private static func newProfile(name: String) -> PlayerIdentity.Profile {
        PlayerIdentity.Profile(
            name: name,
            createdAt: Int(Date().timeIntervalSince1970 * 1000),
            avatarSeed: String(UUID().uuidString.prefix(8)).lowercased(),
            rating: .init(value: PlayerIdentity.Rating.start, games: 0, provisional: true),
            streak: .init(current: 0, longest: 0, lastPlayedDay: "", freezes: 0),
            stats: .init(gamesPlayed: 0, questionsAnswered: 0, correct: 0, liveNights: 0, venuesVisited: 0))
    }

    private static func suggestedName() -> String {
        #if canImport(GameKit)
        if GameCenterManager.shared.isAuthenticated, !GKLocalPlayer.local.alias.isEmpty {
            return GKLocalPlayer.local.alias
        }
        #endif
        return "Player \(Int.random(in: 1000...9999))"
    }
}
