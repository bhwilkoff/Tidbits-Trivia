package com.learningischange.tidbitstrivia.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.learningischange.tidbitstrivia.net.FirebaseNet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.pow

/**
 * The portable Tidbits player identity on Android — ONE shared cross-platform profile
 * (players/{uid}) that spans solo + live, the twin of the Swift PlayerIdentity. The
 * Firebase SDK persists the anonymous session automatically, so the uid (hence the
 * profile) is stable across launches for free. Native Google Play Games links in later.
 * See docs/PLAYER-IDENTITY-CONTRACT.md.
 */
object PlayerIdentity {
    data class Rating(val value: Double = 1000.0, val games: Int = 0, val provisional: Boolean = true)
    data class Streak(val current: Int = 0, val longest: Int = 0, val lastPlayedDay: String = "", val freezes: Int = 0)
    data class Stats(val gamesPlayed: Int = 0, val questionsAnswered: Int = 0, val correct: Int = 0, val liveNights: Int = 0, val venuesVisited: Int = 0)
    data class Profile(val name: String, val createdAt: Long, val avatarSeed: String,
                       val rating: Rating, val streak: Streak, val stats: Stats)

    // L5 social graph: a person you've played with and added — a private "follow".
    data class Friend(val uid: String, val name: String, val avatarSeed: String = "", val since: Long = 0L)

    const val ESTABLISHED_AT = 15
    private val scope = CoroutineScope(Dispatchers.Main)

    var profileId: String? = null; private set
    var profile: Profile? by mutableStateOf(null); private set
    var friends: List<Friend> by mutableStateOf(emptyList()); private set
    /// True once promoted from anonymous via a federated sign-in (records roam + survive
    /// session loss). The Firebase SDK persists the session, so this is authoritative.
    var signedIn: Boolean by mutableStateOf(false); private set
    /// Bumped after the daily log syncs, so the daily card/lock recompose off the fresh data.
    var dailyLogRev: Int by mutableStateOf(0); private set

    /** Ensure identity: stable anon uid → load/create players/{uid}. Local-first: shows a
     *  profile immediately, persists best-effort (works offline / before rules deploy). */
    fun bootstrap() {
        scope.launch {
            try {
                val uid = FirebaseNet.ensureAuth()
                val email = FirebaseNet.currentEmail()
                if (FirebaseNet.isSignedIn() && email != null) {   // signed in → key by verified email
                    signedIn = true
                    val key = accountKey(email)
                    profileId = key
                    val remote = FirebaseNet.loadProfile(key)
                    if (remote != null) profile = remote
                    else {                                          // migrate an older uid-keyed profile
                        val base = FirebaseNet.loadProfile(uid) ?: newProfile()
                        runCatching { FirebaseNet.setEmailOwner(key, email) }
                        runCatching { FirebaseNet.saveProfile(key, base) }
                        profile = base
                    }
                } else {                                            // anonymous → key by uid
                    signedIn = false
                    profileId = uid
                    profile = FirebaseNet.loadProfile(uid) ?: newProfile().also {
                        runCatching { FirebaseNet.saveProfile(uid, it) }
                    }
                }
                profileId?.let { watch(it) }                    // (B) live name sync
            } catch (e: Exception) {
                if (profile == null) profile = newProfile()   // offline / no auth → local profile
            }
        }
    }

    /** Feed a finished game into the profile (rating + streak + stats), persist best-effort. */
    fun recordGame(correct: Int, total: Int, live: Boolean = false) {
        val p = profile ?: return; val uid = profileId ?: return
        if (total <= 0) return
        val np = p.copy(
            rating = updatedRating(p.rating, correct.toDouble() / total, if (live) 1.5 else 1.0),
            streak = playedStreak(p.streak, today(), live),
            stats = p.stats.copy(
                gamesPlayed = p.stats.gamesPlayed + 1,
                questionsAnswered = p.stats.questionsAnswered + total,
                correct = p.stats.correct + correct,
                liveNights = p.stats.liveNights + if (live) 1 else 0))
        profile = np
        scope.launch { runCatching { FirebaseNet.saveProfile(uid, np) } }
    }

