package com.example.appname.ui.theme

import androidx.compose.ui.graphics.Color

// --- BRAND tokens (UI chrome only — never content meaning) -----------
// FILL IN: replace with your brand palette. Mirror the same hex values
// in /css/styles.css :root and ios/Resources/Design.swift so the three
// platforms render identical chrome.
val BrandPrimary    = Color(0xFFFF5C35)   // CTAs, active states
val BrandSecondary  = Color(0xFF0047FF)   // links, interactive accents
val BrandTertiary   = Color(0xFF8B00FF)   // optional third accent
val BrandBackground = Color(0xFF080810)   // page background
val BrandSurface    = Color(0xFF0D0D1A)   // card / panel surface

// --- SEMANTIC tokens (content only — never chrome) -------------------
// Use these on data-bearing chips, status pills, charts. Keep distinct
// from brand. Add domain-specific tokens here (e.g. WeaponFire) and
// expose via a dedicated AppSemantics object — NEVER through
// colorScheme overrides (Material You opt-in must not change them).
object AppSemantics {
    val Success = Color(0xFF1FB57A)
    val Warning = Color(0xFFFFB020)
    val Error   = Color(0xFFE5484D)
}
