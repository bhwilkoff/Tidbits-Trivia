#if os(macOS)
import SwiftUI
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

// MARK: - Host session (macOS-DESIGN Part A §A3 — the emcee cockpit)

/// The live hosting session: the host drives pacing + reveal, and OWNS the
/// score (manual override is first-class — the #1 gap across the field, §A3.2).
/// v1 is paper-style (teams answer on paper, host marks); networked phone join
/// (#10) layers on top without changing this model.
@Observable
@MainActor
final class LiveHostSession {
    /// The session owns its OWN copy of the night, so this is var: G5 marks board
    /// cells taken as they are played, and the grid the projector draws has to be
    /// the same object the host picks from or the two drift apart mid-round.
    var event: LiveEvent
    var teams: [LiveTeam] = []
    var index = 0
    var revealed = false
    var scoredIndices: Set<Int> = []   // adaptability: score each question ONCE (so go-back / re-reveal never double-scores)
    var onBreak = false                // adaptability: hold the big screen on an intermission slide (game position preserved)
    /// Show the standings SO FAR on the big screen, between rounds. A pub host
    /// reads the scores out after every round; the projector could show a vote
    /// tally per question and the FINAL table, and nothing in between
    /// (COMPETITOR-SCAN G2 — QuizXpress, Sporcle and Crowdpurr all do this).
    var showScores = false
    /// G5: hold the big screen on the pick-a-category GRID, between questions of a
    /// board round. The room cannot pick a cell it cannot see, so this is a real
    /// phase of the round rather than a decoration.
    var showBoard = false
    /// G5: the team whose turn it is to pick (nil = anyone / not a board round).
    var boardChooser: String? = nil
    var finished = false
    var deadlineMs: Int? = nil   // Wave A: epoch-ms countdown deadline for the current timed question
    var locked = false           // Wave C: answers locked ("pencils down") — auto-set at the timer deadline or manually
    var blockedTeams: Set<String> = []   // Wave C: networked team uids the host hid from the big screen (a bad name)
    /// G1: teams that already buzzed this question and got it WRONG. They are
    /// skipped when resolving the next buzz, which is what "a wrong buzz reopens
    /// it to the rest" means in practice. Cleared with every question.
    var buzzedOut: Set<String> = []
    func toggleBlocked(_ uid: String) { if blockedTeams.contains(uid) { blockedTeams.remove(uid) } else { blockedTeams.insert(uid) } }
    /// Points DEDUCTED for a wrong answer, 0 = off (the default, and what every
    /// existing night has played under). QuizXpress offers this and pub hosts use
    /// it to stop blind guessing on a four-option question — see COMPETITOR-SCAN
    /// G3. Only a team that ANSWERED can lose points: staying silent is not wrong,
    /// it is declining to guess, and penalising it would punish a table whose phone
    /// died.
    var wrongAnswerPenalty = 0

    /// Points a correct answer is worth this round (host-adjustable; pub default 1).
    var pointsPerCorrect = 1
    /// Per-question display shuffles (fixed once so publish + reveal agree).
    var shuffledOrder: [String] = []
    var shuffledValues: [String] = []

    init(event: LiveEvent) { self.event = event; prepare(); armTimer() }

    /// Compute the display shuffles for the current question (ordering/matching).
    func prepare() {
        shuffledOrder = current?.ordering?.shuffled() ?? []
        shuffledValues = current?.matching?.values.shuffled() ?? []
        buzzedOut = []          // G1: a new question reopens the buzzer to everyone
    }

    var questions: [Question] { event.questionStream }
    var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    var roundNumber: Int { (current?.roundIndex ?? 0) + 1 }
    var roundCount: Int { max(event.rounds.count, 1) }
    var roundTitle: String {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? event.rounds[ri].title : ""
    }
    /// Wave A: the host's prep note for the current round (cockpit-only; never published).
    var currentRoundNote: String? {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? event.rounds[ri].hostNote : nil
    }
    /// Wave A: is the current round a wager round (teams stake points)?
    var currentRoundIsWager: Bool {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? (event.rounds[ri].isWager ?? false) : false
    }
    /// G4: the first-letter theme of the current round, if it has one — the room
    /// is told the rule on the big screen, not just by the host saying it once.
    var currentRoundLetter: Character? {
        let ri = current?.roundIndex ?? 0
        guard event.rounds.indices.contains(ri) else { return nil }
        return event.rounds[ri].letter?.first.map { Character($0.uppercased()) }
    }
    /// G5: the pick-your-category grid of the current round, if it is a board
    /// round — what the projector draws and the host picks from.
    var currentRoundBoard: LiveBoard? {
        let ri = current?.roundIndex ?? 0
        guard event.rounds.indices.contains(ri) else { return nil }
        return event.rounds[ri].board
    }
    /// Wave B: is the current round a speed round (fastest-first bonus)?
    var currentRoundIsSpeed: Bool {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? (event.rounds[ri].isSpeed ?? false) : false
    }
    /// G1: is the current round a BUZZ round?
    var currentRoundIsBuzz: Bool {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? (event.rounds[ri].isBuzz ?? false) : false
    }


    /// Wave B: the audio clip bookmark for the current question (nil unless it's an audio round).
    var currentAudioBookmark: Data? {
        let ri = current?.roundIndex ?? 0
        guard event.rounds.indices.contains(ri), let bms = event.rounds[ri].audioBookmarks else { return nil }
        let pos = questionInRound.n - 1
        return bms.indices.contains(pos) ? bms[pos] : nil
    }
    /// Wave B: the video clip bookmark for the current question (nil unless it's a video round).
    var currentVideoBookmark: Data? {
        let ri = current?.roundIndex ?? 0
        guard event.rounds.indices.contains(ri), let bms = event.rounds[ri].videoBookmarks else { return nil }
        let pos = questionInRound.n - 1
        return bms.indices.contains(pos) ? bms[pos] : nil
    }
    var questionInRound: (n: Int, of: Int) {
        let ri = current?.roundIndex ?? 0
        let inRound = questions.enumerated().filter { $0.element.roundIndex == ri }
        let pos = (inRound.firstIndex { $0.offset == index } ?? 0) + 1
        return (pos, inRound.count)
    }

