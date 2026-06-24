import SwiftUI
import GameKit
import UIKit   // GKGameCenterViewController / UIApplication presentation (iOS + tvOS)

/// Game Center bridge — authentication, leaderboard submission, achievement
/// reporting, the access point, and the dashboard. Every method is a safe no-op
/// until the player is authenticated, so the single-player build runs without a
/// provisioning profile and nothing here crashes before Game Center is enabled
/// in App Store Connect.
///
/// IDs below MUST match the leaderboards/achievements created in App Store
/// Connect verbatim (see docs/GAME-CENTER-SETUP.md).
@Observable
@MainActor
final class GameCenterManager {
    static let shared = GameCenterManager()

    private(set) var isAuthenticated = false

    /// Leaderboard IDs — create these in App Store Connect (Features → Game Center).
    enum Leaderboard {
        static let classicHigh = "tidbits.classic.high"
        static let dailyStreak = "tidbits.daily.streak"
    }

    /// Achievement IDs — create these in App Store Connect with matching ids.
    enum Achievement {
        static let firstGame    = "tidbits.ach.firstgame"   // play your first game
        static let perfectRound = "tidbits.ach.perfect"     // a flawless round (≥7 Qs)
        static let century      = "tidbits.ach.century"     // 100 lifetime correct (progress)
        static let streak7      = "tidbits.ach.streak7"     // 7-day daily streak (progress)
        static let streak30     = "tidbits.ach.streak30"    // 30-day daily streak (progress)
        static let fullPie      = "tidbits.ach.fullpie"     // all 7 knowledge wedges (progress)
        static let sharpshooter = "tidbits.ach.sharp"       // a Stake round where every chip landed
        static let explorer     = "tidbits.ach.explorer"    // play 10 distinct game modes (progress)
        static let scholar      = "tidbits.ach.scholar"     // 1,000 lifetime correct (progress)
    }

    // Game Center Challenges (iOS 26): friends challenge each other to beat a
    // leaderboard score / earn an achievement, async with a deadline. The system
    // drives the UI once the leaderboards/achievements are flagged "challengeable"
    // in App Store Connect; the app only routes "play this challenge" into a game.
    private let challengeListener = ChallengeListener()
    /// Set when the player taps "Play" on a challenge; the home screen consumes it.
    private(set) var pendingChallengeMode: GameMode?
    func consumePendingChallenge() -> GameMode? {
        defer { pendingChallengeMode = nil }
        return pendingChallengeMode
    }
    fileprivate func routeChallenge(_ mode: GameMode) { pendingChallengeMode = mode }

    // MARK: Authentication

    /// Set ONCE at app launch. GameKit calls the handler several times during
    /// init; on a not-signed-in device it hands back a view controller to present.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if let error {
                print("[GameCenter] auth: \(error.localizedDescription)")
                return
            }
            if self.isAuthenticated {
                self.configureAccessPoint()
                GKLocalPlayer.local.register(self.challengeListener)   // challenge events
            }
        }
    }

    // MARK: Access point + dashboard

    private func configureAccessPoint() {
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.showHighlights = true
        GKAccessPoint.shared.isActive = true
    }

    /// Hide the access point during active gameplay, show it on menus.
    func setAccessPointActive(_ active: Bool) {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.isActive = active
    }

    /// Open the full Game Center dashboard (leaderboards + achievements + profile).
    func showDashboard() {
        guard isAuthenticated, let top = Self.topViewController() else { return }
        let vc = GKGameCenterViewController(state: .dashboard)
        vc.gameCenterDelegate = DashboardDelegate.shared
        top.present(vc, animated: true)
    }

    // MARK: Leaderboards

    func submit(_ value: Int, to leaderboardID: String) {
        guard isAuthenticated else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    value, context: 0, player: GKLocalPlayer.local,
                    leaderboardIDs: [leaderboardID])
            } catch {
                print("[GameCenter] submit failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Achievements

    /// Report achievement progress (0…100). GameKit ignores a value lower than
    /// already-reached, so it's safe to report the current computed progress
    /// after every game.
    func report(_ identifier: String, percent: Double = 100) {
        guard isAuthenticated else { return }
        Task {
            let a = GKAchievement(identifier: identifier)
            a.percentComplete = max(0, min(100, percent))
            a.showsCompletionBanner = true
            do { try await GKAchievement.report([a]) }
            catch { print("[GameCenter] achievement \(identifier): \(error.localizedDescription)") }
        }
    }

    // MARK: Top view controller (for presenting GameKit UIKit screens)

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// Dashboard dismissal — GKGameCenterControllerDelegate must be an NSObject, so
/// it lives here rather than on the @Observable manager.
private final class DashboardDelegate: NSObject, GKGameCenterControllerDelegate {
    static let shared = DashboardDelegate()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

/// Challenge events. Must be an NSObject (GKLocalPlayerListener). When the player
/// taps "Play" on a challenge from Game Center, route them into a game — score
/// challenges open Classic (the primary leaderboard mode); the system's own UI
/// reports completion, so we only need to launch.
private final class ChallengeListener: NSObject, GKLocalPlayerListener {
    func player(_ player: GKPlayer, wantsToPlay challenge: GKChallenge) {
        Task { @MainActor in GameCenterManager.shared.routeChallenge(.classic) }
    }
}
