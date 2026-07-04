#if os(macOS)
import SwiftUI

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
    /// Points a correct answer is worth this round (host-adjustable; pub default 1).
    var pointsPerCorrect = 1
    /// Per-question display shuffles (fixed once so publish + reveal agree).
    var shuffledOrder: [String] = []
    var shuffledValues: [String] = []

    init(event: LiveEvent) { self.event = event; prepare() }

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
    func reveal() { revealed = true }
    func next() {
        revealed = false
        if index + 1 >= questions.count { finished = true } else { index += 1; prepare() }
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
    }

    /// On reveal, award points to every joined team whose submission matched the
    /// correct option. Manual override (± in the scoreboard) still applies on top.
    private func scoreReveal() async {
        guard let q = session.current else { return }
        for (uid, ans) in net.answers where ans.choice == q.correctIndex {
            await net.setScore(uid, (net.scores[uid] ?? 0) + session.pointsPerCorrect)
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
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Scoreboard (manual scoring — the differentiator)

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Teams").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
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
    /// (writes back to the room) and a live "answered this question" dot.
    private func joinedRow(_ team: LiveHostNet.Joined) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if net.answers[team.id] != nil && !session.revealed {
                        Circle().fill(Tidbits.Palette.mint).frame(width: 7, height: 7)
                    }
                    Text(team.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                }
                Text("\(team.score)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            }
            Spacer()
            Button { Task { await net.setScore(team.id, team.score - 1) } } label: { Image(systemName: "minus") }.buttonStyle(.bordered)
            Button { Task { await net.setScore(team.id, team.score + 1) } } label: { Image(systemName: "plus") }.buttonStyle(.bordered)
        }
        .padding(12).chunkyCard(fill: Tidbits.Palette.blue.opacity(0.10))
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
#endif
