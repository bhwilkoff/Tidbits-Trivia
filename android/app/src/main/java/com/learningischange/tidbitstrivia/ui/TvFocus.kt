package com.learningischange.tidbitstrivia.ui

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import com.learningischange.tidbitstrivia.ui.theme.Ink
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/**
 * Android TV / Fire TV support (7th platform).
 *
 * The rule this file exists to satisfy: **on a ten-foot screen, focus does the
 * work.** The focused card IS the chrome. Compose already gives a `clickable`
 * element D-pad focus and fires it on CENTER — measured on a Fire TV, the home
 * screen had 10 focusable nodes and moved focus correctly — but it draws
 * NOTHING, so a player on a couch cannot tell what is selected. That is the
 * whole difference between "runs on a TV" and "is a TV app".
 *
 * The treatment is deliberately not a colour change. Tidbits' cards are already
 * coral / grape / blue / yellow, so any single accent ring disappears against
 * one of them. Scale plus a shadow plus a thick ink ring reads against every
 * fill, which is why brightness is reserved for the focused element rather than
 * spent on the surrounding ones.
 */

/** True on a leanback device. Cached per composition; the mode cannot change. */
@Composable
fun isTv(): Boolean {
    val ctx = LocalContext.current
    return remember(ctx) { isTvDevice(ctx) }
}

fun isTvDevice(ctx: Context): Boolean {
    val ui = ctx.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    if (ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
    // Fire TV reports the leanback feature but has historically not always set
    // the UI mode, so the feature check is the belt to that braces.
    val pm = ctx.packageManager
    return pm.hasSystemFeature("android.software.leanback") ||
        pm.hasSystemFeature("amazon.hardware.fire_tv")
}

/**
 * Give an element a visible focus state on TV. A no-op everywhere else, so the
 * phone and tablet UI is untouched.
 *
 * Apply to the OUTER modifier of a clickable surface. The element must already
 * be focusable (any `clickable` is); this only draws the state.
 */
@Composable
fun Modifier.tvFocus(shape: Shape, enabled: Boolean = true): Modifier {
    if (!enabled || !isTv()) return this
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.045f else 1f, tween(120), label = "tvFocusScale")
    return this
        .onFocusChanged { focused = it.isFocused || it.hasFocus }
        .scale(scale)
        .shadow(if (focused) 18.dp else 0.dp, shape)
        // Two-tone ring: a white band with an ink outline. A single white ring
        // disappears on the white answer cards and a single ink ring disappears
        // on the coral and grape ones — Tidbits has no fill this pair loses to.
        .then(if (focused) Modifier.border(5.dp, Color.White, shape) else Modifier)
        .then(if (focused) Modifier.border(1.5.dp, Ink, shape) else Modifier)
}

/**
 * Overscan padding. TVs crop the outer ~5% of the panel, so a layout drawn to
 * the literal frame edge loses its first and last rows on real hardware — which
 * a screenshot over adb will never show you, because the capture is the
 * framebuffer, not what the panel displays.
 */
@Composable
fun tvOverscan(): Modifier = if (isTv()) Modifier.padding(horizontal = 28.dp, vertical = 20.dp)
                             else Modifier
