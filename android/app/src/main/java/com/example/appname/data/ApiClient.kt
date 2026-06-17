package com.example.appname.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.json.Json

/**
 * Shared API client — ALL network calls go through this Hilt
 * singleton. Composables / ViewModels never use HttpClient or
 * OkHttpClient directly.
 *
 * Same architectural rule as iOS APIClient.shared and web js/api.js.
 *
 * When the project uses Supabase + Cloudflare Workers:
 *  - Add SupabaseAuthInterceptor to the OkHttpClient builder so
 *    every Worker call refreshes the JWT first (the cross-platform
 *    "refresh-before-call" rule — see CLAUDE.md).
 *  - Share the OkHttpClient with Coil 3 via Application#sharedOkHttp.
 */
@Singleton
class ApiClient @Inject constructor() {

    private val client = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json(
                Json {
                    ignoreUnknownKeys = true
                    encodeDefaults = false
                },
            )
        }
        // FILL IN: defaultRequest { url(BASE_URL); header("Authorization", ...) }
    }

    suspend inline fun <reified T> get(url: String): T = client.get(url).body()

    suspend inline fun <reified T, reified B : Any> post(url: String, body: B): T =
        client.post(url) {
            contentType(ContentType.Application.Json)
            setBody(body)
        }.body()
}
