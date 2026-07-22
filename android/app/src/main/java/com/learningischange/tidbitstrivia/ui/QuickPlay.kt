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
data class GamePreset(val name: String, val modeName: String, val categoryIds: List<String>,
                      val modeIds: List<String>? = null) {
    val mode: Mode get() = runCatching { Mode.valueOf(modeName) }.getOrNull() ?: Mode.CLASSIC
    val category: Category get() = Category.byId(categoryIds.firstOrNull() ?: "mixed")
    /** For MIX presets: the modes behind the mix. */
    val modes: List<Mode> get() = (modeIds ?: emptyList()).mapNotNull { runCatching { Mode.valueOf(it) }.getOrNull() }
}

private val presetJson = Json { ignoreUnknownKeys = true }

/** Everything a Quick Play / Customize game can be — the Daily and networked night are
 *  separate; Weak-Spot Arena / Marathon are Club-gated and each has its own Home entry
 *  point (never the free Customize grid / Surprise-Me / remembered default —
 *  docs/CLUB-FEATURES-BUILD.md). */
val playableModes: List<Mode> = Mode.entries.filter { it != Mode.DAILY && it != Mode.BAR_TRIVIA && it != Mode.MIX && it != Mode.WEAK_SPOT && it != Mode.MARATHON }
/** The four shown first in the Customize sheet; the rest live under "More modes". */
val coreModes: List<Mode> = listOf(Mode.CLASSIC, Mode.TIME_ATTACK, Mode.SURVIVAL, Mode.STAKE)

fun Store.quickPlay(): Pair<Mode, Category> {
    val m = lastPlayedModeName()?.let { runCatching { Mode.valueOf(it) }.getOrNull() } ?: Mode.CLASSIC
    return m to Category.byId(lastPlayedCategoryId())
}
fun Store.rememberPlay(mode: Mode, category: Category) {
    // Defense-in-depth: Weak-Spot Arena / Marathon are already excluded from
    // playableModes (so they can't reach this via Quick Play/Customize/Surprise-Me),
    // but never remember either as the Quick Play default even if a future caller
    // passes one directly.
    if (mode != Mode.DAILY && mode != Mode.WEAK_SPOT && mode != Mode.MARATHON) rememberSelection(mode.name, category.id)
}
fun Store.surprise(): Pair<Mode, Category> = playableModes.random() to Category.all.random()

/** Custom Mix memory — so Quick Play can replay the last multi-select. */
fun Store.rememberMix(modes: List<Mode>, category: Category) {
    rememberSelection(Mode.MIX.name, category.id)
    saveMixModes(modes.joinToString(",") { it.name })
}
fun Store.lastMixModes(): List<Mode> =
    (mixModesCsv() ?: "").split(",").mapNotNull { runCatching { Mode.valueOf(it) }.getOrNull() }

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