    func addTeam(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !teams.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return }
        teams.append(LiveTeam(name: n))
    }
    func removeTeam(_ id: LiveTeam.ID) { teams.removeAll { $0.id == id } }
    /// Wave C: merge one team's score into another and drop it (a split team reconciled).
    func merge(_ from: LiveTeam.ID, into to: LiveTeam.ID) {
        guard from != to,
              let fi = teams.firstIndex(where: { $0.id == from }),
              let ti = teams.firstIndex(where: { $0.id == to }) else { return }
        teams[ti].score += teams[fi].score
        teams.remove(at: fi)
    }
    /// Manual score adjustment — the referee model (§A3.2). Never below 0.
    func adjust(_ id: LiveTeam.ID, by delta: Int) {
        guard let i = teams.firstIndex(where: { $0.id == id }) else { return }
        teams[i].score = max(0, teams[i].score + delta)
    }
    func reveal() { revealed = true; deadlineMs = nil }
    func next() {
        revealed = false
        locked = false   // Wave C: new question — answers reopen
        if index + 1 >= questions.count { finished = true } else { index += 1; prepare(); armTimer() }
        LiveVideoPlayer.shared.stop()   // Wave B: clear the previous question's video + clip (the music bed keeps looping)
        LiveAudioPlayer.shared.stop()
    }

    /// G5: the room picked a cell — play it.
    ///
    /// Marks the cell taken on the ROUND (so the grid the projector draws and the
    /// question the host reads can never disagree) and jumps to that question.
    /// Returns false when the cell is missing or already taken, which is what a
    /// second click on the same tile is; the caller must not advance on that.
    @discardableResult
    func pickBoardCell(_ categoryID: String, _ tier: Int) -> Bool {
        let ri = current?.roundIndex ?? 0
        guard event.rounds.indices.contains(ri),
              var board = event.rounds[ri].board,
              let cell = board.cell(categoryID, tier), !cell.taken,
              board.take(categoryID, tier) else { return false }
        event.rounds[ri].board = board
        guard let target = questions.firstIndex(where: { $0.id == cell.questionID }) else { return false }
        revealed = false
        locked = false
        showBoard = false
        index = target
        prepare()
        armTimer()
        return true
    }

    /// G5: back to the grid for the next pick.
    func returnToBoard() {
        revealed = false
        showBoard = true
    }

    /// G5: the chooser for the next pick, from the team that just answered
    /// correctly. Rotates when nobody did, so one table cannot drive the board.
    func advanceBoardChooser(correct: String?, teams: [String]) {
        boardChooser = LiveBoardBuilder.nextChooser(current: boardChooser, correct: correct, teams: teams)
    }

    /// Adaptability: skip the current question WITHOUT revealing or scoring it ("let's skip this one").
    func skip() {
        guard index + 1 < questions.count else { finished = true; return }
        revealed = false; locked = false
        index += 1; prepare(); armTimer()
        LiveVideoPlayer.shared.stop(); LiveAudioPlayer.shared.stop()
    }

    /// Adaptability: step back to the previous question, shown already-revealed (it was scored;
    /// the scoredIndices guard means re-revealing never double-scores). "Wait, go back."
    func previous() {
        guard index > 0 else { return }
        index -= 1; prepare()
        locked = false; deadlineMs = nil
        revealed = true
        LiveVideoPlayer.shared.stop(); LiveAudioPlayer.shared.stop()
    }
    var canGoBack: Bool { index > 0 }

    /// Adaptability: jump to any question (or the first of any round) on the fly. Un-revealed +
    /// re-armed; the scoredIndices guard keeps scoring correct if you leap over questions.
    func jump(to i: Int) {
        guard questions.indices.contains(i), i != index else { return }
        revealed = false; locked = false
        index = i; prepare(); armTimer()
        LiveVideoPlayer.shared.stop(); LiveAudioPlayer.shared.stop()
    }
    /// Adaptability: extend the current question's countdown live ("give them 30 more seconds").
    /// Starting from now if no timer was running. Re-opens answers if a passed timer had auto-locked.
    func addTime(_ seconds: Int) {
        let base = max(deadlineMs ?? 0, Int(Date().timeIntervalSince1970 * 1000))
        deadlineMs = base + seconds * 1000
        locked = false
    }
    /// Adaptability: drop the countdown entirely (untimed from here).
    func clearTimer() { deadlineMs = nil }

    /// Wave A: arm the per-question countdown from the current round's timer (0/nil = off).
    func armTimer() {
        let ri = current?.roundIndex ?? 0
        let secs = (event.rounds.indices.contains(ri) ? event.rounds[ri].timerSeconds : nil) ?? 0
        deadlineMs = secs > 0 ? Int(Date().timeIntervalSince1970 * 1000) + secs * 1000 : nil
    }
    var standings: [LiveTeam] { teams.sorted { $0.score > $1.score } }

    // MARK: Tie-break engine (§A3.5 — the field punts this; we ship it)

    /// Groups of teams sharing a score (the ties a host must resolve for prizes).
    var tiedGroups: [[LiveTeam]] {
        Dictionary(grouping: teams.filter { $0.score > 0 }, by: \.score)
            .values.filter { $0.count > 1 }
            .sorted { ($0.first?.score ?? 0) > ($1.first?.score ?? 0) }
            .map { $0.sorted { $0.name < $1.name } }
    }
    /// Resolve a tie: the closest guess to `target` wins the tie-break (+1),
    /// nudging them clear. Numeric "closest wins" is the pub-standard protocol.
    func breakTie(target: Double, guesses: [LiveTeam.ID: Double]) {
        guard let winner = guesses.min(by: { abs($0.value - target) < abs($1.value - target) })?.key else { return }
        adjust(winner, by: 1)
    }

    // MARK: Networked publish (the pub state phones/web render — LiveRoom.Pub)

    var currentFormat: String {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? event.rounds[ri].format.rawValue : ""
    }
    /// The live state to publish for the current question (or an "ended" frame).
    func currentPub() -> LiveRoom.Pub {
        // G5: while the grid is up there is NO live question. Publishing the
        // previous one left it on every phone with its answer buttons live, so the
        // room could answer a question that was no longer being asked.
        if showBoard, let b = currentRoundBoard {
            return LiveRoom.Pub(
                round: roundNumber, roundTitle: roundTitle, qid: "board-\(roundNumber)",
                qNum: 0, qTotal: 0, phase: LiveRoom.Phase.board,
                prompt: "Pick a category", options: nil, format: "", answerIndex: nil,
                board: LiveRoom.BoardPub(
                    categories: b.categories.map { TriviaCategory.named($0).name },
                    tiers: b.tiers,
                    taken: b.cells.filter(\.taken).compactMap { cell in
                        b.categories.firstIndex(of: cell.categoryID).map { "\($0):\(cell.tier)" }
                    },
                    chooser: boardChooser,
                    remaining: b.remaining.count,
                    points: b.pointsRemaining))
        }
        guard let q = current else {
            return LiveRoom.Pub(round: roundNumber, roundTitle: roundTitle, qid: "end", qNum: 0, qTotal: 0,
                                phase: LiveRoom.Phase.ended, prompt: "", options: nil, format: "", answerIndex: nil)
        }
        let inR = questionInRound
        let mcq = LiveNightHost.isMCQ(q)
        var p = LiveRoom.Pub(round: roundNumber, roundTitle: roundTitle,
                             qid: LiveRoom.qid(round: q.roundIndex ?? 0, question: index),
                             qNum: inR.n, qTotal: inR.of,
                             phase: revealed ? LiveRoom.Phase.reveal : LiveRoom.Phase.question,
                             prompt: q.prompt, options: mcq ? q.options : nil, format: currentFormat,
                             answerIndex: (revealed && mcq) ? q.correctIndex : nil)
        p.imageURL = q.imageURL?.absoluteString
        if let c = q.closest { p.numeric = LiveRoom.Numeric(min: c.min, max: c.max, step: c.step, unit: c.unit) }
        if q.ordering != nil { p.orderItems = shuffledOrder }
        if let m = q.matching { p.matchKeys = m.keys; p.matchValues = shuffledValues }
        if let e = q.enumerate { p.enumTarget = e.total }
        if !revealed, let d = deadlineMs { p.deadline = d }   // Wave A: the countdown deadline
        if !revealed, locked { p.locked = true }              // Wave C: pencils down — no more answers
        if !revealed, currentRoundIsWager { p.wager = true }  // Wave A: wager round — joiners show a stake input
        if !revealed, currentRoundIsBuzz { p.buzz = true }    // G1: buzz round — joiners show a BUZZ button
        if let l = currentRoundLetter { p.letter = String(l) }   // G4: first-letter round — joiners see the rule
        if revealed {   // Wave A: the story behind the answer — the learning payoff, only at reveal
            let s = q.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { p.story = s }
        }
        return p
    }
}

// MARK: - Host container + cockpit

