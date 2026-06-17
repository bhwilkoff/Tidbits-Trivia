// Root build file — plugin declarations only; no buildscript block.
// Per-module configuration lives in each module's own build.gradle.kts.

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
