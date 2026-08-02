package com.learningischange.tidbitstrivia.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.decodeFromStream
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
    val tags: List<String> = emptyList(), // Wikipedia-category-derived topic keywords for Create search
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
            Category("business", "Business", "🏢", 3, "Companies and the brands behind them."),
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
    MIX("Custom Mix", "Your picked modes, shuffled together.", 20, null, 10),
    DAILY("Daily Tidbit", "Everyone's puzzle. Keep your streak.", 30, null, 7),
    // Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 1"). Never in
    // playableModes (the free Customize/Surprise-Me pool) — it has its own Home
    // entry point (WeakSpotArena) and is always launched with a pre-built custom set.
    WEAK_SPOT("Weak-Spot Arena", "Turn your misses into a round.", 20, null, 10),
    // Tidbits Club EXCLUSIVE (docs/CLUB-FEATURES-BUILD.md "Feature 3"). Never in
    // playableModes — its own Home entry point (Marathon), always launched with a
    // pre-resolved custom set (the run's remaining questions). `count` is a nominal
    // cap only — the real per-session length is whatever's left of the run; see
    // Marathon.runLength for the (debug-only) shortened test length. 45s/Q is
    // generous by design — endurance, not speed.
    MARATHON("Marathon", "200 questions. Play it across as many sittings as you like.", 45, null, 200),
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

/** Decision 037: rank = FNV-1a64(UTF-8 "daily:<day>:<categoryId>:<id>"), take the
 *  `count` SMALLEST (unsigned!), ascending. Order-independent — no RNG, no shuffle.
 *  Keep byte-identical with DailyPick.swift and engine.js pickDaily; the golden
 *  check is tools/daily-parity/run.sh. */
fun dailyRank(day: String, categoryId: String, id: String): ULong =
    stableSeed("daily:$day:$categoryId:$id").toULong()

fun pickDailyIds(ids: List<String>, day: String, categoryId: String, count: Int): List<String> =
    ids.sortedWith(compareBy({ dailyRank(day, categoryId, it) }, { it }))
        .take(count)

/** Decision 050 v2: spread the day's set across categories instead of drawing
 *  uniformly, so a corpus that is 29% Film & TV does not make 15% of Dailies
 *  four-of-seven one category. Same FNV ranking — which question a category
 *  contributes is unchanged — then the best unused id from each category in
 *  turn, with the category ORDER itself hashed from the day.
 *  Keep byte-identical with DailyPick.pickBalanced, engine.js
 *  pickDailyBalanced and aggregate_dailyboard.pick_daily_balanced. */
fun pickDailyBalancedIds(
    ids: List<String>, cats: List<String>, day: String, categoryId: String, count: Int
): List<String> {
    val ranked = ids.indices
        .sortedWith(compareBy({ dailyRank(day, categoryId, ids[it]) }, { ids[it] }))
    val byCat = LinkedHashMap<String, MutableList<String>>()
    for (i in ranked) byCat.getOrPut(cats[i]) { mutableListOf() }.add(ids[i])
    val order = byCat.keys.sortedWith(
        compareBy({ stableSeed("dailycat:$day:$it").toULong() }, { it }))

    val out = mutableListOf<String>()
    var round = 0
    while (out.size < count) {
        var progressed = false
        for (c in order) {
            val bucket = byCat[c] ?: continue
            if (round < bucket.size) {
                out.add(bucket[round]); progressed = true
                if (out.size == count) break
            }
        }
        if (!progressed) break            // fewer ids than `count`
        round++
    }
    return out
}

