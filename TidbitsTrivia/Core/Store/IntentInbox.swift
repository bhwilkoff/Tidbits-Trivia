import Foundation

/// Where an App Intent leaves what it wants the app to do.
///
/// An intent with `openAppWhenRun` runs in the app's process but has NO reference to
/// `AppStore` — the store is a `@State` on the scene, created after the intent has already
/// run on a cold launch. So the intent writes here and the root view drains it into the
/// same deep-link inbox every other external entry point uses (CLAUDE.md: external entry
/// points never mutate the router directly).
///
/// UserDefaults-backed rather than a static var, because on a cold launch the intent's
/// `perform()` and the scene's first render are not guaranteed to share a memory state —
/// and a request that evaporates is worse than one that arrives a beat late.
enum IntentInbox {
    private static let key = "tidbits.intent.pending"

    /// What an intent asked for, if anything. Reading CONSUMES it: a "surprise me" that
    /// replayed on the next launch would be a ghost round nobody asked for.
    static func take() -> DeepLink? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        switch raw {
        case "surprise": return .surprise
        case "daily": return .daily
        default: return nil
        }
    }

    static func put(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: key)
    }
}
