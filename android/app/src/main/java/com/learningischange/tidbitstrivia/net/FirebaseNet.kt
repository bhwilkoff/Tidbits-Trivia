package com.learningischange.tidbitstrivia.net

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.MutableData
import com.google.firebase.database.Transaction
import com.google.firebase.database.ValueEventListener
import kotlinx.coroutines.tasks.await
import kotlin.random.Random

/**
 * Online Quick Match over Firebase Realtime Database (Decision 040) — the Android
 * twin of js/firebase.js. Same room model as local Trivia Night: a room code
 * gates entry, each device runs its own engine over the shared question set and
 * self-reports its score; a leader-elected coordinator paces. Anonymous auth
 * gives each device a uid so Security Rules scope writes; no accounts, no PII.
 * (Apple online rides GameKit instead — Decision 039.)
 */
object FirebaseNet {
    private val auth by lazy { FirebaseAuth.getInstance() }
    private val db by lazy { FirebaseDatabase.getInstance() }
    var uid: String? = null; private set

    private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private fun newCode() = (1..4).map { ALPHABET[Random.nextInt(ALPHABET.length)] }.joinToString("")

    /** Ensure an anonymous session; throws if the provider is disabled. */
    suspend fun ensureAuth(): String {
        uid?.let { return it }
        val result = auth.signInAnonymously().await()
        val u = result.user!!.uid
        uid = u
        return u
    }

    // ---- Portable player identity (players/{uid}) — see PlayerIdentity.kt ----

    suspend fun loadProfile(uid: String): com.learningischange.tidbitstrivia.data.PlayerIdentity.Profile? {
        val s = db.getReference("players/$uid").get().await()
        if (!s.exists()) return null
        fun i(c: com.google.firebase.database.DataSnapshot, k: String) = c.child(k).getValue(Long::class.java)?.toInt() ?: 0
        val r = s.child("rating"); val st = s.child("streak"); val stat = s.child("stats")
        return com.learningischange.tidbitstrivia.data.PlayerIdentity.Profile(
            name = s.child("name").getValue(String::class.java) ?: "",
            createdAt = s.child("createdAt").getValue(Long::class.java) ?: 0L,
            avatarSeed = s.child("avatarSeed").getValue(String::class.java) ?: "",
            rating = com.learningischange.tidbitstrivia.data.PlayerIdentity.Rating(
                r.child("value").getValue(Double::class.java) ?: 1000.0, i(r, "games"),
                r.child("provisional").getValue(Boolean::class.java) ?: true),
            streak = com.learningischange.tidbitstrivia.data.PlayerIdentity.Streak(
                i(st, "current"), i(st, "longest"),
                st.child("lastPlayedDay").getValue(String::class.java) ?: "", i(st, "freezes")),
            stats = com.learningischange.tidbitstrivia.data.PlayerIdentity.Stats(
                i(stat, "gamesPlayed"), i(stat, "questionsAnswered"), i(stat, "correct"),
                i(stat, "liveNights"), i(stat, "venuesVisited")))
    }

    fun isSignedIn(): Boolean = auth.currentUser?.let { !it.isAnonymous } ?: false
    fun currentEmail(): String? = auth.currentUser?.takeIf { !it.isAnonymous }?.email

    /** Sign out of the federated account and return to a FRESH anonymous session (new
     *  uid). The account's records stay keyed by email; signing in again restores them. */
    suspend fun signOutUser(): String {
        auth.signOut()
        return auth.signInAnonymously().await().user!!.uid
    }

    /** Ownership proof for the email-keyed profile — the players/{key} write rule requires
     *  emailOwners/{key} to match auth.token.email. */
    suspend fun setEmailOwner(accountKey: String, email: String) {
        db.getReference("emailOwners/$accountKey").setValue(email).await()
    }

    /** Synced daily log (dayKey → score) — so "done today" + the archive follow the identity. */
    suspend fun setDailyScore(key: String, day: String, score: Int) {
        db.getReference("dailyLog/$key/$day").setValue(score).await()
    }
    suspend fun loadDailyLog(key: String): Map<String, Int> {
        val snap = db.getReference("dailyLog/$key").get().await()
        val out = HashMap<String, Int>()
        for (child in snap.children) child.getValue(Int::class.java)?.let { out[child.key!!] = it }
        return out
    }

