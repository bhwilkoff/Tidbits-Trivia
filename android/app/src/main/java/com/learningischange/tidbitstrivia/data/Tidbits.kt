package com.learningischange.tidbitstrivia.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// ---- Domain models (mirror of the Apple Core) ----

// Closest Call (M5): estimate a value on a [min,max] slider; proximity-scored.
data class ClosestSpec(
    val answer: Double, val min: Double, val max: Double,
    val step: Double, val tolerance: Double, val unit: String,
) {
    fun points(guess: Double): Int {
        val err = kotlin.math.abs(guess - answer)
        return if (err < tolerance) Math.round(50.0 * (1 - err / tolerance)).toInt() else 0
    }
    fun isClose(guess: Double) = kotlin.math.abs(guess - answer) <= tolerance / 2
    val formattedAnswer: String get() = fmt(answer)
    fun fmt(v: Double): String {
        val n = v.toLong()
        if (unit.isEmpty()) return n.toString()   // years: no thousands separator
        val s = if (kotlin.math.abs(v) >= 1000) "%,d".format(n) else n.toString()
        return "$s $unit"
    }
}

data class Question(
    val id: String,
    val prompt: String,
    val options: List<String>,
    val correctIndex: Int,
    val categoryId: String,
    val difficulty: Int,
    val explanation: String,
    val sourceTitle: String,
    val sourceUrl: String,
    val imageUrl: String? = null,   // Picture ID (Q7): Commons image to identify
    val closest: ClosestSpec? = null, // Closest Call (M5)
    val ordering: List<String>? = null, // Ordering (Q4): items in CORRECT order
    val matching: MatchSpec? = null,  // Matching (Q5): keys ↔ correct values
    val accepted: List<String>? = null, // Type-the-answer (Q6): accepted free-text
    val enumerate: EnumSpec? = null,  // Enumeration (Q8): name as many of a set as you can
    val roundIndex: Int? = null,      // Trivia Night: which round this belongs to (set at runtime)
) {
    val answerText: String get() = options.getOrNull(correctIndex)
        ?: closest?.formattedAnswer ?: ordering?.joinToString(" → ")
        ?: matching?.let { it.keys.zip(it.values).joinToString(" · ") { (k, v) -> "$k → $v" } } ?: ""
}

object TypeMatch {
    fun normalize(s: String): String {
        var t = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "").lowercase()
        t = t.replace(Regex("[^a-z0-9]+"), " ").trim()
        if (t.startsWith("the ")) t = t.substring(4)
        return t
    }
    fun matches(input: String, accepted: List<String>): Boolean {
        val n = normalize(input)
        return n.isNotEmpty() && accepted.any { normalize(it) == n }
    }
}

data class MatchSpec(val keys: List<String>, val values: List<String>)

// Enumeration (Q8): a set named against a 60s clock. Each group is one accepted
// answer ([canonical, alias, ...]); any alias counts but a group fills once.
data class EnumSpec(val groups: List<List<String>>) {
    val total: Int get() = groups.size
    val displayNames: List<String> get() = groups.map { it.firstOrNull() ?: "" }
}

data class Category(val id: String, val name: String, val icon: String, val colorIndex: Int, val blurb: String) {
    companion object {
        val all = listOf(
            Category("mixed", "Mixed Bag", "🔀", 0, "A little of everything."),
            Category("history", "History", "📜", 1, "People, places, and the past."),
            Category("science", "Science", "⚛️", 3, "How the universe works."),
            Category("geography", "Geography", "🌎", 4, "The whole wide world."),
            Category("arts", "Arts & Lit", "🎭", 5, "Books, art, and culture."),
            Category("screen", "Film & TV", "🎬", 0, "The big and small screen."),
            Category("music", "Music", "🎵", 2, "From Bach to beats."),
            Category("sports", "Sports", "🏆", 1, "Games and the greats."),
        )
        fun byId(id: String) = all.firstOrNull { it.id == id } ?: all[0]
    }
}

enum class Mode(val title: String, val blurb: String, val perQuestion: Int?, val globalClock: Int?, val count: Int) {
    CLASSIC("Classic", "Ten questions. Speed counts.", 20, null, 10),
    TIME_ATTACK("Time Attack", "How many in 60 seconds?", null, 60, 25),
    SURVIVAL("Survival", "One wrong answer ends it.", 15, null, 99),
    STAKE("Stake", "Bet your confidence. No risk.", 30, null, 8),
    SWEEP("Sweep", "Fill the set. Beat your best.", 12, null, 12),
    PICTURE_ID("Picture ID", "Name what you see.", 20, null, 10),
    THIS_OR_THAT("Which First?", "Which came first?", 12, null, 10),
    CLOSEST_CALL("Closest Call", "How close can you get?", 25, null, 8),
    ORDERING("In Order", "Arrange them in time.", 35, null, 6),
    MATCHING("Match Up", "Link each pair.", 40, null, 6),
    TYPE_ANSWER("Name It", "Type the answer.", 25, null, 8),
    ODD_ONE_OUT("Odd One Out", "Which doesn't belong?", 20, null, 8),
    LADDER("Ladder", "Climb from easy to hard.", 20, null, 10),
    ENUMERATE("Name as Many", "How many can you name?", 60, null, 3),
    BAR_TRIVIA("Trivia Night", "Host a night. Every kind of round.", 20, null, 20),
    DAILY("Daily Tidbit", "Everyone's puzzle. Keep your streak.", 30, null, 7),
}

// Trivia Night ("bar trivia") — a configurable night of themed rounds, each round
// drawing one question TYPE, so one night pulls from EVERY type. A client meta-mode
// over the shape-routing game loop (mirror of NightPlan.swift / store.js NIGHT).
object Night {
    val kinds = listOf("classic", "pictureId", "thisOrThat", "closestCall", "ordering", "matching", "typeAnswer", "oddOneOut", "enumerate")
    val roundTitle = mapOf(
        "classic" to "General Knowledge", "pictureId" to "Picture Round", "thisOrThat" to "Which Came First?",
        "closestCall" to "Closest Wins", "ordering" to "Put Them In Order", "matching" to "Match-Up",
        "typeAnswer" to "Name It", "oddOneOut" to "Odd One Out", "enumerate" to "Name As Many",
    )
    // Per-question clock by question SHAPE (a night mixes shapes in one run).
    fun shapeBudget(q: Question?): Double = when {
        q == null -> 25.0
        q.enumerate != null -> 60.0
        q.matching != null -> 40.0
        q.ordering != null -> 35.0
        q.closest != null -> 25.0
        q.accepted != null -> 25.0
        q.imageUrl != null -> 22.0
        else -> 20.0
    }
    data class Preset(val name: String, val blurb: String, val rounds: List<Pair<String, Int>>)
    val presets = listOf(
        Preset("Quick Night", "3 rounds · ~12 questions", listOf("classic" to 5, "pictureId" to 4, "closestCall" to 3)),
        Preset("Pub Night", "5 rounds · ~22 questions", listOf("classic" to 6, "pictureId" to 4, "thisOrThat" to 4, "closestCall" to 4, "oddOneOut" to 4)),
        Preset("The Works", "Every question type · ~28", listOf("classic" to 4, "pictureId" to 4, "thisOrThat" to 4, "closestCall" to 4, "ordering" to 4, "matching" to 4, "typeAnswer" to 4, "oddOneOut" to 4, "enumerate" to 2)),
    )
}

