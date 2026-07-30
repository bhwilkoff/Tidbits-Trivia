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
    /// Surfaced to the sign-in UI so a failed Sign in with Apple is VISIBLE (not silently dropped).
    private(set) var authError: String?
    func reportAuthError(_ message: String?) { authError = message }

    private let db = FirebaseRTDB.shared

    /// Ensure identity: stable anon uid → load/create profile → link native ids.
    /// Idempotent; safe to call at launch and again after Game Center authenticates.
    func bootstrap() async {
        if screenshotSeeded { return }   // never clobber a screenshot seed
        do {
            let uid = try await db.ensureAuth()
            // Prefer the token's email; fall back to the persisted one so an Apple session
            // (whose refreshed token can omit the email) still re-keys to the shared profile.
            if let email = await db.currentEmail() ?? Self.persistedEmail() {   // signed in → key by verified email
                signedIn = true
                UserDefaults.standard.set(true, forKey: "tidbits.identity.signedIn")
                Self.persistEmail(email)
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

    /// Wave E: write this player's cumulative per-venue season standing after a live night.
    /// Keyed by the AUTH uid (the standings rule requires `auth.uid === $uid`); the $0
    /// GitHub-Actions cron aggregates these into the static cross-venue leaderboard.
    func recordStanding(venue: String, score: Int) async {
        let vk = PlayerIdentity.venueKey(venue)
        guard !vk.isEmpty, score > 0, let profile else { return }
        guard let authUid = await db.uid else { return }
        let path = PlayerIdentity.standingPath(season: PlayerIdentity.currentSeason(), venue: vk, uid: authUid)
        let existing = (try? await db.get(path, as: PlayerIdentity.Standing.self)) ?? nil
        let s = PlayerIdentity.Standing(name: profile.name,
                                        score: (existing?.score ?? 0) + score,
                                        nights: (existing?.nights ?? 0) + 1,
                                        updatedAt: Int(Date().timeIntervalSince1970 * 1000))
        try? await db.put(path, s)
    }

    /// Push registry (docs/PUSH-CONTRACT.md): store this device's push token under the
    /// owner-only `pushTokens/{authUid}/{platform}` node so the reminders cron can reach
    /// it. Keyed by the AUTH uid (per-device), mirroring the standings/board writes.
    func savePushToken(_ token: String, platform: String) async {
        guard !token.isEmpty, let authUid = await db.uid else { return }
        try? await db.put("pushTokens/\(authUid)/\(platform)", token)
    }

    /// Turn reminders off — delete the token node (App Store 4.5.4: an in-app opt-out).
    func clearPushToken(platform: String) async {
        guard let authUid = await db.uid else { return }
        try? await db.delete("pushTokens/\(authUid)/\(platform)")
    }

    /// The Daily's global board (docs/DAILY-BOARD-CONTRACT.md): after finishing TODAY's
    /// Daily, write this player's one row so the hourly cron can rank the field. Keyed by
    /// the AUTH uid (the rule requires `auth.uid === $uid`), like standings. Archive replays
    /// of past days never write (they pass a non-nil dailyDay). Free — sign-in not required.
    func submitDailyBoard(summary: GameSummary) async {
        guard summary.mode == .daily, summary.dailyDay == nil else { return }   // today only
        guard let profile, let authUid = await db.uid else { return }
        let day = QuestionProvider.dayKey()
        let allIDs = CorpusDatabase.shared.orderedIDs(categoryID: "mixed")
        let qids = DailyPick.pick(ids: allIDs, day: day, categoryID: "mixed", count: GameMode.daily.questionCount)
        let ms = Int(summary.answered.reduce(0.0) { $0 + $1.secondsTaken } * 1000)
        let entry = DailyBoard.Entry(name: profile.name,
                                     avatarSeed: profile.avatarSeed,
                                     score: summary.score,
                                     correct: summary.correct,
                                     marks: DailyBoard.marks(answered: summary.answered, qids: qids),
                                     ms: ms,
                                     at: Int(Date().timeIntervalSince1970 * 1000))
        try? await db.put("dailyBoard/\(day)/\(authUid)", entry)
    }

    /// Sign in with Apple → key the profile by the verified email so Apple + Google (and
    /// every device) share one record set. Merges this device's anonymous activity into the
    /// email-keyed profile; the guard prevents ever re-merging. Called from the
    /// SignInWithAppleButton completion with the identity token + raw nonce.
    func linkApple(idToken: String, rawNonce: String, appleName: String? = nil, appleEmail: String? = nil) async {
        print("[Identity] linkApple entry — signedIn already \(signedIn)")
        guard !signedIn else { print("[Identity] linkApple no-op — already signed in"); return }   // already on a durable account — never re-merge the same records
        authError = nil
        do {
            let local = profile ?? Self.newProfile(name: Self.suggestedName())
            let res = try await db.signInWithApple(identityToken: idToken, rawNonce: rawNonce)
            print("[Identity] db.signInWithApple returned uid=\(res.uid) email=\(res.email ?? "nil")")
            // Apple shares the email ONLY on the first authorization. Capture it wherever it
            // appears — Firebase's response, the native credential, or Apple's identity-token
            // claim — so the profile keys by email (and converges with Google) even when
            // Firebase's response omits it. Without this, Apple fell back to uid-keying.
            let email = [res.email, appleEmail, FirebaseRTDB.email(fromJWT: idToken)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            guard let email else {                              // no email anywhere — uid-keyed fallback
                print("[Identity] no email anywhere — uid-keyed fallback")
                profileId = res.uid
                try? await db.put(PlayerIdentity.publicPath(res.uid), local)
                Self.persistEmail(nil); markSignedIn()
                print("[Identity] markSignedIn done (uid-keyed) — signedIn=\(signedIn)")
                return
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
            Self.persistEmail(email)                            // survive Apple's empty token email on relaunch
            markSignedIn()
            print("[Identity] markSignedIn done — signedIn=\(signedIn) profileId=\(profileId ?? "nil")")
            watch(key)                                          // (B) live name sync
            await syncDailyLog(pushLocal: true)                 // (L2) push anon plays, pull the union
        } catch {
            authError = "Sign-in couldn't complete. \((error as NSError).localizedDescription)"
            print("[Identity] Apple sign-in failed: \(error)")
        }
    }

    private func markSignedIn() {
        signedIn = true
        UserDefaults.standard.set(true, forKey: "tidbits.identity.signedIn")
    }

    private static let emailDefaultsKey = "tidbits.identity.email"
    /// Persist the resolved account email so bootstrap can re-key by it after relaunch even
    /// when the (Apple) token omits the email claim. Cleared on sign-out.
    static func persistEmail(_ email: String?) {
        if let email { UserDefaults.standard.set(email, forKey: emailDefaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: emailDefaultsKey) }
    }
    static func persistedEmail() -> String? { UserDefaults.standard.string(forKey: emailDefaultsKey) }

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
        let remote = ((try? await db.get("dailyLog/\(key)", as: [String: Int].self)) ?? nil) ?? [:]
        // Push only days the account doesn't already have — an established daily score is never
        // overwritten, so replaying a day while logged out can't beat it.
        if pushLocal {
            for (day, score) in DailyLog.all() where remote[day] == nil {
                try? await db.put("dailyLog/\(key)/\(day)", score)
            }
        }
        // The account is authoritative — adopt its value for every day (reconciles cross-device).
        for (day, score) in remote { DailyLog.adopt(day: day, score: score) }
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
        EntitlementStore.shared.clearOnSignOut()   // the next person on this device isn't you — never keep cached Club
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
            Self.persistEmail(nil)                              // forget the account email
            watch(uid)                                          // (B) re-point to the fresh anon
        } catch {
            print("[Identity] sign-out failed: \(error)")
        }
    }

    // MARK: - Account deletion (App Store 5.1.1(v))

    /// Permanently delete this player's account and every record keyed to it, then return the
    /// app to a brand-new anonymous identity. Offered on every platform's Settings/Profile
    /// surface — App Review 5.1.1(v) requires an in-app path from "I have an account" to
    /// "it's gone", with no support ticket and no website detour.
    ///
    /// Order matters: the RTDB nodes go first (the auth token dies with the user), the
    /// Identity Toolkit account last. Each node delete is best-effort — a single 403 on a
    /// stale leaderboard row must not strand the caller with a half-deleted account — but the
    /// auth delete is authoritative and its failure IS reported.
    ///
    /// Local state (SwiftData records) is the caller's to wipe; `resetLocalState()` covers the
    /// UserDefaults/Keychain half so the two halves can't drift.
    func deleteAccount() async -> Bool {
        deleteError = nil
        let key = profileId
        let authUid = await db.uid

        // 1. Public + account-keyed records.
        if let key {
            try? await db.delete(PlayerIdentity.publicPath(key))
            try? await db.delete("dailyLog/\(key)")
            try? await db.delete("emailOwners/\(key)")
        }
        // 2. Records keyed by the AUTH uid (private bucket, push registry, boards).
        if let authUid {
            try? await db.delete(PlayerIdentity.privatePath(authUid))
            try? await db.delete("pushTokens/\(authUid)")
            for day in DailyLog.all().keys {
                try? await db.delete("dailyBoard/\(day)/\(authUid)")
            }
            let index = await LeaderboardAPI.index()
            for (season, venues) in index {
                for venue in venues {
                    try? await db.delete(PlayerIdentity.standingPath(season: season, venue: venue, uid: authUid))
                }
            }
            // A duel record is SHARED with the opponent — drop only my own slot, never theirs.
            for duel in await DuelStore.shared.mine() {
                try? await db.delete("duels/\(duel.id)/players/\(authUid)")
                try? await db.delete("duelInbox/\(authUid)/\(duel.id)")
            }
        }

        // 3. The credential itself. This is the one that must succeed.
        do {
            let fresh = try await db.deleteAccount()
            watchTask?.cancel(); watchTask = nil
            resetLocalState()
            profileId = fresh
            let profileForDevice = Self.newProfile(name: Self.suggestedName())
            profile = profileForDevice
            try? await db.put(PlayerIdentity.publicPath(fresh), profileForDevice)
            watch(fresh)
            loaded = true
            return true
        } catch {
            deleteError = "Couldn't delete your account. \((error as NSError).localizedDescription)"
            print("[Identity] account deletion failed: \(error)")
            return false
        }
    }

    /// Surfaced to the delete-account UI so a failure is VISIBLE rather than a silent no-op.
    private(set) var deleteError: String?

    /// Set once `seedForScreenshots` runs. Something after the seed was replacing `profile`
    /// again (the macOS Records shot kept reading "0 days" beside 24 games), so once seeded
    /// the store refuses to re-bootstrap over it. Screenshot runs only.
    private var screenshotSeeded = false

    /// Forget everything this device remembers about the deleted account.
    private func resetLocalState() {
        EntitlementStore.shared.clearOnSignOut()
        signedIn = false
        UserDefaults.standard.set(false, forKey: "tidbits.identity.signedIn")
        Self.persistEmail(nil)
        friends = []
        UserDefaults.standard.removeObject(forKey: "tidbits.friends")
        UserDefaults.standard.removeObject(forKey: "tidbits.duels")
        DailyLog.clear()
        authError = nil
    }

    /// Screenshot seeding only (`TIDBITS_SEED_RECORDS`): give the local profile a plausible
    /// streak + stats so the Records store shot doesn't read "0 days" next to 24 games.
    /// Local-only — never written to the shared plane.
    func seedForScreenshots(streak: Int, longest: Int, games: Int, correct: Int, answered: Int) {
        screenshotSeeded = true
        var p = profile ?? Self.newProfile(name: Self.suggestedName())
        p.streak = .init(current: streak, longest: longest, lastPlayedDay: PlayerIdentity.todayString(), freezes: 1)
        p.stats = .init(gamesPlayed: games, questionsAnswered: answered, correct: correct,
                        liveNights: 2, venuesVisited: 1)
        p.rating = .init(value: 1180, games: games, provisional: false)
        profile = p
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

    /// L4 cosmetics: re-roll the avatar seed → a new deterministic color. Persists + syncs like rename.
    func rerollAvatar() async {
        guard let uid = profileId, var p = profile else { return }
        p.avatarSeed = String(UUID().uuidString.prefix(8)).lowercased()
        do { try await db.put(PlayerIdentity.publicPath(uid), p); profile = p }
        catch { print("[Identity] avatar reroll failed: \(error)") }
    }

    // MARK: - Social graph (L5): a private "people I've played with" list

    var friends: [PlayerIdentity.Friend] = {
        guard let d = UserDefaults.standard.data(forKey: "tidbits.friends"),
              let list = try? JSONDecoder().decode([PlayerIdentity.Friend].self, from: d) else { return [] }
        return list.sorted { $0.since > $1.since }
    }()

    func isFriend(_ uid: String) -> Bool { friends.contains { $0.uid == uid } }

    private func persistFriends() {
        if let d = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(d, forKey: "tidbits.friends") }
    }

    func addFriend(uid: String, name: String, avatarSeed: String = "") async {
        guard !uid.isEmpty, let me = await db.uid, uid != me, !isFriend(uid) else { return }
        let f = PlayerIdentity.Friend(uid: uid, name: name.isEmpty ? "Player" : name, avatarSeed: avatarSeed,
                                      since: Int(Date().timeIntervalSince1970 * 1000))
        friends.insert(f, at: 0); persistFriends()
        try? await db.put("playersPrivate/\(me)/friends/\(uid)", f)
    }

    func removeFriend(_ uid: String) async {
        friends.removeAll { $0.uid == uid }; persistFriends()
        guard let me = await db.uid else { return }
        try? await db.delete("playersPrivate/\(me)/friends/\(uid)")
    }

    func loadFriends() async {
        guard let me = await db.uid,
              let remote = (try? await db.get("playersPrivate/\(me)/friends", as: [String: PlayerIdentity.Friend].self)) ?? nil
        else { return }
        friends = remote.values.sorted { $0.since > $1.since }; persistFriends()
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

// MARK: - Async friend duels (L5)

nonisolated struct DuelQ: Codable, Sendable {
    var p: String; var o: [String]; var c: Int; var e: String = ""
}
nonisolated struct DuelPlayer: Codable, Sendable {
    var name: String; var done: Bool = false; var score: Int = 0
}
nonisolated struct Duel: Codable, Sendable {
    var createdBy: String; var createdAt: Int; var challenged: String
    var questions: [DuelQ]; var players: [String: DuelPlayer]
}
nonisolated struct DuelInvite: Codable, Sendable, Identifiable {
    var id: String; var from: String; var fromName: String; var at: Int
}
private nonisolated struct DuelInviteWrite: Codable { var from: String; var fromName: String; var at: Int }

/// One row of the duels list — my duel + how it stands (your-turn / waiting / result).
nonisolated struct DuelStanding: Identifiable, Sendable {
    var id: String; var oppName: String; var oppUid: String
    var myDone: Bool; var myScore: Int; var oppDone: Bool; var oppScore: Int
}

/// The async-duel store — mirror of js/duels.js. A duel is one shared question set both players
/// answer on their own time; each writes only their own score slot; the challenger drops an
/// invite in the friend's private inbox. Serverless, $0.
@Observable @MainActor
final class DuelStore {
    static let shared = DuelStore()
    private let db = FirebaseRTDB.shared
    private static let key = "tidbits.duels"

    private(set) var trackedIDs: [String] = UserDefaults.standard.stringArray(forKey: DuelStore.key) ?? []

    private func track(_ id: String) {
        guard !trackedIDs.contains(id) else { return }
        trackedIDs = Array(([id] + trackedIDs).prefix(40))
        UserDefaults.standard.set(trackedIDs, forKey: Self.key)
    }
    private func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    func challenge(friendUID: String, friendName: String, questions: [DuelQ]) async -> String? {
        guard let me = await db.uid, !friendUID.isEmpty, !questions.isEmpty else { return nil }
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased())
        let myName = PlayerIdentityStore.shared.profile?.name ?? "You"
        let duel = Duel(createdBy: me, createdAt: nowMs(), challenged: friendUID,
                        questions: questions, players: [me: DuelPlayer(name: myName)])
        do {
            try await db.put("duels/\(id)", duel)
            try await db.put("duelInbox/\(friendUID)/\(id)", DuelInviteWrite(from: me, fromName: myName, at: nowMs()))
            track(id); return id
        } catch { return nil }
    }

    func load(_ id: String) async -> Duel? { (try? await db.get("duels/\(id)", as: Duel.self)) ?? nil }

    func submit(_ id: String, score: Int) async {
        guard let me = await db.uid else { return }
        let myName = PlayerIdentityStore.shared.profile?.name ?? "You"
        try? await db.put("duels/\(id)/players/\(me)", DuelPlayer(name: myName, done: true, score: score))
        track(id)
    }

    func inbox() async -> [DuelInvite] {
        guard let me = await db.uid,
              let raw = (try? await db.get("duelInbox/\(me)", as: [String: DuelInviteWrite].self)) ?? nil
        else { return [] }
        return raw.map { DuelInvite(id: $0.key, from: $0.value.from, fromName: $0.value.fromName, at: $0.value.at) }
            .sorted { $0.at > $1.at }
    }

    func accept(_ id: String) async {
        track(id)
        if let me = await db.uid { try? await db.delete("duelInbox/\(me)/\(id)") }
    }

    func mine() async -> [DuelStanding] {
        guard let me = await db.uid else { return [] }
        var out: [DuelStanding] = []
        for id in trackedIDs {
            guard let d = await load(id) else { continue }
            let mine = d.players[me]
            let oppUID = d.players.keys.first { $0 != me } ?? d.challenged
            let opp = d.players[oppUID]
            out.append(DuelStanding(id: id, oppName: opp?.name ?? "Opponent", oppUid: oppUID,
                                    myDone: mine?.done ?? false, myScore: mine?.score ?? 0,
                                    oppDone: opp?.done ?? false, oppScore: opp?.score ?? 0))
        }
        return out
    }
}
