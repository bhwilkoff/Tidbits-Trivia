package com.learningischange.tidbitstrivia.net

import com.google.firebase.auth.FirebaseAuth
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

    data class LivePub(
        val round: Int, val roundTitle: String, val qid: String, val qNum: Int, val qTotal: Int,
        val phase: String, val prompt: String, val options: List<String>?, val format: String,
        val answerIndex: Int?,
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

    /** Submit an answer for the current question (host reveals + scores). */
    suspend fun liveSubmit(code: String, qid: String, choice: Int) {
        val me = uid ?: return
        db.getReference("live/$code/answers/$qid/$me")
            .setValue(mapOf("choice" to choice.toLong(), "ts" to System.currentTimeMillis())).await()
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
    fun liveOnAnswers(code: String, qid: String, cb: (Map<String, Int>) -> Unit): () -> Unit =
        listen("live/$code/answers/$qid") { snap ->
            cb(snap.children.mapNotNull { c ->
                val id = c.key ?: return@mapNotNull null
                val choice = c.child("choice").getValue(Long::class.java) ?: return@mapNotNull null
                id to choice.toInt()
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
