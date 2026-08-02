package com.learningischange.tidbitstrivia.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Daily-parity golden — Android side (Decision 037, docs/DATA-CONTRACT.md
 * §Daily). Exercises the REAL pickDailyIds/stableSeed from Tidbits.kt against
 * the ids in the bundled corpus asset, and writes
 * tools/daily-parity/golden/android.txt for run.sh to diff against the Swift
 * and JS outputs. The three MUST be identical — the Daily's whole point is
 * "everyone gets the same 7" (owner caught the platforms diverging 2026-07-01).
 */
class DailyParityTest {

    private val days = listOf("2026-07-01", "2026-07-02", "2026-09-01",
                              "2026-12-31", "2027-01-15", "2027-02-28")

    private val repo: File by lazy {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "tools/daily-parity").isDirectory) dir = dir.parentFile
        requireNotNull(dir) { "repo root not found above ${File("").absolutePath}" }
    }

    @Test fun writeGoldenPicks() {
        // The repo-root copy, not the app's asset: Android now ships corpus.sqlite (the same
        // rows in the same order) so the app never holds the corpus in RAM. The daily rank is
        // computed from ids alone, so the shared JSON remains the right golden source.
        val corpus = Json.parseToJsonElement(File(repo, "assets/corpus.json").readText()).jsonObject
        val rows = corpus["questions"]!!.jsonArray
        val ids = rows.map { it.jsonArray[0].jsonPrimitive.content }
        val cats = rows.map { it.jsonArray[4].jsonPrimitive.content }   // v2 needs categories
        assertTrue("corpus too small: ${ids.size}", ids.size > 100)
        val out = StringBuilder()
        for (day in days) {
            val picked = pickDailyBalancedIds(ids, cats, day, "mixed", 7)
            assertTrue("picked ${picked.size} for $day", picked.size == 7)
            out.append(day).append(' ').append(picked.joinToString(" ")).append('\n')
        }
        File(repo, "tools/daily-parity/golden/android.txt").writeText(out.toString())
    }
}