struct LiveHostContainer_macOS: View {
    let event: LiveEvent
    let onClose: () -> Void
    @Environment(LiveHostCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var session: LiveHostSession
    @State private var net = LiveHostNet()
    @State private var lockTask: Task<Void, Never>?   // Wave C: auto-lock at the timer deadline

    init(event: LiveEvent, onClose: @escaping () -> Void) {
        self.event = event; self.onClose = onClose
        _session = State(initialValue: LiveHostSession(event: event))
    }
    /// The single way a night ends. Extracted so the close button and the
    /// TIDBITS_LIVE_AUTOCLOSE hook cannot drift apart — an exit path that only
    /// one of them takes is an exit path nothing tests.
    private func endNight() {
        let net = self.net
        Task { await net.close() }
        coordinator.session = nil            // clear the projector
        coordinator.net = nil
        // ...and CLOSE it. Clearing the session only emptied the projector; the
        // window stayed open on its idle splash forever, which is what left
        // stale "The host will start the night shortly" screens behind after
        // every night. The projector exists to show a session, so it goes when
        // the session does.
        dismissWindow(id: "tidbits-bigscreen")
        onClose()
    }

    var body: some View {
        LiveHostView_macOS(session: session, net: net) { endNight() }
        .onAppear {
            coordinator.session = session          // publish to the big screen (§A1.1)
            coordinator.net = net
            openWindow(id: "tidbits-bigscreen")     // pop the projector window
        }
        // TIDBITS_LIVE_AUTOCLOSE=<seconds> → end the night on its own. The close
        // control is an icon-only Button deep in the view tree, so it has no
        // accessibility name and cannot be driven from a harness; without this
        // the projector's teardown was the one part of the fix nothing could
        // prove. No-op unless the variable is set.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["TIDBITS_LIVE_AUTOCLOSE"],
                  let secs = Double(raw) else { return }
            try? await Task.sleep(for: .seconds(secs))
            endNight()
        }
        // TIDBITS_LIVE_STATE=reveal|break|standings — put the PROJECTOR into one of
        // the states only a host's clicks can reach.
        //
        // The projector is what the room reads, and until the truncation bug it had
        // never been photographed at all. Every one of these states is a separate
        // layout: the reveal adds the answer capsule, the vote tally and the
        // explanation; standings is a different slide entirely; break is a third.
        // The bug that shipped lived in the ONE state nothing could capture, so the
        // remaining ones get hooks before they are trusted (hooks-are-coverage).
        // No-op in production.
        .task {
            guard let want = ProcessInfo.processInfo.environment["TIDBITS_LIVE_STATE"] else { return }
            try? await Task.sleep(for: .seconds(3))   // let the room open and publish
            switch want {
            case "reveal":    session.reveal()
            case "break":     session.onBreak = true
            case "scores":    session.showScores = true
            case "standings": session.finished = true
            case "board":     session.showBoard = true
            default: break
            }
        }
        // Open the networked room and publish the first question.
        .task {
            await net.open(name: event.name, venue: event.venue)
            await net.setState("live")
            await net.publish(session.currentPub())
        }
        // Re-publish whenever the host advances or reveals; auto-score on reveal.
        .onChange(of: session.index) { _, _ in
            Task { await net.publish(session.currentPub()) }
        }
        .onChange(of: session.revealed) { _, revealed in
            Task {
                await net.publish(session.currentPub())
                if revealed { await scoreReveal() }
            }
        }
        .onChange(of: session.finished) { _, done in
            if done { Task { await net.setState("ended"); await net.publish(session.currentPub()) } }
        }
        // Wave C: answer-lock timer — when a question is armed with a deadline, auto-lock
        // answers ("pencils down") the moment it passes, and republish so phones stop accepting.
        .onChange(of: session.deadlineMs) { _, deadline in
            lockTask?.cancel()
            Task { await net.publish(session.currentPub()) }   // adaptability: extend/clear updates the room's countdown live
            guard let deadline else { return }
            lockTask = Task {
                let ms = deadline - Int(Date().timeIntervalSince1970 * 1000)
                if ms > 0 { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
                guard !Task.isCancelled, session.deadlineMs == deadline, !session.revealed else { return }
                session.locked = true
                await net.publish(session.currentPub())
            }
        }
    }

    /// On reveal, auto-score every joined team's submission for EVERY question type
    /// (shared scorer). Free-text answers are alias-matched; the host reviews +
    /// overrides borderline ones in the scoreboard (§A3.3 leniency). Manual ± still
    /// applies on top (§A3.2).
    private func scoreReveal() async {
        guard let q = session.current else { return }
        guard !session.scoredIndices.contains(session.index) else { return }   // adaptability: score each question ONCE
        session.scoredIndices.insert(session.index)
        let wagerRound = session.currentRoundIsWager
        let speedRound = session.currentRoundIsSpeed
        var speedCorrect: [(uid: String, ts: Int, pts: Int)] = []
        // G7: exactly one answer per TEAM reaches the scoreboard. Walking the
        // answers per uid is correct while a device IS a team, and awards a table
        // twice the moment two of its phones answer — or penalises it twice under
        // negative marking.
        let scorable = LiveTeamRoster.scorableUIDs(
            members: net.members,
            answeredAt: net.answers.mapValues { $0.sv ?? $0.ts })
        for (uid, ans) in net.answers where scorable.contains(uid) {
            let pts = LiveNightHost.score(q, ans, shuffledOrder: session.shuffledOrder,
                                          shuffledValues: session.shuffledValues, mcqPoints: session.pointsPerCorrect)
            if wagerRound {
                // Wave A: stake clamped to the team's current score; correct +stake, wrong −stake.
                let current = net.scores[uid] ?? 0
                let stake = max(0, min(ans.wager ?? 0, current))
                guard stake > 0 else { continue }
                await net.setScore(uid, pts > 0 ? current + stake : current - stake)
            } else if pts > 0 {
                if speedRound { speedCorrect.append((uid, ans.sv ?? ans.ts, pts)) }   // server clock; falls back for older clients
                else { await net.setScore(uid, (net.scores[uid] ?? 0) + pts) }
            } else if session.wrongAnswerPenalty > 0 {
                // G3: negative marking. This team ANSWERED and got it wrong; a team
                // that submitted nothing never reaches here, which is the whole point.
                await net.setScore(uid, (net.scores[uid] ?? 0) - session.wrongAnswerPenalty)
            }
        }
        // Wave B: speed round — base points + a fastest-first bonus (1st correct +3, 2nd +2, 3rd +1).
        for (rank, c) in speedCorrect.sorted(by: { $0.ts < $1.ts }).enumerated() {
            await net.setScore(c.uid, (net.scores[c.uid] ?? 0) + c.pts + max(0, 3 - rank))
        }
    }
}

struct LiveHostView_macOS: View {
    @Bindable var session: LiveHostSession
    var net: LiveHostNet
    let onClose: () -> Void
    @State private var newTeam = ""
    @State private var showTieBreak = false
    @State private var tieGroup: [LiveTeam] = []

    var body: some View {
        Group {
            if session.finished { standings }
            else { cockpit }
        }
        // Explicit min so window resizing measures the prompt at a real width. Without
        // it, .contentMinSize proposes ~0 width to the fixedSize prompt Text, which
        // wraps to one glyph per line and reports a runaway min height (~5800px),
        // pinning the window absurdly tall. The projector avoids this the same way.
        // minHeight raised 560 → 680: the cockpit stage (header + join + question + round
        // indicators + answer distribution + timer + action row + the 3 AV bars) needs more than
        // 560pt, so at the old minimum the bottom AV controls clipped. This keeps the window tall
        // enough to show every control without a risky ScrollView restructure of the tuned layout.
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        .background(Tidbits.Palette.bg)
    }

    // MARK: Cockpit

