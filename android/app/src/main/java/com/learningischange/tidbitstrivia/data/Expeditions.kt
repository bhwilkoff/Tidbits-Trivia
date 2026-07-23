package com.learningischange.tidbitstrivia.data

/** One themed stage inside an Expedition — a normal category/difficulty-band round the
 *  EXISTING engine already plays (`Mode.CLASSIC`, via [Expeditions.startStage]). NOT a
 *  new game mode. The taxonomy ([Category.all]) is FLAT — no sub-domain like "1920s" or
 *  "South America" — so stages within one Expedition differentiate by DIFFICULTY BAND,
 *  not sub-category (same constraint the Knowledge Atlas hit; see
 *  docs/CLUB-FEATURES-BUILD.md "Feature 5"). Android mirror of Apple's `ExpeditionStage`
 *  (Core/Models/ExpeditionModels.swift) / web's stage shape in store.js. */
data class ExpeditionStage(
    val index: Int,
    val title: String,
    val blurb: String,
    val categoryId: String,
    val difficultyRange: IntRange,
    val questionCount: Int = 10,
    /** Correct answers needed (out of [questionCount]) to advance. */
    val passBar: Int = 6,
)

/** A curated multi-stage campaign through one domain — the portable shape other
 *  platforms mirror (Apple `ExpeditionModels.swift` / web `Expeditions` in store.js).
 *  Adding an expedition is additive: append to [Expeditions.all]; no client change
 *  needed. */
data class Expedition(
    val id: String,
    val title: String,
    val subtitle: String,
    /** [Category.id] this expedition is themed around (icon/color only — stages carry
     *  their own [ExpeditionStage.categoryId], usually the same domain). */
    val domain: String,
    /** Portable icon token (mirrors Apple's SF Symbol name) — kept for cross-platform
     *  data-shape parity; Android renders the domain via [categoryIcon] instead (native
     *  idiom), so this is metadata only. */
    val symbol: String,
    val stages: List<ExpeditionStage>,
) {
    val stageCount: Int get() = stages.size
}

/** One stage's outcome inside an in-progress Expedition — the progress JSON unit
 *  (mirrors Apple's `ExpeditionStageResult` / web's per-stage record). */
data class ExpeditionStageResult(val stageIndex: Int, val passed: Boolean, val correct: Int, val total: Int)

/** One in-progress Expedition. Unlike Marathon's at-most-one run, a player can pursue
 *  SEVERAL campaigns at once — keyed by [expeditionId], not a singleton. Persisted after
 *  every stage attempt ([Store.saveExpeditionProgress]) so a player can leave and come
 *  back over days or weeks. */
data class ExpeditionProgress(
    val expeditionId: String,
    val currentStageIndex: Int = 0,
    val stageResults: List<ExpeditionStageResult> = emptyList(),
    val startedAt: Long,
    val lastPlayedAt: Long,
)

/** A completed Expedition — permanent (docs/CLUB-FEATURES-BUILD.md "Feature 5").
 *  Written once the LAST stage passes; the in-progress [ExpeditionProgress] row is
 *  deleted at the same time (mirrors Marathon's finish -> history + clear-the-run). */
data class ExpeditionCertificate(
    val expeditionId: String,
    val domain: String,
    val title: String,
    val completedAt: Long,
    val totalScore: Int,
    val stagesCompleted: Int,
)

/**
 * Generates and tracks Club Expeditions — multi-week structured campaigns through a
 * single domain (docs/CLUB-FEATURES-BUILD.md "Feature 5"). NOT a new game engine: every
 * stage routes into the EXISTING `Mode.CLASSIC` launch path via a category +
 * difficulty-band filtered question set drawn fresh from the bundled corpus. Unlike
 * Marathon's at-most-one run, several expeditions may be in progress at once — each
 * tracked by its own [ExpeditionProgress] row, keyed by [Expedition.id]. Android mirror
 * of Apple's `Expeditions.swift` (Core/Store) / web's `Expeditions` in store.js.
 */
object Expeditions {
    /** DEBUG-only verification hook (BuildConfig.DEBUG-gated; set from MainActivity's
     *  `expedition_force_pass` intent extra), mirroring Apple's
     *  TIDBITS_EXPEDITION_FORCE_PASS — a played stage always records as a full pass
     *  regardless of score, so a stage/campaign can be advanced quickly on the emulator
     *  without needing autopilot to answer every MCQ correctly. No-op in production
     *  (only ever read behind `BuildConfig.DEBUG` in AppRoot's GameScreen). */
    var debugForcePass: Boolean = false