// Stake mode's fixed confidence-chip budget (sum of count == Mode.STAKE.count).
// Spending more on one question leaves fewer for the rest — that scarcity is what
// makes it calibration. Adds-only: a wrong answer earns 0 but the chip is spent.
data class StakeTier(val value: Int, val label: String, var remaining: Int)
val STAKE_BUDGET: List<StakeTier> get() = listOf(
    StakeTier(3, "Sure", 2), StakeTier(2, "Likely", 3), StakeTier(1, "Hunch", 3),
)

// ---- Deterministic RNG (mirror SeededRNG.swift / engine.js) ----

class SeededRng(seed: Long) {
    private var state = seed + -0x61c8864680b583ebL // 0x9E3779B97F4A7C15
    fun next(): Double {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L  // 0xBF58476D1CE4E5B9
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L   // 0x94D049BB133111EB
        z = z xor (z ushr 31)
        return ((z ushr 11).toDouble() / (1L shl 53).toDouble())
    }
}

fun stableSeed(s: String): Long {
    var h = -0x340d631b7bdddcdbL // 0xCBF29CE484222325 FNV offset
    for (b in s.toByteArray()) { h = (h xor b.toLong()) * 0x100000001B3L }
    return h
}

fun <T> List<T>.shuffledWith(rng: SeededRng): List<T> {
    val a = toMutableList()
    for (i in a.indices.reversed()) {
        if (i == 0) break
        val j = floor(rng.next() * (i + 1)).toInt()
        val t = a[i]; a[i] = a[j]; a[j] = t
    }
    return a
}

// ---- Scoring (mirror Scoring.swift) ----

object Scoring {
    const val base = 100; const val maxSpeedBonus = 100
    fun points(correct: Boolean, secondsTaken: Double, budget: Double, streak: Int): Int {
        if (!correct) return 0
        val speedFraction = max(0.0, min(1.0, 1 - secondsTaken / max(budget, 0.001)))
        val speed = (maxSpeedBonus * speedFraction).toInt()
        val mult = min(2.0, 1 + max(0, streak - 1) * 0.1)
        return ((base + speed) * mult).toInt()
    }
}

// ---- Corpus (bundled JSON asset, in-memory) ----

object Corpus {
    private var all: List<Question> = emptyList()
    private var byCat: Map<String, List<Question>> = emptyMap()
    var loaded = false; private set
    val count get() = all.size

    suspend fun load(context: Context) = withContext(Dispatchers.IO) {
        if (loaded) return@withContext
        val text = context.assets.open("corpus.json").bufferedReader().use { it.readText() }
        val arr = Json.parseToJsonElement(text).jsonObject["questions"]!!.jsonArray
        all = arr.map { el ->
            val a = el.jsonArray
            Question(
                id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                options = a[2].jsonArray.map { it.jsonPrimitive.content },
                correctIndex = a[3].jsonPrimitive.content.toInt(),
                categoryId = a[4].jsonPrimitive.content,
                difficulty = a[5].jsonPrimitive.content.toInt(),
                explanation = a[6].jsonPrimitive.content,
                sourceTitle = a[7].jsonPrimitive.content,
                sourceUrl = a[8].jsonPrimitive.content,
            )
        }
        byCat = all.groupBy { it.categoryId }
        loaded = true
    }

    fun pull(categoryId: String, seen: Set<String>, limit: Int): List<Question> {
        val src = if (categoryId == "mixed") all else (byCat[categoryId] ?: emptyList())
        return src.filter { it.id !in seen }.shuffled().take(limit)
    }

    fun byId(id: String): Question? = all.firstOrNull { it.id == id }

    /** Create feature: real, already-vetted corpus questions matching the topic's
     *  words (prompt + Wikipedia source title). Grounded generation's retrieval
     *  baseline — no live API, no hallucination (docs/CREATE-QUESTION-GEN-PLAYBOOK.md). */
    fun search(topic: String, limit: Int): List<Question> {
        val tokens = topic.lowercase().split(Regex("[^a-z0-9]+")).filter { it.length >= 3 }
        if (tokens.isEmpty()) return emptyList()
        return all.mapNotNull { q ->
            // Drop questions whose ANSWER is/contains the topic — the player typed it,
            // so that's a giveaway ("Chicago" → answer "Chicago"). Keep ones ABOUT it.
            val answer = q.answerText.lowercase()
            if (tokens.any { answer.contains(it) }) return@mapNotNull null
            val title = q.sourceTitle.lowercase(); val prompt = q.prompt.lowercase()
            val score = tokens.sumOf { (if (title.contains(it)) 2 else 0) + (if (prompt.contains(it)) 1 else 0) }
            if (score > 0) q to score else null
        }.sortedByDescending { it.second }.take(maxOf(limit * 3, 24)).map { it.first }.shuffled().take(limit)
    }

    fun daily(dayKey: String, count: Int): List<Question> =
        all.shuffledWith(SeededRng(stableSeed(dayKey))).take(count)
}

// ---- Enrichment-built mode sources (E1): a bundled JSON question set, same row
// shape as corpus.json; Picture ID also carries a 10th element (image URL). ----

class JsonQuestionSet(private val asset: String) {
    private var all: List<Question> = emptyList()
    private var byCat: Map<String, List<Question>> = emptyMap()
    var loaded = false; private set

