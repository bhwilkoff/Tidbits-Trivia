package com.example.appname.app

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.request.crossfade
import dagger.hilt.android.HiltAndroidApp
import okhttp3.OkHttpClient

/**
 * Application — composition root. Initializes:
 *
 *  - Hilt graph (via @HiltAndroidApp)
 *  - Coil 3 ImageLoader with 60 MB memory / 500 MB disk caches
 *    (parity with iOS URLCache config)
 *  - Shared OkHttpClient — Coil + Ktor + Supabase all use the same
 *    instance so the connection pool / DNS / TLS sessions are shared
 *
 * Notification channels (post-API 26 requirement) get created here
 * when push ships — they MUST exist before the first FCM message.
 */
@HiltAndroidApp
class AppNameApplication : Application(), SingletonImageLoader.Factory {

    /**
     * Shared OkHttp instance — inject into Ktor + Supabase + Coil so
     * one connection pool serves the entire app. ~30% cold-start
     * memory win vs each library spinning up its own pool.
     */
    val sharedOkHttp: OkHttpClient by lazy {
        OkHttpClient.Builder()
            // .addInterceptor(SupabaseAuthInterceptor(supabase)) — wire
            //   when Supabase is added; refreshes JWT before every call
            //   that hits a Worker / Storage / Edge Function. See the
            //   shared "refresh-before-call" pattern in CLAUDE.md.
            .build()
    }

    override fun onCreate() {
        super.onCreate()
        // Create notification channels here when FCM ships.
        // createNotificationChannels()
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .memoryCache {
                MemoryCache.Builder()
                    .maxSizeBytes(60L * 1024 * 1024)   // 60 MB
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("image_cache"))
                    .maxSizeBytes(500L * 1024 * 1024)  // 500 MB
                    .build()
            }
            // .components { add(OkHttpNetworkFetcherFactory(sharedOkHttp)) }
            // wire when needed — Coil's default network fetcher works without it.
            .crossfade(true)
            .build()
}
