package com.learningischange.tidbitstrivia.data

// L5 async friend duels — mirror of js/duels.js + Core DuelStore. A duel = one shared question set
// both players answer on their own time; each writes only their own score slot; the challenger
// drops an invite in the friend's private inbox. Serverless, $0.
// v1: tracked ids are in-memory (lost on process death); SharedPreferences persistence is a follow-up.

import com.google.firebase.database.DataSnapshot
import com.learningischange.tidbitstrivia.net.FirebaseNet

data class DuelQ(val p: String, val o: List<String>, val c: Int, val e: String = "")
data class DuelStanding(val id: String, val oppName: String, val oppUid: String, val myDone: Boolean, val myScore: Int, val oppDone: Boolean, val oppScore: Int)
data class DuelInvite(val id: String, val from: String, val fromName: String, val at: Long)

object Duels {
    private val ids = mutableListOf<String>()
    private var prefs: android.content.SharedPreferences? = null

    /** Called once from the Application so tracked duel ids survive process death. */
    fun init(ctx: android.content.Context) {
        prefs = ctx.getSharedPreferences("tidbits.duels", android.content.Context.MODE_PRIVATE)
        ids.clear()
        ids.addAll((prefs?.getString("ids", "") ?: "").split(",").filter { it.isNotBlank() })
    }
    /** The duel ids this device is tracking — account deletion drops MY slot in each. */
    fun trackedIds(): List<String> = ids.toList()

    /** Account deletion: forget the duels this device remembers. The shared duel record
     *  itself is the opponent's too, so only my slot in it is removed (by the caller). */
    fun clearLocal() {
        ids.clear()
        prefs?.edit()?.remove("ids")?.apply()
    }

    private fun track(id: String) {
        if (ids.contains(id)) return
        ids.add(0, id); while (ids.size > 40) ids.removeAt(ids.lastIndex)
        prefs?.edit()?.putString("ids", ids.joinToString(","))?.apply()
    }

    suspend fun challenge(friendUid: String, friendName: String, questions: List<DuelQ>): String? {
        val me = FirebaseNet.uid() ?: return null
        if (friendUid.isEmpty() || questions.isEmpty()) return null
        val id = System.currentTimeMillis().toString(36) + (100000..999999).random().toString(36)
        val myName = PlayerIdentity.profile?.name ?: "You"
        val obj = mapOf(
            "createdBy" to me, "createdAt" to System.currentTimeMillis(), "challenged" to friendUid,
            "questions" to questions.map { mapOf("p" to it.p, "o" to it.o, "c" to it.c, "e" to it.e) },
            "players" to mapOf(me to mapOf("name" to myName, "done" to false, "score" to 0)),
        )
        return runCatching {
            FirebaseNet.createDuel(id, obj)
            FirebaseNet.sendDuelInvite(friendUid, id, mapOf("from" to me, "fromName" to myName, "at" to System.currentTimeMillis()))
            track(id); id
        }.getOrNull()
    }

    suspend fun load(id: String): DataSnapshot? = runCatching { FirebaseNet.loadDuel(id).takeIf { it.exists() } }.getOrNull()

    fun questionsOf(snap: DataSnapshot): List<DuelQ> = snap.child("questions").children.map { q ->
        DuelQ(
            q.child("p").getValue(String::class.java) ?: "",
            q.child("o").children.mapNotNull { it.getValue(String::class.java) },
            (q.child("c").getValue(Long::class.java) ?: 0L).toInt(),
            q.child("e").getValue(String::class.java) ?: "",
        )
    }

    suspend fun submit(id: String, score: Int) {
        val me = FirebaseNet.uid() ?: return
        val myName = PlayerIdentity.profile?.name ?: "You"
        runCatching { FirebaseNet.submitDuelPlayer(id, me, mapOf("name" to myName, "done" to true, "score" to score)); track(id) }
    }

    suspend fun inbox(): List<DuelInvite> {
        val me = FirebaseNet.uid() ?: return emptyList()
        val snap = runCatching { FirebaseNet.loadDuelInbox(me) }.getOrNull() ?: return emptyList()
        return snap.children.mapNotNull { c ->
            val id = c.key ?: return@mapNotNull null
            DuelInvite(id, c.child("from").getValue(String::class.java) ?: "",
                c.child("fromName").getValue(String::class.java) ?: "A friend",
                c.child("at").getValue(Long::class.java) ?: 0L)
        }.sortedByDescending { it.at }
    }

    suspend fun accept(id: String) {
        track(id)
        val me = FirebaseNet.uid() ?: return
        runCatching { FirebaseNet.clearDuelInvite(me, id) }
    }

    suspend fun mine(): List<DuelStanding> {
        val me = FirebaseNet.uid() ?: return emptyList()
        val out = mutableListOf<DuelStanding>()
        for (id in ids.toList()) {
            val d = load(id) ?: continue
            val players = d.child("players")
            val mineP = players.child(me)
            val oppUid = players.children.mapNotNull { it.key }.firstOrNull { it != me }
                ?: d.child("challenged").getValue(String::class.java)
            val oppP = oppUid?.let { players.child(it) }
            out.add(
                DuelStanding(id,
                    oppP?.child("name")?.getValue(String::class.java) ?: "Opponent",
                    oppUid ?: "",
                    mineP.child("done").getValue(Boolean::class.java) ?: false,
                    (mineP.child("score").getValue(Long::class.java) ?: 0L).toInt(),
                    oppP?.child("done")?.getValue(Boolean::class.java) ?: false,
                    (oppP?.child("score")?.getValue(Long::class.java) ?: 0L).toInt()),
            )
        }
        return out
    }
}