    suspend fun load(context: Context) = withContext(Dispatchers.IO) {
        if (loaded) return@withContext
        runCatching {
            val text = context.assets.open(asset).bufferedReader().use { it.readText() }
            val arr = Json.parseToJsonElement(text).jsonObject["questions"]!!.jsonArray
            all = arr.map { el ->
                val a = el.jsonArray
                if (a[2] is JsonArray && a[2].jsonArray.isNotEmpty() && a[2].jsonArray[0] is JsonArray) {
                    // Enumeration (Q8): [id, prompt, groups([[String]]), cat, seconds, url]
                    Question(
                        id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                        options = emptyList(), correctIndex = 0,
                        categoryId = a[3].jsonPrimitive.content, difficulty = 3,
                        explanation = "", sourceTitle = "",
                        sourceUrl = if (a.size > 5) a[5].jsonPrimitive.content else "",
                        enumerate = EnumSpec(a[2].jsonArray.map { g -> g.jsonArray.map { it.jsonPrimitive.content } }),
                    )
                } else if (a[2] is JsonArray && a[3] is JsonArray) {
                    val arr3 = a[3].jsonArray
                    val keys = a[2].jsonArray.map { it.jsonPrimitive.content }
                    if (arr3.isNotEmpty() && arr3[0].jsonPrimitive.isString) {
                        // Matching (Q5): [id, prompt, keys, values(strings), cat, expl, "", ""]
                        Question(
                            id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                            options = keys, correctIndex = 0,
                            categoryId = a[4].jsonPrimitive.content, difficulty = 3,
                            explanation = a[5].jsonPrimitive.content, sourceTitle = "", sourceUrl = "",
                            matching = MatchSpec(keys, arr3.map { it.jsonPrimitive.content }),
                        )
                    } else {
                        // Ordering (Q4): [id, prompt, names(correct order), years(ints), cat, expl, title, url]
                        Question(
                            id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                            options = keys, correctIndex = 0,
                            categoryId = a[4].jsonPrimitive.content, difficulty = 3,
                            explanation = a[5].jsonPrimitive.content,
                            sourceTitle = a[6].jsonPrimitive.content, sourceUrl = a[7].jsonPrimitive.content,
                            ordering = keys,
                        )
                    }
                } else if (a[2] is JsonArray) {
                    // MCQ (corpus / picture / thisorthat)
                    Question(
                        id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                        options = a[2].jsonArray.map { it.jsonPrimitive.content },
                        correctIndex = a[3].jsonPrimitive.content.toInt(),
                        categoryId = a[4].jsonPrimitive.content,
                        difficulty = a[5].jsonPrimitive.content.toInt(),
                        explanation = a[6].jsonPrimitive.content,
                        sourceTitle = a[7].jsonPrimitive.content,
                        sourceUrl = a[8].jsonPrimitive.content,
                        imageUrl = if (a.size >= 10) a[9].jsonPrimitive.content else null,
                    )
                } else if (a[2].jsonPrimitive.isString && a[3] is JsonArray) {
                    // Type-the-answer (Q6): [id, prompt, answer, accepted(strings), cat, expl, title, url]
                    val answer = a[2].jsonPrimitive.content
                    Question(
                        id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                        options = listOf(answer), correctIndex = 0,
                        categoryId = a[4].jsonPrimitive.content, difficulty = 3,
                        explanation = a[5].jsonPrimitive.content,
                        sourceTitle = a[6].jsonPrimitive.content, sourceUrl = a[7].jsonPrimitive.content,
                        accepted = a[3].jsonArray.map { it.jsonPrimitive.content },
                    )
                } else {
                    // Numeric (Closest Call): [id,prompt,answer,min,max,step,tol,unit,cat,expl,title,url]
                    Question(
                        id = a[0].jsonPrimitive.content, prompt = a[1].jsonPrimitive.content,
                        options = emptyList(), correctIndex = 0,
                        categoryId = a[8].jsonPrimitive.content, difficulty = 3,
                        explanation = a[9].jsonPrimitive.content,
                        sourceTitle = a[10].jsonPrimitive.content,
                        sourceUrl = a[11].jsonPrimitive.content,
                        closest = ClosestSpec(
                            a[2].jsonPrimitive.double, a[3].jsonPrimitive.double, a[4].jsonPrimitive.double,
                            a[5].jsonPrimitive.double, a[6].jsonPrimitive.double, a[7].jsonPrimitive.content),
                    )
                }
            }
            byCat = all.groupBy { it.categoryId }
            loaded = true
        }
        Unit
    }

    fun pull(categoryId: String, seen: Set<String>, limit: Int): List<Question> {
        val src = if (categoryId == "mixed") all else (byCat[categoryId] ?: emptyList())
        return src.filter { it.id !in seen }.shuffled().take(limit)
    }
}

val Pictures = JsonQuestionSet("picture.json")
val ThisOrThat = JsonQuestionSet("thisorthat.json")
val ClosestCall = JsonQuestionSet("closest.json")
val OrderingSet = JsonQuestionSet("order.json")
val MatchingSet = JsonQuestionSet("match.json")
val TypeAnswerSet = JsonQuestionSet("typeanswer.json")
val OddOneOutSet = JsonQuestionSet("oddoneout.json")   // standard MCQ rows
val EnumerateSet = JsonQuestionSet("enumerate.json")   // Q8 list puzzles

// F3 derived-difficulty overlay (Wikipedia pageviews → 1..5 per subject).
object Difficulty {
    private var map: Map<String, Int> = emptyMap()
    var loaded = false; private set
    suspend fun load(context: Context) = withContext(Dispatchers.IO) {
        if (loaded) return@withContext
        runCatching {
            val text = context.assets.open("difficulty.json").bufferedReader().use { it.readText() }
            val obj = Json.parseToJsonElement(text).jsonObject["difficulty"]!!.jsonObject
            map = obj.mapValues { it.value.jsonPrimitive.int }
            loaded = true
        }
        Unit
    }
    fun get(title: String): Int = map[title.replace(" ", "_")] ?: 3
}

// Build a Trivia Night's mixed question list from a round plan — one round draws
// one question TYPE, so a night pulls from every type (Decision 033). Shared by the
// solo night (GameState) and the networked host (LiveNight); each question is tagged
// with its roundIndex for the round banners. The host ships the IDS of this list;
// each joiner resolves them locally, then re-tags roundIndex from the same plan.
suspend fun buildNightQuestions(rounds: List<Pair<String, Int>>, categoryId: String, seen: Set<String>): List<Question> {
    val all = mutableListOf<Question>()
    val picked = mutableSetOf<String>()
    rounds.forEachIndexed { ri, (kind, count) ->
        val excl = seen + picked
        for (q in sourceNightType(kind, categoryId, count, excl)) { all.add(q.copy(roundIndex = ri)); picked.add(q.id) }
    }
    return all
}

private suspend fun sourceNightType(kind: String, categoryId: String, count: Int, seen: Set<String>): List<Question> = when (kind) {
    "pictureId" -> Pictures.pull(categoryId, seen, count)
    "thisOrThat" -> ThisOrThat.pull(categoryId, seen, count)
    "closestCall" -> ClosestCall.pull(categoryId, seen, count)
    "ordering" -> OrderingSet.pull(categoryId, seen, count)
    "matching" -> MatchingSet.pull(categoryId, seen, count)
    "typeAnswer" -> TypeAnswerSet.pull(categoryId, seen, count)
    "oddOneOut" -> OddOneOutSet.pull("mixed", seen, count)
    "enumerate" -> EnumerateSet.pull("mixed", emptySet(), count)
    else -> {
        var pulled = Corpus.pull(categoryId, seen, count)
        if (pulled.size < count) {
            val topic = if (categoryId == "mixed") "popular" else Category.byId(categoryId).name
            pulled = pulled + Wikipedia.generate(topic, categoryId, count - pulled.size)
        }
        pulled.take(count)
    }
}

