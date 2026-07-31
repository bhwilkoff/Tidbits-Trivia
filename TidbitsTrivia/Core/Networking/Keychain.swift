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

    /// tvOS: synchronizable is the ONLY durable keychain. Elsewhere it stays local —
    /// syncing every device's token through iCloud isn't wanted on iOS/macOS, where
    /// a plain item already persists.
    #if os(tvOS)
    nonisolated private static let synchronizable = true
    #else
    nonisolated private static let synchronizable = false
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
    }

    nonisolated static func get(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
        // Also clear any item written by a build that predates the synchronizable
        // switch, so a stale non-syncing token can't shadow the new one.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
    }
}
