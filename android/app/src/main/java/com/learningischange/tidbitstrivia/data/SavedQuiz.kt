package com.learningischange.tidbitstrivia.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.random.Random

/**
 * A quiz the player created and kept — the first user-authored object in Tidbits, so
 * it is a wire contract before it is a screen (docs/QUIZ-CONTRACT.md).
 *
 * A quiz stores question REFERENCES, not question text: every platform already ships
 * the corpus, so a 20-question quiz is under 1KB and costs nothing to sync, host, or
 * put in a URL. Only live-generated questions (always plain MCQ, because the corpus
 * was thin on that topic) travel inline, in the exact corpus.json row shape every
 * stack already decodes.
 *
 * Mirrors Swift SavedQuiz.swift, C# SavedQuiz.cs and JS quiz.js; pinned by
 * tools/quiz-wire/golden/quiz-v1.json.
 */
data class SavedQuiz(
    val id: String,
    val title: String,
    val topic: String,
    val creatorId: String,
    val creatorName: String,
    val createdAtMs: Long,
    val mode: String,
    val entries: List<QuizEntry>,
) {
    val questionCount: Int get() = entries.size

    /** Resolve refs in order, keeping inline questions verbatim. [lookup] returns null
     *  for an ID this build can't resolve. Never substitutes a different question — a
     *  shared quiz that quietly changes content is worse than an incomplete one. */
    /** `setLookup` comes FIRST so the trailing-lambda idiom (`quiz.resolve { ... }`)
     *  still binds to `lookup`, the one every caller needs. With the obvious ordering
     *  a trailing lambda silently became the SET lookup and every corpus ref resolved
     *  to nothing — a quiz that looked empty for no visible reason. */
    fun resolve(
        setLookup: (String, String) -> Question? = { _, _ -> null },
        lookup: (String) -> Question?,
    ): QuizResolution {
        val out = mutableListOf<Question>()
        var missing = 0
        for (e in entries) when (e) {
            is QuizEntry.Ref -> lookup(e.id)?.let { out.add(it) } ?: missing++
            // Deliberately does NOT fall back to the corpus: the corpus holds a
            // DIFFERENT question under this ID, and serving it would be the silent
            // substitution the contract forbids. Better to be one short.
            is QuizEntry.SetRef -> setLookup(e.set, e.id)?.let { out.add(it) } ?: missing++
            is QuizEntry.Inline -> out.add(e.question.toQuestion())
        }
        return QuizResolution(out, missing)
    }

    /** Keys are written in SORTED order because two devices writing the same quiz must
     *  produce byte-identical output — that is what makes the merge guard in
     *  QUIZ-CONTRACT section 4 ("created or deleted, never edited in place")
     *  checkable rather than aspirational. */
    fun toJson(): String = JSON.encodeToString(JsonElement.serializer(), toWire())

    fun toWire(): JsonObject = buildJsonObject {
        put("at", JsonPrimitive(createdAtMs))
        put("bn", JsonPrimitive(creatorName))
        put("by", JsonPrimitive(creatorId))
        put("id", JsonPrimitive(id))
        put("m", JsonPrimitive(mode))
        put("qs", buildJsonArray {
            for (e in entries) when (e) {
                is QuizEntry.Ref -> add(JsonPrimitive(e.id))
                is QuizEntry.SetRef -> add(buildJsonObject {   // keys sorted: i before s
                    put("i", JsonPrimitive(e.id))
                    put("s", JsonPrimitive(e.set))
                })
                is QuizEntry.Inline -> add(e.question.toRow())
            }
        })
        put("t", JsonPrimitive(title))
        put("tp", JsonPrimitive(topic))
        put("v", JsonPrimitive(1))
    }

    companion object {
        /** Crockford-style, with 0/o, 1/l/i and u removed so an ID read aloud in a pub
         *  or typed off a projector is unambiguous, and a random ID can't spell
         *  something unfortunate. 30 chars: 30^10 ~= 5.9e14. */
        const val ID_ALPHABET = "23456789abcdefghjkmnpqrstvwxyz"
        const val ID_LENGTH = 10

        /** The modes a created quiz can be played as. Deliberately a SUBSET: a saved
         *  quiz deals a FIXED set of questions, so any mode that draws its own
         *  (daily, marathon, weakSpot) would silently ignore the very questions the
         *  quiz exists to preserve. */
        val PLAYABLE_MODES = listOf("mix", "classic", "timeAttack", "survival", "stake")

        fun modeLabel(m: String): String = when (m) {
            "classic" -> "Classic"
            "timeAttack" -> "Time Attack"
            "survival" -> "Survival"
            "stake" -> "Stake"
            else -> "Mixed shapes"
        }

        /** An unknown mode from a newer build must still PLAY rather than refuse —
         *  these objects outlive the version that wrote them (QUIZ-CONTRACT §6). */
        fun playableMode(m: String): String = if (m in PLAYABLE_MODES) m else "mix"

        /** Below this a quiz isn't worth playing; above it we play and say so. */
        const val MINIMUM_PLAYABLE = 3

        private val JSON = Json { ignoreUnknownKeys = true }

        /** Random, never derived from content: two people who both make a "Jazz" quiz
         *  must get different IDs, and an ID must not leak what is inside it. */
        fun makeId(rng: Random = Random.Default): String =
            (1..ID_LENGTH).map { ID_ALPHABET[rng.nextInt(ID_ALPHABET.length)] }.joinToString("")

        /** Titles ride in share cards and list rows, so they are trimmed and capped
         *  rather than rejected — a long paste should still save. */
        fun cleanTitle(raw: String?): String {
            val t = (raw ?: "").trim()
            if (t.isEmpty()) return "Untitled quiz"
            return if (t.length <= 60) t else t.substring(0, 60)
        }

        /** Live Wikipedia generation is the only source that isn't addressable by ID
         *  from a bundled file, so it is the only thing a quiz has to carry inline. */
        fun isLiveGenerated(q: Question): Boolean = q.id.startsWith("live:")

        /** Which bundled set a question came from, or null for a plain corpus row.
         *  Derived from the question's SHAPE rather than threaded through from the
         *  call site, so it stays correct no matter which surface built the set. */
        fun bundledSetName(q: Question): String? = when {
            q.imageUrl != null -> "picture"
            q.closest != null -> "closest"
            q.ordering != null -> "order"
            q.matching != null -> "match"
            q.accepted != null -> "typeanswer"
            q.enumerate != null -> "enumerate"
            q.id.startsWith("tot:") -> "thisorthat"
            q.id.startsWith("odd:") -> "oddoneout"
            else -> null
        }

        fun from(
            questions: List<Question>,
            topic: String,
            creatorId: String,
            creatorName: String,
            title: String? = null,
            mode: String = "mix",
            id: String? = null,
            createdAtMs: Long = System.currentTimeMillis(),
        ) = SavedQuiz(
            id = id ?: makeId(),
            title = cleanTitle(title ?: topic),
            topic = topic,
            creatorId = creatorId,
            creatorName = creatorName,
            createdAtMs = createdAtMs,
            mode = mode,
            entries = questions.map {
                when {
                    isLiveGenerated(it) -> QuizEntry.Inline(InlineQuestion.of(it))
                    else -> bundledSetName(it)
                        ?.let { set -> QuizEntry.SetRef(set, it.id) } ?: QuizEntry.Ref(it.id)
                }
            },
        )

        /** Lenient by contract: unknown keys are ignored and a malformed entry is
         *  skipped rather than failing the whole quiz, because these objects outlive
         *  the app version that wrote them. */
        fun fromJson(text: String): SavedQuiz? = try {
            fromWire(JSON.parseToJsonElement(text).jsonObject)
        } catch (_: Exception) {
            null
        }

        fun fromWire(w: JsonObject): SavedQuiz? {
            val id = str(w, "id") ?: return null
            if (id.isEmpty()) return null
            val by = str(w, "by") ?: return null
            val qs = (w["qs"] as? JsonArray) ?: return null
            val entries = qs.mapNotNull { raw ->
                val prim = raw as? JsonPrimitive
                if (prim != null && prim.isString) {
                    prim.content.takeIf { it.isNotEmpty() }?.let { QuizEntry.Ref(it) }
                } else if (raw is JsonObject) {
                    val set = (raw["s"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                    val qid = (raw["i"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                    if (!set.isNullOrEmpty() && !qid.isNullOrEmpty()) QuizEntry.SetRef(set, qid) else null
                } else {
                    (raw as? JsonArray)?.let { InlineQuestion.fromRow(it) }?.let { QuizEntry.Inline(it) }
                }
            }
            return SavedQuiz(
                id = id,
                title = cleanTitle(str(w, "t")),
                topic = str(w, "tp") ?: "",
                creatorId = by,
                creatorName = str(w, "bn") ?: "",
                createdAtMs = (w["at"] as? JsonPrimitive)?.longOrNull ?: 0L,
                mode = str(w, "m") ?: "mix",
                entries = entries,
            )
        }

        private fun str(o: JsonObject, key: String): String? =
            (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}

/** One entry in a quiz's ordered question list: a REF (corpus/bundled-set question ID)
 *  or an INLINE question in corpus.json row shape. */
sealed interface QuizEntry {
    data class Ref(val id: String) : QuizEntry

    /** A BUNDLED-SET question, carrying which set it came from. Exists because a bare
     *  ID is genuinely ambiguous: the bundled sets share the corpus `src:` namespace,
     *  and 166 of 200 sampled Picture ID rows have an ID that ALSO exists in the corpus
     *  as a different question shape, so resolving corpus-first served a text question
     *  in place of a saved picture question. */
    data class SetRef(val set: String, val id: String) : QuizEntry

    data class Inline(val question: InlineQuestion) : QuizEntry
}

/** What a reader got back after resolving refs. Refs go missing legitimately (older
 *  build, retired row), so this reports the shortfall instead of hiding it. */
data class QuizResolution(val questions: List<Question>, val missing: Int) {
    val isPlayable: Boolean get() = questions.size >= SavedQuiz.MINIMUM_PLAYABLE
    val isComplete: Boolean get() = missing == 0
}

/** A live-generated MCQ carried inside a quiz, in the corpus.json row shape:
 *  [id, prompt, [o0,o1,o2,o3], correctIndex, category, difficulty, explanation,
 *  sourceTitle, sourceURL]. Reusing the corpus row is the whole point — every stack
 *  already decodes it, so the six implementations cannot drift. */
data class InlineQuestion(
    val id: String,
    val prompt: String,
    val options: List<String>,
    val correctIndex: Int,
    val categoryId: String,
    val difficulty: Int,
    val explanation: String,
    val sourceTitle: String,
    val sourceUrl: String,
) {
    fun toRow(): JsonArray = buildJsonArray {
        add(JsonPrimitive(id))
        add(JsonPrimitive(prompt))
        add(buildJsonArray { options.forEach { add(JsonPrimitive(it)) } })
        add(JsonPrimitive(correctIndex))
        add(JsonPrimitive(categoryId))
        add(JsonPrimitive(difficulty))
        add(JsonPrimitive(explanation))
        add(JsonPrimitive(sourceTitle))
        add(JsonPrimitive(sourceUrl))
    }

    fun toQuestion() = Question(
        id = id, prompt = prompt, options = options, correctIndex = correctIndex,
        categoryId = categoryId, difficulty = difficulty, explanation = explanation,
        sourceTitle = sourceTitle, sourceUrl = sourceUrl,
    )

    companion object {
        fun of(q: Question) = InlineQuestion(
            q.id, q.prompt, q.options, q.correctIndex, q.categoryId,
            q.difficulty, q.explanation, q.sourceTitle, q.sourceUrl,
        )

        fun fromRow(row: JsonArray): InlineQuestion? {
            if (row.size < 9) return null
            val id = strAt(row, 0) ?: return null
            val prompt = strAt(row, 1) ?: return null
            val opts = (row[2] as? JsonArray)?.takeIf { it.size == 4 }
                ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: return null
            if (opts.size != 4) return null
            val correct = (row[3] as? JsonPrimitive)?.intOrNull ?: return null
            val cat = strAt(row, 4) ?: return null
            val diff = (row[5] as? JsonPrimitive)?.intOrNull ?: return null
            val expl = strAt(row, 6) ?: return null
            val title = strAt(row, 7) ?: return null
            return InlineQuestion(id, prompt, opts, correct, cat, diff, expl, title,
                strAt(row, 8) ?: "")
        }

        private fun strAt(a: JsonArray, i: Int): String? =
            (a.getOrNull(i) as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}
