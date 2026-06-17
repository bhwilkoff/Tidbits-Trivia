import SwiftUI

/// Global app state — injected via @Environment(AppStore.self). One
/// navigation path per tab, owned here (the four-shipped-apps rule). Deep
/// links land in `inbox` and are consumed by the root once foregrounded.
@Observable
@MainActor
final class AppStore {
    enum Tab: String, CaseIterable { case play, records, create }

    var selectedTab: Tab = .play
    var playPath = NavigationPath()
    var recordsPath = NavigationPath()
    var createPath = NavigationPath()

    /// Deep-link inbox (e.g. tidbits://daily, tidbits://topic/<x>).
    var inbox: [DeepLink] = []

    /// The single live game. Created on demand; observed by the game view.
    var game = GameEngine()

    func post(_ link: DeepLink) { inbox.append(link) }
    func drainInbox() -> [DeepLink] { defer { inbox.removeAll() }; return inbox }
}

enum DeepLink: Equatable, Sendable {
    case daily
    case topic(String)
    case category(String)
}

/// A request to launch a game with a given mode + category. Shared by the
/// iOS and tvOS home screens (Core has no UI, but this is a plain value).
nonisolated struct LaunchRequest: Identifiable, Sendable {
    let mode: GameMode
    let category: TriviaCategory
    var id: String { "\(mode.rawValue)-\(category.id)" }
}
