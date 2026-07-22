// Tidbits Club membership on the web (docs/CLUB-MONETIZATION-BUILD.md, MONETIZATION §7).
// Mirror of the Swift EntitlementStore — same isClub gate, same fail-open discipline.
//
// The web has NO local store (Class A = StoreKit/Play/MSStore, which the web isn't), so on
// the web isClub is purely the REMOTE read: entitlements/{accountKey}, written by the
// Worker after a Merchant-of-Record purchase. Requires a verified-email sign-in — the RTDB
// rule keys the read on emailOwners/{key} === the token email.
//
// Fail OPEN: a transient read miss NEVER revokes Club (a paying member on a flaky
// connection stays Club). Cache the last-known-good so a returning member is Club instantly.

import { FirebaseNet } from './firebase.js';
import { Identity } from './identity.js';

const CACHE_KEY = 'tidbits.entitlement.isClub';

function grantsClub(ent) {
  if (!ent || ent.tier !== 'club') return false;
  if (ent.until == null) return true;            // lifetime / non-expiring
  return Date.now() < Number(ent.until);
}

export const Entitlement = {
  // Seed from the cached last-known-good so gating is correct before any network round-trip.
  isClub: (() => { try { return localStorage.getItem(CACHE_KEY) === '1'; } catch { return false; } })(),
  _subs: [],

  /** Subscribe to Club-status changes (fires immediately with the current value). */
  onChange(fn) { this._subs.push(fn); try { fn(this.isClub); } catch {} },
  _emit() { this._subs.forEach((f) => { try { f(this.isClub); } catch {} }); },

  _set(club) {
    const changed = this.isClub !== club;
    this.isClub = club;
    try { localStorage.setItem(CACHE_KEY, club ? '1' : '0'); } catch {}
    if (changed) this._emit();
  },

  /** Recompute Club status. Safe at launch, after sign-in, and after a purchase returns. */
  async refresh() {
    if (!Identity.signedIn || !Identity.profileId) {
      // Not signed in → no web entitlement is readable. Don't aggressively revoke a cached
      // true (fail open); it re-confirms on the next signed-in refresh. A fresh anon session
      // with no cache is simply not Club.
      return;
    }
    try {
      const ent = await FirebaseNet.loadEntitlement(Identity.profileId);
      this._set(grantsClub(ent));   // a clean read (incl. null → not club) is authoritative
    } catch {
      // transient error → keep cached (fail open)
    }
  },

  /** Sign-out clears Club (the next person on this device isn't you). */
  clearOnSignOut() { this._set(false); },
};
