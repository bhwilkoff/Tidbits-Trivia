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
    private fun firstSentence(t: String): String {
        val s = t.trim(); val m = Regex("\\.\\s").find(s)
        return if (m != null) s.substring(0, m.range.first) + "." else s
    }
    private fun cap(c: String) = if (c.isEmpty()) c else c[0].uppercase() + c.substring(1)
    private fun redact(text: String, title: String): String {
        var out = text
        for (n in setOf(title, stripParens(title))) if (n.isNotEmpty())
            out = out.replace(Regex(Regex.escape(n), RegexOption.IGNORE_CASE), "—————")
        return out
    }

    fun make(pool: List<Wikipedia.Summary>, categoryId: String, count: Int, seed: Long): List<Question> {
        val usableList = pool.filter { usable(it) }
        if (usableList.size < 4) return emptyList()
        val rng = SeededRng(seed)
        val subjects = usableList.shuffledWith(rng)
        val out = mutableListOf<Question>()
        for (s in subjects) {
            if (out.size >= count) break
            val useDesc = out.size % 2 == 0
            val q = if (useDesc) descOf(s, usableList, categoryId, rng) else subjectFrom(s, usableList, categoryId, rng)
            if (q != null) out.add(q)
        }
        return out
    }

    private fun pickDistractors(subject: Wikipedia.Summary, pool: List<Wikipedia.Summary>, value: (Wikipedia.Summary) -> String?, exclude: String, rng: SeededRng): List<String> {
        val subjWords = (subject.description ?: "").lowercase().split(" ").toSet()
        val seen = mutableSetOf<String>()
        val ranked = pool.filter { it.title != subject.title }.mapNotNull { c ->
            val v = value(c)?.trim() ?: return@mapNotNull null
            if (v.isEmpty() || v.equals(exclude, true)) return@mapNotNull null
            val words = (c.description ?: "").lowercase().split(" ").toSet()
            v to subjWords.intersect(words).size
        }.sortedByDescending { it.second }.mapNotNull { if (seen.add(it.first.lowercase())) it.first else null }
        return ranked.take(8).shuffledWith(rng).take(3)
    }

    private fun assemble(s: Wikipedia.Summary, categoryId: String, prompt: String, correct: String, distractors: List<String>, template: String, rng: SeededRng): Question {
        val options = (listOf(correct) + distractors).shuffledWith(rng)
        return Question(
            id = "live:$template:${s.title}".replace(" ", "_"), prompt = prompt, options = options,
            correctIndex = options.indexOf(correct), categoryId = categoryId, difficulty = 3,
            explanation = firstSentence(s.extract ?: s.description ?: ""), sourceTitle = s.title, sourceUrl = s.url ?: "",
        )
    }

    private fun descOf(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, cat: String, rng: SeededRng): Question? {
        val correct = s.description ?: return null
        val ds = pickDistractors(s, pool, { it.description }, correct, rng)
        if (ds.size != 3) return null
        return assemble(s, cat, "How is ${stripParens(s.title)} best described?", cap(correct), ds.map { cap(it) }, "descriptionOf", rng)
    }
    private fun subjectFrom(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, cat: String, rng: SeededRng): Question? {
        val clue = redact(firstSentence(s.extract ?: s.description ?: ""), s.title)
        if (clue.length < 25) return null
        val ds = pickDistractors(s, pool, { it.title }, s.title, rng)
        if (ds.size != 3) return null
        return assemble(s, cat, "Which subject is this? “$clue”", stripParens(s.title), ds.map { stripParens(it) }, "subjectFrom", rng)
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
