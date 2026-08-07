package com.learningischange.tidbitstrivia.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The shape sets are streamed a row at a time rather than read into one String and one
 * whole-file DOM. That change exists because the DOM was the remaining half of the OOM
 * class Play rejected version codes 75 and 85 for — deferring the load off the launch
 * path moved the allocation, it did not shrink it, so it simply became "player opens
 * Type It In" instead of "app opens".
 *
 * The risk in that change is NOT a crash, it is silence: if the splitter drops, merges or
 * mis-slices a row, the affected mode shows "No questions yet" and every build still
 * passes. This codebase has shipped that bug before. So the test is an EQUIVALENCE test
 * against the parse the streaming version replaced, over every asset that actually ships.
 */
class JsonQuestionSetStreamTest {

    private fun repoFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, rel).exists()) dir = dir.parentFile
        return File(requireNotNull(dir) { "cannot find $rel above ${File("").absolutePath}" }, rel)
    }

    private val sets = listOf(
        "typeanswer.json", "picture.json", "closest.json", "match.json",
        "order.json", "oddoneout.json", "thisorthat.json", "enumerate.json",
    )

    @Test
    fun `streaming yields exactly the rows the whole-file parse yields`() {
        for (name in sets) {
            val file = repoFile("android/app/src/main/assets/$name")
            assertTrue("$name is not where the app expects it", file.exists())

            // The parse this replaced: whole file -> String -> DOM.
            val whole: List<JsonArray> = Json.parseToJsonElement(file.readText())
                .jsonObject["questions"]!!.jsonArray.map { it.jsonArray }

            // The parse that ships.
            val streamed = ArrayList<JsonArray>()
            file.bufferedReader().use { r ->
                forEachQuestionRow(r) { streamed.add(Json.parseToJsonElement(it).jsonArray) }
            }

            assertEquals("$name row count", whole.size, streamed.size)
            for (i in whole.indices) {
                // Compares element types too, not just rendered text — a year decoded as a
                // string instead of a number is precisely what would flip every Ordering row
                // into the Matching branch, and both files are 8 columns wide so nothing
                // else would catch it.
                assertEquals("$name row $i", whole[i], streamed[i])
            }
        }
    }

    @Test
    fun `every row still maps to the question the mode expects`() {
        // Row count is not enough: the sets must still produce the SPEC each mode reads.
        val expect = mapOf(
            "match.json" to { q: Question -> q.matching != null },
            "order.json" to { q: Question -> q.ordering != null },
            "closest.json" to { q: Question -> q.closest != null },
            "enumerate.json" to { q: Question -> q.enumerate != null },
            "typeanswer.json" to { q: Question -> !q.accepted.isNullOrEmpty() },
            "picture.json" to { q: Question -> q.options.size > 1 },
            "oddoneout.json" to { q: Question -> q.options.size > 1 },
            "thisorthat.json" to { q: Question -> q.options.size > 1 },
        )
        for ((name, holds) in expect) {
            val set = JsonQuestionSet(name)
            val file = repoFile("android/app/src/main/assets/$name")
            var n = 0
            var bad = 0
            file.bufferedReader().use { r ->
                forEachQuestionRow(r) { row ->
                    val q = set.rowToQuestion(Json.parseToJsonElement(row).jsonArray)
                    n++
                    if (!holds(q)) bad++
                }
            }
            assertTrue("$name produced no rows", n > 0)
            assertEquals("$name rows that lost their mode spec", 0, bad)
        }
    }

    @Test
    fun `splitter survives the structural characters real prompts contain`() {
        // Prompts carry quotes, escaped quotes and brackets — the three things a
        // depth-counting splitter gets wrong.
        val json = """
            {"version":"x","count":3,"questions":[
              ["a","He said \"go [now]\" — then left","x",["y"],"c","e","t","u"],
              ["b","brackets ] [ inside a string","x",["y"],"c","e","t","u"],
              ["c","trailing backslash \\","x",["y"],"c","e","t","u"]
            ]}
        """.trimIndent()
        val rows = ArrayList<String>()
        forEachQuestionRow(json.reader()) { rows.add(it) }
        assertEquals(3, rows.size)
        val ids = rows.map { Json.parseToJsonElement(it).jsonArray[0].toString() }
        assertEquals(listOf("\"a\"", "\"b\"", "\"c\""), ids)
    }
}
