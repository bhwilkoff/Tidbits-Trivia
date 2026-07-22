package com.learningischange.tidbitstrivia.data

/** The archive's plain filter set (favorited / missed / mastered), alongside domain +
 *  free-text search — mirrors Apple's `StoryFilter` / web's `filter` param. */
enum class StoryFilter(val label: String) {
    ALL("All"), FAVORITES("★ Favorites"), MISSED("Missed"), MASTERED("Got it")
}

/**
 * The Club Story Archive's read side (docs/CLUB-FEATURES-BUILD.md "Feature 2") — a
 * plain, transparent view over [Store.seenStories]. No ranking model: search is
 * substring match, filters are simple predicates — the corpus stays legible, never an
 * opaque "for you" feed. Android mirror of Apple's `StoryArchive.swift` / web's
 * `StoryArchive` in store.js.
 */
object StoryArchive {
    /** Every seen story, most-recently-encountered first. */
    fun list(store: Store): List<Store.SeenStory> = store.seenStories().values.sortedByDescending { it.lastSeen }

    /** Distinct domains actually present, in canonical [Category] order — filter chips
     *  only ever show domains the player has actually played (never an empty chip). */
    fun domainsSeen(store: Store): List<Category> {
        val present = list(store).map { it.categoryId }.toSet()
        return Category.all.filter { it.id in present }
    }

    /** Plain substring match across prompt/answer/story text — never a relevance model. */
    fun search(store: Store, text: String, domain: String? = null, filter: StoryFilter = StoryFilter.ALL): List<Store.SeenStory> {
        var results = list(store)
        if (domain != null) results = results.filter { it.categoryId == domain }
        results = when (filter) {
            StoryFilter.ALL -> results
            StoryFilter.FAVORITES -> results.filter { it.favorite }
            StoryFilter.MISSED -> results.filter { !it.everCorrect }
            StoryFilter.MASTERED -> results.filter { it.everCorrect }
        }
        val needle = text.trim().lowercase()
        if (needle.isEmpty()) return results
        return results.filter {
            it.prompt.lowercase().contains(needle) || it.answer.lowercase().contains(needle) || it.story.lowercase().contains(needle)
        }
    }

    fun count(store: Store): Int = store.seenStories().size

    /** A genuine one-line sample from the player's own archive (MONETIZATION §4a: "a
     *  real preview, never a nag") — the non-member Records-row + archive pitch. Null
     *  once there's no local story to show (an honest static line covers that case). */
    fun previewLine(store: Store): String? {
        val s = list(store).firstOrNull() ?: return null
        val text = s.story.ifBlank { s.prompt }
        return "“$text” — Club keeps every story you unlock, searchable forever."
    }
}
