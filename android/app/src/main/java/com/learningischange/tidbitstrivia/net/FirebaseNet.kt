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
