package com.example.appname

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.example.appname.ui.AppRoot
import com.example.appname.ui.theme.AppTheme
import dagger.hilt.android.AndroidEntryPoint

/**
 * Single Activity — Compose-only, no Fragments, no AppCompat.
 *
 * Hosts the NavHost via [AppRoot]; handles edge-to-edge, splash screen,
 * and deep-link dispatch. Per ANDROID-DESIGN §0, every interaction
 * exhausts native M3 components first.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Splash Screen API — call BEFORE super.onCreate(). Android 12+
        // composites this over our themed window for the first frame.
        installSplashScreen()
        super.onCreate(savedInstanceState)

        // Mandatory at targetSdk >= 35; Android 16 ignores opt-out.
        // Scaffold + WindowInsets do the right thing from here.
        enableEdgeToEdge()

        // Deep link dispatch — supabase OAuth callbacks + app-internal
        // routes. Switch by scheme, never by URL shape (see iOS lesson:
        // .onOpenURL fires for both Universal Links and custom schemes,
        // and the equivalent confusion existed across deep-link surfaces).
        handleDeepLink(intent)

        setContent {
            AppTheme {
                AppRoot()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        // supabase.handleDeeplinks(intent) — wire when Supabase ships
        when (uri.scheme) {
            "https" -> routeUniversalLink(uri)
            "appname" -> routeCustomScheme(uri)
        }
    }

    private fun routeUniversalLink(uri: android.net.Uri) {
        // FILL IN: route by uri.pathSegments
    }

    private fun routeCustomScheme(uri: android.net.Uri) {
        // FILL IN: route by uri.host / uri.pathSegments
    }
}