    /** (B) Live NAME sync — a remote name change on players/{key} fires cb. Returns an
     *  unsubscribe fn. Name-only so a game in progress elsewhere can't revert local stats. */
    fun observeName(key: String, cb: (String?) -> Unit): () -> Unit {
        val ref = db.getReference("players/$key")
        val listener = object : ValueEventListener {
            override fun onDataChange(snap: DataSnapshot) { cb(snap.child("name").getValue(String::class.java)) }
            override fun onCancelled(e: DatabaseError) {}
        }
        ref.addValueEventListener(listener)
        return { ref.removeEventListener(listener) }
    }

    data class FederatedResult(val uid: String, val email: String?, val displayName: String?)

    /** Google sign-in via Credential Manager → the Google Firebase account + its verified
     *  email. Identity keys the shared profile by the email so Apple + Google converge. */
    suspend fun signInGoogle(context: Context, webClientId: String): FederatedResult {
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(webClientId)
            .setFilterByAuthorizedAccounts(false)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val response = CredentialManager.create(context).getCredential(context, request)
        val googleCred = GoogleIdTokenCredential.createFrom(response.credential.data)
        val firebaseCred = GoogleAuthProvider.getCredential(googleCred.idToken, null)
        val res = auth.signInWithCredential(firebaseCred).await()
        return FederatedResult(res.user!!.uid, res.user!!.email, res.user!!.displayName)
    }

    suspend fun saveProfile(uid: String, p: com.learningischange.tidbitstrivia.data.PlayerIdentity.Profile) {
        db.getReference("players/$uid").setValue(mapOf(
            "name" to p.name, "createdAt" to p.createdAt, "avatarSeed" to p.avatarSeed,
            "rating" to mapOf("value" to p.rating.value, "games" to p.rating.games, "provisional" to p.rating.provisional),
            "streak" to mapOf("current" to p.streak.current, "longest" to p.streak.longest, "lastPlayedDay" to p.streak.lastPlayedDay, "freezes" to p.streak.freezes),
            "stats" to mapOf("gamesPlayed" to p.stats.gamesPlayed, "questionsAnswered" to p.stats.questionsAnswered, "correct" to p.stats.correct, "liveNights" to p.stats.liveNights, "venuesVisited" to p.stats.venuesVisited))).await()
    }

    data class Match(val roomId: String, val isLeader: Boolean)

    /** Claim an open room from the queue, else create + advertise one. */
    suspend fun quickMatch(name: String): Match {
        val me = ensureAuth()
        val queueRef = db.getReference("queue/mixed")
        val claimed = queueRef.claimOpenRoom(me)
        if (claimed != null) {
            db.getReference("rooms/$claimed/players/$me").setValue(mapOf("name" to name, "score" to 0L)).await()
            return Match(claimed, false)
        }
        val roomId = newCode()
        val now = System.currentTimeMillis()
        db.getReference("rooms/$roomId/meta").setValue(mapOf("host" to me, "createdAt" to now, "state" to "lobby")).await()
        db.getReference("rooms/$roomId/players/$me").setValue(mapOf("name" to name, "score" to 0L)).await()
        queueRef.setValue(mapOf("roomId" to roomId, "host" to me, "ts" to now)).await()
        return Match(roomId, true)
    }

    /** Transaction: if an open room (advertised by someone else) is waiting, take
     *  it and clear the slot; return its id. Otherwise leave the queue untouched. */
    private suspend fun DatabaseReference.claimOpenRoom(me: String): String? {
        var claimedId: String? = null
        val txn = runTransaction { current ->
            @Suppress("UNCHECKED_CAST")
            val v = current.value as? Map<String, Any?>
            val roomId = v?.get("roomId") as? String
            val host = v?.get("host") as? String
            if (roomId != null && host != me) { claimedId = roomId; current.value = null }
            Transaction.success(current)
        }
        return if (txn) claimedId else null
    }