    /** A finished LIVE game — advances the cross-context streak (a live night, +freeze),
     *  counts the night, nudges the rating from MCQ accuracy when available. */
    fun recordLiveGame(correct: Int, answered: Int) {
        val p = profile ?: return; val uid = profileId ?: return
        val rating = if (answered > 0) updatedRating(p.rating, correct.toDouble() / answered, 1.5) else p.rating
        val np = p.copy(
            rating = rating,
            streak = playedStreak(p.streak, today(), true),
            stats = p.stats.copy(
                gamesPlayed = p.stats.gamesPlayed + 1,
                questionsAnswered = p.stats.questionsAnswered + (if (answered > 0) answered else 0),
                correct = p.stats.correct + (if (answered > 0) correct else 0),
                liveNights = p.stats.liveNights + 1))
        profile = np
        scope.launch { runCatching { FirebaseNet.saveProfile(uid, np) } }
    }

    /** Wave E: write this player's cumulative per-venue season standing after a live night —
     *  keyed by the AUTH uid (the standings rule requires auth.uid === $uid). The $0 cron
     *  aggregates these into the static cross-venue leaderboard. */
    fun recordStanding(venue: String, score: Int) {
        val vk = venueKey(venue); val name = profile?.name
        if (vk.isEmpty() || score <= 0 || name == null) return
        scope.launch {
            val uid = FirebaseNet.uid() ?: return@launch
            val path = "standings/${currentSeason()}/$vk/$uid"
            runCatching {
                val existing = FirebaseNet.loadStanding(path)
                val prevScore = (existing?.get("score") as? Number)?.toInt() ?: 0
                val prevNights = (existing?.get("nights") as? Number)?.toInt() ?: 0
                FirebaseNet.setStanding(path, mapOf(
                    "name" to name,
                    "score" to (prevScore + score).toLong(),
                    "nights" to (prevNights + 1).toLong(),
                    "updatedAt" to System.currentTimeMillis()))
            }
        }
    }

    /** Byte-identical to Swift/JS: calendar-quarter season id + a path-safe venue key. */
    fun currentSeason(): String {
        val c = java.util.Calendar.getInstance()
        return "${c.get(java.util.Calendar.YEAR)}-S${c.get(java.util.Calendar.MONTH) / 3 + 1}"
    }
    fun venueKey(v: String): String = v.trim().lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')

    /** Google sign-in → key the profile by the verified email so Apple + Google (and every
     *  device) share one record set. Merges this device's anonymous activity in; the guard
     *  prevents ever re-merging. Returns true if it merged into an existing account. */
    suspend fun linkGoogle(context: android.content.Context, webClientId: String): Boolean {
        if (signedIn) return false   // already on a durable account — never re-merge the same records
        val local = profile ?: newProfile()
        val res = FirebaseNet.signInGoogle(context, webClientId)
        val email = res.email
        if (email == null) {                                    // no email (rare) — uid-keyed fallback
            profileId = res.uid
            runCatching { FirebaseNet.saveProfile(res.uid, local) }
            signedIn = true
            watch(res.uid)
            return false
        }
        val key = accountKey(email)
        runCatching { FirebaseNet.setEmailOwner(key, email) }
        val existing = FirebaseNet.loadProfile(key)
        var merged = if (existing != null) merge(local, existing) else local
        val dn = res.displayName?.trim()
        if (isDefaultName(merged.name) && !dn.isNullOrEmpty()) merged = merged.copy(name = dn.take(24))   // (A) adopt provider name
        profile = merged
        profileId = key
        runCatching { FirebaseNet.saveProfile(key, merged) }
        signedIn = true
        watch(key)   // (B) live name sync
        return existing != null
    }

    private var unwatch: (() -> Unit)? = null
    /** (B) Live cross-device NAME sync — a rename elsewhere updates this device in place. */
    private fun watch(key: String) {
        unwatch?.invoke(); unwatch = null
        unwatch = FirebaseNet.observeName(key) { name ->
            val p = profile
            if (name != null && p != null && name != p.name) profile = p.copy(name = name)
        }
    }

