package com.learningischange.tidbitstrivia.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.learningischange.tidbitstrivia.net.FirebaseNet

/**
 * Is this player a Tidbits Club member? The one gate every Club feature checks
 * (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION §7). Android twin of the Swift
 * EntitlementStore (TidbitsTrivia/Core/Networking/EntitlementStore.swift) and the web
 * mirror (js/entitlement.js) — same isClub gate, same fail-open discipline.
 *
 * Android has no local store yet (Class A = Google Play Billing, a later phase), so —
 * exactly like the web mirror — isClub is purely the REMOTE read: entitlements/{accountKey},
 * written by the Worker after a Merchant-of-Record purchase. Requires a verified-email
 * sign-in; the RTDB rule keys the read on emailOwners/{key} matching the auth token email.
 *
 * Fail OPEN: a transient read miss NEVER revokes Club (a paying member on a flaky
 * connection stays Club). Cache the last-known-good in SharedPreferences (mirror of
 * Duels.kt's init(ctx) pattern) so a returning member is Club instantly, before any
 * network round-trip.
 */
object Entitlement {
    private const val PREFS_NAME = "tidbits.entitlement"
    private const val KEY_IS_CLUB = "isClub"

    private var prefs: SharedPreferences? = null

    /** The gate. Seeded from the cached last-known-good so a returning member is Club
     *  instantly, before any network round-trip. */
    var isClub: Boolean by mutableStateOf(false); private set

    /** Called once from the Application so the cached Club flag survives process death —
     *  mirror of Duels.init(ctx). Must run before the first refresh()/read of isClub. */
    fun init(ctx: Context) {
        prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isClub = prefs?.getBoolean(KEY_IS_CLUB, false) ?: false
    }

    /** True when this record grants an active Club membership. A subscription past
     *  `until` no longer grants; a lifetime (`until == null`) always does. */
    private fun grantsClub(ent: FirebaseNet.EntitlementRecord?): Boolean {
        if (ent == null || ent.tier != "club") return false
        val until = ent.until ?: return true
        return System.currentTimeMillis() < until
    }

    /** Recompute Club status. Safe to call at launch, after sign-in, and after a purchase. */
    suspend fun refresh() {
        if (!PlayerIdentity.signedIn || PlayerIdentity.profileId == null) {
            // Not signed in → no remote entitlement is readable. Don't aggressively revoke
            // a cached true (fail open); it re-confirms on the next signed-in refresh. A
            // fresh anon session with no cache is simply not Club.
            return
        }
        val key = PlayerIdentity.profileId ?: return
        try {
            val ent = FirebaseNet.loadEntitlement(key)
            set(grantsClub(ent))   // a clean read (incl. null -> not club) is authoritative
        } catch (e: Exception) {
            // transient RTDB error -> keep the cached answer (fail open)
        }
    }

    private fun set(club: Boolean) {
        isClub = club
        prefs?.edit()?.putBoolean(KEY_IS_CLUB, club)?.apply()
    }

    /** Sign-out clears the cached Club state (the next person on this device isn't you). */
    fun clearOnSignOut() { set(false) }
}
