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

    // MARK: - Quick Play memory + presets (home redesign — rule R-HOME-1)

    /// Last-played mode/category — surfaced as the Quick Play default so a
    /// returning player taps once into the game they last chose. Persisted.
    var lastPlayedModeRaw: String? = UserDefaults.standard.string(forKey: "tidbits.lastMode") {
        didSet { UserDefaults.standard.set(lastPlayedModeRaw, forKey: "tidbits.lastMode") }
    }
    var lastPlayedCategoryID: String? = UserDefaults.standard.string(forKey: "tidbits.lastCategory") {
        didSet { UserDefaults.standard.set(lastPlayedCategoryID, forKey: "tidbits.lastCategory") }
    }
    /// Saved game presets ("My Mix"), capped at 5. Persisted as JSON.
    var presets: [GamePreset] = AppStore.loadPresets() {
        didSet { AppStore.savePresets(presets) }
    }

    /// Record what the player just launched, so Quick Play mirrors their groove.
    func rememberSelection(mode: GameMode, category: TriviaCategory) {
        guard mode != .daily else { return }   // the Daily is a separate habit
        lastPlayedModeRaw = mode.rawValue
        lastPlayedCategoryID = category.id
    }

    /// The Quick Play target: last-played if known, else the friendly default.
    var quickPlay: LaunchRequest {
        if let raw = lastPlayedModeRaw, let mode = GameMode(rawValue: raw), let cid = lastPlayedCategoryID {
            return LaunchRequest(mode: mode, category: .named(cid))
        }
        return LaunchRequest(mode: .classic, category: .named("mixed"))
    }
    var hasQuickPlayHistory: Bool { lastPlayedModeRaw != nil }

    /// Serendipity — opt-in, never the default (a random default reads as "the
    /// app doesn't know what I want").
    func surpriseMe() -> LaunchRequest {
        let modes = GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia }
        return LaunchRequest(mode: modes.randomElement() ?? .classic,
                             category: TriviaCategory.all.randomElement() ?? .named("mixed"))
    }

    func savePreset(_ p: GamePreset) {
        var l = presets.filter { $0.name.caseInsensitiveCompare(p.name) != .orderedSame }
        l.insert(p, at: 0)
        presets = Array(l.prefix(5))
    }
    func deletePreset(_ p: GamePreset) { presets.removeAll { $0.id == p.id } }

    static func loadPresets() -> [GamePreset] {
        guard let d = UserDefaults.standard.data(forKey: "tidbits.presets"),
              let l = try? JSONDecoder().decode([GamePreset].self, from: d) else { return [] }
        return l
    }
    static func savePresets(_ p: [GamePreset]) {
        if let d = try? JSONEncoder().encode(Array(p.prefix(5))) {
            UserDefaults.standard.set(d, forKey: "tidbits.presets")
        }
    }
}

/// A saved way to play — a named (mode, categories) combo. Multi-category is
/// stored now (draw-filter is a fast follow); `category` is the primary.
nonisolated struct GamePreset: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var name: String
    var mode: GameMode
    var categoryIDs: [String]
    var primaryCategoryID: String { categoryIDs.first ?? "mixed" }
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

/// A request to launch a configured Trivia Night — drives a `fullScreenCover(item:)`
/// from the iOS and tvOS home screens. Shared so both platforms use one shape.
struct NightLaunchRequest: Identifiable, Sendable {
    let id = UUID()
    let plan: NightPlan
    let category: TriviaCategory
}
