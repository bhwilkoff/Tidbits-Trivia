package com.example.appname

import com.example.appname.data.ApiClient
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * Trivial smoke test — proves the JVM test pipeline is wired so
 * `./gradlew :app:testDebugUnitTest` produces a green report on
 * first clone. Replace as the data layer grows.
 *
 * For ViewModel + Flow tests, pull in Turbine (already in the
 * version catalog) — pattern lives in `rcosteira79/android-skills`
 * (the testing track).
 */
class ApiClientTest {
    @Test
    fun `ApiClient instantiates`() {
        val client = ApiClient()
        assertNotNull(client)
    }
}
