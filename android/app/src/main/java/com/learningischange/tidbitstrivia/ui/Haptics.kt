package com.learningischange.tidbitstrivia.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView
import com.learningischange.tidbitstrivia.data.Store

/**
 * Correct/wrong haptics (parity with iOS Haptics.swift). Uses the platform
 * View feedback so it honors the system Touch-feedback setting; gated on the
 * in-app toggle (Settings → Haptics). CONFIRM/REJECT are API 30+; on API 29 we
 * fall back to the always-present key/long-press constants.
 */
class GameHaptics(private val view: android.view.View, private val enabled: () -> Boolean) {
    private fun fire(modern: Int, legacy: Int) {
        if (!enabled()) return
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) modern else legacy)
    }
    fun correct() = fire(HapticFeedbackConstants.CONFIRM, HapticFeedbackConstants.VIRTUAL_KEY)
    fun wrong() = fire(HapticFeedbackConstants.REJECT, HapticFeedbackConstants.LONG_PRESS)
}

@Composable
fun rememberGameHaptics(store: Store): GameHaptics {
    val view = LocalView.current
    return remember(view) { GameHaptics(view) { store.hapticsEnabled() } }
}
