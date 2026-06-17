package com.learningischange.tidbitstrivia

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.learningischange.tidbitstrivia.app.AppNameApplication
import com.learningischange.tidbitstrivia.ui.AppRoot
import com.learningischange.tidbitstrivia.ui.theme.AppTheme

/** Single Activity, Compose-only, edge-to-edge. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as AppNameApplication).container
        setContent {
            AppTheme { AppRoot(container.store) }
        }
    }
}
