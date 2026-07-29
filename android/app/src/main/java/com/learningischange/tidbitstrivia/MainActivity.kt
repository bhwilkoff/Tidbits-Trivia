package com.learningischange.tidbitstrivia

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.learningischange.tidbitstrivia.app.AppNameApplication
import com.learningischange.tidbitstrivia.data.Entitlement
import com.learningischange.tidbitstrivia.data.Expeditions
import com.learningischange.tidbitstrivia.data.Marathon
import com.learningischange.tidbitstrivia.ui.AppRoot
import com.learningischange.tidbitstrivia.ui.theme.AppTheme

/** Synthetic history so the Records store shot isn't an empty state. Only ever writes into
 *  an EMPTY store, so it can never touch a real player's data (mirrors Apple's seeder). */
private fun seedRecordsForScreenshots(store: com.learningischange.tidbitstrivia.data.Store, n: Int) {
    if (!BuildConfig.DEBUG || store.records().isNotEmpty()) return
    val modes = listOf("classic", "timeAttack", "survival", "stake", "sweep", "oddOneOut", "ladder")
    val cats = listOf("history", "science", "geography", "arts", "screen", "music", "sports", "business", "mixed")
    val now = System.currentTimeMillis()
    for (i in 0 until n) {
        val total = 7 + (i % 4)
        val correct = maxOf(1, total - (i % 5))
        store.addRecord(
            com.learningischange.tidbitstrivia.data.Store.Rec(
                mode = modes[i % modes.size], categoryId = cats[i % cats.size],
                score = 40 + (i * 37) % 120, correct = correct, total = total,
                maxStreak = correct, day = "", at = now - i * 3_600_000L,
            ),
            countsForStreak = false,
        )
    }
    com.learningischange.tidbitstrivia.data.PlayerIdentity.seedForScreenshots(streak = 12, longest = 27, games = n)
}

/** Single Activity, Compose-only, edge-to-edge. */
class MainActivity : ComponentActivity() {
    // Deep-link route parsed from the launching/new intent, drained by AppRoot.
    private val deepLink = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val store = (application as AppNameApplication).container.store
        deepLink.value = routeFor(intent)
        // DEBUG-only store-screenshot hooks (docs/STORE-SCREENSHOTS.md §2) — the Kotlin
        // mirror of Apple's DebugHooks family, so an Android capture run is as autonomous
        // as the Apple ones instead of relying on blind `adb input tap` coordinates.
        com.learningischange.tidbitstrivia.data.ScreenshotHooks.apply(intent)
        if (com.learningischange.tidbitstrivia.data.ScreenshotHooks.skipOnboarding) store.setOnboarded(true)
        com.learningischange.tidbitstrivia.data.ScreenshotHooks.seedRecords?.let { seedRecordsForScreenshots(store, it) }
        // DEBUG-only env hook (no-op in release): `--ez tidbits_club_debug true` forces
        // Entitlement.isClub so Club features (Weak-Spot Arena, etc.) are verifiable on
        // the emulator pre-launch, with no real purchase (docs/CLUB-FEATURES-BUILD.md).
        if (intent.hasExtra("tidbits_club_debug")) {
            Entitlement.setDebugForceClub(intent.getBooleanExtra("tidbits_club_debug", false))
        }
        // DEBUG-only env hook (no-op in release): `--ei marathon_len <n>` shortens a
        // Marathon run so it can be played to completion on the emulator — production
        // always sees the full 200 (docs/CLUB-FEATURES-BUILD.md "Feature 3").
        if (BuildConfig.DEBUG && intent.hasExtra("marathon_len")) {
            Marathon.debugLengthOverride = intent.getIntExtra("marathon_len", 0).takeIf { it > 0 }
        }
        // DEBUG-only env hook (no-op in release): `--ez expedition_force_pass true` makes
        // a played Expedition stage always record as a full pass regardless of score —
        // verification-only, mirrors Apple's TIDBITS_EXPEDITION_FORCE_PASS
        // (docs/CLUB-FEATURES-BUILD.md "Feature 5").
        if (BuildConfig.DEBUG && intent.hasExtra("expedition_force_pass")) {
            Expeditions.debugForcePass = intent.getBooleanExtra("expedition_force_pass", false)
        }
        setContent {
            var dynamic by remember { mutableStateOf(store.dynamicColorEnabled()) }
            AppTheme(dynamicColor = dynamic) {
                AppRoot(
                    store = store,
                    dynamicColor = dynamic,
                    onDynamicColor = { dynamic = it; store.setDynamicColorEnabled(it) },
                    deepLink = deepLink.value,
                    onDeepLinkConsumed = { deepLink.value = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLink.value = routeFor(intent)
    }

    // tidbits://<route> and https://tidbitstrivia.com/<route> both map to a
    // single route token AppRoot understands (DEEP_LINKS.md). App Shortcuts
    // launch via these same intents.
    private fun routeFor(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        val token = when (uri.scheme) {
            "tidbits" -> uri.host
            "https" -> uri.pathSegments.firstOrNull()
            else -> null
        }?.lowercase()
        return token?.takeIf { it in setOf("daily", "night", "party", "create", "settings") }
    }
}
