import Foundation

/// Environment hooks that drive the app to a known state for screenshots
/// and CI verification. No-ops in production (the env vars are never set);
/// they exist so `simctl launch --setenv` can open any screen directly —
/// the backbone of both debugging and store-screenshot generation
/// (CLAUDE.md "Drive the app to a known state for screenshots").
enum DebugHooks {
    /// TIDBITS_AUTOPLAY="mode:category" → launch straight into a game.
    static var autoplay: (mode: GameMode, category: TriviaCategory)? {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_AUTOPLAY"] else { return nil }
        let parts = raw.split(separator: ":").map(String.init)
        let mode = GameMode(rawValue: parts.first ?? "classic") ?? .classic
        let cat = TriviaCategory.named(parts.count > 1 ? parts[1] : "mixed")
        return (mode, cat)
    }

    /// TIDBITS_AUTOPILOT=1 → auto-answer each question so the reveal and
    /// results screens can be screenshotted without manual taps.
    static var autopilot: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOPILOT"] == "1"
    }

    /// TIDBITS_TAB="records"|"create"|"play" → open straight to a tab.
    static var initialTab: AppStore.Tab? {
        ProcessInfo.processInfo.environment["TIDBITS_TAB"]
            .flatMap { AppStore.Tab(rawValue: $0) }
    }

    /// TIDBITS_AUTOCREATE="<topic>" → prefill Create and generate a live
    /// quiz from Wikipedia (verifies the live generation path end to end).
    static var autoCreate: String? {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOCREATE"]
    }
}