    private var cockpit: some View {
        HStack(spacing: 0) {
            stage
            Divider().overlay(Tidbits.Palette.border)
            scoreboard
        }
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                Text(session.event.name).font(.headline).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button { session.showScores.toggle() } label: {   // G2: scores between rounds
                    Label(session.showScores ? "Hide scores" : "Scores",
                          systemImage: "list.number").font(.callout)
                }
                .buttonStyle(.bordered)
                .help("Show the standings so far on the big screen")
                Button { session.onBreak.toggle() } label: {   // adaptability: intermission hold
                    Label(session.onBreak ? "Resume" : "Hold", systemImage: session.onBreak ? "play.fill" : "pause.fill").font(.callout)
                }
                .buttonStyle(.bordered)
                // Tinted only while the break is ACTIVE. Tinting a bordered button
                // with the near-white surface colour erases its own label.
                .tint(session.onBreak ? Tidbits.Palette.mint : Color.accentColor)
                .keyboardShortcut("b", modifiers: .command)
                .help(session.onBreak ? "Resume the game" : "Hold — show a 'Back in a moment' slide on the big screen (⌘B)")
                Menu {   // adaptability: jump to any round/question on the fly
                    ForEach(Array(session.event.rounds.enumerated()), id: \.offset) { ri, round in
                        Section(round.title) {
                            ForEach(Array(session.questions.enumerated()).filter { $0.element.roundIndex == ri }, id: \.offset) { pair in
                                Button("\(pair.offset + 1). \(String(pair.element.prompt.prefix(50)))") { session.jump(to: pair.offset) }
                            }
                        }
                    }
                } label: { Label("Jump", systemImage: "list.number").font(.callout) }
                .menuStyle(.button).buttonStyle(.bordered).fixedSize()
                Text("ROUND \(session.roundNumber)/\(session.roundCount) · \(session.roundTitle)")
                    .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            if net.isOpen {
                HStack(spacing: 8) {
                    if let qr = makeLiveQR(liveJoinURL(net.code)) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 40, height: 40)
                    }
                    Text("Players scan, or join at tidbitstrivia.com/live").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text("CODE \(net.code)").font(.system(size: 15, weight: .black, design: .monospaced)).foregroundStyle(Tidbits.Palette.ink)
                    if !net.joined.isEmpty {
                        // Phones, not teams: this line tells the host whether the
                        // ROOM is filling up, and a table of three phones is three
                        // people who got in.
                        Text("· \(net.joined.count) joined").font(.callout).foregroundStyle(Tidbits.Palette.mint)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Tidbits.Palette.border.opacity(0.55), lineWidth: 1))
            }
            // G5: while the board is up nobody has picked a cell yet, so there IS
            // no current question. Showing the previous one with a live "Reveal
            // answer" under it invites the host to reveal a question the room was
            // never asked — which is what the first version of this panel did.
            if session.showBoard, let board = session.currentRoundBoard {
                boardPicker(board)
            } else if let q = session.current {
                let inR = session.questionInRound
                Text("Question \(inR.n) of \(inR.of)").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(q.prompt).font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink).fixedSize(horizontal: false, vertical: true)
                if let note = session.currentRoundNote, !note.isEmpty {   // Wave A: host prep note (cockpit only)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text").foregroundStyle(Tidbits.Palette.blue)
                        Text(note).font(.callout).foregroundStyle(Tidbits.Palette.blue).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Tidbits.Palette.blue.opacity(0.12)))
                }
                if session.currentRoundIsWager {   // Wave A: wager round indicator
                    Label("Wager round — teams stake points (correct +stake, wrong −stake)", systemImage: "dollarsign.circle.fill")
                        .font(.callout).foregroundStyle(Tidbits.Palette.coral)
                }
                if session.currentRoundIsSpeed {   // Wave B: speed round indicator
                    Label("Speed round — fastest correct answers earn a bonus (+3/+2/+1)", systemImage: "bolt.fill")
                        .font(.callout).foregroundStyle(Tidbits.Palette.yellow)
                }
                // An audio/video round shows either a WORKING play control or an
                // explicit "unavailable" line — never a Play button that does
                // nothing, which is what shipped and is what the host discovers
                // mid-round with a room watching.
                if let clip = session.currentAudioBookmark {   // Wave B: audio round — play this question's clip
                    if LiveClip.isPlayable(clip) {
                        Button { LiveAudioPlayer.shared.openBookmark(clip); LiveAudioPlayer.shared.togglePlay() } label: {
                            Label("Play this clip", systemImage: "play.circle.fill").font(.body)
                        }
                        .buttonStyle(.bordered).tint(Tidbits.Palette.blue)
                    } else {
                        Label("Clip unavailable — re-attach it in the builder", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(Tidbits.Palette.coral)
                    }
                }
                if let vid = session.currentVideoBookmark {   // Wave B: video round — play on the big screen
                    if LiveClip.isPlayable(vid) {
                        Button { LiveVideoPlayer.shared.openBookmark(vid); LiveVideoPlayer.shared.play() } label: {
                            Label("Play video on the big screen", systemImage: "play.rectangle.fill").font(.body)
                        }
                        .buttonStyle(.bordered).tint(Tidbits.Palette.blue)
                    } else {
                        Label("Video unavailable — re-attach it in the builder", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(Tidbits.Palette.coral)
                    }
                }
                if session.revealed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Tidbits.Palette.mint)
                        Text(q.correctAnswer).font(.title2.weight(.semibold)).foregroundStyle(Tidbits.Palette.ink)
                    }
                    if !q.explanation.isEmpty {
                        Text(q.explanation).font(.body).foregroundStyle(Tidbits.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Read it out. Reveal the answer when the room is ready.")
                        .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            answerDistribution   // §A3.4: live per-option tally — read the room before revealing
            if !session.revealed, session.current != nil {   // adaptability: extend/clear the countdown live
                HStack(spacing: 8) {
                    Image(systemName: "timer").foregroundStyle(Tidbits.Palette.inkSoft)
                    Button("+30s") { session.addTime(30) }.buttonStyle(.bordered)
                    Button("+15s") { session.addTime(15) }.buttonStyle(.bordered)
                    if session.deadlineMs != nil {
                        Button("Clear timer") { session.clearTimer() }.buttonStyle(.bordered)
                    }
                }
                .font(.caption)
            }
            Spacer()
            HStack(spacing: 12) {
                Button { session.previous() } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)) }   // adaptability: go back
                    .buttonStyle(.bordered)
                    .disabled(!session.canGoBack)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Back to the previous question (⌘←)")
                if session.showBoard {
                    // G5: the room is choosing. The only move is to pick a cell in
                    // the grid above, or to move on once the board is clear — a
                    // Lock/Skip/Reveal row here acts on a question nobody has asked.
                    if session.currentRoundBoard?.isComplete == true {
                        Button("Board clear — next round") { session.showBoard = false; session.next() }
                            .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Text("Waiting for the room to pick a cell.")
                            .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                } else if !session.revealed {
                    Button(session.locked ? "Answers locked" : "Lock answers") {   // Wave C: manual pencils-down
                        session.locked = true; Task { await net.publish(session.currentPub()) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.locked)
                    Button("Skip") { session.skip() }   // adaptability: skip this question (no score)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                        .help("Skip this question — no score (⌘→)")
                    // G1: the buzz panel. Only on a buzz round, and only once
                    // somebody has actually buzzed — a control that names nobody is
                    // noise in a cockpit the host is driving live.
                    if session.currentRoundIsBuzz, !session.revealed,
                       let uid = LiveNightHost.firstBuzz(net.answers, excluding: session.buzzedOut) {
                        let who = net.teams[uid]?.name ?? "Team"
                        Text("\(who) buzzed").font(.headline).foregroundStyle(Tidbits.Palette.coral)
                        Button("Correct") {
                            Task {
                                await net.setScore(uid, (net.scores[uid] ?? 0) + session.pointsPerCorrect)
                                session.reveal()
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(Tidbits.Palette.mint)
                        .help("Award \(session.pointsPerCorrect) and reveal")
                        Button("Wrong") { session.buzzedOut.insert(uid) }
                            .buttonStyle(.bordered)
                            .help("Rule this team out and reopen the buzzer to the rest")
                    }
                    Button("Reveal answer") { session.reveal() }
                        .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                        .keyboardShortcut(.defaultAction)
                } else if session.currentRoundBoard != nil {
                    // G5: on a board round the room chooses, so "Next question" is
                    // the wrong verb — the host goes BACK TO THE BOARD and taps
                    // whatever was called out.
                    Button(session.currentRoundBoard?.isComplete == true ? "Board clear — next round" : "Back to the board") {
                        if session.currentRoundBoard?.isComplete == true {
                            session.next()
                        } else {
                            session.returnToBoard()
                            // Republish: the flag alone changes the host's screen and
                            // leaves the last question live on every phone.
                            Task { await net.publish(session.currentPub()) }
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(session.index + 1 >= session.questions.count ? "Finish night" : "Next question") { session.next() }
                        .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
                Text("\(session.index + 1) / \(session.questions.count) overall · Space to advance").font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            showBar       // Wave B: stingers + clip playback + music bed, one wrapping row
            Button("") {   // intuitive: SPACE = advance the show (reveal → next) — the emcee's clicker key.
                guard !session.onBreak else { return }   // won't fire while a text field is focused (the field takes space)
                if session.revealed { session.next() } else { session.reveal() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// G5 — the cockpit's pick-a-category grid.
    private func boardPicker(_ board: LiveBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.boardChooser.map { "\($0) picks" } ?? "Pick a category")
                .font(.headline).foregroundStyle(Tidbits.Palette.ink)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(board.categories, id: \.self) { c in
                        Text(TriviaCategory.named(c).name)
                            .font(.caption).bold().foregroundStyle(Tidbits.Palette.inkSoft)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                ForEach(board.tiers, id: \.self) { t in
                    GridRow {
                        ForEach(board.categories, id: \.self) { c in
                            if let cell = board.cell(c, t) {
                                Button("\(cell.points)") {
                                    if session.pickBoardCell(c, t) {
                                        Task { await net.publish(session.currentPub()) }
                                    }
                                }
                                    .buttonStyle(.bordered)
                                    .disabled(cell.taken)
                                    .help(cell.taken ? "Already played" : "Play this cell")
                            } else {
                                Text("—").font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            Text("\(board.remaining.count) left · \(board.pointsRemaining) points on the board")
                .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
        }
        .padding(12).quietCard()
    }

    /// The show controls as ONE wrapping row. They used to render as three
    /// separate left-aligned rows stacked under the transport, which on a real
    /// cockpit reads as a pile of loose buttons rather than a control surface —
    /// and the bottom two ran off the panel the moment the window narrowed.
    /// `Layout`-free: an HStack in a ViewThatFits reflows to two lines instead
    /// of clipping (the Windows §6.3b rule, which is the same trap).
    private var showBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { sfxBar; Divider().frame(height: 20); audioClipBar; Divider().frame(height: 20); musicBedBar }
            VStack(alignment: .leading, spacing: 8) {
                sfxBar
                HStack(spacing: 10) { audioClipBar; Divider().frame(height: 20); musicBedBar }
            }
        }
    }

    /// Wave B: the SFX / stinger board — the host fires show sounds through the Mac's output
    /// (the venue PA when connected). Sounds are synthesized, so nothing is licensed or bundled.
    private var sfxBar: some View {
        HStack(spacing: 8) {
            Menu {   // Wave B: route show audio to the venue PA (or any output device)
                Button("System default") { LiveSFXBoard.shared.select(deviceID: nil, name: "System default") }
                ForEach(LiveSFXBoard.availableOutputs(), id: \.id) { dev in
                    Button(dev.name) { LiveSFXBoard.shared.select(deviceID: dev.id, name: dev.name) }
                }
            } label: { Label(LiveSFXBoard.shared.outputName, systemImage: "hifispeaker.fill").font(.caption) }
                .menuStyle(.button).buttonStyle(.bordered).fixedSize()
            Divider().frame(height: 20)
            ForEach(LiveSFXBoard.Stinger.allCases) { s in
                Button { LiveSFXBoard.shared.play(s) } label: {
                    Label(s.label, systemImage: s.symbol).font(.caption)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(s.shortcut, modifiers: [])
            }
        }
    }

    /// Wave B: play an audio clip through the routed output (walk-in music, an audio-round clip).
    private var audioClipBar: some View {
        let audio = LiveAudioPlayer.shared
        return HStack(spacing: 10) {
            Button { pickAudioClip() } label: { Label("Open clip…", systemImage: "music.note.list").font(.caption) }
                .buttonStyle(.bordered)
            if !audio.trackName.isEmpty {
                Button { audio.togglePlay() } label: { Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.bordered).tint(Tidbits.Palette.mint)
                Button { audio.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.bordered)
                Text(audio.trackName).font(.caption).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
            }
        }
    }

    private func pickAudioClip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { LiveAudioPlayer.shared.open(url) }
    }

    /// Wave B: a looping background music bed (walk-in / between-round) with a level slider.
    private var musicBedBar: some View {
        let bed = LiveMusicBed.shared
        return HStack(spacing: 10) {
            Button { pickMusicBed() } label: { Label("Music bed…", systemImage: "music.quarternote.3").font(.caption) }
                .buttonStyle(.bordered)
            if !bed.trackName.isEmpty {
                Button { bed.toggle() } label: { Image(systemName: bed.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.bordered).tint(Tidbits.Palette.blue)
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                Slider(value: Binding(get: { Double(bed.volume) }, set: { bed.volume = Float($0) }), in: 0...1).frame(width: 90)
                Text(bed.trackName).font(.caption).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
            }
        }
    }

    private func pickMusicBed() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { LiveMusicBed.shared.open(url) }
    }

    // MARK: Scoreboard (manual scoring — the differentiator)

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Teams").font(.headline).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Stepper(value: $session.wrongAnswerPenalty, in: 0...5) {
                    Text(session.wrongAnswerPenalty == 0
                         ? "No penalty"
                         : "−\(session.wrongAnswerPenalty) pt\(session.wrongAnswerPenalty == 1 ? "" : "s")/wrong")
                        .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .help("Deduct points for a wrong answer. Teams that do not answer are never penalised.")
                Stepper(value: $session.pointsPerCorrect, in: 1...10) {
                    Text("\(session.pointsPerCorrect) pt\(session.pointsPerCorrect == 1 ? "" : "s")/correct")
                        .font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                }
                .fixedSize()
                Button { exportResultsCSV() } label: { Image(systemName: "square.and.arrow.up") }   // Wave C: data export
                    .buttonStyle(.borderless).help("Export standings to CSV")
            }
            .padding(12)
            HStack(spacing: 8) {
                TextField("Add a team…", text: $newTeam)
                    .textFieldStyle(.roundedBorder).onSubmit { session.addTeam(newTeam); newTeam = "" }
                Button("Add") { session.addTeam(newTeam); newTeam = "" }.disabled(newTeam.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(spacing: 10) {
                    if net.isOpen {
                        HStack {
                            Text("JOINED").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                            Spacer()
                            if session.revealed == false, !net.answers.isEmpty {
                                Text("\(net.answeredTeamCount) answered").font(.caption).foregroundStyle(Tidbits.Palette.mint)
                            }
                        }
                        // G7: one row per TEAM. Listing net.joined showed a table
                        // that grouped as three near-identical rows splitting its
                        // own score.
                        if net.joinedTeams.isEmpty {
                            Text("Waiting for phones to join with code \(net.code)…")
                                .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        ForEach(net.joinedTeams) { joinedRow($0) }
                        if !session.teams.isEmpty {
                            Divider().overlay(Tidbits.Palette.border).padding(.vertical, 4)
                            Text("IN-ROOM (PAPER)").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                    } else if session.teams.isEmpty {
                        Text("Add the teams in the room. When you reveal an answer, tap ✓ to award points, or ± to correct any score.")
                            .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft).padding(.top, 20)
                    }
                    ForEach(session.standings) { team in teamRow(team) }
                }
                .padding(12)
            }
        }
        .frame(width: 320)
        .background(Tidbits.Palette.bgDeep)
    }

    /// Wave C: export the unified standings (phone + paper teams) to a CSV the host keeps.
    private func exportResultsCSV() {
        var rows: [(name: String, score: Int, kind: String)] = []
        for (uid, team) in net.teams { rows.append((team.name, net.scores[uid] ?? 0, "phone")) }
        for t in session.teams { rows.append((t.name, t.score, "paper")) }
        rows.sort { $0.score > $1.score }
        func esc(_ s: String) -> String {
            (s.contains(",") || s.contains("\"") || s.contains("\n"))
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        var csv = "rank,team,score,type\n"
        for (i, r) in rows.enumerated() { csv += "\(i + 1),\(esc(r.name)),\(r.score),\(r.kind)\n" }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(session.event.name) — results.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // A `try?` here is a Save button that does nothing when the write fails
            // — and the host only finds out when the file is not there afterwards.
            try Data(csv.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the results"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func teamRow(_ team: LiveTeam) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team.name).font(.headline).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                Text("\(team.score)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            }
            Spacer()
            // Award (only meaningful once revealed) + manual override (always).
            if session.revealed {
                Button { session.adjust(team.id, by: session.pointsPerCorrect) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(Tidbits.Palette.mint).help("Award \(session.pointsPerCorrect)")
            }
            Button { session.adjust(team.id, by: -1) } label: { Image(systemName: "minus") }.buttonStyle(.bordered)
            Button { session.adjust(team.id, by: 1) } label: { Image(systemName: "plus") }.buttonStyle(.bordered)
            Menu {
                if session.teams.count > 1 {   // Wave C: merge a split team into another
                    Menu("Merge into…") {
                        ForEach(session.teams.filter { $0.id != team.id }) { other in
                            Button(other.name) { session.merge(team.id, into: other.id) }
                        }
                    }
                }
                Button("Remove team", role: .destructive) { session.removeTeam(team.id) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 20)
        }
        .padding(12).quietCard()
    }

    /// A phone/web-joined team: auto-scored on reveal, with ± manual override
    /// (writes back to the room), a live "answered" dot, and — for free-text rounds
    /// — the team's typed answer with an auto-match verdict + a leniency "mark
    /// correct" the host can grant on a borderline miss (§A3.3, host pain #2).
    private func joinedRow(_ team: LiveHostNet.Joined) -> some View {
        // G7: the row is a TEAM and its id is the LEADER's uid, but any member may
        // have answered. Looking the answer up by team.id alone showed "no answer"
        // for a table whose second phone submitted — the host would chase a team
        // that had already answered.
        let ans = net.teamAnswer(forTeamID: team.id)
        let q = session.current
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if ans != nil && !session.revealed {
                            Circle().fill(Tidbits.Palette.mint).frame(width: 7, height: 7)
                        }
                        Text(team.name).font(.headline).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                        if ans?.blurred == true {   // Wave C: left the app during the question — a soft cheat signal
                            Image(systemName: "eye.trianglebadge.exclamationmark.fill").font(.system(size: 13))
                                .foregroundStyle(Tidbits.Palette.coral).help("Left the app during this question")
                        }
                    }
                    Text("\(team.score)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                }
                Spacer()
                // Leniency: for a free-text answer the matcher REJECTED, let the host accept it.
                if let q, let ans, session.revealed, q.accepted != nil, !autoMatched(q, ans) {
                    Button { Task { await net.setScore(team.id, team.score + session.pointsPerCorrect) } } label: {
                        Image(systemName: "checkmark")
                    }.buttonStyle(.borderedProminent).tint(Tidbits.Palette.mint).help("Mark correct (+\(session.pointsPerCorrect))")
                }
                Button { Task { await net.setScore(team.id, team.score - 1) } } label: { Image(systemName: "minus") }.buttonStyle(.bordered)
                Button { Task { await net.setScore(team.id, team.score + 1) } } label: { Image(systemName: "plus") }.buttonStyle(.bordered)
                Button { session.toggleBlocked(team.id) } label: {   // Wave C: moderation gate — hide a bad name from the screen
                    Image(systemName: session.blockedTeams.contains(team.id) ? "eye.slash.fill" : "eye")
                }
                .buttonStyle(.bordered)
                .help(session.blockedTeams.contains(team.id) ? "Hidden from the big screen — tap to show" : "Hide this name from the big screen")
            }
            if session.blockedTeams.contains(team.id) {
                Text("Hidden from the big screen").font(.caption).foregroundStyle(Tidbits.Palette.coral)
            }
            if let q, let ans, let typed = submittedText(q, ans) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote").font(.system(size: 11)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text(typed).font(.callout).foregroundStyle(Tidbits.Palette.ink).italic().lineLimit(2)
                    if session.revealed {
                        Image(systemName: autoMatched(q, ans) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(autoMatched(q, ans) ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                    }
                }
            }
        }
        .padding(12).quietCard(fill: Tidbits.Palette.blue.opacity(0.08))
    }

    /// Whether the shared scorer credits this submission (for the ✓/✗ verdict).
    private func autoMatched(_ q: Question, _ a: LiveRoom.Answer) -> Bool {
        LiveNightHost.score(q, a, shuffledOrder: session.shuffledOrder, shuffledValues: session.shuffledValues, mcqPoints: session.pointsPerCorrect) > 0
    }

    /// §A3.4 — the live per-option tally (how many teams chose each option), so the host reads
    /// the room before revealing. Host-only; the correct option is marked (the host knows it).
    private func optionCounts(_ count: Int) -> [Int] {
        var c = [Int](repeating: 0, count: count)
        for a in net.answers.values { if let ch = a.choice, c.indices.contains(ch) { c[ch] += 1 } }
        return c
    }

    @ViewBuilder private var answerDistribution: some View {
        if !session.revealed, let q = session.current, let opts = session.currentPub().options, !opts.isEmpty {
            let counts = optionCounts(opts.count)
            let total = max(1, counts.reduce(0, +))
            VStack(alignment: .leading, spacing: 5) {
                Text("LIVE ANSWERS").font(.caption).foregroundStyle(Tidbits.Palette.inkSoft)
                ForEach(Array(opts.enumerated()), id: \.offset) { i, opt in
                    let isCorrect = opt == q.correctAnswer
                    HStack(spacing: 8) {
                        Text(opt).font(.caption).foregroundStyle(isCorrect ? Tidbits.Palette.mint : Tidbits.Palette.ink)
                            .frame(width: 180, alignment: .leading).lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Tidbits.Palette.surface)
                                Capsule().fill(isCorrect ? Tidbits.Palette.mint : Tidbits.Palette.blue)
                                    .frame(width: max(4, geo.size.width * CGFloat(counts[i]) / CGFloat(total)))
                            }
                        }
                        .frame(height: 14)
                        Text("\(counts[i])").font(.caption).monospacedDigit()
                            .foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 24, alignment: .trailing)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Tidbits.Palette.bg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Tidbits.Palette.border.opacity(0.55), lineWidth: 1))
        }
    }

    /// The team's submission rendered for host review (free-text shows what they typed).
    private func submittedText(_ q: Question, _ a: LiveRoom.Answer) -> String? {
        if q.accepted != nil { return a.text }
        if let c = q.closest, let n = a.number { let s = n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n); return c.unit.isEmpty ? s : "\(s) \(c.unit)" }
        if let c = a.choice, q.options.indices.contains(c) { return q.options[c] }
        if let list = a.list, !list.isEmpty { return list.joined(separator: " · ") }
        return nil
    }

    // MARK: Final standings

    private var standings: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Final standings").font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink).padding(.top, 24)
                Text(session.event.name).font(.headline).foregroundStyle(Tidbits.Palette.inkSoft)
                ForEach(Array(session.standings.enumerated()), id: \.element.id) { i, team in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 30)
                        if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
                        Text(team.name).font(.title2.weight(.semibold)).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Text("\(team.score)").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(16).frame(maxWidth: .infinity)
                    .quietCard(fill: i == 0 ? Tidbits.Palette.yellow.opacity(0.35) : Tidbits.Palette.surface)
                }
                if session.teams.isEmpty { Text("No teams were scored this night.").font(.callout).foregroundStyle(Tidbits.Palette.inkSoft) }
                HStack(spacing: 14) {
                    if !session.tiedGroups.isEmpty {
                        Button("Break a tie…") { tieGroup = session.tiedGroups.first ?? []; showTieBreak = true }
                            .buttonStyle(.bordered).tint(Tidbits.Palette.yellow)
                    }
                    Button("Print results") { LivePrint.results(name: session.event.name, standings: session.standings) }
                        .buttonStyle(.bordered)
                    Button("Done", action: onClose).buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral).keyboardShortcut(.cancelAction)
                }
                .padding(.top, 8)
            }
            .padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showTieBreak) {
            TieBreakSheet_macOS(teams: tieGroup, onResolve: { target, guesses in
                session.breakTie(target: target, guesses: guesses)
            }, onPickWinner: { winner in
                session.adjust(winner, by: 1)   // Wave C: brains-only — nudge the chosen team clear
            })
        }
    }
}

