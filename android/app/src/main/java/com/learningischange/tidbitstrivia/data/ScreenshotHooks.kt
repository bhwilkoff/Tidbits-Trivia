package com.learningischange.tidbitstrivia.data

import android.content.Intent
import com.learningischange.tidbitstrivia.BuildConfig

/**
 * The Kotlin mirror of Apple's `DebugHooks` screenshot family (docs/STORE-SCREENSHOTS.md §2).
 * Every value is set from a DEBUG-only launch intent and is inert in release, so the store
 * capture run can drive Android to a known screen without a single tap — the same guarantee
 * the Apple sets already had, and the reason the Android shots were the only ones that
 * needed brittle `adb input tap` coordinates.
 *
 *   adb shell am start -n <pkg>/...MainActivity \
 *     --es tidbits_autoplay classic:mixed --ez tidbits_autopilot true --ei tidbits_autopilot_steps 1
 */
object ScreenshotHooks {
    /** "mode:category" — launch straight into a round. */
    var autoplay: Pair<String, String>? = null
        private set

    /** Auto-answer, so a reveal / scorecard can be captured without taps. */
    var autopilot = false
        private set

    /** Take exactly N autopilot actions then STOP, parking the app on that phase. */
    var autopilotSteps: Int? = null
        private set

    /** Answer correctly rather than picking option 0 (which advertises a bad score). */
    var autopilotCorrect = false
        private set

    /** "play" | "records" | "create" — the tab to open on. */
    var initialTab: String? = null
        private set

    /** Insert N synthetic games so Records isn't an empty state in the store shot. */
    var seedRecords: Int? = null
        private set

    var openParty = false
        private set
    var openNightSetup = false
        private set

    /** Join a Tidbits Live / Trivia Night room by code, as `code to displayName`.
     *  Apple already had TIDBITS_LIVE_JOIN; without the Kotlin mirror the only way to
     *  put an Android device in a host's room was blind tapping, so cross-platform
     *  multiplayer was the one feature no harness could actually exercise. */
    var liveJoin: Pair<String, String>? = null
        private set

    /** Draw the autoplay round from ScreenshotQuestions instead of a random corpus pull
     *  (rule R-SHOT-3) — a random draw put a Holocaust question in a listing's reveal slot. */
    var screened = false
        private set

    /** Treat the first-run walkthrough as already seen — a fresh install otherwise opens on it. */
    var skipOnboarding = false
        private set

    /**
     * "clubHub" | "paywall" | "atlas" | "linkWall" | "expeditions" | "storyArchive" |
     * "marathonHistory" | "settings" | "profile" | "leaderboard" | "duels" | "online" —
     * push that destination on launch.
     *
     * ONE string rather than a boolean per surface: the previous set covered only Party
     * and Night setup, so ~10 Club/account screens had no hook at all and the Android
     * sweep silently skipped them — they read as "not covered" in the QA log rather than
     * as passing. A single mapped extra means a new destination costs one line here.
     */
    var openRoute: String? = null
        private set

    fun apply(intent: Intent) {
        if (!BuildConfig.DEBUG) return
        intent.getStringExtra("tidbits_autoplay")?.let { raw ->
            val parts = raw.split(":")
            autoplay = (parts.getOrNull(0) ?: "classic") to (parts.getOrNull(1) ?: "mixed")
        }
        if (intent.hasExtra("tidbits_autopilot")) autopilot = intent.getBooleanExtra("tidbits_autopilot", false)
        if (intent.hasExtra("tidbits_autopilot_steps")) autopilotSteps = intent.getIntExtra("tidbits_autopilot_steps", -1).takeIf { it >= 0 }
        if (intent.hasExtra("tidbits_autopilot_correct")) autopilotCorrect = intent.getBooleanExtra("tidbits_autopilot_correct", false)
        intent.getStringExtra("tidbits_tab")?.let { initialTab = it }
        if (intent.hasExtra("tidbits_seed_records")) seedRecords = intent.getIntExtra("tidbits_seed_records", 0).takeIf { it > 0 }
        if (intent.hasExtra("tidbits_party")) openParty = intent.getBooleanExtra("tidbits_party", false)
        if (intent.hasExtra("tidbits_night_setup")) openNightSetup = intent.getBooleanExtra("tidbits_night_setup", false)
        if (intent.hasExtra("tidbits_skip_onboard")) skipOnboarding = intent.getBooleanExtra("tidbits_skip_onboard", false)
        if (intent.hasExtra("tidbits_screened")) screened = intent.getBooleanExtra("tidbits_screened", false)
        intent.getStringExtra("tidbits_open")?.let { openRoute = it }
        intent.getStringExtra("tidbits_live_join")?.takeIf { it.isNotBlank() }?.let { code ->
            liveJoin = code.trim().uppercase() to
                (intent.getStringExtra("tidbits_live_name")?.takeIf { it.isNotBlank() } ?: "Android")
        }
    }
}
