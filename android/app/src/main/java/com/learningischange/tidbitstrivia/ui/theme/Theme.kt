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

private val BrandLightColors = lightColorScheme(
    primary = BrandPrimary,
    secondary = BrandSecondary,
    tertiary = BrandTertiary,
    background = CreamBg,
    surface = CreamSurface,
    onBackground = Ink,
    onSurface = Ink,
)

private val BrandDarkColors = darkColorScheme(
    primary = BrandPrimary,
    secondary = BrandSecondary,
    tertiary = BrandTertiary,
    background = BrandBackground,
    surface = BrandSurface,
)