// MARK: - Tie-break sheet

/// Numeric "closest wins" tie-break (§A3.5). The host asks a number question,
/// enters the answer, then each tied team's guess; the engine picks the winner.
struct TieBreakSheet_macOS: View {
    let teams: [LiveTeam]
    let onResolve: (Double, [LiveTeam.ID: Double]) -> Void
    let onPickWinner: (LiveTeam.ID) -> Void   // Wave C: brains-only manual pick
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0   // 0 = closest number, 1 = brains-only
    @State private var target = ""
    @State private var guesses: [LiveTeam.ID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tie-break").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Picker("", selection: $mode) {
                Text("Closest number").tag(0)
                Text("Brains-only").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            if mode == 0 {
                Text("Ask a number question (e.g. \u{201C}what year did the Eiffel Tower open?\u{201D}). Enter the answer, then each team's guess — closest wins.")
                    .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Correct number").font(.headline).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    TextField("e.g. 1889", text: $target).frame(width: 120).textFieldStyle(.roundedBorder)
                }
                Divider().overlay(Tidbits.Palette.border)
                ForEach(teams) { team in
                    HStack {
                        Text(team.name).font(.headline).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                        Spacer()
                        TextField("guess", text: Binding(get: { guesses[team.id] ?? "" }, set: { guesses[team.id] = $0 }))
                            .frame(width: 120).textFieldStyle(.roundedBorder)
                    }
                }
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Resolve tie") {
                        let t = Double(target) ?? 0
                        var g: [LiveTeam.ID: Double] = [:]
                        for team in teams { if let v = Double(guesses[team.id] ?? "") { g[team.id] = v } }
                        onResolve(t, g); dismiss()
                    }
                    .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                    .keyboardShortcut(.defaultAction).disabled(target.isEmpty)
                }
            } else {
                Text("Phones down. Ask a question aloud — first correct hand wins. Tap the team that won.")
                    .font(.callout).foregroundStyle(Tidbits.Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                ForEach(teams) { team in
                    Button { onPickWinner(team.id); dismiss() } label: {
                        HStack {
                            Text(team.name).font(.headline).foregroundStyle(Tidbits.Palette.ink)
                            Spacer()
                            Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 460).background(Tidbits.Palette.bg)
    }
}

// MARK: - Wave B: SFX / stinger board (synthesized — nothing licensed or bundled)

/// The host's show soundboard. Sounds are generated on the fly (simple tone + envelope
/// synthesis) and played through the Mac's current output — the venue PA when the Mac is
/// plugged into it. Closes the "run a separate soundboard app" gap.
@Observable @MainActor
final class LiveSFXBoard {
    static let shared = LiveSFXBoard()

    enum Stinger: String, CaseIterable, Identifiable {
        case correct, wrong, countdown, timeUp, fanfare
        var id: String { rawValue }
        var label: String {
            switch self {
            case .correct: return "Correct"; case .wrong: return "Wrong"
            case .countdown: return "Tick"; case .timeUp: return "Time!"; case .fanfare: return "Fanfare"
            }
        }
        var symbol: String {
            switch self {
            case .correct: return "checkmark.circle.fill"; case .wrong: return "xmark.octagon.fill"
            case .countdown: return "timer"; case .timeUp: return "bell.fill"; case .fanfare: return "party.popper.fill"
            }
        }
        /// A number-key shortcut so the host can fire a stinger without leaving the keyboard.
        var shortcut: KeyEquivalent {
            switch self {
            case .correct: return "1"; case .wrong: return "2"; case .countdown: return "3"
            case .timeUp: return "4"; case .fanfare: return "5"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var buffers: [Stinger: AVAudioPCMBuffer] = [:]
    private var prepared = false
    /// The chosen output device (nil = system default). Show audio routes here — point it at
    /// the venue PA. Observable so the picker reflects the selection.
    private(set) var outputName = "System default"
    private var selectedDeviceID: AudioDeviceID?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for s in Stinger.allCases { buffers[s] = Self.render(s, format: format) }
        // Restore a previously-chosen PA output by name (device IDs aren't stable; names are).
        if let saved = UserDefaults.standard.string(forKey: "tidbits.sfx.output"),
           let dev = Self.availableOutputs().first(where: { $0.name == saved }) {
            selectedDeviceID = dev.id; outputName = dev.name
        }
    }

    func play(_ s: Stinger) {
        guard let buf = buffers[s] else { return }
        do {
            if !prepared {
                if let id = selectedDeviceID, let unit = engine.outputNode.audioUnit {
                    var dev = id   // route to the chosen device BEFORE the engine starts
                    AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                         kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
                }
                try engine.start(); player.play(); prepared = true
            }
            player.scheduleBuffer(buf, at: nil, options: .interrupts)
        } catch { print("[SFX] play failed: \(error)") }
    }

    /// Route show audio to a device (nil = system default). Applied on the next play; if the
    /// engine is running it's torn down so the new device takes effect.
    func select(deviceID: AudioDeviceID?, name: String) {
        selectedDeviceID = deviceID
        outputName = name
        if deviceID == nil { UserDefaults.standard.removeObject(forKey: "tidbits.sfx.output") }
        else { UserDefaults.standard.set(name, forKey: "tidbits.sfx.output") }
        if engine.isRunning { player.stop(); engine.stop(); prepared = false }
    }

    /// Every current output device (id + name) — the venue PA, the Mac speakers, etc.
    static func availableOutputs() -> [(id: AudioDeviceID, name: String)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.stride)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var result: [(AudioDeviceID, String)] = []
        for id in ids {
            var cfgAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var cfgSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &cfgAddr, 0, nil, &cfgSize) == noErr, cfgSize > 0 else { continue }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(cfgSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &cfgAddr, 0, nil, &cfgSize, raw) == noErr else { continue }
            let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            guard abl.reduce(0, { $0 + Int($1.mNumberChannels) }) > 0 else { continue }   // output channels only
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr,
                  let cf = name?.takeRetainedValue() else { continue }
            result.append((id, cf as String))
        }
        return result
    }

    /// Render a stinger to a mono PCM buffer. Each note is (freq, seconds, sawtooth?); a short
    /// attack + linear release envelope keeps it click-free. freq 0 = a rest.
    private static func render(_ s: Stinger, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let notes: [(f: Double, d: Double, saw: Bool)]
        switch s {
        case .correct:   notes = [(659.25, 0.11, false), (987.77, 0.20, false)]                 // E5 → B5 chime
        case .wrong:     notes = [(196.00, 0.16, true), (155.56, 0.28, true)]                   // G3 → D#3 buzz
        case .countdown: notes = [(880.0, 0.07, false)]                                          // A5 tick
        case .timeUp:    notes = [(220, 0.12, true), (0, 0.05, true), (220, 0.12, true), (0, 0.05, true), (220, 0.22, true)]
        case .fanfare:   notes = [(523.25, 0.1, false), (659.25, 0.1, false), (783.99, 0.1, false), (1046.5, 0.32, false)]
        }
        let sr = format.sampleRate
        let total = max(1, notes.reduce(0) { $0 + Int($1.d * sr) })
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buf.frameLength = AVAudioFrameCount(total)
        let ch = buf.floatChannelData![0]
        var idx = 0
        for note in notes {
            let n = Int(note.d * sr)
            for i in 0..<n where idx < total {
                let t = Double(i) / sr
                let attack = min(1.0, t / 0.005)                    // 5ms fade-in
                let release = 1.0 - Double(i) / Double(max(n, 1))   // linear fade-out
                var sample = 0.0
                if note.f > 0 {
                    if note.saw {
                        let phase = (note.f * t).truncatingRemainder(dividingBy: 1.0)
                        sample = 2.0 * phase - 1.0
                    } else {
                        sample = sin(2.0 * .pi * note.f * t)
                    }
                }
                ch[idx] = Float(sample * attack * release * 0.45)
                idx += 1
            }
        }
        return buf
    }
}

/// Apply the host's chosen show-audio output device (persisted by name via the SFX board) to
/// an engine's output node. Call BEFORE engine.start(). No-op for the system default.
@MainActor
func applyShowOutputDevice(to engine: AVAudioEngine) {
    guard let name = UserDefaults.standard.string(forKey: "tidbits.sfx.output"),
          let dev = LiveSFXBoard.availableOutputs().first(where: { $0.name == name }),
          let unit = engine.outputNode.audioUnit else { return }
    var id = dev.id
    AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                         kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
}

// MARK: - Wave B: audio clip playback to the venue PA (audio rounds / walk-in music)

/// Full-level clip playback on the host's chosen output device — the host opens an audio file
/// and plays it through the PA. The streamed-file core that audio rounds build on.
@Observable @MainActor
final class LiveAudioPlayer {
    static let shared = LiveAudioPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var started = false
    private var scheduled = false
    private(set) var trackName = ""
    private(set) var isPlaying = false

    private init() { engine.attach(player) }

    private var accessedURL: URL?
    /// Open a saved audio-round clip from its security-scoped bookmark (starts sandbox access;
    /// released on the next open/stop).
    func openBookmark(_ data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        open(url)             // open() → stop() releases the PREVIOUS accessed url
        accessedURL = url     // ...then hold the new one
    }

    /// Load an audio file (stops anything playing). Its format drives the node connection.
    func open(_ url: URL) {
        stop()
        do {
            let f = try AVAudioFile(forReading: url)
            file = f
            trackName = url.deletingPathExtension().lastPathComponent
            engine.connect(player, to: engine.mainMixerNode, format: f.processingFormat)
        } catch { print("[Audio] open failed: \(error)"); file = nil; trackName = "" }
    }

    /// Play from the start / resume from pause; a second tap pauses.
    func togglePlay() {
        guard let file else { return }
        do {
            if isPlaying { player.pause(); isPlaying = false; return }
            if !started { applyShowOutputDevice(to: engine); try engine.start(); started = true }
            if !scheduled {
                player.scheduleFile(file, at: nil) { [weak self] in
                    Task { @MainActor in self?.isPlaying = false; self?.scheduled = false }
                }
                scheduled = true
            }
            player.play(); isPlaying = true
        } catch { print("[Audio] play failed: \(error)") }
    }

    func stop() {
        player.stop(); if engine.isRunning { engine.stop() }
        isPlaying = false; started = false; scheduled = false
        if let u = accessedURL { u.stopAccessingSecurityScopedResource(); accessedURL = nil }
    }
}

// MARK: - Wave B: looping music bed (walk-in / between-round ambiance)

/// A looping background music bed at a low level — walk-in music, between-round ambiance — on
/// the routed output, independent of the SFX board and clip player (a clip plays over it).
@Observable @MainActor
final class LiveMusicBed {
    static let shared = LiveMusicBed()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var accessedURL: URL?
    private var started = false
    private(set) var trackName = ""
    private(set) var isPlaying = false
    var volume: Float = 0.35 { didSet { engine.mainMixerNode.outputVolume = max(0, min(1, volume)) } }

    private init() { engine.attach(player) }

    func open(_ url: URL) {
        stop()
        do {
            let f = try AVAudioFile(forReading: url)
            file = f; trackName = url.deletingPathExtension().lastPathComponent
            engine.connect(player, to: engine.mainMixerNode, format: f.processingFormat)
        } catch { print("[MusicBed] open failed: \(error)"); file = nil; trackName = "" }
    }

    func openBookmark(_ data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        open(url); accessedURL = url
    }

    func toggle() {
        guard file != nil else { return }
        if isPlaying { player.pause(); isPlaying = false; return }
        do {
            if !started {
                applyShowOutputDevice(to: engine); try engine.start()
                engine.mainMixerNode.outputVolume = volume; started = true; scheduleLoop()
            }
            player.play(); isPlaying = true
        } catch { print("[MusicBed] play failed: \(error)") }
    }

    func stop() {
        player.stop(); if engine.isRunning { engine.stop() }
        isPlaying = false; started = false
        if let u = accessedURL { u.stopAccessingSecurityScopedResource(); accessedURL = nil }
    }

    /// Re-schedule the file each time it finishes so it loops for any length of clip.
    private func scheduleLoop() {
        guard let file else { return }
        player.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in if self?.isPlaying == true { self?.scheduleLoop() } }
        }
    }
}

