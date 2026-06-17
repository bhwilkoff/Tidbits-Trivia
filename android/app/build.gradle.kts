// :app — composition root. Manifest, R8 config, all features.
// Modular split (core/* + feature/*) is the next step as the app grows.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.example.appname"  // FILL IN: your reverse-DNS package
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.appname"  // FILL IN
        minSdk = 29                            // Android 10 — >95% device coverage in 2026
        targetSdk = 36                         // bump to 37 when Android 17 ships + Play forces
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }

        // FILL IN: Google sign-in client ID (Web OAuth client created in GCP).
        // Keep secrets out of git — read from gradle.properties.
        buildConfigField(
            "String",
            "GOOGLE_WEB_CLIENT_ID",
            "\"${providers.gradleProperty("GOOGLE_WEB_CLIENT_ID").orNull ?: ""}\"",
        )
    }

    signingConfigs {
        // Upload signing config — keystore + creds live in gradle.properties
        // (git-excluded). Play App Signing handles the production key.
        create("release") {
            val keystorePath = providers.gradleProperty("UPLOAD_KEYSTORE_PATH").orNull
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = providers.gradleProperty("UPLOAD_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.gradleProperty("UPLOAD_KEY_ALIAS").orNull
                keyPassword = providers.gradleProperty("UPLOAD_KEY_PASSWORD").orNull
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
        }
        release {
            // R8 always on for release — single highest-impact perf knob.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/LICENSE*",
            )
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    // Compose BOM — pins ui / foundation / material together
    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))
    implementation(libs.bundles.compose.core)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // Adaptive layouts (tablet + Chromebook from day one per ANDROID-DESIGN §6.6)
    implementation(libs.bundles.adaptive)

    // Activity + lifecycle (edge-to-edge + predictive back)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)

    // Navigation 3
    implementation(libs.bundles.nav3)
    implementation(libs.hilt.navigation.compose)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // Coroutines + serialization
    implementation(libs.coroutines.core)
    implementation(libs.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    // Persistence: Room + DataStore + Tink (encrypted secrets)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.datastore.preferences)
    implementation(libs.tink.android)

    // Image loading
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    // Networking — OkHttp shared with Coil; Ktor on top
    implementation(libs.okhttp)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.json)

    // Auth — Credential Manager + Google one-tap. Wire Supabase or your
    // own backend on top.
    implementation(libs.credentials)
    implementation(libs.credentials.play.services)
    implementation(libs.googleid)

    // Supabase (uncomment if your project uses it)
    // implementation(platform(libs.supabase.bom))
    // implementation(libs.supabase.auth)
    // implementation(libs.supabase.postgrest)
    // implementation(libs.supabase.compose.auth)

    // Biometric (sensitive Profile actions)
    implementation(libs.biometric.compose)

    // Splash screen API
    implementation(libs.splashscreen)

    // Tests
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.turbine)
    testImplementation(libs.mockk)

    androidTestImplementation(libs.junit.ext)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation(libs.compose.ui.test.junit4)
}
