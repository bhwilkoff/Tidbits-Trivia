package com.learningischange.tidbitstrivia.ui.theme

import androidx.compose.ui.graphics.Color

// Brand palette — token parity with the Apple Design.swift / web :root.
// Android keeps its own idiom (Material components) but the same hues.
val BrandPrimary = Color(0xFFFF5C5C)   // coral
val BrandSecondary = Color(0xFF2D5BFF) // blue
val BrandTertiary = Color(0xFF8B5CF6)  // grape
val BrandBackground = Color(0xFF141210)
val BrandSurface = Color(0xFF1E1B18)

// Cream surfaces for the (default) light theme.
val CreamBg = Color(0xFFFBF3E4)
val CreamSurface = Color(0xFFFFFFFF)
val Ink = Color(0xFF1A1714)

object Pops {
    val coral = Color(0xFFFF5C5C)
    val blue = Color(0xFF2D5BFF)
    val yellow = Color(0xFFFFC93C)
    val mint = Color(0xFF2FCB8A)
    val grape = Color(0xFF8B5CF6)
    val pink = Color(0xFFFF5DA2)
    val teal = Color(0xFF13B6C9) // sweep mode accent
    val all = listOf(coral, blue, yellow, mint, grape, pink)
    fun at(i: Int) = all[((i % all.size) + all.size) % all.size]
}

object AppSemantics {
    val Success = Color(0xFF2FCB8A)
    val Warning = Color(0xFFFFC93C)
    val Error = Color(0xFFFF5C5C)
}