fun stableSeed(s: String): Long {
    var h = -0x340d631b7bdddcdbL // 0xCBF29CE484222325 FNV offset
    // Mask to an unsigned byte: Kotlin's Byte is SIGNED, so a bare toLong()
    // sign-extends every non-ASCII UTF-8 byte (e.g. the å in Skarsgård) and
    // silently diverges from the Swift/JS FNV-1a — the daily-parity golden
    // caught exactly this (Decision 037).
    for (b in s.toByteArray()) { h = (h xor (b.toLong() and 0xFF)) * 0x100000001B3L }
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

// ---- Corpus (bundled SQLite asset, queried not loaded) ----

/**
 * The 128,670-question corpus, backed by the SAME prebuilt `corpus.sqlite` the Apple apps ship
 * (byte-identical rows, same order), queried per request instead of held in RAM.
 *
 * Why: decoding corpus.json into 128,670 `Question` objects cost ~180MB of Java heap. The app
 * needed `android:largeHeap` just to open, sat at 230MB resident, and peaked at 299MB inside
 * [search] — so any device whose largeHeap cap is 256MB died mid-session. That is what Google
 * Play review hit on version code 75 ("the app opens, but it keeps crashing"), and it is the
 * same OOM class that once made every mode silently show "No questions yet".
 *
 * Only the `id`s stay resident (~13MB): both the Daily rank and Marathon need the whole id
 * space, and ranking streams nothing useful.
 */
object Corpus {
    private var db: android.database.sqlite.SQLiteDatabase? = null
    private var ids: List<String> = emptyList()
    var loaded = false; private set
    val count get() = ids.size

    private const val COLS = "id,prompt,option0,option1,option2,option3,correct_index," +
        "category_id,difficulty,explanation,source_title,source_url,tags"

    suspend fun load(context: Context) = withContext(Dispatchers.IO) {
        if (loaded) return@withContext
        val file = java.io.File(context.filesDir, "corpus.sqlite")
        // Re-install whenever the app version moves: a shipped corpus update would otherwise be
        // invisible forever, because the copy already on disk still exists.
        val stamp = java.io.File(context.filesDir, "corpus.stamp")
        val want = com.learningischange.tidbitstrivia.BuildConfig.VERSION_CODE.toString()
        if (!file.exists() || file.length() == 0L || runCatching { stamp.readText() }.getOrNull() != want) {
            install(context, file)
            runCatching { stamp.writeText(want) }
        }
        var opened = android.database.sqlite.SQLiteDatabase.openDatabase(
            file.path, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
        )
        // Self-heal a corpus whose SCHEMA is older than this build's queries.
        //
        // The version-code stamp only catches a corpus whose CONTENT changed on a
        // ship that remembered to bump. When `search_text` was added, an existing
        // install kept its old file and every Create query died with
        // "no such column: search_text" -- so Create returned nothing, for every
        // topic, for every upgrading user. Checking the columns we actually query
        // makes that unrecoverable-by-the-user state impossible regardless of
        // version bookkeeping.
        if (!hasExpectedSchema(opened)) {
            android.util.Log.w("Corpus", "bundled corpus schema is stale — reinstalling")
            opened.close()
            install(context, file)
            runCatching { stamp.writeText(want) }
            opened = android.database.sqlite.SQLiteDatabase.openDatabase(
                file.path, null, android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
            )
        }
        db = opened
        ids = opened.rawQuery("SELECT id FROM questions", null).use { c ->
            ArrayList<String>(c.count).apply { while (c.moveToNext()) add(c.getString(0)) }
        }
        loaded = true
        android.util.Log.d("Corpus", "opened ${ids.size} questions")
    }

    /** A blank `source_url` means "derive it from the title" — 80% of rows are
     *  exactly wiki/<source_title>, and storing that repeats 4.7 MB in every APK
     *  to say what the reader can rebuild. Without this the reveal loses its
     *  "Read on Wikipedia" link. */
    fun wikiUrl(stored: String?, title: String?): String {
        if (!stored.isNullOrEmpty()) return stored
        val t = title.orEmpty()
        if (t.isEmpty()) return ""
        return "https://en.wikipedia.org/wiki/" +
            java.net.URLEncoder.encode(t.replace(' ', '_'), "UTF-8").replace("+", "%20")
    }

    /** Every column the app's queries reference. A corpus missing any of them is
     *  older than this build and must be replaced, not queried. */
    private val REQUIRED_COLUMNS = setOf(
        "id", "prompt", "option0", "option1", "option2", "option3", "correct_index",
        "category_id", "difficulty", "explanation", "source_title", "source_url",
        "tags", "search_text",
    )

    private fun hasExpectedSchema(db: android.database.sqlite.SQLiteDatabase): Boolean =
        runCatching {
            db.rawQuery("PRAGMA table_info(questions)", null).use { c ->
                val have = HashSet<String>()
                val nameIdx = c.getColumnIndex("name")
                while (c.moveToNext()) have.add(c.getString(nameIdx))
                have.containsAll(REQUIRED_COLUMNS)
            }
        }.getOrDefault(false)

    /** SQLite needs a real file, so the asset is copied out of the APK once. The copy also gets
     *  the one index the shared database lacks — `category_id`, which every [pull] filters on. */
    private fun install(context: Context, target: java.io.File) {
        val tmp = java.io.File(target.parentFile, "corpus.sqlite.tmp")
        tmp.delete()
        context.assets.open("corpus.sqlite").use { input ->
            tmp.outputStream().use { out -> input.copyTo(out, 1 shl 16) }
        }
        android.database.sqlite.SQLiteDatabase.openDatabase(
            tmp.path, null, android.database.sqlite.SQLiteDatabase.OPEN_READWRITE,
        ).use { it.execSQL("CREATE INDEX IF NOT EXISTS idx_questions_category ON questions(category_id)") }
        check(tmp.renameTo(target)) { "could not install corpus.sqlite" }
    }

    private fun map(c: android.database.Cursor) = Question(
        id = c.getString(0), prompt = c.getString(1) ?: "",
        options = listOf(c.getString(2) ?: "", c.getString(3) ?: "", c.getString(4) ?: "", c.getString(5) ?: ""),
        correctIndex = c.getInt(6), categoryId = c.getString(7) ?: "", difficulty = c.getInt(8),
        explanation = c.getString(9) ?: "", sourceTitle = c.getString(10) ?: "",
        sourceUrl = wikiUrl(c.getString(11), c.getString(10)),
        tags = c.getString(12)?.takeIf { it.isNotEmpty() }?.split('|') ?: emptyList(),
    )

    private fun query(sql: String, args: Array<String>? = null): List<Question> {
        val d = db ?: return emptyList()
        return runCatching {
            d.rawQuery(sql, args).use { c ->
                ArrayList<Question>(c.count).apply { while (c.moveToNext()) add(map(c)) }
            }
        }.getOrDefault(emptyList())
    }

    fun pull(categoryId: String, seen: Set<String>, limit: Int): List<Question> {
        // Over-fetch by the seen count so they can be dropped without a second round trip;
        // SQL RANDOM() is what the old in-memory .shuffled() did.
        val want = (limit + seen.size).toString()
        val rows = if (categoryId == "mixed")
            query("SELECT $COLS FROM questions ORDER BY RANDOM() LIMIT ?", arrayOf(want))
        else
            query("SELECT $COLS FROM questions WHERE category_id=? ORDER BY RANDOM() LIMIT ?", arrayOf(categoryId, want))
        return rows.filter { it.id !in seen }.take(limit)
    }

    fun byId(id: String): Question? =
        query("SELECT $COLS FROM questions WHERE id=? LIMIT 1", arrayOf(id)).firstOrNull()

    /** Every question id — the Marathon seeded-pick pool (docs/CLUB-FEATURES-BUILD.md
     *  "Feature 3"); mirrors Apple's `CorpusDatabase.shared.orderedIDs(categoryID: "mixed")`. */
    fun allIds(): List<String> = ids

    /** Create feature: real, already-vetted corpus questions matching the topic's
     *  words (prompt + Wikipedia source title). Grounded generation's retrieval
     *  baseline — no live API, no hallucination (docs/CREATE-QUESTION-GEN-PLAYBOOK.md). */
    /** Words too common to narrow anything — they made the pre-filter match nearly
     *  the whole corpus, crowding out real hits before ranking. Mirrors Swift/JS/C#. */
    /** Lowercase + strip diacritics, so "beyonce" finds "Beyoncé". Mirrors the corpus
     *  build's `search_text` and the Swift/C#/JS `fold` — all must agree or a topic
     *  returns different questions per platform. */
    fun fold(s: String): String = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFKD)
        .replace(Regex("\\p{M}+"), "").lowercase()

    private val STOPWORDS = setOf("the", "and", "for", "with", "from", "that", "this", "his", "her", "its", "was", "were", "are", "who", "what", "which", "how", "why", "all", "any")

    private fun isWordChar(c: Char) = c.isLetterOrDigit()

    /** Word-bounded containment — the single most load-bearing rule in Create.
     *  Plain `contains` matched the typed word INSIDE longer words, so "Ansel Adams"
     *  returned Hansel and Gretel, "Harry Kane" returned Spokane, "India" returned
     *  Indianapolis. Mirrors Swift `CorpusDatabase.containsWord`. */
    fun containsWord(text: String, token: String): Boolean {
        if (token.isEmpty()) return false
        var from = 0
        while (true) {
            val i = text.indexOf(token, from)
            if (i < 0) return false
            val end = i + token.length
            val beforeOk = i == 0 || !isWordChar(text[i - 1])
            val afterOk = end == text.length || !isWordChar(text[end])
            if (beforeOk && afterOk) return true
            from = i + 1
        }
    }

    /** Does `token` occur in the prompt as ITSELF, rather than as part of someone
     *  else's name? Word-bounded matching is not enough inside prose: "Denver"
     *  matched "...and John Denver", "Michael Jackson" matched a Glenda Jackson
     *  biopic. The tell is the word before it — Capitalized and not itself part of
     *  the typed topic means a different proper name. That second half is what
     *  keeps "John Lennon and Paul McCartney" matching for "Paul McCartney".
     *  A possessive is still the name ("Jackson's"). Mirrors Swift promptHasWord. */
    fun promptHasWord(raw: String, token: String, topic: List<String>): Boolean {
        fun bareOf(w: String): String {
            var b = w.filter { it.isLetterOrDigit() || it == '\'' || it == '\u2019' }
            for (suffix in listOf("'s", "\u2019s")) if (b.endsWith(suffix)) b = b.dropLast(suffix.length)
            return fold(b.filter { it.isLetterOrDigit() })
        }
        val words = raw.split(' ', '\n', '\t').filter { it.isNotEmpty() }
        var previous: String? = null
        for (w in words) {
            if (bareOf(w) == token) {
                val p = previous
                if (p != null && p.firstOrNull()?.isUpperCase() == true &&
                    fold(p.filter { it.isLetterOrDigit() }) !in topic) {
                    previous = w
                    continue
                }
                return true
            }
            previous = w
        }
        // Hyphenated or punctuated forms ("Denver-based") the split cannot see.
        return containsWord(fold(raw), token) && words.none { bareOf(it) == token }
    }

    /** A Wikipedia disambiguator is not part of what the player means:
     *  "Backrooms (film)", "Masters of the Universe (2026 film)". */
    fun stripParens(s: String): String {
        val out = StringBuilder()
        var depth = 0
        for (c in s) {
            when {
                c == '(' || c == '[' -> depth++
                c == ')' || c == ']' -> depth = maxOf(0, depth - 1)
                depth == 0 -> out.append(c)
            }
        }
        return out.toString().trim()
    }

    /** Punctuation flattened to single spaces, nothing dropped — phrase matching
     *  needs the stopwords kept and in order ("masters of the universe"), and needs
     *  the parenthetical kept on ROW titles, where it carries the meaning. */
    fun flattened(s: String): String =
        fold(s).split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString(" ")

    fun topicPhrase(s: String): String = flattened(stripParens(s))

    /** Did the topic lose MEANINGFUL words to the >=3-character rule?
     *  "George VI" reduces to the single token `george`, so every George matched —
     *  measured, it returned George Martin, George Mallory, George Eliot and Paul
     *  George; "O. J. Simpson" reduced to `simpson` and returned Homer and Bart.
     *  A regnal numeral or an initial is short but not insignificant, and the tell
     *  is that the phrase still holds a non-stopword the token list threw away.
     *  Does NOT fire for "The Beatles", where the dropped word is a stopword. */
    fun phraseIsRequired(topic: String): Boolean {
        val significant = topicPhrase(topic).split(" ").filter { it.isNotEmpty() && it !in STOPWORDS }
        return significant.size > topicTokens(topic).size
    }

    fun topicTokens(s: String): List<String> {
        val raw = flattened(stripParens(s)).split(" ").filter { it.length >= 3 }
        val kept = raw.filter { it !in STOPWORDS }
        return kept.ifEmpty { raw }
    }

    /** Wikipedia categories mean "about" only in their agentive form. "Albums
     *  produced by Michael Jackson" makes a Thriller question an MJ question;
     *  "Actresses from Denver" does not make a Kristin Cavallari birth-year
     *  question a Denver question. Mirrors Swift `hasAgentiveTag`. */
    fun hasAgentiveTag(tags: List<String>, phrase: String): Boolean {
        for (t in tags) {
            for (prep in listOf("by ", "of ")) {
                var from = 0
                while (true) {
                    val i = t.indexOf(prep, from)
                    if (i < 0) break
                    var rest = t.substring(i + prep.length)
                    if (rest.startsWith("the ")) rest = rest.substring(4)
                    if (rest.startsWith(phrase)) {
                        val after = rest.substring(phrase.length)
                        if (after.isEmpty() || !isWordChar(after[0])) return true
                    }
                    from = i + prep.length
                }
            }
        }
        return false
    }

    /** Relevance TIER, or null to REJECT. A floor, not just a ranking: a topic the
     *  corpus knows nothing about must fall through to live generation rather than
     *  produce eight confident strangers. Mirrors Swift `CorpusDatabase.tier`.
     *
     *   3 the row's subject IS the topic
     *   2 the whole typed phrase appears, word-bounded, in the title
     *   1 every typed word appears, word-bounded, in the title
     *   0 every typed word appears in the prompt the player reads
     *  -1 an agentive tag only — a real connection the question never shows
     *
     *  The OPTIONS are deliberately not consulted: that made the topic match as a
     *  DISTRACTOR ("Zlatan Ibrahimović" returned a picture of Neymar) because the
     *  giveaway rule had already removed every row where it was the right answer. */
    fun tier(title: String, prompt: String, tags: List<String>,
             tokens: List<String>, phrase: String, guardNames: Boolean,
             requirePhrase: Boolean = false): Int? {
        val fTitle = fold(title)
        val subject = flattened(title)
        // Identity ignores the disambiguator — "Drake (musician)" IS Drake, and
        // the corpus has no row titled plainly "Drake", so without this the guard
        // never armed and typing "Drake" returned Nick Drake and Drake & Josh.
        if (subject == phrase || flattened(stripParens(title)) == phrase) return 3
        if (containsWord(subject, phrase)) {
            // When the typed word is itself a subject here, a bare two-word title
            // that merely contains it is a DIFFERENT named thing: "Bob Denver".
            if (guardNames && subject.split(" ").size == 2) return null
            return 2
        }
        // A numeral or an initial was dropped as "too short", so the surviving
        // tokens name the wrong thing — only the phrase above could be trusted.
        if (requirePhrase) return if (containsWord(fold(prompt), phrase)) 0 else null
        val need = if (tokens.size <= 2) tokens.size else tokens.size - 1
        if (tokens.count { containsWord(fTitle, it) } >= need) return 1
        if (tokens.count { containsWord(fTitle, it) || promptHasWord(prompt, it, tokens) } >= need) return 0
        // An agentive tag is a real connection but an INVISIBLE one: the question
        // never says so. It was the last measurable source of drift — "Rod Stewart"
        // produced Britt Ekland's height off a "Partners of Rod Stewart" tag. The
        // tag still contributes to SCORING above.
        return null
    }

    /** Does some row's SUBJECT reduce to exactly this topic? That single fact is
     *  what licenses the different-person guard: "Denver" is a place in this
     *  corpus, so "Bob Denver" is someone else; "Potter" is not, so "Harry Potter"
     *  is the best reading of it. */
    private fun isOwnSubject(phrase: String): Boolean {
        val head = phrase.split(" ").firstOrNull() ?: return false
        val d = db ?: return false
        d.rawQuery(
            "SELECT source_title FROM questions WHERE source_title LIKE ? GROUP BY source_title LIMIT 800",
            arrayOf("%$head%"),
        ).use { c ->
            while (c.moveToNext()) {
                val t = c.getString(0) ?: ""
                if (flattened(t) == phrase || flattened(stripParens(t)) == phrase) return true
            }
        }
        return false
    }

    fun search(topic: String, limit: Int): List<Question> {
        val tokens = topicTokens(topic)
        if (tokens.isEmpty()) return emptyList()
        // A topic made of nothing but stopwords cannot be searched for. "From (TV
        // series)" reduces to the word `from`, which matched every row containing
        // it — Notes from Underground, Spider-Man: Far From Home, From Dusk till
        // Dawn. The corpus says so and live generation takes the topic instead.
        if (tokens.none { it !in STOPWORDS }) return emptyList()
        val phrase = topicPhrase(topic)
        val guardNames = tokens.size == 1 && isOwnSubject(phrase)
        val requirePhrase = phraseIsRequired(topic)
        // Narrow to rows that mention a token at all before scoring in Kotlin. LIKE is
        // ASCII-case-insensitive in SQLite and the tokens are [a-z0-9] by construction, so this
        // matches what the old full scan found. The cap stops a common word ("history") from
        // materialising a big slice of the corpus — the caller only ever takes a handful, so a
        // deeper candidate pool would not change what ships.
        // search_text is the folded mirror of the four text columns, present only where
        // folding changes something. It is what makes "beyonce" find "Beyoncé":
        // SQL LIKE cannot strip diacritics, so without it every accented subject was
        // invisible to Create (measured: 0 results for Beyonce, Bjork, Dvorak).
        val clause = tokens.joinToString(" OR ") {
            "(prompt LIKE ? OR source_title LIKE ? OR explanation LIKE ? OR tags LIKE ? OR search_text LIKE ?)"
        }
        val args = tokens.flatMap { t -> List(5) { "%$t%" } }.toTypedArray()
        // The two owner rules (drop the repetitive "which continent" template and the
        // trivially-easy tier) push down into SQL; the answer-giveaway rule needs answerText.
        // 6,000 was not enough once relevance became strict: a common word like
        // "art" OR-matches ~19,500 rows and the genuine ones sit past the cap in
        // rowid order. The cap is now only a runaway guard.
        val candidates = query(
            "SELECT $COLS FROM questions WHERE difficulty > 1 " +
                "AND id NOT LIKE 'src:continent:%' AND ($clause) LIMIT 25000",
            args,
        )
        return rank(candidates, topic, limit, isOwnSubject(phrase))
    }

    /** The whole Create ranking POLICY, over an already-fetched candidate list.
     *
     *  Split out so it can be exercised on the JVM. `search` reaches straight into
     *  Android SQLite, which left Kotlin the one engine of the four that could not
     *  be held to `tools/create/golden/search.txt` — its pure helpers were tested,
     *  the query and assembly around them were not.
     *
     *  The two owner rules (drop the repetitive "which continent" template and the
     *  trivially-easy tier) are applied HERE as well as in the SQL. That is
     *  deliberate duplication: it makes SQL a pure optimisation, so feeding this
     *  function every row in the corpus produces exactly what feeding it the
     *  pre-filtered subset does — which is what makes the golden test meaningful. */
    fun rank(
        candidates: List<Question>,
        topic: String,
        limit: Int,
        ownSubject: Boolean,
    ): List<Question> {
        val tokens = topicTokens(topic)
        if (tokens.isEmpty()) return emptyList()
        if (tokens.none { it !in STOPWORDS }) return emptyList()
        val phrase = topicPhrase(topic)
        val guardNames = tokens.size == 1 && ownSubject
        val requirePhrase = phraseIsRequired(topic)
        val scoredAll = candidates.mapNotNull { q ->
            if (q.difficulty <= 1) return@mapNotNull null
            if (q.id.startsWith("src:continent:")) return@mapNotNull null
            // The relevance FLOOR, before any ranking.
            val t = tier(q.sourceTitle, q.prompt, q.tags, tokens, phrase, guardNames, requirePhrase)
                ?: return@mapNotNull null
            // Folded, not merely lowercased: the tokens are folded, so an accented row
            // would score 0 against them — the pre-filter would surface it and the
            // ranker would throw it straight away.
            val title = fold(q.sourceTitle); val prompt = fold(q.prompt); val explanation = fold(q.explanation)
            val tagsLower = q.tags.map { fold(it) }
            val score = tokens.sumOf {
                (if (tagsLower.any { tag -> containsWord(tag, it) }) 3 else 0) +
                (if (containsWord(title, it)) 2 else 0) +
                (if (containsWord(prompt, it)) 1 else 0) +
                (if (containsWord(explanation, it)) 1 else 0)
            }
            Triple(q, score, t)
        }
        // A question whose ANSWER is/contains the topic is a giveaway ("Chicago" →
        // answer "Chicago") and is held in RESERVE rather than dropped: for a person
        // most good questions answer with their name (17 of the 20 real van Gogh
        // questions do), so a hard drop starved the pool below a full quiz.
        val (giveaways, clean) = scoredAll.partition { (q, _, _) ->
            val answer = fold(q.answerText)
            tokens.any { containsWord(answer, it) }
        }
        var out = fillByTier(clean, limit)
        if (out.size < limit) {
            val taken = out.map { it.id }.toSet()
            out = out + fillByTier(giveaways, limit).filter { it.id !in taken }.take(limit - out.size)
        }
        return out
    }

    /** Does any of these rows have the topic as its SUBJECT? The JVM analogue of
     *  the `isOwnSubject` title query, for callers that already hold the rows. */
    fun ownSubject(candidates: List<Question>, phrase: String): Boolean =
        candidates.any {
            flattened(it.sourceTitle) == phrase || flattened(stripParens(it.sourceTitle)) == phrase
        }

    /** Take from the highest occupied relevance tier first, diversifying INSIDE it.
     *  Diversifying across tiers is what promoted a one-word coincidence into a
     *  category lane — "Ansel Adams" returned exactly one row per category (Samuel
     *  Adams, Hansel and Gretel, Phil Anselmo, Davante Adams…). Mirrors Swift. */
    private fun fillByTier(scored: List<Triple<Question, Int, Int>>, limit: Int): List<Question> {
        val out = mutableListOf<Question>()
        for (t in listOf(3, 2, 1, 0)) {
            if (out.size >= limit) break
            // Score THEN id: Swift's sort is not stable, so a score-only sort let
            // tied rows come out in different orders per platform, and the
            // per-category cap then kept a different SET.
            val lane = scored.filter { it.third == t }
                .sortedWith(compareByDescending<Triple<Question, Int, Int>> { it.second }
                    .thenBy { it.first.id })
                .map { it.first }
            out.addAll(diversifyByCategory(lane, limit - out.size))
        }
        return out.take(limit)
    }

    /** Round-robin a ranked list across categories, capping any one domain — the
     *  anti-monopoly rule for Create (owner: too many sports/geography questions). */
    private fun diversifyByCategory(ranked: List<Question>, limit: Int): List<Question> {
        val perCat = maxOf(2, Math.ceil(limit / 3.0).toInt())
        val lanes = LinkedHashMap<String, MutableList<Question>>()
        for (q in ranked) {
            val lane = lanes.getOrPut(q.categoryId) { mutableListOf() }
            if (lane.size < perCat) lane.add(q)
        }
        val out = mutableListOf<Question>()
        var progressed = true
        while (out.size < limit && progressed) {
            progressed = false
            for (lane in lanes.values) {
                if (lane.isNotEmpty()) { out.add(lane.removeAt(0)); progressed = true; if (out.size >= limit) break }
            }
        }
        // The per-category cap is an ANTI-MONOPOLY rule, not a quota: a genuinely
        // single-domain relevant pool must not starve the set ("Marie Curie" is
        // all science — capping at 3 turned a requested 8-question quiz into 4).
        if (out.size < limit) {
            val taken = out.map { it.id }.toHashSet()
            out.addAll(ranked.filter { it.id !in taken }.take(limit - out.size))
        }
        return out.shuffled()
    }

    /** Look up one question by ID — a saved quiz's refs resolve through here
     *  (docs/QUIZ-CONTRACT.md). */
    fun question(id: String): Question? =
        query("SELECT $COLS FROM questions WHERE id = ? LIMIT 1", arrayOf(id)).firstOrNull()

    /** Batched lookup: a 20-question quiz would otherwise be 20 round trips. */
    fun questions(ids: List<String>): Map<String, Question> {
        if (ids.isEmpty()) return emptyMap()
        return query(
            "SELECT $COLS FROM questions WHERE id IN (${ids.joinToString(",") { "?" }})",
            ids.toTypedArray(),
        ).associateBy { it.id }
    }

    fun daily(dayKey: String, count: Int): List<Question> {
        // Canonical hash-rank selection (Decision 037) — the SAME 7 on every
        // platform (mirrors DailyPick.swift + engine.js pickDaily exactly).
        val picked = pickDailyIds(ids, dayKey, "mixed", count)
        if (picked.isEmpty()) return emptyList()
        val rows = query(
            "SELECT $COLS FROM questions WHERE id IN (${picked.joinToString(",") { "?" }})",
            picked.toTypedArray(),
        ).associateBy { it.id }
        return picked.mapNotNull { rows[it] }   // keep the ranked order, not SQL's
    }
}

