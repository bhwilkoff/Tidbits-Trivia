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
import com.learningischange.tidbitstrivia.data.Marathon
import com.learningischange.tidbitstrivia.ui.AppRoot
import com.learningischange.tidbitstrivia.ui.theme.AppTheme

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
