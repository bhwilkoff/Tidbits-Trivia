package com.learningischange.tidbitstrivia.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// FILL IN: replace with your brand font.
// Drop the .ttf into res/font/ and reference R.font.<name>. Avoid
// downloadable fonts in the splash path — they add a network
// dependency to first paint.
//
// Bundled-font fallback to system-ui:
private val BrandFontFamily = FontFamily.Default

/**
 * Six hierarchy levels (per mobile-first-density-design). Refuse a
 * seventh — if a new level seems necessary, refactor existing ones
 * before adding.
 *
 * Keep these labels stable across iOS / web / Android so design
 * decisions translate. The pixel mapping differs per platform; the
 * NAMES don't.
 */
val AppTypography = Typography(
    displaySmall  = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Bold,   fontSize = 32.sp),  // L1 — page title
    headlineSmall = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Bold,   fontSize = 24.sp),  // L2 — section header
    titleMedium   = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Medium, fontSize = 16.sp),  // L3 — emphasized body
    bodyMedium    = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 14.sp),  // L4 — body
    labelMedium   = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 12.sp),  // L5 — caption
    bodySmall     = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 12.sp),  // L6 — tabular (use tnum modifier)
)