    /** Start with 2-3 hand-defined campaigns (design spec) — the SAME 3 as Apple/web,
     *  7 stages each, differing by DIFFICULTY BAND (the taxonomy is flat). The shape
     *  allows adding more without any client change. */
    val all: List<Expedition> = listOf(
        Expedition(
            id = "20th-century", title = "The 20th Century",
            subtitle = "A hundred years, decade by decade — from the Great War to the dot-com boom.",
            domain = "history", symbol = "scroll.fill",
            stages = listOf(
                ExpeditionStage(0, "Turn of the Century", "Where it all began — the basics of a hundred years.", "history", 1..2),
                ExpeditionStage(1, "The Great Wars", "Two wars that reshaped the century.", "history", 1..3),
                ExpeditionStage(2, "The Cold War Era", "A world split in two.", "history", 2..3),
                ExpeditionStage(3, "Movements & Milestones", "Civil rights, independence, revolutions.", "history", 2..4),
                ExpeditionStage(4, "Leaders & Turning Points", "The decisions that moved history.", "history", 3..4),
                ExpeditionStage(5, "The Wider Century", "Everything else the timeline holds.", "history", 3..5),
                ExpeditionStage(6, "The Historian's Final Exam", "The century's hardest corners.", "history", 4..5),
            ),
        ),
        Expedition(
            id = "around-the-world", title = "Around the World",
            subtitle = "A geography trek from the basics of the map to its far corners.",
            domain = "geography", symbol = "globe.americas.fill",
            stages = listOf(
                ExpeditionStage(0, "The Basics of the Map", "Continents, oceans, and the big picture.", "geography", 1..2),
                ExpeditionStage(1, "Capitals & Borders", "Where the lines are drawn.", "geography", 1..3),
                ExpeditionStage(2, "Rivers, Ranges & Deserts", "The planet's physical geography.", "geography", 2..3),
                ExpeditionStage(3, "Nations & Peoples", "Who lives where, and why.", "geography", 2..4),
                ExpeditionStage(4, "Cities of the World", "The places everyone's heard of.", "geography", 3..4),
                ExpeditionStage(5, "The Far Corners", "The places most people haven't.", "geography", 3..5),
                ExpeditionStage(6, "World-Class", "Geography's hardest questions.", "geography", 4..5),
            ),
        ),
        Expedition(
            id = "scientific-record", title = "The Scientific Record",
            subtitle = "From first principles to the frontier — the story of how we know what we know.",
            domain = "science", symbol = "atom",
            stages = listOf(
                ExpeditionStage(0, "First Principles", "The fundamentals everyone starts with.", "science", 1..2),
                ExpeditionStage(1, "Matter & Energy", "Physics and chemistry, from the ground up.", "science", 1..3),
                ExpeditionStage(2, "Life Itself", "Biology's big ideas.", "science", 2..3),
                ExpeditionStage(3, "The Great Discoveries", "The breakthroughs that changed everything.", "science", 2..4),
                ExpeditionStage(4, "The Scientists Behind It", "The people who did the work.", "science", 3..4),
                ExpeditionStage(5, "The Frontier", "Where the science is still being written.", "science", 3..5),
                ExpeditionStage(6, "The Comprehensive Exam", "Science's deepest cuts.", "science", 4..5),
            ),
        ),
    )

    fun named(id: String): Expedition? = all.firstOrNull { it.id == id }

    /** Every catalog expedition, paired with its progress row if one exists. */
    fun available(store: Store): List<Pair<Expedition, ExpeditionProgress?>> {
        val rows = store.expeditionProgress()
        return all.map { exp -> exp to rows[exp.id] }
    }

    fun progress(store: Store, expeditionId: String): ExpeditionProgress? = store.expeditionProgress()[expeditionId]

    /** The question set for one stage — a fresh, difficulty-banded pull from the
     *  bundled corpus each attempt (a stage is replayable on a miss, so there's no
     *  "seen" exclusion the way a normal round has). Never-empty: relaxes to the whole
     *  category pool if the difficulty band comes up thin. */
    fun startStage(expedition: Expedition, stageIndex: Int): List<Question> {
        val stage = expedition.stages.firstOrNull { it.index == stageIndex } ?: return emptyList()
        val overfetch = maxOf(stage.questionCount * 8, 80)
        val pool = Corpus.pull(stage.categoryId, emptySet(), overfetch)
        var banded = pool.filter { it.difficulty in stage.difficultyRange }
        if (banded.size < stage.questionCount) banded = pool
        return banded.shuffled().take(stage.questionCount)
    }

    /** A stage just finished — pass advances (and unlocks the next stage); the LAST
     *  stage passing writes the permanent certificate and clears the in-progress row
     *  (mirrors Marathon's finish). Fail leaves progress exactly where it was — the
     *  player stays on the same stage, "try again." */
    fun recordStageResult(
        store: Store, expedition: Expedition, stageIndex: Int, correct: Int, total: Int,
    ): Pair<Boolean, ExpeditionCertificate?> {
        val stage = expedition.stages.firstOrNull { it.index == stageIndex } ?: return false to null
        val now = System.currentTimeMillis()
        val existing = store.expeditionProgress()[expedition.id]
        val passed = correct >= stage.passBar
        val results = (existing?.stageResults ?: emptyList()).filterNot { it.stageIndex == stageIndex } +
            ExpeditionStageResult(stageIndex, passed, correct, total)
        val nextIndex = if (passed) maxOf(existing?.currentStageIndex ?: 0, stageIndex + 1) else (existing?.currentStageIndex ?: 0)
        val updated = ExpeditionProgress(expedition.id, nextIndex, results, existing?.startedAt ?: now, now)

        if (!passed) { store.saveExpeditionProgress(updated); return false to null }
        if (stageIndex < expedition.stages.size - 1) { store.saveExpeditionProgress(updated); return true to null }

        // Final stage passed — write the certificate, retire the progress row.
        val totalScore = results.sumOf { it.correct }
        val cert = ExpeditionCertificate(expedition.id, expedition.domain, expedition.title, now, totalScore, expedition.stages.size)
        store.appendExpeditionCertificate(cert)
        store.deleteExpeditionProgress(expedition.id)
        return true to cert
    }

    /** Every completed Expedition, most recent first — the permanent history (the
     *  Completed/certificates shelf). */
    fun certificates(store: Store): List<ExpeditionCertificate> = store.expeditionCertificates()

    /** A real, concrete illustration (MONETIZATION §4a: "a real preview, never a nag").
     *  Mirrors the Apple/web copy verbatim — the empty/first-run line from the design
     *  spec doubles as the non-member pitch since the hub/map are a real preview
     *  reachable by everyone. */
    fun previewLine(): String =
        "Pick an expedition — a guided journey through a subject, one stage at a time, at your own pace."
}
