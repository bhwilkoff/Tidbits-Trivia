// js/push.js — the Web Push leg of the three-legged $0 sender (docs/PUSH-CONTRACT.md).
// Subscribes through the existing service worker with a VAPID key and stores the whole
// PushSubscription blob (endpoint + p256dh + auth) at pushTokens/{authUid}/web, which is
// exactly what pywebpush wants back on the cron side.
//
// Inert until the owner generates the VAPID keypair (§Owner setup 4) and pastes the PUBLIC
// half below: with the placeholder in place `enable()` returns false and nothing else in
// the app is affected. That mirrors how the Android Google client id is handled.
import { FirebaseNet } from './firebase.js';

// `web-push generate-vapid-keys` → public half here, private half into the
// VAPID_PRIVATE_KEY repo secret. The public key is not a secret; it ships to every client.
export const VAPID_PUBLIC_KEY = 'TODO_GENERATE_VAPID_KEYPAIR';

const ASKED_KEY = 'tidbits.push.asked';

export const Push = {
  get configured() { return VAPID_PUBLIC_KEY !== 'TODO_GENERATE_VAPID_KEYPAIR'; },
  get supported() { return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window; },
  get permission() { return this.supported ? Notification.permission : 'unsupported'; },
  get hasAsked() { return localStorage.getItem(ASKED_KEY) === '1'; },

  /** True when this browser currently holds a subscription we've stored. */
  async isSubscribed() {
    if (!this.supported) return false;
    try {
      const reg = await navigator.serviceWorker.ready;
      return !!(await reg.pushManager.getSubscription());
    } catch { return false; }
  },

  /**
   * Ask with context (call after a Daily, not on load), subscribe, and store the blob.
   * Returns true only when a subscription actually reached the registry — a denied
   * permission, an unconfigured VAPID key and an unsupported browser are all false, and
   * none of them are errors the player needs to see.
   */
  async enable() {
    if (!this.supported || !this.configured) return false;
    localStorage.setItem(ASKED_KEY, '1');
    try {
      if (Notification.permission === 'denied') return false;
      if (Notification.permission !== 'granted') {
        if (await Notification.requestPermission() !== 'granted') return false;
      }
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription()
        || await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
        });
      const uid = FirebaseNet.uid;
      if (!uid) return false;
      await FirebaseNet.setPushToken(uid, 'web', JSON.parse(JSON.stringify(sub)));
      return true;
    } catch (e) {
      console.warn('[Push] subscribe failed', e);
      return false;
    }
  },

  /** The in-app opt-out (App Store 4.5.4's twin on the web): unsubscribe AND drop the node,
   *  because a subscription left in the registry keeps receiving sends. */
  async disable() {
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) await sub.unsubscribe();
    } catch {}
    const uid = FirebaseNet.uid;
    if (uid) { try { await FirebaseNet.removePath(`pushTokens/${uid}/web`); } catch {} }
  },

  /** Re-store the blob on launch when already subscribed — a browser can rotate an
   *  endpoint, and a stale one in the registry is a reminder that silently never lands. */
  async refresh() {
    if (!this.supported || !this.configured) return;
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      const uid = FirebaseNet.uid;
      if (sub && uid) await FirebaseNet.setPushToken(uid, 'web', JSON.parse(JSON.stringify(sub)));
    } catch {}
  },
};

// VAPID keys travel base64url; PushManager wants raw bytes.
function urlBase64ToUint8Array(base64) {
  const padded = (base64 + '='.repeat((4 - base64.length % 4) % 4)).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(padded);
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
}
