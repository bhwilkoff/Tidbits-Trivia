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
 * EntitlementStore (TidbitsTrivia/Core/Networking/EntitlementStore.swift) and the
 * Windows EntitlementStore.cs — same isClub gate, same fail-open discipline.
 *
 * Two independent sources, per Decision 047:
 *  - **Class A (local store):** Google Play Billing, verified on-device, authoritative,
 *    works offline. Provided by [Billing] (Phase 2) via [localCheck] so this object never
 *    imports the billing client directly.
 *  - **Class B (remote):** a web purchase the Worker wrote to `entitlements/{accountKey}`.
 *    Read-only for the client; requires a verified-email sign-in (the rule enforces it).
 *
 * `isClub = localStoreEntitled || remoteEntitled`.
 *
 * Fail OPEN: a transient read miss NEVER revokes Club (a paying member on a flaky
 * connection stays Club), and an unknown local signal (Play not yet connected) NEVER
 * revokes a cached true either. Cache the last-known-good in SharedPreferences (mirror of
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

    /** The Billing adapter installs this in Phase 2 ([Billing.start]). Returns the locally-
     *  proven state:
     *   - `true`  — an owned, acknowledged, non-expired Club purchase exists.
     *   - `false` — the store definitively reports no Club entitlement.
     *   - `null`  — unknown (Play not connected yet, or the query failed) → treat as
     *               "no clean signal", never revoke. Default `null` until Billing starts. */
    var localCheck: (suspend () -> Boolean?)? = null

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

    /** Recompute Club status. Safe to call at launch, after sign-in, and after a purchase.
     *  Never throws; the worst case is "keep the cached answer". */
    suspend fun refresh() {
        // Class A — local store (Play Billing), authoritative and offline. A clean YES wins
        // immediately, with no network round-trip needed.
        val local = try { localCheck?.invoke() } catch (e: Exception) { null }
        if (local == true) { set(true); return }

        // Class B — the web purchase. Only possible when signed in with a verified email
        // (the accountKey is the sha256 of that email, and the rule checks emailOwners).
        if (!PlayerIdentity.signedIn || PlayerIdentity.profileId == null) {
            // Not signed in → no remote entitlement is readable. A clean local "no" with no
            // remote possibility is a definitive negative; a local "unknown" keeps the cached
            // answer (fail open) — it re-confirms on the next signed-in/connected refresh.
            if (local == false) set(false)
            return
        }
        val key = PlayerIdentity.profileId ?: return
        try {
            val ent = FirebaseNet.loadEntitlement(key)
            if (grantsClub(ent)) { set(true); return }
            // A clean remote read of nothing AND a clean local "no" is a definitive negative.
            if (local == false) { set(false); return }
            // else: local was unknown (null) — no clean negative, keep cached (fail open).
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