// MARK: - Wave B: video questions (played on the big screen)

/// A video clip for a video-round question, shown on the BIG SCREEN (the room watches) via
/// AVKit. The host loads + plays it; the big screen renders whatever is loaded here.
@Observable @MainActor
final class LiveVideoPlayer {
    static let shared = LiveVideoPlayer()

    private(set) var player: AVPlayer?
    private(set) var hasVideo = false
    private var accessedURL: URL?

    func open(_ url: URL) {
        stop()
        player = AVPlayer(url: url)
        hasVideo = true
    }

    func openBookmark(_ data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        open(url); accessedURL = url
    }

    func play() { player?.seek(to: .zero); player?.play() }
    func pause() { player?.pause() }

    func stop() {
        player?.pause(); player = nil; hasVideo = false
        if let u = accessedURL { u.stopAccessingSecurityScopedResource(); accessedURL = nil }
    }
}
#endif

#if os(macOS)
import AppKit

/// Offline design-observability: render the real cockpit (with a mock session) to a PNG so the
/// UI can be inspected without driving a live event. Gated by the TIDBITS_SNAPSHOT env var
/// (see the app entry) — never runs in normal use.
enum LiveCockpitSnapshot {
    @MainActor static func writePNG(to path: String) {
        func q(_ p: String, _ opts: [String]) -> Question {
            Question(id: UUID().uuidString, prompt: p, options: opts, correctIndex: 0, categoryID: "history",
                     difficulty: 3, explanation: "A quick note on why that's the answer.", sourceTitle: "", sourceURL: nil, templateID: "mcq")
        }
        let round = LiveRound(title: "Round 1 — General Knowledge", format: .classic, categoryID: "history",
                              questions: [q("In what year did the Berlin Wall fall?", ["1989", "1991", "1987", "1990"]),
                                          q("Who painted the Mona Lisa?", ["Leonardo da Vinci", "Michelangelo", "Raphael", "Donatello"])])
        let event = LiveEvent(name: "Thursday Night Trivia", venue: "The Anchor", rounds: [round])
        let session = LiveHostSession(event: event)
        let net = LiveHostNet()
        let coord = LiveHostCoordinator()
        let view = LiveHostView_macOS(session: session, net: net, onClose: {})
            .environment(coord)
            .frame(width: 1280, height: 820)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
#endif
