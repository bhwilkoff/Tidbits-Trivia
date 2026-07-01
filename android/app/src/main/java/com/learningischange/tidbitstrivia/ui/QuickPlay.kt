package com.learningischange.tidbitstrivia.ui

import com.learningischange.tidbitstrivia.data.Category
import com.learningischange.tidbitstrivia.data.Mode
import com.learningischange.tidbitstrivia.data.Store
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Quick Play memory + presets (home redesign — rule R-HOME-1). Mirrors the iOS
 * AppStore additions: last-played resolves the Quick Play default, and named
 * presets are a power-user affordance. See docs/HOME-REDESIGN-PROPOSAL.md.
 */
@Serializable
data class GamePreset(val name: String, val modeName: String, val categoryIds: List<String>) {
    val mode: Mode get() = runCatching { Mode.valueOf(modeName) }.getOrNull() ?: Mode.CLASSIC
    val category: Category get() = Category.byId(categoryIds.firstOrNull() ?: "mixed")
}

private val presetJson = Json { ignoreUnknownKeys = true }

/** Everything a Quick Play / Customize game can be — the Daily and networked night are separate. */
val playableModes: List<Mode> = Mode.entries.filter { it != Mode.DAILY && it != Mode.BAR_TRIVIA }
/** The four shown first in the Customize sheet; the rest live under "More modes". */
val coreModes: List<Mode> = listOf(Mode.CLASSIC, Mode.TIME_ATTACK, Mode.SURVIVAL, Mode.STAKE)

fun Store.quickPlay(): Pair<Mode, Category> {
    val m = lastPlayedModeName()?.let { runCatching { Mode.valueOf(it) }.getOrNull() } ?: Mode.CLASSIC
    return m to Category.byId(lastPlayedCategoryId())
}
fun Store.rememberPlay(mode: Mode, category: Category) {
    if (mode != Mode.DAILY) rememberSelection(mode.name, category.id)
}
fun Store.surprise(): Pair<Mode, Category> = playableModes.random() to Category.all.random()

fun Store.presets(): List<GamePreset> =
    runCatching { presetJson.decodeFromString<List<GamePreset>>(presetsJson()) }.getOrDefault(emptyList())
fun Store.savePreset(p: GamePreset) {
    val list = presets().filterNot { it.name.equals(p.name, ignoreCase = true) }.toMutableList()
    list.add(0, p)
    savePresetsJson(presetJson.encodeToString(list.take(5)))
}
fun Store.deletePreset(p: GamePreset) {
    savePresetsJson(presetJson.encodeToString(presets().filterNot { it.name == p.name }))
}