/** Re-tag a resolved id-based night with roundIndex from the plan (by position). */
fun List<Question>.tagRounds(rounds: List<Pair<String, Int>>): List<Question> {
    val out = ArrayList<Question>(size)
    var i = 0
    rounds.forEachIndexed { ri, (_, count) ->
        repeat(count) { if (i < size) { out.add(this[i].copy(roundIndex = ri)); i++ } }
    }
    while (i < size) { out.add(this[i]); i++ }
    return out
}

fun dayKey(): String {
    val c = Calendar.getInstance()
    return "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
}

// ---- Wikipedia live generation (OkHttp; mirror WikipediaClient + TemplateEngine) ----

object Wikipedia {
    private val http = OkHttpClient()
    private const val ACTION = "https://en.wikipedia.org/w/api.php"
    private const val UA = "TidbitsTrivia/1.0 (learning trivia app; ben@learningischange.com)"

    private fun get(url: String): String? = try {
        http.newCall(Request.Builder().url(url).header("User-Agent", UA).build()).execute().use {
            if (it.isSuccessful) it.body?.string() else null
        }
    } catch (e: Exception) { null }

    data class Summary(val title: String, val description: String?, val extract: String?, val url: String?)

    private fun search(topic: String, limit: Int): List<String> {
        val url = "$ACTION?action=query&list=search&srsearch=${enc(topic)}&srlimit=$limit&srnamespace=0&format=json"
        val body = get(url) ?: return emptyList()
        val hits = JSONObject(body).optJSONObject("query")?.optJSONArray("search") ?: return emptyList()
        return (0 until hits.length()).map { hits.getJSONObject(it).getString("title") }
    }

    private fun summaries(titles: List<String>): List<Summary> {
        val out = mutableListOf<Summary>()
        titles.chunked(50).forEach { batch ->
            val url = "$ACTION?action=query&prop=extracts|description|info&exintro=1&explaintext=1&inprop=url&redirects=1&titles=${enc(batch.joinToString("|"))}&format=json"
            val body = get(url) ?: return@forEach
            val pages = JSONObject(body).optJSONObject("query")?.optJSONObject("pages") ?: return@forEach
            pages.keys().forEach { k ->
                val p = pages.getJSONObject(k)
                val title = p.optString("title", "")
                if (title.isNotEmpty()) out.add(Summary(title, p.optString("description").ifEmpty { null }, p.optString("extract").ifEmpty { null }, p.optString("fullurl").ifEmpty { null }))
            }
        }
        return out
    }

    suspend fun generate(topic: String, categoryId: String, count: Int): List<Question> = withContext(Dispatchers.IO) {
        val titles = search(topic, 35)
        if (titles.isEmpty()) return@withContext emptyList()
        TemplateEngine.make(summaries(titles), categoryId, count, stableSeed(topic))
    }

    private fun enc(s: String) = java.net.URLEncoder.encode(s, "UTF-8")
}

object TemplateEngine {
    private fun usable(s: Wikipedia.Summary): Boolean {
        val d = s.description; val e = s.extract
        if (d == null || d.length < 6 || d.length > 90) return false
        // Fame floor: a long intro is a strong, free notability proxy. Obscure
        // stubs ("X is an American actor.") are short — and unfun to be quizzed on.
        if (e == null || e.length < 600) return false
        val lt = s.title.lowercase()
        if (lt.startsWith("list of") || lt.contains("(disambiguation)")) return false
        if ((e).lowercase().contains("may refer to")) return false
        return true
    }
    private fun stripParens(t: String) = t.replace(Regex("\\s*\\([^)]*\\)"), "")
    private val ABBREV = "lit e.g i.e approx no vs etc st mt mr mrs ms dr fl ca jr sr col gen gov sen rep prof rev inc ltd co u.s u.k".split(" ").toSet()
    private fun firstSentence(t: String): String {
        // Paren/abbreviation-aware so 'lit.' / '(…; lit. …)' / middle initials
        // don't truncate the clue mid-phrase.
        val s = t.trim()
        var depth = 0; var i = 0
        while (i < s.length) {
            val ch = s[i]
            if (ch == '(' || ch == '[') depth++
            else if ((ch == ')' || ch == ']') && depth > 0) depth--
            else if (ch == '.' && depth == 0 && i + 1 < s.length && s[i + 1] == ' ') {
                var k = i + 1                       // skip a run of spaces ("Nigeria.  There")
                while (k < s.length && s[k] == ' ') k++
                val nxt2 = if (k < s.length) s[k] else ' '
                if (k >= s.length || nxt2.isUpperCase() || nxt2 in "“”\"'‘’") {
                    var j = i - 1
                    while (j >= 0 && (s[j].isLetterOrDigit() || s[j] == '.' || s[j] == '\'' || s[j] == '-')) j--
                    val tok = s.substring(j + 1, i)
                    val letters = tok.filter { it.isLetter() }
                    val hasDigit = tok.any { it.isDigit() }   // "1750s" is not an initial → split
                    val isAbbrev = letters.isNotEmpty() && !hasDigit && (letters.length <= 1 || tok.lowercase().trimEnd('.') in ABBREV)
                    if (!isAbbrev) return s.substring(0, i + 1)
                }
            }
            i++
        }
        return s
    }
    private fun cap(c: String) = if (c.isEmpty()) c else c[0].uppercase() + c.substring(1)
    private val FUNCTION_WORDS = "the of and a an in on at to for by with from as or de von van al".split(" ").toSet()
    private val COMMON_WORDS = ("empire battle war wars kingdom dynasty republic treaty river mountain mountains lake island islands city town county state states united nation national american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western great greater new saint university college school company group band series film movie novel book award club team teams league party system century world people region province district area force army navy air language family order house song album season game games sport sports festival prize federal royal international association federation union organization museum park station bridge building tower palace castle church cathedral temple championship cup first second").split(" ").toSet()

    private fun leaks(answer: String, prompt: String): Boolean {
        val p = prompt.lowercase()
        val toks = Regex("[A-Za-z]{4,}").findAll(answer.lowercase()).map { it.value }.toSet() - COMMON_WORDS
        return toks.any { p.contains(it) }
    }