    suspend fun joinRoom(roomId: String, name: String): Match {
        val me = ensureAuth()
        db.getReference("rooms/$roomId/players/$me").setValue(mapOf("name" to name, "score" to 0L)).await()
        return Match(roomId, false)
    }

    suspend fun setMeta(roomId: String, patch: Map<String, Any?>) {
        db.getReference("rooms/$roomId/meta").updateChildren(patch).await()
    }

    suspend fun reportScore(roomId: String, score: Int, done: Boolean) {
        val me = uid ?: return
        db.getReference("rooms/$roomId/players/$me").updateChildren(mapOf("score" to score.toLong(), "done" to done)).await()
    }

    fun leave(roomId: String) {
        val me = uid ?: return
        db.getReference("rooms/$roomId/players/$me").removeValue()
    }

    /** Observe roster (uid -> {name, score, done}); returns an unsubscribe. */
    fun onRoster(roomId: String, cb: (Map<String, Player>) -> Unit): () -> Unit =
        listen("rooms/$roomId/players") { snap ->
            cb(snap.children.mapNotNull { c ->
                val id = c.key ?: return@mapNotNull null
                id to Player(
                    name = c.child("name").getValue(String::class.java) ?: "Player",
                    score = (c.child("score").getValue(Long::class.java) ?: 0L).toInt(),
                    done = c.child("done").getValue(Boolean::class.java) ?: false,
                )
            }.toMap())
        }

    fun onMeta(roomId: String, cb: (Map<String, Any?>) -> Unit): () -> Unit =
        listen("rooms/$roomId/meta") { snap ->
            cb(mapOf(
                "state" to snap.child("state").getValue(String::class.java),
                "questions" to snap.child("questions").getValue(String::class.java),
            ))
        }