// ---- Enrichment-built mode sources (E1): a bundled JSON question set, same row
// shape as corpus.json; Picture ID also carries a 10th element (image URL). ----

class JsonQuestionSet(private val asset: String) {
    private var all: List<Question> = emptyList()
    private var byCat: Map<String, List<Question>> = emptyMap()
    /** Look up by ID — what a saved quiz needs to turn its set-refs back into
     *  questions (docs/QUIZ-CONTRACT.md). */
    private var byId: Map<String, Question> = emptyMap()
    var loaded = false; private set

    fun question(id: String): Question? = byId[id]

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
            byId = all.associateBy { it.id }
            loaded = true
        }
        Unit
    }

    fun pull(categoryId: String, seen: Set<String>, limit: Int): List<Question> {
        val src = if (categoryId == "mixed") all else (byCat[categoryId] ?: emptyList())
        return src.filter { it.id !in seen }.shuffled().take(limit)
    }

    /** Topic-matched pull (Create shape variety): prompt/title mentions a token,
     *  answer doesn't give it away. */
    fun searchMatch(topic: String, limit: Int): List<Question> {
        val tokens = topic.lowercase().split(Regex("[^a-z0-9]+")).filter { it.length >= 3 }
        if (tokens.isEmpty()) return emptyList()
        // Rank by matched-word count and keep the best tier. Matching ANY token
        // then shuffling made a one-word coincidence exactly as likely as a real
        // hit — "Marie Curie" surfaced "In what year did Jean-Marie Le Pen die?".
        val scored = all.mapNotNull { q ->
            val ans = q.answerText.lowercase()
            if (tokens.any { ans.contains(it) }) return@mapNotNull null
            val hay = "${q.prompt} ${q.sourceTitle} ${q.explanation}".lowercase()
            val matched = tokens.count { hay.contains(it) }
            if (matched > 0) q to matched else null
        }
        val bestMatched = scored.maxOfOrNull { it.second } ?: return emptyList()
        return scored.filter { it.second == bestMatched }.map { it.first }.shuffled().take(limit)
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

/** category → whole type pool ("mixed") → Classic backstop; never empty. */
private fun filledType(set: JsonQuestionSet, categoryId: String, count: Int, seen: Set<String>): List<Question> {
    var qs = set.pull(categoryId, seen, count)
    if (qs.size < count && categoryId != "mixed") {
        val have = seen + qs.map { it.id }.toSet()
        qs = qs + set.pull("mixed", have, count - qs.size)
    }
    return qs.ifEmpty { Corpus.pull(categoryId, seen, count) }
}

private suspend fun sourceNightType(kind: String, categoryId: String, count: Int, seen: Set<String>): List<Question> = when (kind) {
    "pictureId" -> filledType(Pictures, categoryId, count, seen)
    "thisOrThat" -> filledType(ThisOrThat, categoryId, count, seen)
    "closestCall" -> filledType(ClosestCall, categoryId, count, seen)
    "ordering" -> filledType(OrderingSet, categoryId, count, seen)
    "matching" -> filledType(MatchingSet, categoryId, count, seen)
    "typeAnswer" -> filledType(TypeAnswerSet, categoryId, count, seen)
    "oddOneOut" -> filledType(OddOneOutSet, categoryId, count, seen)
    "enumerate" -> filledType(EnumerateSet, categoryId, count, emptySet())
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
        val all = summaries(titles)
        // Wikipedia's search returns what is RELATED to the topic, not what is about
        // it: "Zendaya" brings back Tom Holland, Law Roach and Dune. An article earns
        // its place only if it names the topic — the whole PHRASE, since requiring
        // only the words let "Albert Einstein" through Bob Einstein, whose summary
        // happens to name his brother Albert. And the same different-person guard the
        // corpus ranker uses is needed here, or "Denver" fetches John Denver straight
        // from Wikipedia after the corpus correctly refused him.
        val tokens = Corpus.topicTokens(topic)
        val phrase = Corpus.topicPhrase(topic)
        val selfSubject = all.any { Corpus.flattened(it.title) == phrase }
        val guardNames = tokens.size == 1 && selfSubject
        val onTopic = all.filter { sm ->
            val subject = Corpus.flattened(sm.title)
            if (guardNames && subject != phrase && subject.split(" ").size == 2 &&
                Corpus.containsWord(subject, phrase)) return@filter false
            Corpus.containsWord(
                Corpus.fold(sm.title + " " + (sm.extract ?: "") + " " + (sm.description ?: "")), phrase)
        }
        TemplateEngine.make(onTopic, categoryId, count, stableSeed(topic),
                            relaxed = true, distractors = all)
    }

    private fun enc(s: String) = java.net.URLEncoder.encode(s, "UTF-8")
}