    private fun redact(text: String, title: String): String {
        var out = text
        val bare = stripParens(title).trim()
        // 1. Whole-title phrase(s).
        for (n in setOf(title, bare)) if (n.isNotEmpty())
            out = out.replace(Regex(Regex.escape(n), RegexOption.IGNORE_CASE), "—————")
        // 2. Leading proper-noun run (≥2 words) — catches full-name variants.
        out = Regex("^(The |A |An )?((?:[A-Z][\\w’'.\\-]*)(?:[ \\-]+(?:of |the |and |de |von |van |al-)?[A-Z][\\w’'.\\-]*)+)")
            .replace(out) { m -> (m.groupValues[1]) + "—————" }
        // 3. Each CONTENT title word wherever it appears.
        for (w in bare.split(Regex("[^A-Za-z’'\\-]+"))) {
            if (w.length < 3 || w.lowercase() in FUNCTION_WORDS) continue
            out = out.replace(Regex("\\b" + Regex.escape(w) + "(?:’s|'s|s|es)?\\b", RegexOption.IGNORE_CASE), "—————")
        }
        // 4. Collapse adjacent blanks.
        out = Regex("—————(?:[\\s,’'.\\–\\-]+(?:of|the|and)?\\s*—————)+", RegexOption.IGNORE_CASE).replace(out, "—————")
        return out.replace(Regex("\\s{2,}"), " ").trim()
    }

    // Strip parenthetical clutter (foreign scripts, pronunciations, empty
    // parens, leading ALL-CAPS acronyms that leak the answer). Fixpoint loop.
    private val LANG = Regex("(romaniz|pronounc|IPA|listen|lit\\.|Russian|Greek|Latin|Arabic|Chinese|Japanese|Hebrew|Hindi|Persian|German|French|Spanish|Italian|Korean|Portuguese|Turkish|Polish|Dutch|Sanskrit)", RegexOption.IGNORE_CASE)
    private val PAREN = Regex("\\s*\\(([^()]*)\\)")
    private val BRACKET = Regex("\\s*\\[([^\\[\\]]*)\\]")
    private fun dropParen(inner: String): Boolean {
        val t = inner.trim()
        if (t.isEmpty()) return true
        if (t.any { it.code > 127 }) return true
        if (LANG.containsMatchIn(t)) return true
        val tok = (t.split(";")[0].trim().split(Regex("\\s+")).firstOrNull() ?: "").filter { it.isLetter() }
        if (tok.length in 2..6 && tok == tok.uppercase() && tok != tok.lowercase()) return true
        return false
    }
    private fun cleanClue(text: String): String {
        var out = text; var prev = ""
        while (out != prev) {
            prev = out
            out = PAREN.replace(out) { m -> if (dropParen(m.groupValues[1])) "" else m.value }
            out = BRACKET.replace(out) { m -> if (dropParen(m.groupValues[1])) "" else m.value }
        }
        return out.replace(Regex("\\s{2,}"), " ").replace(" ,", ",").replace(" .", ".").trim()
    }

    // "Describe & identify" — leads with the distinguishing facts, asks a natural
    // who/what. The old robotic framings + the "what kind of thing is X?"
    // categorize shape are gone (no human asks those).
    private val STEMS = mapOf(
        "describe_person" to listOf("This %s — who is this?", "Name this %s.", "Who is the %s?", "Which %s?"),
        "describe_thing" to listOf("Name this %s.", "Which %s?", "Name the %s."),
        "cloze" to listOf("Fill in the blank: “%s”", "Complete it: “%s”", "Which name completes this? “%s”"),
    )
    private val SHAPE_ROTATION = listOf("describe", "cloze", "describe", "describe", "cloze")

    fun make(pool: List<Wikipedia.Summary>, categoryId: String, count: Int, seed: Long): List<Question> {
        val usableList = pool.filter { usable(it) }
        if (usableList.size < 4) return emptyList()
        val rng = SeededRng(seed)
        val subjects = usableList.shuffledWith(rng)
        val out = mutableListOf<Question>()
        var gi = 0
        val n = SHAPE_ROTATION.size
        for (s in subjects) {
            if (out.size >= count) break
            val person = isPerson(s)
            for (off in 0 until n) {
                val shape = SHAPE_ROTATION[(gi + off) % n]
                val bank = if (shape == "describe") (if (person) STEMS["describe_person"]!! else STEMS["describe_thing"]!!) else STEMS[shape]!!
                val stem = bank[(gi / n) % bank.size]
                val built = buildShape(shape, s, usableList, stem, rng)
                if (built != null) {
                    // Never ship a question whose answer leaks into the prompt.
                    if (leaks(built.third, built.first)) continue
                    if (built.first.length > 320 || built.first.any { val n = it.code
                            (n in 0x0370..0x06FF) || (n in 0x3040..0x9FFF) || (n in 0xAC00..0xD7AF) || (n in 0x2200..0x22FF) || (n in 0x27E8..0x27EF) }) continue
                    val options = built.second.shuffledWith(rng)
                    out.add(Question(
                        id = "live:$shape:${s.title}".replace(" ", "_"), prompt = built.first, options = options,
                        correctIndex = options.indexOf(built.third), categoryId = categoryId, difficulty = 3,
                        explanation = cleanClue(firstSentence(s.extract ?: s.description ?: "")), sourceTitle = s.title, sourceUrl = s.url ?: "",
                    ))
                    break
                }
            }
            gi++
        }
        return out
    }

    // Siblings ranked by description word-overlap; lengthMatch (when set)
    // prefers similar-length values to kill the "longest = answer" tell.
    // Type-matched distractors (mirror of generate_corpus.py): same TYPE as the
    // answer only; [] (→ drop) when fewer than 3 same-type siblings.
    private val TYPE_LEADING = "american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western central ancient modern medieval former national international royal imperial classical contemporary professional famous notable major minor large small great greater lesser old new young senior junior fictional mythological historical traditional popular official public private federal scottish irish welsh dutch swedish norwegian danish polish turkish greek roman egyptian persian arab arabic jewish canadian australian mexican brazilian argentine chilean austrian swiss belgian portuguese finnish hungarian czech romanian indonesian filipino vietnamese thai largest smallest oldest".split(" ").toSet()
    private val TYPE_STOP = "in of from for by on at near during between that which who known with to and or located based set".split(" ").toSet()
    private val TYPE_FOLD = mapOf("singer" to "musician", "songwriter" to "musician", "singer-songwriter" to "musician", "rapper" to "musician", "guitarist" to "musician", "pianist" to "musician", "drummer" to "musician", "bassist" to "musician", "vocalist" to "musician", "band" to "musician", "duo" to "musician", "composer" to "musician", "actress" to "actor", "filmmaker" to "director", "novelist" to "writer", "author" to "writer", "poet" to "writer", "playwright" to "writer", "screenwriter" to "writer", "essayist" to "writer", "journalist" to "writer", "physicist" to "scientist", "chemist" to "scientist", "biologist" to "scientist", "mathematician" to "scientist", "astronomer" to "scientist", "geologist" to "scientist", "economist" to "scientist", "psychologist" to "scientist", "inventor" to "scientist", "footballer" to "athlete", "player" to "athlete", "cyclist" to "athlete", "swimmer" to "athlete", "boxer" to "athlete", "wrestler" to "athlete", "sprinter" to "athlete", "runner" to "athlete", "golfer" to "athlete", "village" to "settlement", "town" to "settlement", "city" to "settlement", "municipality" to "settlement", "commune" to "settlement", "capital" to "settlement", "mountain" to "peak", "volcano" to "peak")