    private fun listen(path: String, onData: (DataSnapshot) -> Unit): () -> Unit {
        val ref = db.getReference(path)
        val l = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) = onData(snapshot)
            override fun onCancelled(error: DatabaseError) {}
        }
        ref.addValueEventListener(l)
        return { ref.removeEventListener(l) }
    }

    data class Player(val name: String, val score: Int, val done: Boolean)

    // MARK: - Tidbits Live (Mac-hosted pub event; path `live/{code}`)
    //
    // The join half of the Tidbits Live room contract (docs/LIVE-ROOM-CONTRACT.md).
    // A separate room model from Quick Match (`rooms/`): the Mac host owns
    // meta/pub/scores; this player owns teams/{uid} + answers/{qid}/{uid}. Mirrors
    // js/firebase.js (liveJoin/liveOnPub/liveSubmit/…) and the Swift LivePlayerClient
    // exactly — the same keys, so a Mac host reaches Apple, web, AND Android players.

    data class LiveNumeric(val min: Double, val max: Double, val step: Double, val unit: String)
    data class LivePub(
        val round: Int, val roundTitle: String, val qid: String, val qNum: Int, val qTotal: Int,
        val phase: String, val prompt: String, val options: List<String>?, val format: String,
        val answerIndex: Int?,
        // Non-MCQ payloads (only the field for the current `format` is set).
        val imageUrl: String? = null, val numeric: LiveNumeric? = null,
        val orderItems: List<String>? = null, val matchKeys: List<String>? = null,
        val matchValues: List<String>? = null, val enumTarget: Int? = null,
        val locked: Boolean = false,
        val story: String? = null,   // Wave A: the story behind the answer (reveal only)
        val deadline: Long? = null,  // Wave A: epoch-ms countdown deadline (question phase)
        val wager: Boolean = false,  // Wave A: wager question — the joiner shows a stake input
    )
    /** A player's submission (any shape) — the host scores it locally on reveal. */
    data class LiveAnswer(
        val choice: Int? = null, val text: String? = null, val number: Double? = null,
        val order: List<Int>? = null, val pairs: List<Int>? = null, val list: List<String>? = null,
        val ts: Long = 0,
    )
    data class LiveMeta(val state: String, val venue: String)

    /** True if a Mac host has opened `live/{code}` — the unified "Join a game"
     *  front probes this to tell a hosted Live event from a LAN Trivia Night. */
    suspend fun probeLive(code: String): Boolean {
        ensureAuth()
        return db.getReference("live/$code/meta").get().await().exists()
    }

    /** Register this device as a team in the room; returns the uid. */
    suspend fun liveJoin(code: String, team: String): String {
        val me = ensureAuth()
        db.getReference("live/$code/teams/$me")
            .setValue(mapOf("name" to team, "joinedAt" to System.currentTimeMillis())).await()
        return me
    }

    /** Submit an MCQ answer (host reveals + scores). */
    suspend fun liveSubmit(code: String, qid: String, choice: Int) {
        liveSubmitAnswer(code, qid, mapOf("choice" to choice.toLong()))
    }

    /** Submit any answer shape (number/text/order/pairs/list) — see LiveAnswer. */
    suspend fun liveSubmitAnswer(code: String, qid: String, fields: Map<String, Any?>) {
        val me = uid ?: return
        db.getReference("live/$code/answers/$qid/$me")
            .setValue(fields + ("ts" to System.currentTimeMillis())).await()
    }

    fun liveLeave(code: String) {
        val me = uid ?: return
        db.getReference("live/$code/teams/$me").removeValue()
    }

    fun liveOnPub(code: String, cb: (LivePub?) -> Unit): () -> Unit =
        listen("live/$code/pub") { cb(parsePub(it)) }

    fun liveOnMeta(code: String, cb: (LiveMeta?) -> Unit): () -> Unit =
        listen("live/$code/meta") { snap ->
            cb(if (snap.exists()) LiveMeta(
                state = snap.child("state").getValue(String::class.java) ?: "lobby",
                venue = snap.child("venue").getValue(String::class.java) ?: "",
            ) else null)
        }

    fun liveOnScore(code: String, cb: (Int) -> Unit): () -> Unit {
        val me = uid ?: return {}
        return listen("live/$code/scores/$me") { snap -> cb((snap.getValue(Long::class.java) ?: 0L).toInt()) }
    }

    private fun parsePub(snap: DataSnapshot): LivePub? {
        val qid = snap.child("qid").getValue(String::class.java) ?: return null
        val opts = snap.child("options").children.mapNotNull { it.getValue(String::class.java) }
        return LivePub(
            round = (snap.child("round").getValue(Long::class.java) ?: 0L).toInt(),
            roundTitle = snap.child("roundTitle").getValue(String::class.java) ?: "",
            qid = qid,
            qNum = (snap.child("qNum").getValue(Long::class.java) ?: 0L).toInt(),
            qTotal = (snap.child("qTotal").getValue(Long::class.java) ?: 0L).toInt(),
            phase = snap.child("phase").getValue(String::class.java) ?: "question",
            prompt = snap.child("prompt").getValue(String::class.java) ?: "",
            options = opts.ifEmpty { null },
            format = snap.child("format").getValue(String::class.java) ?: "classic",
            answerIndex = snap.child("answerIndex").getValue(Long::class.java)?.toInt(),
            imageUrl = snap.child("imageURL").getValue(String::class.java),
            numeric = snap.child("numeric").takeIf { it.exists() }?.let { n ->
                LiveNumeric(
                    (n.child("min").value as? Number)?.toDouble() ?: 0.0,
                    (n.child("max").value as? Number)?.toDouble() ?: 0.0,
                    (n.child("step").value as? Number)?.toDouble() ?: 1.0,
                    n.child("unit").getValue(String::class.java) ?: "")
            },
            orderItems = snap.child("orderItems").children.mapNotNull { it.getValue(String::class.java) }.ifEmpty { null },
            matchKeys = snap.child("matchKeys").children.mapNotNull { it.getValue(String::class.java) }.ifEmpty { null },
            matchValues = snap.child("matchValues").children.mapNotNull { it.getValue(String::class.java) }.ifEmpty { null },
            enumTarget = snap.child("enumTarget").getValue(Long::class.java)?.toInt(),
            locked = snap.child("locked").getValue(Boolean::class.java) ?: false,
            story = snap.child("story").getValue(String::class.java),
            deadline = snap.child("deadline").getValue(Long::class.java),
            wager = snap.child("wager").getValue(Boolean::class.java) ?: false,
        )
    }

    // ---- HOST side (this device opens live/{code} and owns meta/pub/scores) ----
    // The Android app can now HOST a casual Trivia Night on the same backend as
    // Tidbits Live (owner architecture). Mirrors LiveNightHost (Swift) + the web.

    suspend fun liveHostOpen(name: String): String {
        val me = ensureAuth()
        val code = newCode()
        db.getReference("live/$code/meta").setValue(mapOf(
            "host" to me, "createdAt" to System.currentTimeMillis(),
            "name" to name, "venue" to "", "state" to "lobby")).await()
        return code
    }
    suspend fun livePublish(code: String, pub: Map<String, Any?>) {
        db.getReference("live/$code/pub").setValue(pub).await()
    }
    suspend fun liveSetState(code: String, state: String) {
        db.getReference("live/$code/meta").updateChildren(mapOf("state" to state)).await()
    }
    suspend fun liveSetScore(code: String, uid: String, score: Int) {
        db.getReference("live/$code/scores/$uid").setValue(maxOf(0, score).toLong()).await()
    }
    fun liveOnTeams(code: String, cb: (Map<String, String>) -> Unit): () -> Unit =
        listen("live/$code/teams") { snap ->
            cb(snap.children.mapNotNull { c ->
                val id = c.key ?: return@mapNotNull null
                id to (c.child("name").getValue(String::class.java) ?: "Team")
            }.toMap())
        }
    fun liveOnScores(code: String, cb: (Map<String, Int>) -> Unit): () -> Unit =
        listen("live/$code/scores") { snap ->
            cb(snap.children.mapNotNull { c ->
                val id = c.key ?: return@mapNotNull null
                id to (c.getValue(Long::class.java) ?: 0L).toInt()
            }.toMap())
        }
    fun liveOnAnswers(code: String, qid: String, cb: (Map<String, LiveAnswer>) -> Unit): () -> Unit =
        listen("live/$code/answers/$qid") { snap ->
            cb(snap.children.mapNotNull { c ->
                val id = c.key ?: return@mapNotNull null
                id to LiveAnswer(
                    choice = (c.child("choice").value as? Number)?.toInt(),
                    text = c.child("text").getValue(String::class.java),
                    number = (c.child("number").value as? Number)?.toDouble(),
                    order = c.child("order").children.mapNotNull { (it.value as? Number)?.toInt() }.ifEmpty { null },
                    pairs = c.child("pairs").children.mapNotNull { (it.value as? Number)?.toInt() }.ifEmpty { null },
                    list = c.child("list").children.mapNotNull { it.getValue(String::class.java) }.ifEmpty { null },
                    ts = (c.child("ts").value as? Number)?.toLong() ?: 0L,
                )
            }.toMap())
        }
    // Host-plays-too: register as a team + answer under the host's own uid.
    suspend fun liveHostJoinAsTeam(code: String, name: String) {
        val me = uid ?: return
        db.getReference("live/$code/teams/$me").setValue(mapOf("name" to name, "joinedAt" to System.currentTimeMillis())).await()
    }
    suspend fun liveHostAnswer(code: String, qid: String, choice: Int) {
        val me = uid ?: return
        db.getReference("live/$code/answers/$qid/$me").setValue(mapOf("choice" to choice.toLong(), "ts" to System.currentTimeMillis())).await()
    }
    fun liveClose(code: String) { db.getReference("live/$code").removeValue() }
}

private suspend fun DatabaseReference.runTransaction(handler: (MutableData) -> Transaction.Result): Boolean {
    return kotlin.coroutines.suspendCoroutine { cont ->
        runTransaction(object : Transaction.Handler {
            override fun doTransaction(currentData: MutableData): Transaction.Result = handler(currentData)
            override fun onComplete(error: DatabaseError?, committed: Boolean, currentData: DataSnapshot?) {
                cont.resumeWith(Result.success(committed && error == null))
            }
        })
    }
}
