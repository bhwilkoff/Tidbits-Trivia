package com.learningischange.tidbitstrivia.data

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Does the Kotlin ranker select the SAME questions as the shipped Apple one?
 *
 * `CreateTopicDriftTest` covers the pure helpers — tier, containsWord,
 * promptHasWord, phraseIsRequired — which is not the same as agreeing on a real
 * topic over the real 128k-row corpus. The first end-to-end comparison between
 * Apple and the web found a divergence immediately (Swift's sort is not stable and
 * JavaScript's is, so rows tied on score ordered differently and the per-category
 * cap in `diversifyByCategory` then kept a different SET). This is the Kotlin side
 * of that check, and it was the last of the four engines still unverified.
 *
 * Runs `Corpus.rank` over EVERY row rather than a pre-filtered subset. That is the
 * point: `rank` re-applies the difficulty and continent-template rules that `search`
 * pushes into SQL, so the SQL is a pure optimisation and this test still measures
 * the shipped policy.
 *
 * Order is not compared — `diversifyByCategory` shuffles on purpose so a quiz does
 * not march category-by-category. Membership is the contract.
 */
class CreateGoldenTest {

    private fun repoFile(rel: String): File {
        // Gradle runs unit tests with android/app as the working directory.
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, rel).exists()) dir = dir.parentFile
        return File(requireNotNull(dir) { "cannot find $rel above ${File("").absolutePath}" }, rel)
    }

    private fun loadCorpus(): List<Question> {
        val root = JSONObject(repoFile("assets/corpus.json").readText())
        val rows = root.getJSONArray("questions")
        val out = ArrayList<Question>(rows.length())
        for (i in 0 until rows.length()) {
            val r = rows.getJSONArray(i)
            val opts = r.getJSONArray(2)
            val tags = if (r.length() > 9 && !r.isNull(9)) r.getJSONArray(9) else JSONArray()
            out.add(
                Question(
                    id = r.getString(0),
                    prompt = r.getString(1),
                    options = (0 until opts.length()).map { opts.getString(it) },
                    correctIndex = r.getInt(3),
                    categoryId = r.getString(4),
                    difficulty = r.getInt(5),
                    explanation = r.optString(6, ""),
                    sourceTitle = r.optString(7, ""),
                    sourceUrl = r.optString(8, ""),
                    tags = (0 until tags.length()).map { tags.getString(it) },
                ),
            )
        }
        return out
    }

    private fun golden(): List<Pair<String, Set<String>>> =
        repoFile("tools/create/golden/search.txt").readLines()
            .filter { it.isNotBlank() }
            .map { line ->
                val tab = line.indexOf('\t')
                val topic = if (tab < 0) line else line.substring(0, tab)
                val ids = if (tab < 0) "" else line.substring(tab + 1)
                topic to ids.split(' ').filter { it.isNotEmpty() }.toSet()
            }

    @Test fun theRankerSelectsWhatTheAppleRankerSelects() {
        val corpus = loadCorpus()
        assertTrue("corpus looks wrong: ${corpus.size} rows", corpus.size > 100_000)
        val expected = golden()
        assertTrue(expected.isNotEmpty())

        val differing = mutableListOf<String>()
        for ((topic, want) in expected) {
            val phrase = Corpus.topicPhrase(topic)
            val got = Corpus.rank(corpus, topic, 8, Corpus.ownSubject(corpus, phrase))
                .map { it.id }.toSet()
            if (got != want) {
                differing += "$topic: +${(got - want).sorted()} -${(want - got).sorted()}"
            }
        }
        assertEquals(
            "Kotlin selects different questions than the Apple ranker:\n  " +
                differing.joinToString("\n  "),
            0, differing.size,
        )
    }

    /**
     * Nineteen of the golden's topics correctly return NOTHING — "Harry Kane" is not
     * in this corpus and the honest answer is nothing, not Spokane and Butane. A
     * golden listing only the topics with results would pass a regression that
     * brought all of those back.
     */
    @Test fun theTopicsThatShouldReturnNothingStillReturnNothing() {
        val corpus = loadCorpus()
        val empties = golden().filter { it.second.isEmpty() }.map { it.first }
        assertTrue(empties.isNotEmpty())
        for (topic in empties) {
            val got = Corpus.rank(corpus, topic, 8, Corpus.ownSubject(corpus, Corpus.topicPhrase(topic)))
            assertTrue(
                "'$topic' should return nothing but returned ${got.map { it.sourceTitle }}",
                got.isEmpty(),
            )
        }
    }
}
