package com.learningischange.tidbitstrivia.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The relevance FLOOR, measured by play-testing the 984 most-viewed Wikipedia
 * articles through the shipped Apple assembly on the simulator: 49.8% of every
 * question Create served was about something other than what the player typed.
 * Each case below is one of the measured failures.
 *
 * Mirrors TidbitsTriviaTests/CreateRelevanceTests.swift, windows/.../
 * CreateRelevanceTest.cs and tools/create/web-mirror-check.mjs — if these four
 * disagree, the same topic returns a different quiz per platform, which is the
 * one thing the six-platform contract does not allow.
 *
 * These run on the JVM: the functions under test are pure string logic and touch
 * no SQLite, which is exactly why they were factored out that way.
 */
class CreateTopicDriftTest {

    private fun tier(
        title: String,
        topic: String,
        prompt: String = "",
        tags: List<String> = emptyList(),
        guardNames: Boolean = false,
    ): Int? = Corpus.tier(
        title, prompt, tags,
        Corpus.topicTokens(topic), Corpus.topicPhrase(topic), guardNames,
    )

    /** The single most common failure: the typed word inside a longer word. */
    @Test fun aWordInsideALongerWordIsNotAMatch() {
        assertTrue(Corpus.containsWord("art deco", "art"))
        assertFalse(Corpus.containsWord("mozart", "art"))
        assertFalse(Corpus.containsWord("hansel and gretel", "ansel"))
        assertFalse(Corpus.containsWord("spokane washington", "kane"))
        assertFalse(Corpus.containsWord("indianapolis", "india"))
    }

    /** Nothing here is about Harry Kane, and the honest answer is nothing. */
    @Test fun aTopicTheCorpusDoesNotKnowIsRejectedRatherThanApproximated() {
        assertNull(tier("Spokane, Washington", "Harry Kane"))
        assertNull(tier("Butane", "Harry Kane"))
        assertNull(tier("Harry Potter and the Cursed Child", "Harry Kane"))
    }

    /** The owner's example, one layer down: "Denver" is a place in this corpus,
     *  so a bare two-word title containing it is a different person. */
    @Test fun aDifferentPersonWhoseNameContainsThePlaceIsRejected() {
        assertNull(tier("Bob Denver", "Denver", guardNames = true))
        assertNull(tier("Denver Pyle", "Denver", guardNames = true))
        assertNotNull(tier("Denver International Airport", "Denver", guardNames = true))
    }

    /** ...and only then. "Potter" is not a subject in its own right, so a player
     *  typing it means Harry Potter and must not be left with nothing. */
    @Test fun theSurnameGuardDoesNotFireWhenTheWordIsNotItsOwnSubject() {
        assertNotNull(tier("Harry Potter", "Potter"))
    }

    /** Wikipedia categories mean "about" only in their agentive form. */
    @Test fun onlyAgentiveCategoryTagsAdmitARow() {
        assertNotNull(tier("Thriller (album)", "Michael Jackson",
            tags = listOf("Albums produced by Michael Jackson")))
        assertNull(tier("Kristin Cavallari", "Denver", tags = listOf("Actresses from Denver")))
        assertNull(tier("Neil Sedaka", "Abraham Lincoln",
            tags = listOf("Abraham Lincoln High School (Brooklyn) alumni")))
    }

    /** A tag connection is real but INVISIBLE — the question never says so — and
     *  must rank below anything the player can actually see the topic in. */
    @Test fun anAgentiveTagRanksBelowATitleMatch() {
        val byTag = tier("Bad (album)", "Michael Jackson",
            tags = listOf("Albums produced by Michael Jackson"))
        val byTitle = tier("Dangerous (Michael Jackson album)", "Michael Jackson")
        assertNotNull(byTag); assertNotNull(byTitle)
        assertTrue(byTag!! < byTitle!!)
    }

    @Test fun aDisambiguatorIsNotATopicWord() {
        assertEquals("masters of the universe",
            Corpus.topicPhrase("Masters of the Universe (2026 film)"))
        assertFalse(Corpus.topicTokens("Backrooms (film)").contains("film"))
    }

    /** The phrase keeps its stopwords and its order — the significant-token list
     *  can never reconstruct "masters of the universe". */
    @Test fun thePhraseSurvivesStopwordRemoval() {
        assertEquals("world war ii", Corpus.topicPhrase("World War II"))
        assertEquals(3, tier("Masters of the Universe", "Masters of the Universe (2026 film)"))
    }

    @Test fun theSubjectItselfOutranksAContainingTitle() {
        assertEquals(3, tier("Denver", "Denver"))
        assertEquals(2, tier("Denver International Airport", "Denver"))
    }
}
