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
}
