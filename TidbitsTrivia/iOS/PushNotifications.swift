#if os(iOS)
import SwiftUI
import UserNotifications

/// iOS push registration (docs/PUSH-CONTRACT.md) — 100% Apple-native (no Firebase SDK,
/// per CLAUDE.md). Requests authorization *with context* (after a Daily, not on cold
/// launch), registers with APNs, and stores the hex device token under the owner-only
/// `pushTokens/{uid}/ios` node. The cron sends direct to APNs with a `.p8` key.
///
/// Inert until the owner enables the Push capability on the App ID (§Owner setup) — the
/// code compiles and runs, but `registerForRemoteNotifications()` yields no token without
/// the `aps-environment` entitlement. Nothing else is affected.
@MainActor
final class PushManager: NSObject, ObservableObject, UIApplicationDelegate {
    static let shared = PushManager()

    private let askedKey = "tidbits.push.asked"

    /// Whether we've already shown the system prompt (so we ask at most once unprompted).
    var hasAsked: Bool { UserDefaults.standard.bool(forKey: askedKey) }

    /// Ask for permission if we never have, then register. Call after a Daily completes.
    func requestIfNeeded() async {
        guard !hasAsked else { await registerIfAuthorized(); return }
        UserDefaults.standard.set(true, forKey: askedKey)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Re-register on launch when already authorized, so a rotated token re-uploads.
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - UIApplicationDelegate (APNs token callbacks)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PlayerIdentityStore.shared.savePushToken(hex, platform: "ios") }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected before the owner enables the Push capability. Not user-facing.
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }
}
#endif
