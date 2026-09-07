package com.learningischange.tidbitstrivia

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
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
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

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
        // Edge-to-edge WITHOUT androidx.activity's enableEdgeToEdge(). Its EdgeToEdgeApi23/26/29
        // implementations reference Window.setStatusBarColor, Window.setNavigationBarColor and
        // LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES — all deprecated in Android 15, and all three
        // are what Play Console's "app uses deprecated APIs for edge-to-edge" flags. Upgrading the
        // library does not help: activity 1.13.0's EdgeToEdgeApi35 still references them, and R8
        // keeps every API-level branch because the dispatch is at runtime. These two calls are the
        // non-deprecated equivalent; the transparent bars themselves come from Theme.AppName
        // (ignored on API 35+, where edge-to-edge is the enforced default) and the system-bar icon
        // contrast is set from AppTheme, which is the only place that knows the resolved theme.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }
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
        // Push (docs/PUSH-CONTRACT.md): re-upload the FCM token on every launch when
        // notifications are already allowed, which is also what catches a rotated token on a
        // device that never opens the messaging service. The PROMPT is not here — it fires
        // after a Daily, where the ask has a reason.
        lifecycleScope.launch {
            com.learningischange.tidbitstrivia.notifications.PushTokens.uploadTokenIfAllowed(this@MainActivity)
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

        // A shared quiz carries an ID, so it can't collapse to a bare token:
        //   tidbits://quiz/<id>  ·  tidbitstrivia://quiz/<id>
        //   https://tidbitstrivia.com/#/quiz/<id>
        // The https form puts the route in the FRAGMENT, which no intent filter can
        // match on — the filter matches the host and the fragment is parsed here.
        quizIdFrom(uri)?.let { return "quiz/$it" }
        // A shared single question carries an id too: tidbits://item/<id> and the
        // canonical https://tidbitstrivia.com/item/<id> (DEEP_LINKS.md). The https form
        // is a real PATH here, not a fragment, so the existing host-wide App Link filter
        // already matches it — no new intent-filter, and nothing emitted goes undeclared.
        itemIdFrom(uri)?.let { return "item/$it" }
        // The projector's scan-to-join QR: https://tidbitstrivia.com/live/<code> (and
        // tidbits://live/<code>). The token set below only knew five bare words, so
        // "live" fell through and the link launched the app onto Home with nothing.
        liveCodeFrom(uri)?.let { return "live/$it" }

        val token = when (uri.scheme) {
            "tidbits", "tidbitstrivia" -> uri.host
            "https" -> uri.pathSegments.firstOrNull()
            else -> null
        }?.lowercase()
        return token?.takeIf { it in setOf("daily", "night", "party", "create", "settings") }
    }

    private fun liveCodeFrom(uri: android.net.Uri): String? {
        val code = when {
            (uri.scheme == "tidbits" || uri.scheme == "tidbitstrivia") && uri.host == "live" ->
                uri.pathSegments.firstOrNull()
            uri.scheme == "https" && uri.pathSegments.size >= 2 && uri.pathSegments[0] == "live" ->
                uri.pathSegments[1]
            // The web app is hash-routed, so a pasted link may carry #/live/<code>.
            uri.scheme == "https" && uri.fragment?.startsWith("/live/") == true ->
                uri.fragment?.removePrefix("/live/")?.substringBefore('/')
            else -> null
        }
        return code?.trim()?.uppercase()?.takeIf { it.isNotBlank() }
    }

    private fun itemIdFrom(uri: android.net.Uri): String? {
        if ((uri.scheme == "tidbits" || uri.scheme == "tidbitstrivia") && uri.host == "item") {
            return uri.pathSegments.firstOrNull()?.takeIf { it.isNotBlank() }
        }
        if (uri.scheme == "https") {
            return uri.pathSegments.takeIf { it.size >= 2 && it[0] == "item" }?.get(1)
                ?.takeIf { it.isNotBlank() }
        }
        return null
    }

    private fun quizIdFrom(uri: android.net.Uri): String? {
        if ((uri.scheme == "tidbits" || uri.scheme == "tidbitstrivia") && uri.host == "quiz") {
            return uri.pathSegments.firstOrNull()?.takeIf { it.isNotBlank() }
        }
        if (uri.scheme == "https") {
            // Web canonical: .../#/quiz/<id>
            val frag = uri.fragment ?: return uri.pathSegments
                .takeIf { it.size >= 2 && it[0] == "quiz" }?.get(1)
            val parts = frag.trim('/').split('/')
            if (parts.size >= 2 && parts[0] == "quiz") return parts[1].takeIf { it.isNotBlank() }
        }
        return null
    }
}
