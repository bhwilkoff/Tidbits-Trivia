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

    const val ESTABLISHED_AT = 15
    private val scope = CoroutineScope(Dispatchers.Main)

    var profileId: String? = null; private set
    var profile: Profile? by mutableStateOf(null); private set

    /** Ensure identity: stable anon uid → load/create players/{uid}. Local-first: shows a
     *  profile immediately, persists best-effort (works offline / before rules deploy). */
    fun bootstrap() {
        scope.launch {
            try {
                val uid = FirebaseNet.ensureAuth()
                profileId = uid
                profile = FirebaseNet.loadProfile(uid) ?: newProfile().also {
                    runCatching { FirebaseNet.saveProfile(uid, it) }
                }
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

    fun rename(name: String) {
        val p = profile ?: return; val uid = profileId ?: return
        val t = name.trim().take(24); if (t.isEmpty()) return
        val np = p.copy(name = t); profile = np
        scope.launch { runCatching { FirebaseNet.saveProfile(uid, np) } }
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

    private val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    fun today(): String = fmt.format(Date())
    fun dayGap(from: String, to: String): Int {
        if (from.isEmpty()) return 1
        return try { ((fmt.parse(to)!!.time - fmt.parse(from)!!.time) / 86_400_000L).toInt() }
        catch (e: Exception) { 99 }
    }
}