    private fun typeKey(s: Wikipedia.Summary): String? {
        var d = (s.description ?: "").replace(Regex("\\([^)]*\\)"), "").substringBefore(",").trim().trimEnd('.').lowercase()
        val toks = mutableListOf<String>()
        for (w in d.split(Regex("[^a-z\\-]+")).filter { it.isNotEmpty() }) {
            if (w in TYPE_STOP) break
            toks.add(w)
        }
        while (toks.isNotEmpty() && toks.first() in TYPE_LEADING) toks.removeAt(0)
        val last = toks.lastOrNull() ?: return null
        return TYPE_FOLD[last] ?: last
    }

    private fun typedDistractors(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, rng: SeededRng, value: (Wikipedia.Summary) -> String?, exclude: String, lengthMatch: Int?): List<String> {
        val kt = typeKey(s) ?: return emptyList()
        val seen = mutableSetOf<String>()
        val cands = pool.mapNotNull { c ->
            if (c.title == s.title || typeKey(c) != kt) return@mapNotNull null
            val v = value(c)?.trim() ?: return@mapNotNull null
            if (v.isEmpty() || v.equals(exclude, true) || !seen.add(v.lowercase())) return@mapNotNull null
            val lenPen = if (lengthMatch != null) -kotlin.math.abs(v.length - lengthMatch) else 0
            Pair(v, lenPen)
        }.sortedByDescending { it.second }
        if (cands.size < 3) return emptyList()
        return cands.take(9).map { it.first }.shuffledWith(rng).take(3)
    }
    private fun titleDistractors(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, rng: SeededRng) =
        typedDistractors(s, pool, rng, { stripParens(it.title) }, stripParens(s.title), null)
    private fun descDistractors(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, rng: SeededRng) =
        typedDistractors(s, pool, rng, { it.description }, s.description ?: "", (s.description ?: "").length)

    // --- Describe-shape helpers (mirror of generate_corpus.py) ---
    private val MONTHS = "january february march april may june july august september october november december".split(" ").toSet()
    private val TYPE_NOUNS = "actor actress singer musician composer songwriter rapper band writer author poet novelist playwright journalist artist painter sculptor director filmmaker producer scientist physicist chemist biologist mathematician astronomer economist politician philosopher activist explorer inventor architect dancer comedian footballer player athlete cyclist swimmer boxer golfer film movie television series show novel book album song single painting sculpture poem play opera symphony team club city town country river mountain lake dynasty empire".split(" ").toSet()
    private val NATIONALITIES = "polish french american british english german italian russian japanese chinese spanish dutch canadian australian indian brazilian mexican swedish norwegian danish finnish greek roman egyptian persian turkish irish scottish welsh austrian swiss belgian portuguese hungarian czech romanian korean vietnamese thai argentine chilean colombian peruvian israeli iranian iraqi syrian lebanese moroccan nigerian kenyan ethiopian ukrainian serbian croatian bulgarian icelandic".split(" ").toSet()
    private val CLUE_GENERIC = COMMON_WORDS + TYPE_LEADING + TYPE_NOUNS + NATIONALITIES +
        "this the a an was is were are best known famous noted also who which that based located near former".split(" ").toSet()
    private val LEAD = Regex("^\\s*((?:[A-Z][\\w’'.\\-]*)(?:[ \\-]+(?:of|the|and|de|von|van|al|da|di)?\\s*[A-Z][\\w’'.\\-]*)*)\\s*(?:\\([^)]*\\))?\\s+(?:was|is|were|are)\\s+(?:a|an|the)\\s+(.+)$")
    private val PROPER = Regex("\\b[A-Z][A-Za-z’'\\-]{2,}\\b")
    private val YEAR_RE = Regex("\\b(?:1\\d{3}|20\\d{2})\\b")
    // Decided by the type HEAD-NOUN (typeKey), not a loose word match — a novel
    // "by American author X" must NOT read as a person.
    private val PERSON_TYPEKEYS = "actor actress musician writer scientist athlete director painter singer composer poet novelist author journalist sculptor architect engineer politician philosopher economist historian activist explorer inventor dancer comedian model conductor pianist guitarist rapper businessman entrepreneur king queen emperor empress monarch president general admiral saint pope sultan tsar duke earl baron knight prince princess priest bishop rabbi imam nun monk lawyer diplomat soldier aristocrat theologian".split(" ").toSet()
    private val LIFE_OR_BORN = Regex("\\(\\s*\\d{3,4}\\s*[–-]|\\bborn\\b")

    private fun informativeTokens(clue: String): Int {
        // Strip parentheticals — a "(born 1963)" date is birthday-guessing, not a
        // quizzable clue; pronunciations/IPA are noise.
        val c = clue.replace(Regex("\\([^)]*\\)"), "")
        val proper = PROPER.findAll(c).map { it.value.lowercase() }.filter { it !in CLUE_GENERIC && it !in MONTHS }.toSet()
        val years = YEAR_RE.findAll(c).map { it.value }.toSet()
        return proper.size + years.size
    }
    private fun isPerson(s: Wikipedia.Summary): Boolean {
        val k = typeKey(s)
        if (k in PERSON_TYPEKEYS) return true
        if (k != null) return false   // typed as a non-person thing
        return LIFE_OR_BORN.containsMatchIn(s.extract ?: "")
    }
    private fun firstN(text: String, n: Int): String {
        val parts = mutableListOf<String>(); var rest = text.trim()
        for (k in 0 until n) {
            if (rest.isEmpty()) break
            val sent = firstSentence(rest)
            parts.add(sent.trim()); rest = rest.substring(sent.length).trim()
        }
        return parts.joinToString(" ")
    }
    // Blank ONLY the subject's name (not the leading-run heuristic redact uses).
    private fun blankName(text: String, title: String): String {
        var out = text; val bare = stripParens(title).trim()
        for (nd in setOf(title, bare)) if (nd.isNotEmpty()) out = out.replace(Regex(Regex.escape(nd), RegexOption.IGNORE_CASE), "—————")
        for (w in bare.split(Regex("[^A-Za-z’'\\-]+"))) {
            if (w.length < 3 || w.lowercase() in FUNCTION_WORDS) continue
            out = out.replace(Regex("\\b" + Regex.escape(w) + "(?:’s|'s|s|es)?\\b", RegexOption.IGNORE_CASE), "—————")
        }
        out = Regex("—————(?:[\\s,’'.\\–\\-]+(?:of|the|and)?\\s*—————)+", RegexOption.IGNORE_CASE).replace(out, "—————")
        return out.replace(Regex("\\s{2,}"), " ").trim()
    }
    private fun reframe(sentence: String, title: String): String? {
        // Bare descriptive phrase; the stem supplies the framing.
        val m = LEAD.find(sentence) ?: return null
        return blankName(m.groupValues[2].trim(), title)
    }

