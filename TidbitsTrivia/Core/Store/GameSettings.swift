import Foundation

/// Player-facing gameplay preferences (UserDefaults-backed, read via @AppStorage
/// in views). Kept here so iOS + tvOS share the exact same keys and defaults.
enum GameSettings {
    /// Spaced re-asking of missed questions woven into games. Default ON — some
    /// players prefer only-new questions, so it's a toggle (Settings on iOS, the
    /// home toggle on tvOS).
    static let reviewKey = "tidbits.reviewEnabled"

    static var reviewEnabled: Bool {
        UserDefaults.standard.object(forKey: reviewKey) == nil
            ? true : UserDefaults.standard.bool(forKey: reviewKey)
    }

    /// The push opt-out (docs/PUSH-CONTRACT.md; App Store 4.5.4 requires one in-app).
    /// Default ON so the switch reflects what a granted permission implies — turning it
    /// off is what deletes the token node, and the node is what a send actually needs.
    static let remindersKey = "tidbits.remindersEnabled"

    static var remindersEnabled: Bool {
        UserDefaults.standard.object(forKey: remindersKey) == nil
            ? true : UserDefaults.standard.bool(forKey: remindersKey)
    }
}
