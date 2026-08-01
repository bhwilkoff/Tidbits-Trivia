package com.learningischange.tidbitstrivia.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Local persistence for saved quizzes (docs/QUIZ-CONTRACT.md §4).
 *
 * Local is the source of truth for a player's own quizzes: they must work offline and
 * before sign-in, so nothing here needs an account. What's stored is the CONTRACT
 * JSON, not an Android-specific shape — otherwise there'd be a fifth representation
 * to keep in step with the four stacks.
 *
 * SharedPreferences rather than Room: a quiz is a single opaque string keyed by id,
 * with no relational queries and no migration surface. Room would add a schema to
 * version for a Map<String, String>.
 */
object QuizStore {
    private const val PREFS = "tidbits.quizzes"
    private var prefs: SharedPreferences? = null

    /** Mirrors Duels.init(ctx) — called from Application.onCreate. Without it every
     *  read and write is a silent no-op and nothing a player makes survives. */
    fun init(ctx: Context) {
        if (prefs == null) prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    /** Newest first — a quiz you just made belongs at the top of your list. */
    fun all(): List<SavedQuiz> =
        prefs?.all.orEmpty().values
            .filterIsInstance<String>()
            .mapNotNull { SavedQuiz.fromJson(it) }
            .sortedByDescending { it.createdAtMs }

    fun get(id: String): SavedQuiz? = prefs?.getString(id, null)?.let { SavedQuiz.fromJson(it) }

    /** Idempotent: saving the same quiz twice updates it rather than duplicating. */
    fun save(quiz: SavedQuiz) {
        prefs?.edit()?.putString(quiz.id, quiz.toJson())?.apply()
    }

    fun delete(id: String) {
        prefs?.edit()?.remove(id)?.apply()
    }

    fun rename(id: String, title: String) {
        val q = get(id) ?: return
        save(q.copy(title = SavedQuiz.cleanTitle(title)))
    }

    /** Build and store in one step — every created quiz is kept automatically. */
    fun saveCreated(
        questions: List<Question>,
        topic: String,
        creatorId: String,
        creatorName: String,
        mode: String = "mix",
    ): SavedQuiz {
        val quiz = SavedQuiz.from(questions, topic = topic, creatorId = creatorId,
                                  creatorName = creatorName, mode = mode)
        save(quiz)
        return quiz
    }

    /**
     * Resolve a quiz's refs against everything this build actually ships. Ordering is
     * preserved and an unresolvable ref is COUNTED, not replaced — a shared quiz that
     * quietly swaps in a different question is worse than one that admits it's short.
     */
    fun resolveForPlay(quiz: SavedQuiz): QuizResolution {
        val sets = mapOf(
            "picture" to Pictures, "thisorthat" to ThisOrThat, "closest" to ClosestCall,
            "order" to OrderingSet, "match" to MatchingSet, "typeanswer" to TypeAnswerSet,
            "oddoneout" to OddOneOutSet, "enumerate" to EnumerateSet,
        )
        // One batched corpus fetch rather than a query per ref.
        val refIds = quiz.entries.filterIsInstance<QuizEntry.Ref>().map { it.id }
        val found = Corpus.questions(refIds)
        return quiz.resolve(
            // Deliberately no corpus fallback for a set ref: the corpus holds a
            // DIFFERENT question under a bundled set's ID (166 of 200 sampled Picture
            // ID rows collide), which is the whole reason set-refs carry their set.
            setLookup = { set, id -> sets[set]?.question(id) },
            lookup = { id -> found[id] },
        )
    }
}

// ---- Wire <-> Firebase map bridging ------------------------------------------------
//
// The RTDB SDK wants Maps/Lists, but the quiz format is frozen as JSON and mirrored on
// four stacks. Converting at the edge keeps ONE representation: nothing else in the app
// ever sees a quiz-shaped Kotlin object on the wire.

/** Contract JSON -> the Map/List tree the RTDB SDK writes. */
fun jsonToMap(json: String): Any? = unwrap(Json.parseToJsonElement(json))

private fun unwrap(e: JsonElement): Any? = when (e) {
    is JsonObject -> e.mapValues { unwrap(it.value) }
    is JsonArray -> e.map { unwrap(it) }
    is JsonPrimitive -> when {
        e.isString -> e.content
        e.content == "true" -> true
        e.content == "false" -> false
        e.content.toLongOrNull() != null -> e.content.toLong()
        else -> e.content.toDoubleOrNull() ?: e.content
    }
    else -> null
}

/** The Map/List tree RTDB returns -> contract JSON. */
fun mapToJson(value: Any?): String = wrap(value).toString()

private fun wrap(v: Any?): JsonElement = when (v) {
    null -> JsonNull
    is Map<*, *> -> JsonObject(v.entries.associate { it.key.toString() to wrap(it.value) })
    is List<*> -> JsonArray(v.map { wrap(it) })
    is Boolean -> JsonPrimitive(v)
    is Number -> JsonPrimitive(v)
    else -> JsonPrimitive(v.toString())
}

/** The canonical link target on every platform (QUIZ-CONTRACT §5). */
fun quizShareUrl(id: String): String = "https://tidbitstrivia.com/#/quiz/$id"