    /** (L2) Daily log sync — when signed in, a daily completion also lands in dailyLog/{key}
     *  so "done today" + the archive follow the identity across devices. */
    fun syncDailyScore(day: String, score: Int) {
        if (!signedIn) return
        val key = profileId ?: return
        scope.launch { runCatching { FirebaseNet.setDailyScore(key, day, score) } }
    }

    /** The Daily's global board (docs/DAILY-BOARD-CONTRACT.md): after finishing TODAY's
     *  Daily, write this player's one row so the hourly cron ranks the field. Keyed by the
     *  AUTH uid (like standings). Free — sign-in not required. `marks` is the 7-char hit
     *  string, aligned to the shared pickDaily order by the caller (which has the answers),
     *  so per-question accuracy is comparable across players. */
    fun submitDailyBoard(marks: String, score: Int, correct: Int, ms: Long) {
        val name = profile?.name ?: "Player"
        val seed = profile?.avatarSeed ?: ""
        scope.launch {
            val uid = FirebaseNet.uid() ?: return@launch
            runCatching {
                FirebaseNet.setDailyBoard(dayKey(), uid, mapOf(
                    "name" to name, "avatarSeed" to seed,
                    "score" to score.toLong(), "correct" to correct.toLong(),
                    "marks" to marks, "ms" to ms, "at" to System.currentTimeMillis()))
            }
        }
    }
    /** Reconcile the local daily log with the synced one. On sign-in, push local (anon)
     *  plays first so nothing is lost; then pull the union into the local store. */
    suspend fun syncDailyLog(store: Store, pushLocal: Boolean = false) {
        if (!signedIn) return
        val key = profileId ?: return
        val remote = runCatching { FirebaseNet.loadDailyLog(key) }.getOrNull() ?: emptyMap()
        // Push only days the account doesn't already have — an established daily score is
        // never overwritten, so replaying a day while logged out can't beat it.
        if (pushLocal) store.allDaily().forEach { (day, score) ->
            if (!remote.containsKey(day)) runCatching { FirebaseNet.setDailyScore(key, day, score) }
        }
        // The account is authoritative — adopt its value for every day (reconciles cross-device).
        remote.forEach { (day, score) -> store.adoptDaily(day, score) }
        dailyLogRev++   // trigger recomposition of the daily card/lock
    }