object TemplateEngine {
    /** `relaxed` is the LIVE path (Create), where the fame floor means something
     *  different. Sweeping the corpus, a 600-character intro is a free notability
     *  proxy over millions of candidates. Sweeping the results of a topic the
     *  PLAYER typed it is just a rejection — Folarin Balogun's whole summary is
     *  137 characters and makes a perfectly good clue, and a topic needs four
     *  usable articles to produce anything. Notability is already established by
     *  the player asking. Mirrors Swift TemplateEngine.isUsable(_:relaxed:). */
    private fun usable(s: Wikipedia.Summary, relaxed: Boolean = false): Boolean {
        val d = s.description; val e = s.extract
        if (d == null || d.length < 6 || d.length > 90) return false
        if (e == null || e.length < (if (relaxed) 120 else 600)) return false
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

    /** `distractors` defaults to `pool`, and separating them is what makes live
     *  Create work at all. The SUBJECT of a question must be about the topic the
     *  player typed, which leaves only a handful of articles — and a handful can
     *  never supply three same-class siblings, so every question was dropped for
     *  want of options ("Jalen Brunson" reduced to 4 usable articles, 2 of them
     *  people, and produced nothing). A distractor does not have to be about the
     *  topic; it only has to be a plausible wrong answer of the same kind, so it
     *  comes from the whole search result, which is thematically adjacent by
     *  construction. Mirrors Swift TemplateEngine.makeQuestions. */
    fun make(pool: List<Wikipedia.Summary>, categoryId: String, count: Int, seed: Long,
             relaxed: Boolean = false, distractors: List<Wikipedia.Summary>? = null): List<Question> {
        val usableList = pool.filter { usable(it, relaxed) }
        if (usableList.size < (if (relaxed) 1 else 4)) return emptyList()
        val dPool = (distractors ?: pool).filter { usable(it, relaxed) }
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
                val built = buildShape(shape, s, dPool, stem, relaxed, rng)
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

    /** The coarse kind of thing a subject is. Exact typeKey equality is right when
     *  drawing from a whole corpus, where there are always more footballers. A
     *  Create topic supplies at most 35 articles and they are deliberately
     *  heterogeneous — measured, a topic's usable results split as
     *  `subgenre:1, series:1, internet:1, genre:1`, so three same-type siblings
     *  never existed and every question was dropped for want of distractors. */
    private val WORK_TYPES = "film movie series show sitcom season episode album song single novel book poem play opera musical game franchise character comic manga anime documentary".split(" ").toSet()
    private val PLACE_TYPES = "settlement peak country state province region district county island river lake sea ocean desert park building bridge stadium airport museum palace castle".split(" ").toSet()

    private fun coarseClass(s: Wikipedia.Summary): String {
        if (isPerson(s)) return "person"
        val k = typeKey(s) ?: return "thing"
        return when (k) { in WORK_TYPES -> "work"; in PLACE_TYPES -> "place"; else -> "thing" }
    }

    private fun typedDistractors(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, relaxed: Boolean, rng: SeededRng, value: (Wikipedia.Summary) -> String?, exclude: String, lengthMatch: Int?): List<String> {
        fun gather(matches: (Wikipedia.Summary) -> Boolean): List<String> {
            val seen = mutableSetOf<String>()
            val cands = pool.mapNotNull { c ->
                if (c.title == s.title || !matches(c)) return@mapNotNull null
                val v = value(c)?.trim() ?: return@mapNotNull null
                if (v.isEmpty() || v.equals(exclude, true) || !seen.add(v.lowercase())) return@mapNotNull null
                val lenPen = if (lengthMatch != null) -kotlin.math.abs(v.length - lengthMatch) else 0
                Pair(v, lenPen)
            }.sortedByDescending { it.second }
            if (cands.size < 3) return emptyList()
            return cands.take(9).map { it.first }.shuffledWith(rng).take(3)
        }
        val kt = typeKey(s)
        if (kt != null) {
            val exact = gather { typeKey(it) == kt }
            if (exact.isNotEmpty()) return exact
        }
        if (!relaxed) return emptyList()
        val kc = coarseClass(s)
        return gather { coarseClass(it) == kc }
    }
    private fun titleDistractors(s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, relaxed: Boolean, rng: SeededRng) =
        typedDistractors(s, pool, relaxed, rng, { stripParens(it.title) }, stripParens(s.title), null)

    // --- Describe-shape helpers (mirror of generate_corpus.py) ---
    private val MONTHS = "january february march april may june july august september october november december".split(" ").toSet()
    private val TYPE_NOUNS = "actor actress singer musician composer songwriter rapper band writer author poet novelist playwright journalist artist painter sculptor director filmmaker producer scientist physicist chemist biologist mathematician astronomer economist politician philosopher activist explorer inventor architect dancer comedian footballer player athlete cyclist swimmer boxer golfer film movie television series show novel book album song single painting sculpture poem play opera symphony team club city town country river mountain lake dynasty empire".split(" ").toSet()
    private val NATIONALITIES = "polish french american british english german italian russian japanese chinese spanish dutch canadian australian indian brazilian mexican swedish norwegian danish finnish greek roman egyptian persian turkish irish scottish welsh austrian swiss belgian portuguese hungarian czech romanian korean vietnamese thai argentine chilean colombian peruvian israeli iranian iraqi syrian lebanese moroccan nigerian kenyan ethiopian ukrainian serbian croatian bulgarian icelandic".split(" ").toSet()
    private val CLUE_GENERIC = COMMON_WORDS + TYPE_LEADING + TYPE_NOUNS + NATIONALITIES +
        "this the a an was is were are best known famous noted also who which that based located near former".split(" ").toSet()
    // The `(?:,[^,]{0,80},)?` clause is an APPOSITIVE between the name and the
    // verb, and without it a large share of Wikipedia leads simply do not parse:
    // "Jalen Marquis Brunson, nicknamed \"Captain Clutch\", is an American
    // professional basketball player…" failed both shapes, so a topic with four
    // perfectly good usable articles produced nothing.
    /** "Which %@?" only reads as a question when the clue is a bare noun phrase. Give it a clue carrying a finite relative clause and it becomes a fragment: "Which British politician who has served as Chancellor of the Exchequer under Andy Burnham since 20 July 2026?" — read off a live-generated quiz on the simulator. "Name this ..." is grammatical either way, so the stem steps aside. Mirrors Swift `grammatical`. */
    fun grammatical(stem: String, clue: String): String {
        // Matched EXACTLY, not by prefix: the cloze bank also starts a stem with
        // "Which" ("Which name completes this? ...") and that is already a whole
        // question. Rewriting it would replace a working cloze with nonsense.
        if (stem != "Which %s?") return stem
        val c = " " + clue.lowercase() + " "
        for (rel in listOf(" who ", " whom ", " that ", " which ", " whose ", " where "))
            if (c.contains(rel)) return "Name this %s."
        return stem
    }

    private val LEAD = Regex("^\\s*((?:[A-Z][\\w’'.\\-]*)(?:[ \\-]+(?:of|the|and|de|von|van|al|da|di)?\\s*[A-Z][\\w’'.\\-]*)*)\\s*(?:\\([^)]*\\))?\\s*(?:,[^,]{0,80},)?\\s*(?:was|is|were|are)\\s+(?:a|an|the)\\s+(.+)$")
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
    private fun buildShape(shape: String, s: Wikipedia.Summary, pool: List<Wikipedia.Summary>, stem: String, relaxed: Boolean, rng: SeededRng): Triple<String, List<String>, String>? {
        when (shape) {
            "describe" -> {
                // FIRST sentence only — a 2-sentence clue reads awkwardly under "Name this …?".
                val c = reframe(cleanClue(firstSentence(s.extract ?: "")), s.title)
                if (c == null || c.length < 30 || informativeTokens(c) < 2) return null
                val clue = c.replace(Regex("[.\\s]+$"), "").trim()
                val ds = titleDistractors(s, pool, relaxed, rng); if (ds.size != 3) return null
                val ans = stripParens(s.title)
                return Triple(grammatical(stem, clue).format(clue), listOf(ans) + ds, ans)
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
                val ds = titleDistractors(s, pool, relaxed, rng); if (ds.size != 3) return null
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

// L4: levelable badges — mirror of Core BadgeMath. Tiers match web + iOS.
data class LevelableBadge(val name: String, val value: Int, val tiers: List<Int>, val unit: String) {
    val tier: Int get() = tiers.count { value >= it }
    val maxTier: Int get() = tiers.size
    val next: Int? get() = if (tier < tiers.size) tiers[tier] else null
    val progress: Float get() {
        val n = next ?: return 1f
        val floor = if (tier > 0) tiers[tier - 1] else 0
        return ((value - floor).toFloat() / (n - floor)).coerceIn(0.06f, 1f)
    }
    val detail: String get() = next?.let { "$value/$it $unit to Tier ${tier + 1}" } ?: "Maxed — $value $unit"
}
object BadgeMath {
    fun badges(games: Int, longestStreak: Int, mastered: Int, lifetimeAccuracy: Int, liveNights: Int) = listOf(
        LevelableBadge("Scholar", games, listOf(10, 50, 100, 500), "games"),
        LevelableBadge("On a Roll", longestStreak, listOf(3, 7, 30, 100), "day streak"),
        LevelableBadge("Domain Master", mastered, listOf(1, 3, 5, 7), "domains mastered"),
        LevelableBadge("Sharpshooter", if (games >= 5) lifetimeAccuracy else 0, listOf(60, 75, 85, 95), "% accuracy"),
        LevelableBadge("Regular", liveNights, listOf(1, 5, 15, 40), "live nights"),
    )
}
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

    companion object { private const val SEEN_OPTS_SEP = "" }

    fun seenHas(id: String) = id in seen
    fun markSeen(ids: List<String>) {
        seen.addAll(ids)
        if (seen.size > 9000) seen.clear()
        prefs.edit().putStringSet("seen", seen).apply()
    }
    val seenSet: Set<String> get() = seen

    data class AnswerDetail(val qid: String, val prompt: String, val categoryId: String, val correct: Boolean, val answer: String)
    data class Rec(val mode: String, val categoryId: String, val score: Int, val correct: Int, val total: Int, val maxStreak: Int, val day: String,
                   val at: Long = 0L, val answers: List<AnswerDetail> = emptyList())

    fun addRecord(r: Rec, countsForStreak: Boolean = true) {
        val arr = org.json.JSONArray(prefs.getString("records", "[]"))
        val ans = org.json.JSONArray()
        r.answers.forEach { a -> ans.put(JSONObject().put("qid", a.qid).put("p", a.prompt)
            .put("cat", a.categoryId).put("ok", a.correct).put("ans", a.answer)) }
        val o = JSONObject().put("mode", r.mode).put("cat", r.categoryId).put("score", r.score)
            .put("correct", r.correct).put("total", r.total).put("streak", r.maxStreak).put("day", r.day)
            .put("at", if (r.at > 0) r.at else System.currentTimeMillis()).put("answers", ans)
        val list = (0 until arr.length()).map { arr.getJSONObject(it) }.toMutableList()
        list.add(0, o)
        val out = org.json.JSONArray(); list.take(500).forEach { out.put(it) }
        prefs.edit().putString("records", out.toString()).apply()
        if (r.mode == "DAILY" && countsForStreak) bumpStreak()
    }
    fun records(): List<Rec> {
        val arr = org.json.JSONArray(prefs.getString("records", "[]"))
        return (0 until arr.length()).map { arr.getJSONObject(it) }.map { o ->
            val ansArr = o.optJSONArray("answers")
            val answers = if (ansArr == null) emptyList() else (0 until ansArr.length()).map { i ->
                val a = ansArr.getJSONObject(i)
                AnswerDetail(a.getString("qid"), a.getString("p"), a.getString("cat"), a.getBoolean("ok"), a.getString("ans"))
            }
            Rec(o.getString("mode"), o.getString("cat"), o.getInt("score"), o.getInt("correct"), o.getInt("total"), o.getInt("streak"), o.getString("day"),
                o.optLong("at", 0L), answers)
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
        // Per ANSWER, not per round: a Mixed Bag round is filed under "mixed",
        // which is no domain, so the default mode credited nothing and the
        // screen read "explored 0 of 8 domains" no matter how much you played.
        // Rounds with no stored answers predate that detail and were
        // single-category, so their own category is the right fallback.
        var correct = 0; var total = 0
        for (r in records()) {
            if (r.answers.isEmpty()) {
                if (r.categoryId == id) { correct += r.correct; total += r.total }
            } else {
                for (a in r.answers) if (a.categoryId == id) { total++; if (a.correct) correct++ }
            }
        }
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
    fun lastPlayerName(): String = prefs.getString("player_name", "") ?: ""
    fun savePlayerName(n: String) = prefs.edit().putString("player_name", n).apply()

    fun mixModesCsv(): String? = prefs.getString("mix_modes", null)
    fun saveMixModes(csv: String) = prefs.edit().putString("mix_modes", csv).apply()

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
            .remove("stories")
            .remove("marathonRun").remove("marathonScores")
            .remove("expeditionProgress").remove("expeditionCertificates")
            .remove("linkwall")
            .apply()
    }

    /** Reads one miss entry regardless of format: `{id: {"n": count, "t": lastSeenMs}}`
     *  (current) or a bare int (legacy, pre-Weak-Spot-Arena — treated as lastSeen=0,
     *  i.e. sorts as the oldest gap). */
    private fun missEntry(o: JSONObject, id: String): Pair<Int, Long> = when (val v = o.opt(id)) {
        is JSONObject -> v.optInt("n", 0) to v.optLong("t", 0L)
        is Number -> v.toInt() to 0L
        else -> 0 to 0L
    }

    fun recordMisses(results: List<Pair<String, Boolean>>) {
        val o = JSONObject(prefs.getString("missed", "{}") ?: "{}")
        val now = System.currentTimeMillis()
        for ((id, correct) in results) {
            if (correct) o.remove(id)               // re-asked-and-correct resolves it
            else o.put(id, JSONObject().put("n", missEntry(o, id).first + 1).put("t", now))
        }
        if (o.length() > 800) { prefs.edit().putString("missed", "{}").apply(); return }
        prefs.edit().putString("missed", o.toString()).apply()
    }
    /** Missed question ids, most-missed first — mapped to Questions via Corpus.byId. */
    fun dueReview(limit: Int): List<String> {
        val o = JSONObject(prefs.getString("missed", "{}") ?: "{}")
        return o.keys().asSequence().map { it to missEntry(o, it).first }
            .sortedByDescending { it.second }.take(limit).map { it.first }.toList()
    }

    /** One miss record: id, times missed, and when it was last missed (0 = unknown /
     *  pre-dates the lastSeen field). The Weak-Spot Arena's source
     *  (docs/CLUB-FEATURES-BUILD.md "Feature 1"). */
    data class MissEntry(val id: String, val missCount: Int, val lastSeen: Long)

    /** Full miss detail, most-missed + oldest-gap-first (mirrors iOS
     *  `MissedFact` sort / web's `Store.missed()` sort). */
    fun missDetails(): List<MissEntry> {
        val o = JSONObject(prefs.getString("missed", "{}") ?: "{}")
        return o.keys().asSequence().map { id -> val (n, t) = missEntry(o, id); MissEntry(id, n, t) }
            .sortedWith(compareByDescending<MissEntry> { it.missCount }.thenBy { it.lastSeen })
            .toList()
    }

    /** One story in the Club Story Archive (docs/CLUB-FEATURES-BUILD.md "Feature 2") —
     *  a frozen snapshot of a question the player has answered (right or wrong), captured
     *  at answer-time so it survives later corpus edits. [question] rebuilds a playable
     *  MCQ for "Re-ask this"; null for shapes that don't reduce to >=2 plain options
     *  (mirrors the Apple `SeenStory.question` fallback). */
    data class SeenStory(
        val qid: String, val prompt: String, val answer: String, val story: String, val categoryId: String,
        private val optionsJoined: String, private val correctIndex: Int,
        val firstSeen: Long, val lastSeen: Long, val everCorrect: Boolean, val favorite: Boolean,
    ) {
        val question: Question? get() {
            val opts = optionsJoined.split(SEEN_OPTS_SEP).filter { it.isNotEmpty() }
            if (opts.size < 2 || correctIndex !in opts.indices) return null
            return Question(qid, prompt, opts, correctIndex, categoryId, 3, story, "", "")
        }
    }

    /** Every DISTINCT question the player has ever answered, keyed by qid — upserted
     *  from the same place [recordMisses]/[recordTelemetry] are called, so "seen" = any
     *  answer, not just a correct one (you met the fact either way). ADDITIVE: the free
     *  in-moment story reveal (Question.explanation shown right after answering) is
     *  untouched by this store — R-MON-1. */
    fun seenStories(): Map<String, SeenStory> {
        val o = JSONObject(prefs.getString("stories", "{}") ?: "{}")
        val map = LinkedHashMap<String, SeenStory>()
        o.keys().forEach { id ->
            val s = o.getJSONObject(id)
            map[id] = SeenStory(
                qid = id, prompt = s.optString("p", ""), answer = s.optString("ans", ""),
                story = s.optString("story", ""), categoryId = s.optString("cat", "mixed"),
                optionsJoined = s.optString("opts", ""), correctIndex = s.optInt("ci", -1),
                firstSeen = s.optLong("first", 0L), lastSeen = s.optLong("last", 0L),
                everCorrect = s.optBoolean("ok", false), favorite = s.optBoolean("fav", false),
            )
        }
        return map
    }

    fun recordSeen(answered: List<Pair<Question, Boolean>>) {
        val o = JSONObject(prefs.getString("stories", "{}") ?: "{}")
        val now = System.currentTimeMillis()
        for ((q, correct) in answered) {
            val existing = o.optJSONObject(q.id)
            if (existing != null) {
                existing.put("last", now)
                if (correct) existing.put("ok", true)
            } else {
                o.put(q.id, JSONObject()
                    .put("p", q.prompt).put("ans", q.answerText).put("story", q.explanation)
                    .put("cat", q.categoryId).put("opts", q.options.joinToString(SEEN_OPTS_SEP))
                    .put("ci", q.correctIndex).put("first", now).put("last", now)
                    .put("ok", correct).put("fav", false))
            }
        }
        if (o.length() > 9000) { prefs.edit().putString("stories", "{}").apply(); return }
        prefs.edit().putString("stories", o.toString()).apply()
    }

    /** Returns the new favorite state, or false if the story isn't in the archive. */
    fun toggleStoryFavorite(qid: String): Boolean {
        val o = JSONObject(prefs.getString("stories", "{}") ?: "{}")
        val existing = o.optJSONObject(qid) ?: return false
        val fav = !existing.optBoolean("fav", false)
        existing.put("fav", fav)
        prefs.edit().putString("stories", o.toString()).apply()
        return fav
    }

    // ---- Marathon (Club — docs/CLUB-FEATURES-BUILD.md "Feature 3") ----
    // The AT-MOST-ONE in-progress run + the permanent completed-run history. The
    // resume-across-sessions mechanic is entirely in the persisted shape here: every
    // answer round-trips through [saveMarathonRun] immediately (Marathon.record), so a
    // process death never loses progress. A corrupt/legacy blob reads back as "no run
    // in progress" rather than crashing.

    fun marathonRun(): MarathonRun? {
        val raw = prefs.getString("marathonRun", null) ?: return null
        return try {
            val o = JSONObject(raw)
            val idsArr = o.getJSONArray("ids")
            val ids = (0 until idsArr.length()).map { idsArr.getString(it) }
            val resArr = o.optJSONArray("results") ?: org.json.JSONArray()
            val results = (0 until resArr.length()).map { i ->
                val r = resArr.getJSONObject(i)
                MarathonAnswerRecord(r.getString("qid"), r.getString("cat"), r.getInt("diff"), r.getBoolean("ok"))
            }
            MarathonRun(o.getString("seed"), ids, o.getInt("currentIndex"), results, o.getLong("startedAt"), o.getLong("lastPlayedAt"))
        } catch (e: Exception) { null }
    }

    /** Persist the run immediately — called after EVERY answer ([Marathon.record]) so
     *  a crash/quit never loses progress (the whole point of Marathon). */
    fun saveMarathonRun(run: MarathonRun) {
        val o = JSONObject()
        o.put("seed", run.seed)
        o.put("ids", org.json.JSONArray(run.ids))
        val resArr = org.json.JSONArray()
        run.results.forEach { r ->
            resArr.put(JSONObject().put("qid", r.qid).put("cat", r.categoryId).put("diff", r.difficulty).put("ok", r.correct))
        }
        o.put("results", resArr)
        o.put("currentIndex", run.currentIndex)
        o.put("startedAt", run.startedAt)
        o.put("lastPlayedAt", run.lastPlayedAt)
        prefs.edit().putString("marathonRun", o.toString()).apply()
    }

    fun clearMarathonRun() = prefs.edit().remove("marathonRun").apply()

    /** Past completed Marathons, most recent first — the permanent history. */
    fun marathonHistory(): List<MarathonScore> {
        val arr = org.json.JSONArray(prefs.getString("marathonScores", "[]") ?: "[]")
        return (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            val domArr = o.optJSONArray("domains") ?: org.json.JSONArray()
            val domains = (0 until domArr.length()).map { j ->
                val d = domArr.getJSONObject(j)
                MarathonDomainStat(d.getString("cat"), d.getInt("correct"), d.getInt("total"))
            }
            MarathonScore(o.getLong("date"), o.getInt("score"), o.getInt("correct"), o.getInt("total"), o.getDouble("duration"), domains)
        }.sortedByDescending { it.date }
    }

    fun appendMarathonScore(entry: MarathonScore) {
        val history = listOf(entry) + marathonHistory()
        val arr = org.json.JSONArray()
        history.take(500).forEach { s ->
            val domArr = org.json.JSONArray()
            s.domainBreakdown.forEach { d -> domArr.put(JSONObject().put("cat", d.categoryId).put("correct", d.correct).put("total", d.total)) }
            arr.put(JSONObject().put("date", s.date).put("score", s.score).put("correct", s.correct)
                .put("total", s.total).put("duration", s.durationSeconds).put("domains", domArr))
        }
        prefs.edit().putString("marathonScores", arr.toString()).apply()
    }

    // ---- Link Wall (Club — docs/CLUB-FEATURES-BUILD.md "Feature 6") ----
    // One puzzle per day (the generator itself, LinkWall.puzzle(day), is stateless and
    // deterministic — nothing about the PUZZLE is persisted). What IS persisted is the
    // player's progress THROUGH that day's board, keyed by day, one row per day — a
    // reload/relaunch resumes mid-progress; a completed day shows the result, not a
    // fresh board (mirrors Marathon's immediate-persist-after-every-answer discipline).
    // Shared JSON shape (the contract for the Windows port too):
    //   linkwall = { [day]: { mistakes, completed, won, date,
    //                          guessHistory: [[Int]], solvedLabels: [String] } }

    fun linkWallResult(day: String): LinkWall.LinkWallResult? {
        val all = JSONObject(prefs.getString("linkwall", "{}") ?: "{}")
        val o = all.optJSONObject(day) ?: return null
        return linkWallResultFromJson(o)
    }

    private fun linkWallResultFromJson(o: JSONObject): LinkWall.LinkWallResult {
        val ghArr = o.optJSONArray("guessHistory") ?: org.json.JSONArray()
        val guessHistory = (0 until ghArr.length()).map { i ->
            val row = ghArr.getJSONArray(i)
            (0 until row.length()).map { row.getInt(it) }
        }
        val slArr = o.optJSONArray("solvedLabels") ?: org.json.JSONArray()
        val solvedLabels = (0 until slArr.length()).map { slArr.getString(it) }
        return LinkWall.LinkWallResult(
            mistakes = o.optInt("mistakes", 0),
            completed = o.optBoolean("completed", false),
            won = o.optBoolean("won", false),
            date = o.optLong("date", System.currentTimeMillis()),
            guessHistory = guessHistory,
            solvedLabels = solvedLabels,
        )
    }

    /** Fetch a day's row, or insert a fresh one — never a second row for the same day. */
    fun linkWallResultOrCreate(day: String): LinkWall.LinkWallResult {
        linkWallResult(day)?.let { return it }
        val fresh = LinkWall.LinkWallResult(date = System.currentTimeMillis())
        return saveLinkWallResult(day, fresh)
    }

    fun saveLinkWallResult(day: String, result: LinkWall.LinkWallResult): LinkWall.LinkWallResult {
        val all = JSONObject(prefs.getString("linkwall", "{}") ?: "{}")
        val o = JSONObject()
            .put("mistakes", result.mistakes).put("completed", result.completed).put("won", result.won)
            .put("date", result.date)
        val ghArr = org.json.JSONArray()
        result.guessHistory.forEach { row -> ghArr.put(org.json.JSONArray(row)) }
        o.put("guessHistory", ghArr)
        o.put("solvedLabels", org.json.JSONArray(result.solvedLabels))
        all.put(day, o)
        prefs.edit().putString("linkwall", all.toString()).apply()
        return result
    }

    /** Appends one guess row, correct or not — called immediately on every submit so a
     *  reload/crash never loses progress (same discipline as Marathon.record). */
    fun recordLinkWallGuess(day: String, difficulties: List<Int>): LinkWall.LinkWallResult {
        val r = linkWallResult(day) ?: linkWallResultOrCreate(day)
        return saveLinkWallResult(day, r.copy(guessHistory = r.guessHistory + listOf(difficulties)))
    }

    fun recordLinkWallSolvedGroup(day: String, label: String): LinkWall.LinkWallResult {
        val r = linkWallResult(day) ?: linkWallResultOrCreate(day)
        if (label in r.solvedLabels) return r
        return saveLinkWallResult(day, r.copy(solvedLabels = r.solvedLabels + label))
    }

    // ---- Expeditions (Club — docs/CLUB-FEATURES-BUILD.md "Feature 5") ----
    // Unlike Marathon's at-most-one run, SEVERAL expeditions may be in progress at
    // once — one JSON object keyed by expeditionId (mirrors Apple's per-expeditionID
    // ExpeditionProgress rows / web's tidbits.expeditionProgress MAP). A corrupt/legacy
    // blob reads back as "nothing in progress" rather than crashing.

    fun expeditionProgress(): Map<String, ExpeditionProgress> {
        val raw = prefs.getString("expeditionProgress", null) ?: return emptyMap()
        return try {
            val o = JSONObject(raw)
            o.keys().asSequence().mapNotNull { id ->
                val p = o.optJSONObject(id) ?: return@mapNotNull null
                val resArr = p.optJSONArray("stageResults") ?: org.json.JSONArray()
                val results = (0 until resArr.length()).map { i ->
                    val r = resArr.getJSONObject(i)
                    ExpeditionStageResult(r.getInt("stage"), r.getBoolean("pass"), r.getInt("correct"), r.getInt("total"))
                }
                id to ExpeditionProgress(id, p.getInt("currentStageIndex"), results, p.getLong("startedAt"), p.getLong("lastPlayedAt"))
            }.toMap()
        } catch (e: Exception) { emptyMap() }
    }

    /** Persist one expedition's progress row (upsert by expeditionId) — called after
     *  EVERY stage attempt so a player can leave and come back over days or weeks. */
    fun saveExpeditionProgress(progress: ExpeditionProgress) {
        val root = JSONObject(prefs.getString("expeditionProgress", "{}") ?: "{}")
        val p = JSONObject()
        p.put("currentStageIndex", progress.currentStageIndex)
        val resArr = org.json.JSONArray()
        progress.stageResults.forEach { r ->
            resArr.put(JSONObject().put("stage", r.stageIndex).put("pass", r.passed).put("correct", r.correct).put("total", r.total))
        }
        p.put("stageResults", resArr)
        p.put("startedAt", progress.startedAt)
        p.put("lastPlayedAt", progress.lastPlayedAt)
        root.put(progress.expeditionId, p)
        prefs.edit().putString("expeditionProgress", root.toString()).apply()
    }

    fun deleteExpeditionProgress(expeditionId: String) {
        val root = JSONObject(prefs.getString("expeditionProgress", "{}") ?: "{}")
        root.remove(expeditionId)
        prefs.edit().putString("expeditionProgress", root.toString()).apply()
    }

    /** Every completed Expedition, most recent first — the permanent certificates shelf. */
    fun expeditionCertificates(): List<ExpeditionCertificate> {
        val arr = org.json.JSONArray(prefs.getString("expeditionCertificates", "[]") ?: "[]")
        return (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            ExpeditionCertificate(o.getString("expeditionId"), o.getString("domain"), o.getString("title"),
                o.getLong("completedAt"), o.getInt("totalScore"), o.getInt("stagesCompleted"))
        }.sortedByDescending { it.completedAt }
    }

    fun appendExpeditionCertificate(cert: ExpeditionCertificate) {
        val history = listOf(cert) + expeditionCertificates()
        val arr = org.json.JSONArray()
        history.take(500).forEach { c ->
            arr.put(JSONObject().put("expeditionId", c.expeditionId).put("domain", c.domain).put("title", c.title)
                .put("completedAt", c.completedAt).put("totalScore", c.totalScore).put("stagesCompleted", c.stagesCompleted))
        }
        prefs.edit().putString("expeditionCertificates", arr.toString()).apply()
    }

    // R-DAILY-1: per-day Daily results — first completion locks the day.
    fun dailyScore(day: String): Int? {
        val o = JSONObject(prefs.getString("daily_results", "{}") ?: "{}")
        return if (o.has(day)) o.getInt(day) else null
    }
    /** The whole local map (dayKey → score) — for pushing anon plays to the synced log. */
    fun allDaily(): Map<String, Int> {
        val o = JSONObject(prefs.getString("daily_results", "{}") ?: "{}")
        return o.keys().asSequence().associateWith { o.getInt(it) }
    }
    fun recordDaily(day: String, score: Int) {
        val o = JSONObject(prefs.getString("daily_results", "{}") ?: "{}")
        if (o.has(day)) return
        o.put(day, score)
        prefs.edit().putString("daily_results", o.toString()).apply()
    }
    /** Adopt the signed-in account's authoritative score for a day (overwrites local). Used
     *  ONLY by cross-device sync to reconcile a conflict — gameplay stays first-wins. */
    fun adoptDaily(day: String, score: Int) {
        val o = JSONObject(prefs.getString("daily_results", "{}") ?: "{}")
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
