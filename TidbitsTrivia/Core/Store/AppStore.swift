import SwiftUI

/// Global app state — injected via @Environment(AppStore.self). One
/// navigation path per tab, owned here (the four-shipped-apps rule). Deep
/// links land in `inbox` and are consumed by the root once foregrounded.
@Observable
@MainActor
final class AppStore {
    enum Tab: String, CaseIterable { case play, records, create }

    /// A shared quiz id waiting to be opened (`tidbitstrivia://quiz/<id>`). Set by the

    /// deep-link inbox and CLEARED by the view that consumes it, so a link never

    /// re-opens on the next visit to the tab.

    var pendingSharedQuizID: String?

    /// A shared QUESTION id waiting to be shown (`tidbits://item/<id>`). Same inbox
    /// discipline as the quiz id — set by the deep-link inbox, cleared by the view.
    var pendingItemID: String?

    /// A round an external entry point asked for (a Siri "surprise me", `tidbits://daily`).
    /// Set by the deep-link inbox, CONSUMED by the Play surface — the router never starts
    /// a game itself, and a request that stayed set would replay on every return to Play.
    var pendingLaunch: LaunchRequest?

    /// A room code a link asked us to join (`…/live/<code>`, the projector's QR).
    /// Set by the deep-link inbox, CONSUMED by the Home surface, which opens the
    /// join screen with the code filled in — the player scanned, they don't type.
    var pendingLiveJoinCode: String?


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
    func rememberSelection(mode: GameMode, category: TriviaCategory, mixModes: [GameMode]? = nil) {
        guard mode != .daily, mode != .weakSpot, mode != .marathon else { return }   // separate habit / Club-gated, never the free Quick Play default
        lastPlayedModeRaw = mode.rawValue
        lastPlayedCategoryID = category.id
        if mode == .mix, let mixModes {
            UserDefaults.standard.set(mixModes.map(\.rawValue), forKey: "tidbits.lastMixModes")
        }
    }

    /// The modes behind the last Custom Mix (so Quick Play can replay it).
    var lastMixModes: [GameMode] {
        (UserDefaults.standard.stringArray(forKey: "tidbits.lastMixModes") ?? [])
            .compactMap(GameMode.init(rawValue:))
    }

    /// The Quick Play target: last-played if known, else the friendly default.
    var quickPlay: LaunchRequest {
        if let raw = lastPlayedModeRaw, let mode = GameMode(rawValue: raw), let cid = lastPlayedCategoryID {
            if mode == .mix {
                let modes = lastMixModes
                guard modes.count >= 2 else { return LaunchRequest(mode: .classic, category: .named(cid)) }
                return LaunchRequest(mode: .mix, category: .named(cid), mixModes: modes)
            }
            return LaunchRequest(mode: mode, category: .named(cid))
        }
        return LaunchRequest(mode: .classic, category: .named("mixed"))
    }
    var hasQuickPlayHistory: Bool { lastPlayedModeRaw != nil }

    /// Serendipity — opt-in, never the default (a random default reads as "the
    /// app doesn't know what I want").
    func surpriseMe() -> LaunchRequest {
        // Club-gated modes never surface from a free-tier random pick.
        let modes = GameMode.allCases.filter { $0 != .daily && $0 != .barTrivia && $0 != .mix && $0 != .weakSpot && $0 != .marathon }
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
    /// For `.mix` presets: the modes behind the mix (additive; nil for others).
    var modeIDs: [String]? = nil
    var primaryCategoryID: String { categoryIDs.first ?? "mixed" }
}

enum DeepLink: Equatable, Sendable {
    case daily
    case topic(String)
    case category(String)
    /// A shared quiz: `tidbitstrivia://quiz/<id>`, twin of the canonical
    /// `https://tidbitstrivia.com/quiz/<id>` (docs/QUIZ-CONTRACT.md §5).
    case quiz(String)
    /// A shared single question: `tidbits://item/<id>`, twin of the canonical
    /// `https://tidbitstrivia.com/item/<id>` (DEEP_LINKS.md). What the per-question
    /// "how did YOU know that?" share hands out.
    case item(String)
    /// "Surprise me" — a random mode in a random category. Reached from Siri /
    /// Shortcuts (`SurpriseMeIntent`), not from a URL.
    case surprise
    /// Join a live room by code: `tidbits://live/<code>` and the canonical
    /// `https://tidbitstrivia.com/live/<code>` — the URL the projector's
    /// scan-to-join QR encodes (DEEP_LINKS.md).
    case live(String)

    /// One parser for BOTH URL shapes an entry point can hand the app.
    ///
    /// A custom-scheme link carries its route in the HOST (`tidbits://item/x`); a
    /// Universal Link carries it in the PATH (`https://tidbitstrivia.com/item/x`)
    /// and its host is the domain. The router used to switch on `url.host` alone,
    /// which routed the first shape and silently dropped the second — every
    /// Universal Link, including the projector's QR, launched the app and did
    /// nothing. The web app is hash-routed, so a pasted `…/#/live/CODE` is read too.
    static func parse(_ url: URL) -> DeepLink? {
        let parts: [String]
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            var p = url.pathComponents.filter { $0 != "/" }
            if p.isEmpty, let frag = url.fragment {
                p = frag.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            }
            parts = p
        } else {
            parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        }
        guard let route = parts.first?.lowercased(), !route.isEmpty else { return nil }
        let arg = parts.dropFirst().first ?? ""
        switch route {
        case "daily": return .daily
        case "topic": return arg.isEmpty ? nil : .topic(arg)
        case "category": return arg.isEmpty ? nil : .category(arg)
        case "quiz": return arg.isEmpty ? nil : .quiz(arg)
        case "item": return arg.isEmpty ? nil : .item(arg)
        case "live":
            let code = arg.trimmingCharacters(in: .whitespaces).uppercased()
            return code.isEmpty ? nil : .live(code)
        default: return nil
        }
    }
}

/// A request to launch a game with a given mode + category. Shared by the
/// iOS and tvOS home screens (Core has no UI, but this is a plain value).
nonisolated struct LaunchRequest: Identifiable, Sendable {
    let mode: GameMode
    let category: TriviaCategory
    /// Set only for archive plays of a past Daily (R-DAILY-1).
    var dailyDay: String? = nil
    /// Set only for a Custom Mix (multi-select Customize) — the modes to draw from.
    var mixModes: [GameMode]? = nil
    var id: String { "\(mode.rawValue)-\(category.id)-\(dailyDay ?? "")-\(mixModes?.map(\.rawValue).joined(separator: "+") ?? "")" }
}

/// A request to launch a configured Trivia Night — drives a `fullScreenCover(item:)`
/// from the iOS and tvOS home screens. Shared so both platforms use one shape.
struct NightLaunchRequest: Identifiable, Sendable {
    let id = UUID()
    let plan: NightPlan
    let category: TriviaCategory
}
