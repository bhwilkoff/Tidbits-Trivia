package com.learningischange.tidbitstrivia.notifications

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import com.learningischange.tidbitstrivia.data.PlayerIdentity
import com.learningischange.tidbitstrivia.data.Store
import kotlinx.coroutines.tasks.await

/**
 * Android push registration (docs/PUSH-CONTRACT.md) — the FCM leg of the three-legged
 * $0 sender. Asks for POST_NOTIFICATIONS *with context* (after a Daily, never on cold
 * launch, per the contract's client-behaviour rule), fetches the FCM registration token
 * and writes it to the owner-only `pushTokens/{authUid}/android` node.
 *
 * Inert but harmless until the owner adds the FCM service account secret — the token is
 * captured and stored either way; nothing sends until the cron has credentials.
 */
object PushTokens {
    private const val PREFS = "tidbits.push"
    private const val ASKED = "asked"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Whether the runtime prompt has already been shown, so we ask at most once. */
    fun hasAsked(ctx: Context) = prefs(ctx).getBoolean(ASKED, false)

    private fun granted(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Ask once (API 33+ needs the runtime permission; below that notifications are granted
     * at install), then upload the token. Call after a Daily completes.
     *
     * The permission result arrives asynchronously on the Activity, so the upload is NOT
     * chained to it — `uploadTokenIfAllowed` runs on the next launch as well, which is also
     * what re-uploads a ROTATED token. One code path covers both.
     */
    fun requestIfNeeded(activity: Activity) {
        if (!granted(activity) && !hasAsked(activity)) {
            prefs(activity).edit().putBoolean(ASKED, true).apply()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ActivityCompat.requestPermissions(
                    activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8801)
            }
        }
    }

    /** Fetch + store the FCM token when notifications are allowed AND the player has not
     *  opted out. Safe to call on launch — the opt-out check belongs here rather than at
     *  the call sites, or a launch would quietly re-register a token the player deleted. */
    suspend fun uploadTokenIfAllowed(ctx: Context) {
        if (!granted(ctx)) return
        if (!Store(ctx).remindersEnabled()) return
        runCatching {
            val token = FirebaseMessaging.getInstance().token.await()
            PlayerIdentity.savePushToken(token, "android")
        }.onFailure { android.util.Log.w("Push", "FCM token unavailable: ${it.message}") }
    }

    /** In-app opt-out (App Store 4.5.4 / the same courtesy on Play): drop the token node. */
    suspend fun disable() {
        PlayerIdentity.clearPushToken("android")
    }
}
