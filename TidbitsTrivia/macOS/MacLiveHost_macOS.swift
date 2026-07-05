#if os(macOS)
import SwiftUI
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

// MARK: - Host session (macOS-DESIGN Part A §A3 — the emcee cockpit)

/// One team in a live event. Score is authoritative on the host's Mac.
struct LiveTeam: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var score: Int = 0
}

/// The live hosting session: the host drives pacing + reveal, and OWNS the
/// score (manual override is first-class — the #1 gap across the field, §A3.2).
/// v1 is paper-style (teams answer on paper, host marks); networked phone join
/// (#10) layers on top without changing this model.
@Observable
@MainActor
final class LiveHostSession {
    let event: LiveEvent
    var teams: [LiveTeam] = []
    var index = 0
    var revealed = false
    var finished = false
    var deadlineMs: Int? = nil   // Wave A: epoch-ms countdown deadline for the current timed question
    var locked = false           // Wave C: answers locked ("pencils down") — auto-set at the timer deadline or manually
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
    /// Wave B: is the current round a speed round (fastest-first bonus)?
    var currentRoundIsSpeed: Bool {
        let ri = current?.roundIndex ?? 0
        return event.rounds.indices.contains(ri) ? (event.rounds[ri].isSpeed ?? false) : false
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
    @State private var session: LiveHostSession
    @State private var net = LiveHostNet()
    @State private var lockTask: Task<Void, Never>?   // Wave C: auto-lock at the timer deadline

    init(event: LiveEvent, onClose: @escaping () -> Void) {
        self.event = event; self.onClose = onClose
        _session = State(initialValue: LiveHostSession(event: event))
    }
    var body: some View {
        LiveHostView_macOS(session: session, net: net) {
            let net = self.net
            Task { await net.close() }
            coordinator.session = nil            // clear the projector
            coordinator.net = nil
            onClose()
        }
        .onAppear {
            coordinator.session = session          // publish to the big screen (§A1.1)
            coordinator.net = net
            openWindow(id: "tidbits-bigscreen")     // pop the projector window
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
        let wagerRound = session.currentRoundIsWager
        let speedRound = session.currentRoundIsSpeed
        var speedCorrect: [(uid: String, ts: Int, pts: Int)] = []
        for (uid, ans) in net.answers {
            let pts = LiveNightHost.score(q, ans, shuffledOrder: session.shuffledOrder,
                                          shuffledValues: session.shuffledValues, mcqPoints: session.pointsPerCorrect)
            if wagerRound {
                // Wave A: stake clamped to the team's current score; correct +stake, wrong −stake.
                let current = net.scores[uid] ?? 0
                let stake = max(0, min(ans.wager ?? 0, current))
                guard stake > 0 else { continue }
                await net.setScore(uid, pts > 0 ? current + stake : current - stake)
            } else if pts > 0 {
                if speedRound { speedCorrect.append((uid, ans.ts, pts)) }   // defer — rank by speed below
                else { await net.setScore(uid, (net.scores[uid] ?? 0) + pts) }
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
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
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
                Text(session.event.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Text("ROUND \(session.roundNumber)/\(session.roundCount) · \(session.roundTitle)")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            if net.isOpen {
                HStack(spacing: 8) {
                    if let qr = makeLiveQR(liveJoinURL(net.code)) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 40, height: 40)
                    }
                    Text("Players scan, or join at tidbitstrivia.com/live").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text("CODE \(net.code)").font(.system(size: 15, weight: .black, design: .monospaced)).foregroundStyle(Tidbits.Palette.ink)
                    if !net.joined.isEmpty {
                        Text("· \(net.joined.count) joined").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.mint)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tidbits.Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tidbits.Palette.border, lineWidth: 2))
            }
            if let q = session.current {
                let inR = session.questionInRound
                Text("Question \(inR.n) of \(inR.of)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                Text(q.prompt).font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink).fixedSize(horizontal: false, vertical: true)
                if let note = session.currentRoundNote, !note.isEmpty {   // Wave A: host prep note (cockpit only)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text").foregroundStyle(Tidbits.Palette.blue)
                        Text(note).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.blue).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Tidbits.Palette.blue.opacity(0.12)))
                }
                if session.currentRoundIsWager {   // Wave A: wager round indicator
                    Label("Wager round — teams stake points (correct +stake, wrong −stake)", systemImage: "dollarsign.circle.fill")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.coral)
                }
                if session.currentRoundIsSpeed {   // Wave B: speed round indicator
                    Label("Speed round — fastest correct answers earn a bonus (+3/+2/+1)", systemImage: "bolt.fill")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.yellow)
                }
                if let clip = session.currentAudioBookmark {   // Wave B: audio round — play this question's clip
                    Button { LiveAudioPlayer.shared.openBookmark(clip); LiveAudioPlayer.shared.togglePlay() } label: {
                        Label("Play this clip", systemImage: "play.circle.fill").font(Tidbits.TypeRamp.l4)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                }
                if let vid = session.currentVideoBookmark {   // Wave B: video round — play on the big screen
                    Button { LiveVideoPlayer.shared.openBookmark(vid); LiveVideoPlayer.shared.play() } label: {
                        Label("Play video on the big screen", systemImage: "play.rectangle.fill").font(Tidbits.TypeRamp.l4)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                }
                if session.revealed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Tidbits.Palette.mint)
                        Text(q.correctAnswer).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    }
                    if !q.explanation.isEmpty {
                        Text(q.explanation).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Read it out. Reveal the answer when the room is ready.")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if !session.revealed {
                    Button(session.locked ? "Answers locked" : "Lock answers") {   // Wave C: manual pencils-down
                        session.locked = true; Task { await net.publish(session.currentPub()) }
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                    .disabled(session.locked)
                    Button("Reveal answer") { session.reveal() }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.yellow, textColor: Tidbits.Palette.ink))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(session.index + 1 >= session.questions.count ? "Finish night" : "Next question") { session.next() }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
                Text("\(session.index + 1) / \(session.questions.count)").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            sfxBar        // Wave B: the stinger board
            audioClipBar  // Wave B: clip playback to the PA
            musicBedBar   // Wave B: looping background music
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            } label: { Label(LiveSFXBoard.shared.outputName, systemImage: "hifispeaker.fill").font(Tidbits.TypeRamp.l6) }
                .menuStyle(.borderlessButton).fixedSize()
            Divider().frame(height: 20)
            ForEach(LiveSFXBoard.Stinger.allCases) { s in
                Button { LiveSFXBoard.shared.play(s) } label: {
                    Label(s.label, systemImage: s.symbol).font(Tidbits.TypeRamp.l6)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                .keyboardShortcut(s.shortcut, modifiers: [])
            }
        }
    }

    /// Wave B: play an audio clip through the routed output (walk-in music, an audio-round clip).
    private var audioClipBar: some View {
        let audio = LiveAudioPlayer.shared
        return HStack(spacing: 10) {
            Button { pickAudioClip() } label: { Label("Open clip…", systemImage: "music.note.list").font(Tidbits.TypeRamp.l6) }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
            if !audio.trackName.isEmpty {
                Button { audio.togglePlay() } label: { Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.mint, textColor: .white))
                Button { audio.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                Text(audio.trackName).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
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
            Button { pickMusicBed() } label: { Label("Music bed…", systemImage: "music.quarternote.3").font(Tidbits.TypeRamp.l6) }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
            if !bed.trackName.isEmpty {
                Button { bed.toggle() } label: { Image(systemName: bed.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.blue, textColor: .white))
                Image(systemName: "speaker.fill").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft)
                Slider(value: Binding(get: { Double(bed.volume) }, set: { bed.volume = Float($0) }), in: 0...1).frame(width: 90)
                Text(bed.trackName).font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
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
            HStack {
                Text("Teams").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button { exportResultsCSV() } label: { Image(systemName: "square.and.arrow.up") }   // Wave C: data export
                    .buttonStyle(.borderless).help("Export standings to CSV")
                Text("pts/correct").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                Stepper("\(session.pointsPerCorrect)", value: $session.pointsPerCorrect, in: 1...10).labelsHidden()
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
                            Text("JOINED").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                            Spacer()
                            if session.revealed == false, !net.answers.isEmpty {
                                Text("\(net.answers.count) answered").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.mint)
                            }
                        }
                        if net.joined.isEmpty {
                            Text("Waiting for phones to join with code \(net.code)…")
                                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                        ForEach(net.joined) { joinedRow($0) }
                        if !session.teams.isEmpty {
                            Divider().overlay(Tidbits.Palette.border).padding(.vertical, 4)
                            Text("IN-ROOM (PAPER)").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        }
                    } else if session.teams.isEmpty {
                        Text("Add the teams in the room. When you reveal an answer, tap ✓ to award points, or ± to correct any score.")
                            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).padding(.top, 20)
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
        if panel.runModal() == .OK, let url = panel.url { try? csv.data(using: .utf8)?.write(to: url) }
    }

    private func teamRow(_ team: LiveTeam) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
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
            Menu { Button("Remove team", role: .destructive) { session.removeTeam(team.id) } } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 20)
        }
        .padding(12).chunkyCard()
    }

    /// A phone/web-joined team: auto-scored on reveal, with ± manual override
    /// (writes back to the room), a live "answered" dot, and — for free-text rounds
    /// — the team's typed answer with an auto-match verdict + a leniency "mark
    /// correct" the host can grant on a borderline miss (§A3.3, host pain #2).
    private func joinedRow(_ team: LiveHostNet.Joined) -> some View {
        let ans = net.answers[team.id]
        let q = session.current
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if ans != nil && !session.revealed {
                            Circle().fill(Tidbits.Palette.mint).frame(width: 7, height: 7)
                        }
                        Text(team.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
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
            }
            if let q, let ans, let typed = submittedText(q, ans) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote").font(.system(size: 11)).foregroundStyle(Tidbits.Palette.inkSoft)
                    Text(typed).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink).italic().lineLimit(2)
                    if session.revealed {
                        Image(systemName: autoMatched(q, ans) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(autoMatched(q, ans) ? Tidbits.Palette.mint : Tidbits.Palette.coral)
                    }
                }
            }
        }
        .padding(12).chunkyCard(fill: Tidbits.Palette.blue.opacity(0.10))
    }

    /// Whether the shared scorer credits this submission (for the ✓/✗ verdict).
    private func autoMatched(_ q: Question, _ a: LiveRoom.Answer) -> Bool {
        LiveNightHost.score(q, a, shuffledOrder: session.shuffledOrder, shuffledValues: session.shuffledValues, mcqPoints: session.pointsPerCorrect) > 0
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
                Text(session.event.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                ForEach(Array(session.standings.enumerated()), id: \.element.id) { i, team in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 30)
                        if i == 0 { Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow) }
                        Text(team.name).font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Text("\(team.score)").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(16).frame(maxWidth: .infinity)
                    .chunkyCard(fill: i == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface)
                }
                if session.teams.isEmpty { Text("No teams were scored this night.").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft) }
                HStack(spacing: 14) {
                    if !session.tiedGroups.isEmpty {
                        Button("Break a tie…") { tieGroup = session.tiedGroups.first ?? []; showTieBreak = true }
                            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.yellow, textColor: Tidbits.Palette.ink))
                    }
                    Button("Print results") { LivePrint.results(name: session.event.name, standings: session.standings) }
                        .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
                    Button("Done", action: onClose).buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white)).keyboardShortcut(.cancelAction)
                }
                .padding(.top, 8)
            }
            .padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showTieBreak) {
            TieBreakSheet_macOS(teams: tieGroup) { target, guesses in
                session.breakTie(target: target, guesses: guesses)
            }
        }
    }
}

// MARK: - Tie-break sheet

/// Numeric "closest wins" tie-break (§A3.5). The host asks a number question,
/// enters the answer, then each tied team's guess; the engine picks the winner.
struct TieBreakSheet_macOS: View {
    let teams: [LiveTeam]
    let onResolve: (Double, [LiveTeam.ID: Double]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var guesses: [LiveTeam.ID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tie-break").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("Ask a number question (e.g. \u{201C}what year did the Eiffel Tower open?\u{201D}). Enter the answer, then each team's guess — closest wins.")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Correct number").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                TextField("e.g. 1889", text: $target).frame(width: 120).textFieldStyle(.roundedBorder)
            }
            Divider().overlay(Tidbits.Palette.border)
            ForEach(teams) { team in
                HStack {
                    Text(team.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
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
                    onResolve(t, g)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(Tidbits.Palette.coral)
                .keyboardShortcut(.defaultAction)
                .disabled(target.isEmpty)
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
