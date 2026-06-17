import Foundation
#if os(iOS)
import UIKit
#endif

/// Tactile feedback for answer outcomes and milestones. Respects the
/// user's Settings toggle and is a no-op on platforms without haptics.
@MainActor
enum Haptics {
    static let defaultsKey = "tidbits.hapticsEnabled"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func correct() { play(.success) }
    static func wrong()   { play(.error) }
    static func success() { play(.success) }
    static func tap()     { impact() }

    #if os(iOS)
    private static func play(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    private static func impact() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    #else
    private enum Stub { case success, error }
    private static func play(_ type: Stub) {}
    private static func impact() {}
    #endif
}