    // Returns (prompt, options, answer) or null if this subject can't fill the shape.
    private fun buildShape(shape: String, s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, stem: String, rng: SeededRng): Triple<String, List<String>, String>? {
        when (shape) {
            "describe" -> {
                // FIRST sentence only — a 2-sentence clue reads awkwardly under "Name this …?".
                val c = reframe(cleanClue(firstSentence(s.extract ?: "")), s.title)
                if (c == null || c.length < 30 || informativeTokens(c) < 2) return null
                val clue = c.replace(Regex("[.\\s]+$"), "").trim()
                val ds = titleDistractors(s, pool, rng); if (ds.size != 3) return null
                val ans = stripParens(s.title); return Triple(stem.format(clue), listOf(ans) + ds, ans)
            }
            "cloze" -> {
                val sent = cleanClue(firstSentence(s.extract ?: "")); val bare = stripParens(s.title); var clozed: String? = null
                for (needle in listOf(s.title, bare)) {
                    if (needle.isNotEmpty() && sent.contains(needle, ignoreCase = true)) {
                        clozed = sent.replaceFirst(Regex(Regex.escape(needle), RegexOption.IGNORE_CASE), "_____"); break
                    }
                }
                if (clozed == null) {   // full birth name differs from title → blank the leading name run
                    val m = LEAD.find(sent)
                    if (m != null) { val r = m.groups[1]!!.range; clozed = sent.substring(0, r.first) + "_____" + sent.substring(r.last + 1) }
                }
                if (clozed == null || clozed.length < 30 || informativeTokens(clozed) < 2) return null
                val ds = titleDistractors(s, pool, rng); if (ds.size != 3) return null
                return Triple(stem.format(clozed), listOf(bare) + ds, bare)
            }
        }
        return null
    }
}

// Knowledge-cartography — mirror of Core/Store/ProgressStats.swift.
data class DomainProgress(
    val id: String, val correct: Int, val total: Int,
    val level: Int, val levelProgress: Float, val hasWedge: Boolean,
)
object ProgressMath {
    val domains = listOf("history", "science", "geography", "arts", "screen", "music", "sports")
    const val WEDGE_CORRECT = 15
    const val WEDGE_ACCURACY = 0.60
    fun threshold(level: Int) = 5 * level * (level + 1) / 2
    fun level(correct: Int): Int { var l = 0; while (threshold(l + 1) <= correct) l++; return l }
}

// ---- Records / streak / seen / missed (SharedPreferences) ----

class Store(context: Context) {
    private val prefs = context.getSharedPreferences("tidbits", Context.MODE_PRIVATE)
    private val seen = (prefs.getStringSet("seen", emptySet()) ?: emptySet()).toMutableSet()

    fun seenHas(id: String) = id in seen
    fun markSeen(ids: List<String>) {
        seen.addAll(ids)
        if (seen.size > 9000) seen.clear()
        prefs.edit().putStringSet("seen", seen).apply()
    }
    val seenSet: Set<String> get() = seen

    data class Rec(val mode: String, val categoryId: String, val score: Int, val correct: Int, val total: Int, val maxStreak: Int, val day: String)

    fun addRecord(r: Rec, countsForStreak: Boolean = true) {
        val arr = org.json.JSONArray(prefs.getString("records", "[]"))
        val o = JSONObject().put("mode", r.mode).put("cat", r.categoryId).put("score", r.score)
            .put("correct", r.correct).put("total", r.total).put("streak", r.maxStreak).put("day", r.day)
        val list = (0 until arr.length()).map { arr.getJSONObject(it) }.toMutableList()
        list.add(0, o)
        val out = org.json.JSONArray(); list.take(500).forEach { out.put(it) }
        prefs.edit().putString("records", out.toString()).apply()
        if (r.mode == "DAILY" && countsForStreak) bumpStreak()
    }
    fun records(): List<Rec> {
        val arr = org.json.JSONArray(prefs.getString("records", "[]"))
        return (0 until arr.length()).map { arr.getJSONObject(it) }.map {
            Rec(it.getString("mode"), it.getString("cat"), it.getInt("score"), it.getInt("correct"), it.getInt("total"), it.getInt("streak"), it.getString("day"))
        }
    }
    fun bestScore(mode: String) = records().filter { it.mode == mode }.maxOfOrNull { it.score } ?: 0
    fun lifetime(): Triple<Int, Int, Int> {
        val r = records(); val c = r.sumOf { it.correct }; val t = r.sumOf { it.total }
        return Triple(r.size, c, if (t == 0) 0 else c * 100 / t)
    }
    // Topic Levels (depth) + The Pie (breadth) — SOLO-BACKLOG M3 + M4
    // (mirror of Core/Store/ProgressStats.swift).
    fun progress(): List<DomainProgress> = ProgressMath.domains.map { id ->
        val mine = records().filter { it.categoryId == id }
        val correct = mine.sumOf { it.correct }; val total = mine.sumOf { it.total }
        val acc = if (total == 0) 0.0 else correct.toDouble() / total
        val level = ProgressMath.level(correct)
        val lo = ProgressMath.threshold(level); val hi = ProgressMath.threshold(level + 1)
        DomainProgress(id, correct, total, level,
            if (hi == lo) 1f else ((correct - lo).toFloat() / (hi - lo)).coerceIn(0f, 1f),
            correct >= ProgressMath.WEDGE_CORRECT && acc >= ProgressMath.WEDGE_ACCURACY)
    }
    // F1 calibration: lifetime per-tier (hits,total) across Stake rounds.
    fun calibration(): Map<Int, Pair<Int, Int>> {
        val o = JSONObject(prefs.getString("calibration", "{}") ?: "{}")
        return o.keys().asSequence().associate { k ->
            val a = o.getJSONArray(k); k.toInt() to (a.getInt(0) to a.getInt(1))
        }
    }
    fun addCalibration(outcomes: Map<Int, Pair<Int, Int>>) {
        val cur = calibration().toMutableMap()
        outcomes.forEach { (tier, o) ->
            if (o.second == 0) return@forEach
            val ex = cur[tier] ?: (0 to 0)
            cur[tier] = (ex.first + o.first) to (ex.second + o.second)
        }
        val out = JSONObject()
        cur.forEach { (tier, o) -> out.put(tier.toString(), org.json.JSONArray().put(o.first).put(o.second)) }
        prefs.edit().putString("calibration", out.toString()).apply()
    }

