package com.learningischange.tidbitstrivia.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
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
)

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
    DAILY("Daily Tidbit", "Everyone's puzzle. Keep your streak.", 30, null, 7),
}

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

    fun daily(dayKey: String, count: Int): List<Question> =
        all.shuffledWith(SeededRng(stableSeed(dayKey))).take(count)
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
        if (e == null || e.length < 40) return false
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
                val nxt2 = if (i + 2 < s.length) s[i + 2] else ' '
                if (i + 2 >= s.length || nxt2.isUpperCase() || nxt2 in "“”\"'‘’") {
                    var j = i - 1
                    while (j >= 0 && (s[j].isLetterOrDigit() || s[j] == '.' || s[j] == '\'' || s[j] == '-')) j--
                    val tok = s.substring(j + 1, i)
                    val letters = tok.filter { it.isLetter() }
                    val isAbbrev = letters.isNotEmpty() && (letters.length <= 1 || tok.lowercase().trimEnd('.') in ABBREV)
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

    // Rotating stems ("%s" = clue/title); categorize kept a minority.
    private val STEMS = mapOf(
        "identify" to listOf("Which subject does this describe? “%s”", "Name it — “%s”", "What is being described here? “%s”", "Identify the subject: “%s”", "These clues point to one thing. What is it? “%s”", "Guess the article: “%s”"),
        "jeopardy" to listOf("%s — what is it?", "%s Name the subject.", "%s What are we describing?"),
        "cloze" to listOf("Fill in the blank: “%s”", "Complete the sentence: “%s”", "Which name completes this? “%s”"),
        "categorize" to listOf("What kind of thing is %s?", "What is %s best known as?", "In a few words, what is %s?", "Which description fits %s?"),
    )
    // 'oneliner' dropped — description-as-clue routinely leaked the answer's words.
    private val SHAPE_ROTATION = listOf("identify", "cloze", "jeopardy", "categorize", "identify", "cloze", "jeopardy", "identify", "categorize", "cloze")

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
            for (off in 0 until n) {
                val shape = SHAPE_ROTATION[(gi + off) % n]
                val bank = STEMS[shape]!!
                val stem = bank[(gi / n) % bank.size]
                val built = buildShape(shape, s, usableList, stem, rng)
                if (built != null) {
                    // Never ship a redacted question whose answer leaks into the prompt.
                    if (shape in setOf("identify", "jeopardy", "cloze") && leaks(built.third, built.first)) continue
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

    // Returns (prompt, options, answer) or null if this subject can't fill the shape.
    private fun buildShape(shape: String, s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, stem: String, rng: SeededRng): Triple<String, List<String>, String>? {
        when (shape) {
            "identify" -> {
                val clue = redact(cleanClue(firstSentence(s.extract ?: s.description ?: "")), s.title)
                if (clue.length < 25) return null
                val ds = titleDistractors(s, pool, rng); if (ds.size != 3) return null
                val ans = stripParens(s.title); return Triple(stem.format(clue), listOf(ans) + ds, ans)
            }
            "jeopardy" -> {
                val sent = cleanClue(firstSentence(s.extract ?: "")); if (sent.length < 25) return null
                val bare = stripParens(s.title)
                var clue = when {
                    sent.lowercase().startsWith(s.title.lowercase()) -> "This" + sent.substring(s.title.length)
                    sent.lowercase().startsWith(bare.lowercase()) -> "This" + sent.substring(bare.length)
                    else -> redact(sent, s.title)
                }
                clue = cap(clue.trim())
                val ds = titleDistractors(s, pool, rng); if (ds.size != 3) return null
                return Triple(stem.format(clue), listOf(bare) + ds, bare)
            }
            "cloze" -> {
                val sent = cleanClue(firstSentence(s.extract ?: "")); val bare = stripParens(s.title); var clozed: String? = null
                for (needle in listOf(s.title, bare)) {
                    if (needle.isNotEmpty() && sent.contains(needle, ignoreCase = true)) {
                        clozed = sent.replaceFirst(Regex(Regex.escape(needle), RegexOption.IGNORE_CASE), "_____"); break
                    }
                }
                if (clozed == null || clozed.length < 25) return null
                val ds = titleDistractors(s, pool, rng); if (ds.size != 3) return null
                return Triple(stem.format(clozed), listOf(bare) + ds, bare)
            }
            "categorize" -> {
                val correct = s.description ?: return null
                val ds = descDistractors(s, pool, rng); if (ds.size != 3) return null
                val ans = cap(correct); return Triple(stem.format(stripParens(s.title)), listOf(ans) + ds.map { cap(it) }, ans)
            }
        }
        return null
    }
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

    fun addRecord(r: Rec) {
        val arr = org.json.JSONArray(prefs.getString("records", "[]"))
        val o = JSONObject().put("mode", r.mode).put("cat", r.categoryId).put("score", r.score)
            .put("correct", r.correct).put("total", r.total).put("streak", r.maxStreak).put("day", r.day)
        val list = (0 until arr.length()).map { arr.getJSONObject(it) }.toMutableList()
        list.add(0, o)
        val out = org.json.JSONArray(); list.take(500).forEach { out.put(it) }
        prefs.edit().putString("records", out.toString()).apply()
        if (r.mode == "DAILY") bumpStreak()
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
