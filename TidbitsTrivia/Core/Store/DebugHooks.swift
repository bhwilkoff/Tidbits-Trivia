import Foundation
import SwiftData

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

    /// TIDBITS_PAYWALL=1 → present the Club paywall on launch (screenshot observability).
    static var showPaywall: Bool { ProcessInfo.processInfo.environment["TIDBITS_PAYWALL"] == "1" }

    /// TIDBITS_CLUB=1 → force `EntitlementStore.isClub` true. Pre-launch there are no
    /// real purchases, so this is how every Club feature gets verified
    /// (docs/CLUB-FEATURES-BUILD.md gating convention).
    static var forceClub: Bool { ProcessInfo.processInfo.environment["TIDBITS_CLUB"] == "1" }

    /// TIDBITS_AUTOCREATE="<topic>" → prefill Create and generate a live
    /// quiz from Wikipedia (verifies the live generation path end to end).
    static var autoCreate: String? {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOCREATE"]
    }

    /// TIDBITS_PARTY=1 → open Pass & Play on launch (combine with AUTOPILOT
    /// to drive the whole party flow to the scoreboard for screenshots).
    /// TIDBITS_CUSTOMIZE=1 opens the Customize sheet on launch (screenshots).
    static var openCustomize: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_CUSTOMIZE"] == "1"
    }

    /// TIDBITS_DAILY_ARCHIVE=1 opens the Previous Tidbits archive on launch.
    static var openDailyArchive: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_DAILY_ARCHIVE"] == "1"
    }

    /// TIDBITS_STORY_ARCHIVE=1 opens the Club Story Archive (Records → see
    /// all) on launch — screenshot observability, same idiom as the flags above.
    static var openStoryArchive: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_STORY_ARCHIVE"] == "1"
    }

    /// TIDBITS_ATLAS=1 opens the Club Knowledge Atlas (Records → see all) on
    /// launch — screenshot/simulator observability, same idiom as above.
    static var openAtlas: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_ATLAS"] == "1"
    }

    /// TIDBITS_MARATHON=1 launches (or resumes) the Club Marathon on launch —
    /// screenshot/simulator observability. Combine with TIDBITS_MARATHON_LEN
    /// (read by `Marathon.runLength`) to play a short run to completion.
    static var openMarathon: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_MARATHON"] == "1"
    }

    /// TIDBITS_EXPEDITION=1 opens Club Expeditions on launch — screenshot/
    /// simulator observability, same idiom as TIDBITS_MARATHON/TIDBITS_ATLAS.
    static var openExpedition: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_EXPEDITION"] == "1"
    }

    /// TIDBITS_LINKWALL=1 opens the Club Link Wall (Feature 6, Stage 2) on
    /// launch — same screenshot/simulator observability idiom as the flags
    /// above. Combine with TIDBITS_CLUB=1 (Link Wall is Club-gated).
    static var openLinkWall: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_LINKWALL"] == "1"
    }

    /// TIDBITS_LINKWALL_AUTOPLAY="win"|"lose" drives the Link Wall board to
    /// completion by submitting real guesses programmatically — this dev box
    /// has no GUI Simulator window to tap a 4x4 grid through (same reasoning
    /// as TIDBITS_AUTOPILOT/TIDBITS_EXPEDITION_AUTOPLAY). "win" submits each
    /// group correctly in order; "lose" submits 4 deliberately-mixed (3-of-a-
    /// group + 1 outsider) guesses to exhaust mistakes and trigger the reveal.
    static var linkWallAutoplay: String? {
        ProcessInfo.processInfo.environment["TIDBITS_LINKWALL_AUTOPLAY"]
    }

    /// TIDBITS_EXPEDITION_FORCE_PASS=1 → a played Expedition stage always
    /// records as a full pass regardless of the actual score. Verification-only
    /// (so a stage/campaign can be advanced and a certificate written quickly
    /// in the simulator without needing autopilot to answer every MCQ
    /// correctly — autopilot always submits option 0). No-op in production.
    static var forceExpeditionPass: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_EXPEDITION_FORCE_PASS"] == "1"
    }

    /// TIDBITS_EXPEDITION_MAP=<expeditionID> → open Expeditions straight into
    /// that expedition's map (skips the list tap) — verification/screenshot
    /// convenience on a dev box with no GUI Simulator window to tap through.
    static var expeditionMapPreview: String? {
        ProcessInfo.processInfo.environment["TIDBITS_EXPEDITION_MAP"]
    }

    /// TIDBITS_EXPEDITION_AUTOPLAY="<expeditionID>:<stageIndex>" → open
    /// Expeditions and launch straight into that stage's play (skips the map's
    /// Play tap) — verification-only, same reasoning as `expeditionMapPreview`.
    /// Combine with TIDBITS_AUTOPILOT + TIDBITS_EXPEDITION_FORCE_PASS to drive
    /// a stage pass -> advance/persist -> (on the last stage) certificate,
    /// end to end, from the CLI.
    static var expeditionAutoplay: (expeditionID: String, stageIndex: Int)? {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_EXPEDITION_AUTOPLAY"] else { return nil }
        let parts = raw.split(separator: ":").map(String.init)
        guard let id = parts.first, parts.count > 1, let idx = Int(parts[1]) else { return nil }
        return (id, idx)
    }

    /// TIDBITS_MIX=classic,pictureId,closestCall — the modes for a TIDBITS_AUTOPLAY=mix:… launch.
    static var mixModes: [GameMode]? {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_MIX"] else { return nil }
        let modes = raw.split(separator: ",").compactMap { GameMode(rawValue: String($0)) }
        return modes.isEmpty ? nil : modes
    }

    /// TIDBITS_VERSUS=house|rookie|regular|ace starts a vs-CPU match on launch.
    static var versusBot: String? {
        ProcessInfo.processInfo.environment["TIDBITS_VERSUS"]
    }

    /// TIDBITS_MULTIPLAYER=1 opens the Online Multiplayer sheet on launch.
    static var openMultiplayer: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_MULTIPLAYER"] == "1"
    }

    static var openParty: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_PARTY"] == "1"
    }

    /// TIDBITS_NIGHT_HOST=1 → open the RTDB Trivia Night host lobby (code + QR).
    static var openNightHost: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_NIGHT_HOST"] == "1"
    }

    /// TIDBITS_ONBOARD=1 → force the first-run walkthrough (for screenshots).
    static var forceOnboarding: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_ONBOARD"] == "1"
    }

    /// TIDBITS_SEED_RECORDS=<n> → insert N synthetic games + a streak so the
    /// Records dashboard can be screenshot-verified with realistic data. No-op
    /// unless the env var is set AND the store is empty (never touches real data).
    static var seedRecords: Int? {
        ProcessInfo.processInfo.environment["TIDBITS_SEED_RECORDS"].flatMap(Int.init)
    }

    @MainActor
    static func seedRecordsIfRequested(_ context: ModelContext) {
        guard let n = seedRecords, n > 0 else { return }
        let existing = (try? context.fetch(FetchDescriptor<GameRecord>())) ?? []
        guard existing.isEmpty else { return }
        let modes: [GameMode] = [.classic, .timeAttack, .survival, .stake, .sweep, .oddOneOut, .ladder]
        let cats = ["history", "science", "geography", "arts", "screen", "music", "sports", "business", "mixed"]
        for i in 0..<n {
            let mode = modes[i % modes.count]
            let cat = cats[i % cats.count]
            let total = 7 + (i % 4)
            let correct = max(1, total - (i % 5))
            let answers: [AnswerDetail] = (i % 3 == 0) ? [] : (0..<total).map { k in
                AnswerDetail(qid: "q\(i)_\(k)", prompt: "Sample question \(k + 1) from \(cat)?",
                             categoryID: cat, correct: k < correct, answer: "Answer \(k + 1)")
            }
            context.insert(GameRecord(mode: mode, categoryID: cat, score: 40 + (i * 37) % 120,
                                      correct: correct, total: total, maxStreak: correct,
                                      answers: answers, date: Date().addingTimeInterval(-Double(i) * 3600)))
        }
        context.insert(DailyStreak(current: 5, best: 12, lastPlayedDay: "2026-07-03"))
        try? context.save()
    }
}