    /** Stable, non-reversible profile key from the verified email — mirror of JS/Swift. */
    fun accountKey(email: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(email.trim().lowercase().toByteArray())
            .joinToString("") { "%02x".format(it) }

    /** Sign out → back to a fresh anonymous profile on this device. The account's records
     *  stay in the cloud; signing in again (Google) restores + merges them. */
    suspend fun signOut() {
        Entitlement.clearOnSignOut()   // next person on this device isn't you — drop cached Club
        val uid = FirebaseNet.signOutUser()
        profileId = uid
        profile = FirebaseNet.loadProfile(uid) ?: newProfile().also { runCatching { FirebaseNet.saveProfile(uid, it) } }
        signedIn = false
        watch(uid)                                              // (B) re-point to the fresh anon
    }

    fun rename(name: String) {
        val p = profile ?: return; val uid = profileId ?: return
        val t = name.trim().take(24); if (t.isEmpty()) return
        val np = p.copy(name = t); profile = np
        scope.launch { runCatching { FirebaseNet.saveProfile(uid, np) } }
    }

    /** L4 cosmetics: re-roll the avatar seed -> a new deterministic color. Persists + syncs like rename. */
    fun rerollAvatar() {
        val p = profile ?: return; val uid = profileId ?: return
        val np = p.copy(avatarSeed = java.util.UUID.randomUUID().toString().take(8).lowercase()); profile = np
        scope.launch { runCatching { FirebaseNet.saveProfile(uid, np) } }
    }

    // --- Social graph (L5): a private "people I've played with" list ---
    fun isFriend(uid: String) = friends.any { it.uid == uid }

    fun addFriend(uid: String, name: String, avatarSeed: String = "") {
        val me = FirebaseNet.uid() ?: return
        if (uid.isEmpty() || uid == me || isFriend(uid)) return
        val f = Friend(uid, name.ifEmpty { "Player" }, avatarSeed, System.currentTimeMillis())
        friends = listOf(f) + friends
        scope.launch { runCatching { FirebaseNet.setFriend(me, uid, mapOf("uid" to f.uid, "name" to f.name, "avatarSeed" to f.avatarSeed, "since" to f.since)) } }
    }

    fun removeFriend(uid: String) {
        friends = friends.filterNot { it.uid == uid }
        val me = FirebaseNet.uid() ?: return
        scope.launch { runCatching { FirebaseNet.removeFriend(me, uid) } }
    }

    fun loadFriends() {
        val me = FirebaseNet.uid() ?: return
        scope.launch { runCatching { friends = FirebaseNet.loadFriends(me).sortedByDescending { it.since } } }
    }

    private fun newProfile() = Profile(
        "Player ${(1000..9999).random()}", System.currentTimeMillis(),
        java.util.UUID.randomUUID().toString().take(8).lowercase(), Rating(), Streak(), Stats())

    // --- rating + streak logic (mirror of the Swift PlayerIdentity extensions) ---

    /** Self-correcting bounded Elo: accuracy (0..1) is the score vs an implied field
     *  rating; provisional games move faster; live weighted higher. */
    fun updatedRating(r: Rating, accuracy: Double, weight: Double, field: Double = 1200.0): Rating {
        val expected = 1.0 / (1.0 + 10.0.pow((field - r.value) / 400.0))
        val k = (if (r.provisional) 64.0 else 24.0) * weight
        val n = r.games + 1
        val v = maxOf(100.0, Math.round(r.value + k * (accuracy - expected)).toDouble())
        return Rating(v, n, n < ESTABLISHED_AT)
    }

    /** Cross-context + forgiving: consecutive +1; a one-day gap spends a freeze; a bigger
     *  gap restarts at 1; a live night grants a freeze (cap 3). */
    fun playedStreak(s: Streak, today: String, liveNight: Boolean): Streak {
        var cur = s.current; var freezes = s.freezes; var longest = s.longest; var last = s.lastPlayedDay
        if (today != s.lastPlayedDay) {
            val gap = dayGap(s.lastPlayedDay, today)
            cur = when {
                s.lastPlayedDay.isEmpty() || gap == 1 -> cur + 1
                gap == 2 && freezes > 0 -> { freezes -= 1; cur + 1 }
                else -> 1
            }
            longest = maxOf(longest, cur); last = today
        }
        if (liveNight) freezes = minOf(freezes + 1, 3)
        return Streak(cur, longest, last, freezes)
    }

    fun isDefaultName(n: String) = n.startsWith("Player ")

    /** LOSSLESS merge of a local anon profile into an account profile (survivor) on
     *  sign-in conflict — stats summed, order-independent. Mirror of Swift/JS merge. */
    fun merge(local: Profile, account: Profile): Profile {
        val name = if (!isDefaultName(account.name)) account.name else if (!isDefaultName(local.name)) local.name else account.name
        val rGames = local.rating.games + account.rating.games
        val rating = Rating(maxOf(local.rating.value, account.rating.value), rGames, rGames < ESTABLISHED_AT)
        val streak = Streak(
            if (local.streak.lastPlayedDay >= account.streak.lastPlayedDay) local.streak.current else account.streak.current,
            maxOf(local.streak.longest, account.streak.longest),
            maxOf(local.streak.lastPlayedDay, account.streak.lastPlayedDay),
            maxOf(local.streak.freezes, account.streak.freezes))
        val stats = Stats(
            local.stats.gamesPlayed + account.stats.gamesPlayed,
            local.stats.questionsAnswered + account.stats.questionsAnswered,
            local.stats.correct + account.stats.correct,
            local.stats.liveNights + account.stats.liveNights,
            maxOf(local.stats.venuesVisited, account.stats.venuesVisited))
        return Profile(name, minOf(local.createdAt, account.createdAt), account.avatarSeed, rating, streak, stats)
    }

    private val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    fun today(): String = fmt.format(Date())
    fun dayGap(from: String, to: String): Int {
        if (from.isEmpty()) return 1
        return try { ((fmt.parse(to)!!.time - fmt.parse(from)!!.time) / 86_400_000L).toInt() }
        catch (e: Exception) { 99 }
    }
}
