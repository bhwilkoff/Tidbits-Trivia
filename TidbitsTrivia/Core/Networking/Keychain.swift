import Foundation
import Security
import CryptoKit

/// Minimal Keychain string store — used to persist the Firebase anonymous refresh
/// token so the player's `uid` (hence their portable profile) survives relaunches.
/// `afterFirstUnlock` so a background refresh works without the device being unlocked.
///
/// **tvOS has no persistent local keychain.** Items written without
/// `kSecAttrSynchronizable` live only for the app's lifetime, so the refresh token
/// vanished on every quit and each launch minted a BRAND-NEW anonymous account.
/// Measured on the tvOS 26 simulator: two consecutive launches produced uids
/// `OwyaJJEedk` and `hns9Zbye1V`. Everything keyed on that uid — records sync,
/// streaks, Club entitlement, the Daily log, standings, friends, duels, saved-quiz
/// sync — silently belonged to a different person each time the app opened. It first
/// surfaced as a bare HTTP 401 when re-publishing a quiz whose `by` no longer matched.
///
/// The documented fix is iCloud Keychain: `kSecAttrSynchronizable` items DO persist
/// on tvOS. It also means an Apple TV and an iPhone on the same Apple Account share
/// the anonymous session, which is what a "portable identity" should have meant all
/// along.
enum Keychain {

    /// tvOS: synchronizable is the only keychain that CAN persist, so it is still
    /// asked first — it costs nothing and works on a TV signed into an Apple Account.
    /// Elsewhere it stays local; syncing every device's token through iCloud isn't
    /// wanted on iOS/macOS, where a plain item already persists.
    #if os(tvOS)
    nonisolated private static let synchronizable = true
    #else
    nonisolated private static let synchronizable = false
    #endif

    #if os(tvOS)
    /// The tvOS fallback: an ENCRYPTED file in Caches.
    ///
    /// Why a fallback exists at all: measured on the tvOS 26 simulator, two cold
    /// launches produced different uids even with `kSecAttrSynchronizable`, so the
    /// keychain alone could not be relied on. Decision 017 makes Caches one of the
    /// few writable locations (Application Support crashes on device).
    ///
    /// **Never plaintext.** The token is sealed with AES-GCM under a key that lives
    /// in the Keychain, so what sits on disk is ciphertext with no usable material
    /// beside it. The layering is deliberate:
    ///
    /// - Keychain persists (real hardware) → the key survives → the token decrypts →
    ///   identity is stable, which is the whole point of the fallback.
    /// - Keychain does NOT persist → the key is gone → the ciphertext is inert and is
    ///   discarded, and the player gets a fresh anonymous uid. That is the ORIGINAL
    ///   bug's behaviour, but with no credential ever readable at rest.
    ///
    /// So the security floor never depends on the keychain working; only the
    /// convenience does. A stolen disk image yields nothing either way.
    nonisolated private static let sealKeyAccount = "tb-seal-key-v1"

    /// The AES key, minted once and kept in the Keychain. Deliberately NOT
    /// synchronizable: a device-local key means the ciphertext is useless off this
    /// device, and the token it protects is device-scoped anyway.
    nonisolated private static func sealKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sealKeyAccount,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let d = out as? Data {
            return SymmetricKey(data: d)
        }
        // Mint one. If the keychain won't hold it, return nil rather than falling back
        // to writing plaintext — no token at rest beats a readable token at rest.
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sealKeyAccount,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: raw,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(add as CFDictionary)
        add[kSecReturnData as String] = nil
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? fresh : nil
    }

    nonisolated private static func fileURL(_ key: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("tb-\(key).sealed")
    }
    #endif

    /// macOS has TWO keychains, and the default is the wrong one.
    ///
    /// Without this flag, `SecItemAdd` on macOS writes to the legacy *file-based*
    /// login keychain, where every item carries an ACL naming the applications
    /// allowed to read it. Any binary whose signature is not on that list triggers
    /// the modal *"TidbitsTrivia wants to use your confidential information stored
    /// in 'tidbits.fb.anonRefresh' in your keychain — enter the 'login' keychain
    /// password"*. Observed once on the shipped Mac app, over the Home screen and
    /// before it was usable. It is a ONE-TIME decision per signing identity, not a
    /// per-launch prompt — it did not recur once answered — but it fires exactly
    /// when a player first opens a build whose signature is not on the item's ACL,
    /// which is the worst possible moment for a password demand.
    ///
    /// The data-protection keychain is the iOS one. Access is decided by the app's
    /// team/keychain-access-group, not a per-item ACL, so a re-signed build reads
    /// its own item silently and that dialog cannot occur. iOS and tvOS already use
    /// it and the flag is a no-op there.
    ///
    /// The two keychains are separate stores, so an existing Mac token is not
    /// migrated: those players mint one fresh anonymous uid on the next launch,
    /// which is the same outcome as a reinstall and strictly better than the prompt.
    nonisolated private static func base(_ key: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecAttrSynchronizable as String: synchronizable]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    nonisolated static func set(_ value: String, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        var add = base(key)
        add[kSecValueData as String] = Data(value.utf8)
        // A synchronizable item cannot use a `ThisDeviceOnly` accessibility class,
        // and afterFirstUnlock is already the right level for a background refresh.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        #if os(tvOS)
        // Seal, or write NOTHING. A failed seal must never degrade to plaintext.
        if let url = fileURL(key), let k = sealKey(),
           let sealed = try? AES.GCM.seal(Data(value.utf8), using: k).combined {
            try? sealed.write(to: url, options: [.atomic, .completeFileProtection])
        }
        #endif
    }

    nonisolated static func get(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let s = String(data: data, encoding: .utf8) {
            return s
        }
        #if os(tvOS)
        // The keychain miss is the NORMAL path on tvOS, not an error.
        if let url = fileURL(key), let blob = try? Data(contentsOf: url), let k = sealKey(),
           let box = try? AES.GCM.SealedBox(combined: blob),
           let opened = try? AES.GCM.open(box, using: k) {
            return String(data: opened, encoding: .utf8)
        }
        #endif
        return nil
    }

    nonisolated static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
        // Also clear any item written by a build that predates the synchronizable
        // switch, so a stale non-syncing token can't shadow the new one.
        //
        // NOT on macOS. Without the data-protection flag this query addresses the
        // legacy login keychain, and DELETING an ACL-protected legacy item raises
        // the very "enter the login keychain password" dialog this file is trying
        // to eliminate — measured: moving reads to the data-protection keychain
        // made this path run on every cold launch, so the prompt survived the fix
        // and had moved from the read to the cleanup. The orphaned legacy item is
        // never read again, so leaving it is harmless.
        #if !os(macOS)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
        #endif
        #if os(tvOS)
        // Sign-out must clear the file too, or the next launch silently restores the
        // session the player just ended.
        if let url = fileURL(key) { try? FileManager.default.removeItem(at: url) }
        #endif
    }
}
