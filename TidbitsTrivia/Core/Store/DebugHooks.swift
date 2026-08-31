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

    /// TIDBITS_SCREENED=1 → the autoplay round draws from `ScreenshotQuestions.pick` instead
    /// of the normal random corpus draw (rule R-SHOT-3). A random draw put a Holocaust
    /// question in the reveal slot of a store listing; screenshot runs must never roll dice.
    static var screenedQuestions: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_SCREENED"] == "1"
    }

    /// TIDBITS_AUTOPILOT_CORRECT=1 → autopilot submits the RIGHT answer instead of option 0.
    /// The store scorecard shot otherwise advertises ~28% accuracy, which is an artefact of
    /// the test harness rather than the game (docs/STORE-SCREENSHOTS.md §2).
    static var autopilotCorrect: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOPILOT_CORRECT"] == "1"
    }

    /// TIDBITS_AUTOPILOT_STEPS=<n> → autopilot takes exactly N actions and then STOPS,
    /// parking the app on whatever phase it reached. Plain autopilot advances every 0.9s,
    /// which is far too tight to catch the reveal with a `sleep` — so the store-screenshot
    /// run uses STEPS=1 to submit one answer and hold on the reveal for as long as the
    /// capture needs (docs/STORE-SCREENSHOTS.md §2). nil = run to completion.
    static var autopilotSteps: Int? {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOPILOT_STEPS"].flatMap(Int.init)
    }

    /// TIDBITS_NIGHT_SETUP=1 → open the Trivia Night setup surface on launch (the store
    /// screenshot for the night; distinct from TIDBITS_NIGHT_HOST, which starts hosting).
    static var openNightSetup: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_NIGHT_SETUP"] == "1"
    }

    /// TIDBITS_TAB="records"|"create"|"play" → open straight to a tab.
    static var initialTab: AppStore.Tab? {
        ProcessInfo.processInfo.environment["TIDBITS_TAB"]
            .flatMap { AppStore.Tab(rawValue: $0) }
    }

    /// TIDBITS_PAYWALL=1 → present the Club paywall on launch (screenshot observability).
    static var showPaywall: Bool { ProcessInfo.processInfo.environment["TIDBITS_PAYWALL"] == "1" }

    /// TIDBITS_CLUB_HUB=1 → open the Club hub on launch (R-CLUB-1's one door). Combine with
    /// TIDBITS_CLUB=1, since non-members are routed to the paywall instead.
    static var openClubHub: Bool { ProcessInfo.processInfo.environment["TIDBITS_CLUB_HUB"] == "1" }

    /// TIDBITS_CLUB=1 → force `EntitlementStore.isClub` true. Pre-launch there are no
    /// real purchases, so this is how every Club feature gets verified
    /// (docs/CLUB-FEATURES-BUILD.md gating convention).
    static var forceClub: Bool { ProcessInfo.processInfo.environment["TIDBITS_CLUB"] == "1" }

    /// TIDBITS_AUTOCREATE="<topic>" → prefill Create and generate a live
    /// quiz from Wikipedia (verifies the live generation path end to end).
    static var autoCreate: String? {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOCREATE"]
    }

    /// TIDBITS_PLAY_SAVED=1 → replay the most recently saved quiz on launch. This is
    /// the only way to exercise `resolveAgainstBundle` against the REAL bundled
    /// corpus: the logic-only test bundle has no corpus.sqlite, so refs resolving
    /// correctly is a simulator-only check.
    static var playSavedQuiz: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_PLAY_SAVED"] == "1"
    }

    /// TIDBITS_SHARED_QUIZ="<id>" → act as if `tidbitstrivia://quiz/<id>` arrived.
    /// The OS confirmation dialog on `simctl openurl` can't be dismissed from the
    /// CLI, so this exercises everything downstream of delivery.
    static var sharedQuizID: String? {
        ProcessInfo.processInfo.environment["TIDBITS_SHARED_QUIZ"]
    }

    /// TIDBITS_CREATE=1 → open Create on launch. On tvOS the surface is several
    /// focus-moves down the home screen, and driving the remote from the CLI is far
    /// less reliable than saying which screen you want.
    static var openCreate: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_CREATE"] == "1"
    }

    /// TIDBITS_CREATE_SWEEP="<path>" → run Create's real assembly over every topic
    /// in that file and print the resulting question set, then exit.
    ///
    /// Relevance can be reasoned about against `corpus.sqlite` from a script, but
    /// what the PLAYER gets is decided by the shipped Swift — the bundled corpus,
    /// the shape sources, the live top-up and the assembly order together. This
    /// runs hundreds of topics through exactly that, on the simulator, in one
    /// launch. `TIDBITS_CREATE_SWEEP_CORPUS_ONLY=1` skips the live top-up so a
    /// sweep measures the offline floor instead of the network.
    static var createSweepPath: String? {
        ProcessInfo.processInfo.environment["TIDBITS_CREATE_SWEEP"]
    }

    /// TIDBITS_CREATE_SWEEP_SEARCH_ONLY=1 → emit ONLY `CorpusDatabase.search`, with
    /// no shape-source questions mixed in. The shape sets reuse corpus IDs
    /// (`src:describe:K._R._Narayanan` is both a corpus row and a picture row), so a
    /// cross-stack diff cannot tell which source a question came from — this makes
    /// the ranker comparable against the other engines on its own terms.
    static var createSweepSearchOnly: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_CREATE_SWEEP_SEARCH_ONLY"] == "1"
    }

    static var createSweepCorpusOnly: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_CREATE_SWEEP_CORPUS_ONLY"] == "1"
    }

    /// TIDBITS_PLAY_SWEEP=<n> → play N real games across every mode x category and
    /// print each delivered question as JSON, then exit.
    ///
    /// The Create sweep audits ONE surface. A player meets the corpus through
    /// fourteen modes and nine categories, and the things that spoil a round —
    /// a duplicated distractor, a shape-less "Closest Call", a round that comes
    /// up four questions short — are properties of the assembled ROUND, not of any
    /// row. This drives the shipped assembly at that scale so they are measurable.
    static var playSweepGames: Int? {
        ProcessInfo.processInfo.environment["TIDBITS_PLAY_SWEEP"].flatMap(Int.init)
    }

    /// TIDBITS_PLAYTHROUGH=<n> → actually PLAY n games to their results screen,
    /// answering correctly, and report anything the game got wrong about it.
    /// Distinct from TIDBITS_PLAY_SWEEP, which only assembles rounds and inspects
    /// the questions — it never submits an answer, so it cannot see a right answer
    /// marked wrong, a round that will not end, or a score that disagrees with the
    /// play.
    static var playthroughGames: Int? {
        ProcessInfo.processInfo.environment["TIDBITS_PLAYTHROUGH"].flatMap(Int.init)
    }

    /// TIDBITS_MARATHON_GAMES=<n> → play N games back to back THROUGH THE REAL
    /// VIEWS, walking the mode x category grid, without relaunching the app.
    ///
    /// `TIDBITS_PLAYTHROUGH` drives the engine and finishes a thousand games in
    /// minutes, which tests the RULES and renders nothing. It cannot see a clipped
    /// option, an empty panel, a reveal that scrolls off. This one goes through
    /// GamePlayView and ResultsView at the autopilot's real pace, so every screen
    /// is drawn and can be photographed — a thousand games takes hours, and that
    /// is the point of it.
    static var marathonGames: Int? {
        ProcessInfo.processInfo.environment["TIDBITS_MARATHON_GAMES"].flatMap(Int.init)
    }

    /// The nth (mode, category) of the rendered marathon — the same odometer the
    /// engine sweep walks, so the two runs cover the grid in the same order and
    /// their findings line up game for game.
    static func marathonCombination(at index: Int) -> (mode: GameMode, category: TriviaCategory) {
        let modes = playSweepModes, cats = playSweepCategories
        return (modes[index % modes.count], cats[(index / modes.count) % cats.count])
    }

    /// TIDBITS_AUTOPILOT_DELAY=<seconds> → override the autopilot's 0.9s step.
    /// The default is tuned so a human can watch; a long unattended run can go
    /// faster without skipping a single rendered frame.
    static var autopilotDelay: Double {
        ProcessInfo.processInfo.environment["TIDBITS_AUTOPILOT_DELAY"]
            .flatMap(Double.init) ?? 0.9
    }

    /// TIDBITS_QUESTION="<id>[,<id>…]" → start a game containing exactly those
    /// corpus rows, so a specific question can be LOOKED AT.
    ///
    /// The audit can say "131 prompts are over 220 characters"; it cannot say
    /// whether any of them overflows, truncates or simply reads long, and driving
    /// a random round until the one you care about turns up is not a plan. This
    /// makes "does this row render" a one-command question.
    static var forcedQuestionIDs: [String]? {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_QUESTION"] else { return nil }
        let ids = raw.split(separator: ",").map(String.init)
        return ids.isEmpty ? nil : ids
    }

    /// TIDBITS_PLAYTHROUGH_STYLE=correct|wrong|timeout → how the playthrough plays.
    /// Auditing only the happy path misses whole classes of bug (the tie, the
    /// zero, the round that ends on question one), so the losing outcomes get
    /// driven too.
    static var playthroughStyle: String {
        ProcessInfo.processInfo.environment["TIDBITS_PLAYTHROUGH_STYLE"] ?? "correct"
    }

    /// TIDBITS_PLAY_SWEEP_MODES / _CATS → restrict the sweep grid (comma-separated
    /// raw values). Default is the fourteen modes and nine categories the mode and
    /// category pickers actually offer.
    static var playSweepModes: [GameMode] {
        let picker: [GameMode] = [.classic, .timeAttack, .survival, .stake, .sweep,
                                  .pictureId, .thisOrThat, .closestCall, .ordering,
                                  .matching, .typeAnswer, .oddOneOut, .ladder, .enumerate]
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_PLAY_SWEEP_MODES"] else { return picker }
        let names = raw.split(separator: ",").map { String($0) }
        let picked = names.compactMap { GameMode(rawValue: $0) }
        // Say so when a name does not resolve. Passing "matchUp,inOrder" (the
        // real cases are `matching` and `ordering`) silently walked three modes
        // instead of five, and the run LOOKED like a clean sweep of the board
        // modes. A harness that quietly narrows its own coverage reports success
        // it did not earn.
        let unknown = names.filter { GameMode(rawValue: $0) == nil }
        if !unknown.isEmpty {
            print("MARATHON-BAD-MODE\t\(unknown.joined(separator: ","))\tknown: "
                  + picker.map(\.rawValue).joined(separator: ","))
        }
        return picked.isEmpty ? picker : picked
    }

    static var playSweepCategories: [TriviaCategory] {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_PLAY_SWEEP_CATS"] else {
            return TriviaCategory.all
        }
        let picked = raw.split(separator: ",").map { TriviaCategory.named(String($0)) }
        return picked.isEmpty ? TriviaCategory.all : picked
    }

    /// TIDBITS_TV_SHARE=1 → open the newest saved quiz's detail and publish it, so
    /// the QR panel can actually be seen. The tvOS simulator takes no synthesised
    /// remote presses, and a QR that has never been rendered is a QR nobody has
    /// checked scans.
    static var tvShareNewest: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_TV_SHARE"] == "1"
    }

    /// TIDBITS_PARTY=1 → open Pass & Play on launch (combine with AUTOPILOT
    /// to drive the whole party flow to the scoreboard for screenshots).
    /// TIDBITS_CUSTOMIZE=1 opens the Customize sheet on launch (screenshots).
    static var openCustomize: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_CUSTOMIZE"] == "1"
    }

    /// TIDBITS_CUSTOMIZE_PICK="mode:category" → open Customize with that mode and
    /// category already selected. TIDBITS_AUTOPLAY would launch the game instead,
    /// and what needs looking at here is the PICKER — whether a combination the
    /// bundle cannot fill is visibly marked as such before the player commits.
    static var customizePick: (mode: GameMode, category: TriviaCategory)? {
        guard let raw = ProcessInfo.processInfo.environment["TIDBITS_CUSTOMIZE_PICK"] else { return nil }
        let parts = raw.split(separator: ":").map(String.init)
        guard let mode = GameMode(rawValue: parts.first ?? "") else { return nil }
        return (mode, TriviaCategory.named(parts.count > 1 ? parts[1] : "mixed"))
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

    /// TIDBITS_PROFILE=1 → push Profile inside Settings on open (iOS). Profile owns Sign in
    /// with Apple and Delete Account, so both stay verifiable without a tap.
    static var openProfile: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_PROFILE"] == "1"
    }

    /// TIDBITS_NO_GAMECENTER=1 → never call `GKLocalPlayer.authenticateHandler`, so GameKit's
    /// full-screen sign-in sheet can't cover the app during simulator screenshots.
    static var skipGameCenter: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_NO_GAMECENTER"] == "1"
    }

    /// TIDBITS_ITEM=<id> opens the shared-question sheet on launch — the same thing
    /// `tidbits://item/<id>` does. `simctl openurl` puts iOS's "Open in Tidbits?" prompt
    /// in the way and this dev box has no GUI Simulator window to tap it, so a deep link
    /// is otherwise unverifiable from the CLI (docs/DEEP_LINKS.md).
    static var openItemID: String? {
        ProcessInfo.processInfo.environment["TIDBITS_ITEM"]
    }

    /// TIDBITS_SETTINGS=1 opens Settings on launch — same screenshot/
    /// simulator observability idiom as the flags above (tvOS has no GUI
    /// Simulator window on this dev box to tap through to it manually).
    static var openSettings: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_SETTINGS"] == "1"
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

    /// TIDBITS_LIVE_JOIN=<code> → open the JOIN surface on launch. iOS read this
    /// already; tvOS had no way to reach its join screen without a remote press,
    /// so the Apple TV could host a night but could never be driven to join one.
    static var openLiveJoin: String? {
        guard let c = ProcessInfo.processInfo.environment["TIDBITS_LIVE_JOIN"]?
                .trimmingCharacters(in: .whitespaces), !c.isEmpty else { return nil }
        return c
    }

    /// TIDBITS_NIGHT_AUTOSTART=<seconds> → after the room is open and this many
    /// seconds have passed, start the night without waiting for the host's press.
    ///
    /// A night deliberately sits in a LOBBY until a human starts it — that is correct
    /// product behaviour, and it is why a whole matrix of "every platform hosts a
    /// night" reported `host published no question` on every Apple host. The harness
    /// could press only the Apple TV's remote; the other four had no way to begin.
    /// One hook beats four ways to press a button, and the grace period is what makes
    /// it useful: the joiners need time to land before the first question publishes.
    static var nightAutostart: TimeInterval? {
        guard let v = ProcessInfo.processInfo.environment["TIDBITS_NIGHT_AUTOSTART"],
              let n = TimeInterval(v), n >= 0 else { return nil }
        return n
    }

    /// TIDBITS_QA_LABEL=<text> → draw a small banner naming what this device is
    /// testing. Six devices on a desk all running Tidbits look identical, so a bench
    /// photograph said nothing about which one was under test, and a device left over
    /// from an earlier run was indistinguishable from one in the current run.
    static var qaLabel: String? {
        guard let v = ProcessInfo.processInfo.environment["TIDBITS_QA_LABEL"]?
                .trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        return String(v.prefix(60))
    }

    /// TIDBITS_LIVE_NAME=<name> → the display name to join a room under.
    ///
    /// The Kotlin twin (`tidbits_live_name`) existed; Apple's did not, so every Apple
    /// device joined under whatever profile name the device already had. In a
    /// multi-device run that made the iPhone and the iPad BOTH "iOS Tester" — two rows
    /// with one name, indistinguishable in the standings, and a join count that read
    /// "3 of 4 landed" when all four had. A harness that cannot tell its devices apart
    /// cannot prove a device joined.
    static var liveJoinName: String? {
        guard let n = ProcessInfo.processInfo.environment["TIDBITS_LIVE_NAME"]?
                .trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return String(n.prefix(24))
    }

    /// TIDBITS_NIGHT_HOST=1 → open the RTDB Trivia Night host lobby (code + QR).
    static var openNightHost: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_NIGHT_HOST"] == "1"
    }

    /// TIDBITS_NIGHT_PLAYS=1 / TIDBITS_NIGHT_SPEED=1 → preset the host lobby's
    /// "I'll play too" / "Speed bonus" toggles. The QA harness's remote presses
    /// are unreliable enough that toggling chips by focus dance costs more than
    /// it tests; the chips' own toggling is covered by direct UI runs.
    static var nightHostPlays: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_NIGHT_PLAYS"] == "1"
    }
    static var nightSpeedBonus: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_NIGHT_SPEED"] == "1"
    }

    /// TIDBITS_SKIP_ONBOARD=1 → treat onboarding as already done. A fresh simulator install
    /// otherwise opens on the walkthrough, so the Home and Create store shots both came back
    /// as the same "All of Wikipedia, as trivia" card (docs/STORE-SCREENSHOTS.md §2).
    static var skipOnboarding: Bool {
        ProcessInfo.processInfo.environment["TIDBITS_SKIP_ONBOARD"] == "1"
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

    /// Records reads the IDENTITY streak, not the legacy per-device one — so a seeded run
    /// needs both, and this half has to survive `bootstrap()` replacing the profile.
    @MainActor
    static func applyIdentitySeed(_ n: Int) {
        PlayerIdentityStore.shared.seedForScreenshots(
            streak: 12, longest: 27, games: n,
            correct: (7 * n * 3) / 4, answered: 7 * n)
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
        // Records shows the IDENTITY streak, not this legacy per-device one — seed it too,
        // or the store screenshot reads "0 days" beside a full game history.
        // Bootstrap is async and replaces `profile` wholesale, so seeding here alone gets
        // clobbered — the app entry re-applies this once bootstrap has settled.
        applyIdentitySeed(n)
    }
}
