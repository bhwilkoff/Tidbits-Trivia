import SwiftUI
import GameKit

/// Game Center bridge. Wired now so leaderboards/achievements light up
/// the moment the entitlement + App Store Connect config land (Phase 2),
/// but every method is a safe no-op until the player is authenticated —
/// so the single-player build runs without a provisioning profile.
@Observable
@MainActor
final class GameCenterManager {
    static let shared = GameCenterManager()

    private(set) var isAuthenticated = false

    /// Leaderboard IDs (must match App Store Connect when configured).
    enum Leaderboard {
        static let classicHigh = "tidbits.classic.high"
        static let dailyStreak = "tidbits.daily.streak"
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            guard let self else { return }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            if let error { print("[GameCenter] auth: \(error.localizedDescription)") }
        }
    }

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
}
