import Foundation
import Security

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
    /// The tvOS fallback: a file in Caches.
    ///
    /// Measured: even with `kSecAttrSynchronizable`, two cold launches produced
    /// different uids, so the keychain alone cannot be relied on here. Decision 017
    /// establishes Caches as one of the few writable locations on tvOS (Application
    /// Support crashes on device), and the SwiftData store already lives there.
    ///
    /// **The tradeoff, stated plainly:** this is a refresh token in a plaintext file.
    /// It sits inside the app's own sandbox container, which no other app can read,
    /// and Caches may be purged under storage pressure — in which case the player
    /// gets a new anonymous uid, which is exactly today's behaviour, so the failure
    /// mode is no worse than the bug. What it buys is that records, streaks, Club
    /// entitlement, the Daily log and quiz sync stop silently belonging to a
    /// different person on every launch. A device-bound encrypted store would be
    /// better and is the right follow-up (the Windows port answered the same
    /// question with DPAPI); it is not a reason to keep shipping a broken identity.
    nonisolated private static func fileURL(_ key: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("tb-\(key).token")
    }
    #endif

    nonisolated private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: synchronizable]
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
        if let url = fileURL(key) {
            try? Data(value.utf8).write(to: url, options: [.atomic])
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
        if let url = fileURL(key), let data = try? Data(contentsOf: url) {
            return String(data: data, encoding: .utf8)
        }
        #endif
        return nil
    }

    nonisolated static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
        // Also clear any item written by a build that predates the synchronizable
        // switch, so a stale non-syncing token can't shadow the new one.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
        #if os(tvOS)
        // Sign-out must clear the file too, or the next launch silently restores the
        // session the player just ended.
        if let url = fileURL(key) { try? FileManager.default.removeItem(at: url) }
        #endif
    }
}
