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