    // F4 answer-distribution telemetry: local, privacy-respecting per-option
    // counts keyed by question id ({ qid: [perOptionCount] }). No PII, no
    // network — the invisible foundation a backend later aggregates into the
    // "X% picked this" / Predict-the-Crowd reveal. Modes whose chosen index is
    // synthetic (right/wrong, not a real option pick) are skipped.
    private val telemetrySkip = setOf(Mode.CLOSEST_CALL, Mode.ORDERING, Mode.MATCHING, Mode.TYPE_ANSWER, Mode.ENUMERATE)
    fun recordTelemetry(mode: Mode, answered: List<Pair<Question, Int?>>) {
        if (mode in telemetrySkip) return
        val map = JSONObject(prefs.getString("answerTelemetry", "{}") ?: "{}")
        for ((q, chosen) in answered) {
            val n = q.options.size
            val c = chosen ?: continue
            if (n < 2 || c < 0 || c >= n) continue
            val arr = map.optJSONArray(q.id) ?: org.json.JSONArray().also { for (i in 0 until n) it.put(0) }
            while (arr.length() < n) arr.put(0)
            arr.put(c, arr.getInt(c) + 1)
            map.put(q.id, arr)
        }
        if (map.length() > 5000) { prefs.edit().putString("answerTelemetry", "{}").apply(); return }
        prefs.edit().putString("answerTelemetry", map.toString()).apply()
    }
    fun answerDistribution(qid: String): List<Int>? {
        val arr = JSONObject(prefs.getString("answerTelemetry", "{}") ?: "{}").optJSONArray(qid) ?: return null
        return (0 until arr.length()).map { arr.getInt(it) }
    }

    // Spaced re-asking of missed questions (parity with iOS/web). Default ON;
    // toggle in Records → Settings. Stores missed corpus question ids -> miss
    // count; review re-asks them by id via Corpus.byId (so a question removed from
    // the corpus is simply never re-asked).
    fun reviewEnabled(): Boolean = prefs.getBoolean("reviewEnabled", true)
    fun setReviewEnabled(v: Boolean) = prefs.edit().putBoolean("reviewEnabled", v).apply()

    // Stable per-device id for Trivia Night rejoin-by-identity (Decision 033).
    fun deviceId(): String = prefs.getString("deviceId", null) ?: java.util.UUID.randomUUID().toString().also {
        prefs.edit().putString("deviceId", it).apply()
    }

    // Last room joined — pre-fills the Join screen so a quick rejoin is one tap.
    fun lastNightCode(): String = prefs.getString("lastNightCode", "") ?: ""
    fun lastNightName(): String = prefs.getString("lastNightName", "") ?: ""
    fun rememberNight(code: String, name: String) =
        prefs.edit().putString("lastNightCode", code.uppercase()).putString("lastNightName", name).apply()

    // Quick Play memory + presets (home redesign — R-HOME-1, mirrors iOS AppStore).
    fun lastPlayedModeName(): String? = prefs.getString("lastMode", null)
    fun lastPlayedCategoryId(): String = prefs.getString("lastCat", null) ?: "mixed"
    fun hasQuickPlayHistory(): Boolean = prefs.getString("lastMode", null) != null
    fun rememberSelection(modeName: String, catId: String) =
        prefs.edit().putString("lastMode", modeName).putString("lastCat", catId).apply()
    fun presetsJson(): String = prefs.getString("presets", "[]") ?: "[]"
    fun savePresetsJson(json: String) = prefs.edit().putString("presets", json).apply()

    // First-run onboarding + per-user prefs (parity with iOS @AppStorage).
    fun hasOnboarded(): Boolean = prefs.getBoolean("hasOnboarded", false)
    fun setOnboarded(v: Boolean) = prefs.edit().putBoolean("hasOnboarded", v).apply()
    fun hapticsEnabled(): Boolean = prefs.getBoolean("hapticsEnabled", true)
    fun setHapticsEnabled(v: Boolean) = prefs.edit().putBoolean("hapticsEnabled", v).apply()
    fun dynamicColorEnabled(): Boolean = prefs.getBoolean("dynamicColor", false)
    fun setDynamicColorEnabled(v: Boolean) = prefs.edit().putBoolean("dynamicColor", v).apply()

    // Settings → Data. Reset Seen re-opens the whole corpus; Reset All Records
    // wipes scores/streak/calibration/telemetry/misses but keeps onboarding +
    // preference flags (mirror iOS SettingsView "Reset All Records").
    fun resetSeen() { seen.clear(); prefs.edit().remove("seen").apply() }
    fun resetAllRecords() {
        prefs.edit()
            .remove("records").remove("calibration").remove("answerTelemetry")
            .remove("missed").remove("streak_cur").remove("streak_best").remove("streak_day")
            .apply()
    }

    fun recordMisses(results: List<Pair<String, Boolean>>) {
        val o = JSONObject(prefs.getString("missed", "{}") ?: "{}")
        for ((id, correct) in results) {
            if (correct) o.remove(id)               // re-asked-and-correct resolves it
            else o.put(id, o.optInt(id, 0) + 1)
        }
        if (o.length() > 800) { prefs.edit().putString("missed", "{}").apply(); return }
        prefs.edit().putString("missed", o.toString()).apply()
    }
    /** Missed question ids, most-missed first — mapped to Questions via Corpus.byId. */
    fun dueReview(limit: Int): List<String> {
        val o = JSONObject(prefs.getString("missed", "{}") ?: "{}")
        return o.keys().asSequence().map { it to o.getInt(it) }
            .sortedByDescending { it.second }.take(limit).map { it.first }.toList()
    }

    // R-DAILY-1: per-day Daily results — first completion locks the day.
    fun dailyScore(day: String): Int? {
        val o = JSONObject(prefs.getString("daily_results", "{}") ?: "{}")
        return if (o.has(day)) o.getInt(day) else null
    }
    fun recordDaily(day: String, score: Int) {
        val o = JSONObject(prefs.getString("daily_results", "{}") ?: "{}")
        if (o.has(day)) return
        o.put(day, score)
        prefs.edit().putString("daily_results", o.toString()).apply()
    }

    fun streak(): Pair<Int, Int> = (prefs.getInt("streak_cur", 0)) to (prefs.getInt("streak_best", 0))
    private fun bumpStreak() {
        val today = dayKey(); if (prefs.getString("streak_day", "") == today) return
        val c = Calendar.getInstance(); c.add(Calendar.DAY_OF_MONTH, -1)
        val yest = "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
        val cur = if (prefs.getString("streak_day", "") == yest) prefs.getInt("streak_cur", 0) + 1 else 1
        prefs.edit().putInt("streak_cur", cur).putInt("streak_best", max(cur, prefs.getInt("streak_best", 0)))
            .putString("streak_day", today).apply()
    }
}
