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
            if let email = await db.currentEmail() {            // signed in → key by verified email
                signedIn = true
                UserDefaults.standard.set(true, forKey: "tidbits.identity.signedIn")
                let key = PlayerIdentity.accountKey(forEmail: email)
                profileId = key
                if let existing = try? await db.get(PlayerIdentity.publicPath(key), as: PlayerIdentity.Profile.self) {
                    profile = existing
                } else {                                        // migrate an older uid-keyed profile
                    let base = (try? await db.get(PlayerIdentity.publicPath(uid), as: PlayerIdentity.Profile.self)) ?? Self.newProfile(name: Self.suggestedName())
                    try? await db.put("emailOwners/\(key)", email)
                    try? await db.put(PlayerIdentity.publicPath(key), base)
                    profile = base
                }
            } else {                                            // anonymous → key by uid
                signedIn = false
                UserDefaults.standard.set(false, forKey: "tidbits.identity.signedIn")
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
            }
            if let id = profileId { watch(id) }                 // (B) live name sync
            if signedIn { await syncDailyLog() }                 // (L2) pull the synced daily log
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

    /// Sign in with Apple → key the profile by the verified email so Apple + Google (and
    /// every device) share one record set. Merges this device's anonymous activity into the
    /// email-keyed profile; the guard prevents ever re-merging. Called from the
    /// SignInWithAppleButton completion with the identity token + raw nonce.
    func linkApple(idToken: String, rawNonce: String, appleName: String? = nil) async {
        guard !signedIn else { return }   // already on a durable account — never re-merge the same records
        do {
            let local = profile ?? Self.newProfile(name: Self.suggestedName())
            let res = try await db.signInWithApple(identityToken: idToken, rawNonce: rawNonce)
            guard let email = res.email else {                  // no email (rare) — uid-keyed fallback
                profileId = res.uid
                try? await db.put(PlayerIdentity.publicPath(res.uid), local)
                markSignedIn(); return
            }
            let key = PlayerIdentity.accountKey(forEmail: email)
            try? await db.put("emailOwners/\(key)", email)
            let existing = (try? await db.get(PlayerIdentity.publicPath(key), as: PlayerIdentity.Profile.self)) ?? nil
            var merged = existing.map { PlayerIdentity.merge(local: local, account: $0) } ?? local
            if PlayerIdentity.isDefaultName(merged.name),
               let n = (appleName ?? res.displayName)?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                merged.name = String(n.prefix(24))              // (A) adopt the provider's name
            }
            profile = merged
            profileId = key
            try? await db.put(PlayerIdentity.publicPath(key), merged)
            markSignedIn()
            watch(key)                                          // (B) live name sync
            await syncDailyLog(pushLocal: true)                 // (L2) push anon plays, pull the union
        } catch {
            print("[Identity] Apple sign-in failed: \(error)")
        }
    }

    private func markSignedIn() {
        signedIn = true
        UserDefaults.standard.set(true, forKey: "tidbits.identity.signedIn")
    }

    /// (L2) Daily log sync — when signed in, a daily completion also lands in
    /// dailyLog/{key} so "done today" + the archive follow the identity across devices.
    func syncDailyScore(day: String, score: Int) async {
        guard signedIn, let key = profileId else { return }
        try? await db.put("dailyLog/\(key)/\(day)", score)
    }

    /// Reconcile the local DailyLog with the synced one. On sign-in, push local (anon)
    /// plays first so nothing is lost; then pull the union into the local store.
    func syncDailyLog(pushLocal: Bool = false) async {
        guard signedIn, let key = profileId else { return }
        if pushLocal { for (day, score) in DailyLog.all() { try? await db.put("dailyLog/\(key)/\(day)", score) } }
        if let remote = (try? await db.get("dailyLog/\(key)", as: [String: Int].self)) ?? nil {
            for (day, score) in remote { DailyLog.record(day: day, score: score) }
        }
    }

    private var watchTask: Task<Void, Never>?
    /// (B) Live cross-device NAME sync — stream players/{key} and apply remote name changes
    /// (name-only, so a game in progress on another device can't revert local stats). The
    /// SSE stream ends on drop; back off and reconnect. Re-pointed on bootstrap/sign-in/out.
    private func watch(_ key: String) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let db = self?.db else { return }
                if let stream = try? await db.stream(PlayerIdentity.publicPath(key)) {
                    do {
                        for try await ev in stream {
                            guard ev.event == "put", ev.path == "/", let data = ev.dataJSON,
                                  let p = try? JSONDecoder().decode(PlayerIdentity.Profile.self, from: data) else { continue }
                            await MainActor.run {
                                guard let self, self.profileId == key, self.profile?.name != p.name else { return }
                                self.profile?.name = p.name
                            }
                        }
                    } catch {}
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// Sign out → back to a fresh anonymous profile on this device. The account's records
    /// stay in the cloud; signing in again (Apple) restores + merges them.
    func signOut() async {
        do {
            let uid = try await db.signOut()
            profileId = uid
            if let existing = try? await db.get(PlayerIdentity.publicPath(uid), as: PlayerIdentity.Profile.self) {
                profile = existing
            } else {
                let fresh = Self.newProfile(name: Self.suggestedName())
                profile = fresh
                try? await db.put(PlayerIdentity.publicPath(uid), fresh)
            }
            signedIn = false
            UserDefaults.standard.set(false, forKey: "tidbits.identity.signedIn")
            watch(uid)                                          // (B) re-point to the fresh anon
        } catch {
            print("[Identity] sign-out failed: \(error)")
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
