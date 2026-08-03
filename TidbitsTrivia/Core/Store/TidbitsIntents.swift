#if os(iOS) || os(tvOS)
import AppIntents

/// Voice + Shortcuts entry points (PARITY §11 "App Intents voice launches").
///
/// Two verbs only, and both are things the app already does — `AppStore.surpriseMe()` and
/// the Daily. An intent that can't be said in one breath won't be, and a Shortcuts list
/// full of near-duplicates is worse than a short one.
///
/// Both open the app rather than running headless: a trivia round is not a background
/// task, and answering it IS the feature.
struct SurpriseMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Surprise Me"
    static let description = IntentDescription("Start a random Tidbits round — a random mode in a random category.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.put("surprise")
        return .result()
    }
}

struct PlayDailyIntent: AppIntent {
    static let title: LocalizedStringResource = "Play the Daily"
    static let description = IntentDescription("Open today's Daily Tidbit — the same seven questions everyone gets.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.put("daily")
        return .result()
    }
}

/// Phrases have to contain the app name for Siri to resolve them, and
/// `${applicationName}` is what App Intents substitutes.
struct TidbitsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SurpriseMeIntent(),
            phrases: [
                "Surprise me in \(.applicationName)",
                "Play a random round in \(.applicationName)",
            ],
            shortTitle: "Surprise Me",
            systemImageName: "dice.fill")
        AppShortcut(
            intent: PlayDailyIntent(),
            phrases: [
                "Play the Daily in \(.applicationName)",
                "Start my \(.applicationName) Daily",
            ],
            shortTitle: "Play the Daily",
            systemImageName: "sun.max.fill")
    }
}
#endif
