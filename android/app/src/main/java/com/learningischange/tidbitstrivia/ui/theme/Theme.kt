package com.learningischange.tidbitstrivia.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext

/**
 * App theme — brand-first by default; dynamic color (Material You)
 * opt-in only.
 *
 * Tonal elevation tokens (surface / surfaceContainer / surfaceContainerLow
 * etc.) live in MaterialTheme.colorScheme — use those for chrome
 * elevation. Content surfaces stay at `surface` flat per the binding
 * design rule "tonal elevation = navigation chrome only".
 *
 * Pass `dynamicColor = true` from Settings when the user enables
 * "Use system colors" — overrides `primary` only on Android 12+;
 * the [AppSemantics] tokens never change.
 */
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        darkTheme -> BrandDarkColors
        else -> BrandLightColors
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        content = content,
    )
}

// The brand fills (coral/blue/grape) are all dark/saturated enough that white is
// the correct "on" color in BOTH themes. Setting these explicitly keeps default
// Buttons (e.g. "Play Again") readable in dark mode, where the M3 default "on"
// color would otherwise resolve dark → dark-text-on-bright-button.
private val BrandLightColors = lightColorScheme(
    primary = BrandPrimary,
    onPrimary = Color.White,
    secondary = BrandSecondary,
    onSecondary = Color.White,
    tertiary = BrandTertiary,
    onTertiary = Color.White,
    background = CreamBg,
    surface = CreamSurface,
    onBackground = Ink,
    onSurface = Ink,
)

private val BrandDarkColors = darkColorScheme(
    primary = BrandPrimary,
    onPrimary = Color.White,
    secondary = BrandSecondary,
    onSecondary = Color.White,
    tertiary = BrandTertiary,
    onTertiary = Color.White,
    background = BrandBackground,
    surface = BrandSurface,
)

// --- Contrast-safe accent helpers (used where a Pops accent meets text) ---

// Text color to place ON an accent FILL (e.g. a category level badge): ink on
// light fills (yellow/mint), white on dark fills (coral/blue/grape).
fun onAccent(fill: Color): Color = if (fill.luminance() > 0.55f) Ink else Color.White

// An accent color used AS text on the page canvas. Bright accents (yellow/mint)
// are illegible on the cream light canvas, so darken them toward ink for light
// mode; on the dark canvas the vivid accent reads fine as-is.
@Composable
fun accentText(c: Color): Color =
    if (isSystemInDarkTheme()) c else lerp(c, Ink, 0.45f)
