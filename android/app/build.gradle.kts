// :app — composition root. v1 is deliberately lean: manual DI + sealed
// Route + BackHandler (android-production-gotchas), in-memory corpus from a
// bundled JSON asset. Hilt / Nav3 / Room / Ktor arrive when complexity
// demands them, not before.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.learningischange.tidbitstrivia"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.learningischange.tidbitstrivia"
        minSdk = 29
        targetSdk = 36
        versionCode = 22
        versionName = "1.2.9"   // lockstep with iOS MARKETING_VERSION (X.Y.Z, bump every ship)
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }

    packaging {
        resources { excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "/META-INF/LICENSE*") }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))
    implementation(libs.bundles.compose.core)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    implementation(libs.bundles.adaptive)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)

    implementation(libs.coroutines.core)
    implementation(libs.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.datastore.preferences)
    implementation(libs.okhttp)
    implementation(libs.splashscreen)
    implementation(libs.coil.compose)         // Picture ID (Q7) image loading
    implementation(libs.coil.network.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
}
