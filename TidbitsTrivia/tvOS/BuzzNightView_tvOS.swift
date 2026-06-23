#if os(tvOS)
import SwiftUI
import SwiftData

/// Trivia Night hosted on the Apple TV with phones as buzzers (the Phase-1
/// Bonjour host, Decision 030). The TV is the stage + scoreboard; phones read
/// the question, buzz, and the first in answers ON THEIR OWN DEVICE. The TV
/// (which holds the question) judges it and CELEBRATES each outcome so it feels
/// like a game you're playing with friends: who buzzed, who got it, the points,
/// and the running scoreboard between questions (Jackbox/Kahoot shared-awareness
/// + leaderboard-moment patterns). Right = points; wrong = that seat locks out
/// and buzzing re-opens to everyone else; if everyone misses or the clock runs
/// out, the answer is revealed and the game moves on (no dead air). Every
/// question ends on the shared Learn-the-fact reveal.
///
/// Buzzable MCQ rounds only: a phone can buzz but can't drive a slider / board.
struct BuzzNightView_tvOS: View {
    let plan: NightPlan
    let category: TriviaCategory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var host = BuzzerHost()
    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var phase: Phase = .lobby
    @State private var loaded = false
    @State private var missed: [AnsweredQuestion] = []
    @State private var lastScorerName: String?   // who just scored (celebration)
    @State private var lastScorerPoints = 0
    @State private var lastTimedOut = false      // a no-winner reveal: clock ran out vs all wrong
    @State private var wrongFeedback: String?    // "Bob missed — reopened!" (never names the option)
    @State private var wrongCount = 0            // wrong answers on this question (for the move-on rule)
    @State private var buzzSecondsLeft = 0
    @State private var questionNonce = 0         // bumps each question (drives the clock)

    private enum Phase { case lobby, loading, playing, buzzed, reveal, finished }
    private let awardPoints = 10
    private let buzzBudget = 30

    private var current: Question? { questions.indices.contains(index) ? questions[index] : nil }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            switch phase {
            case .lobby:    lobby
            case .loading:  loadingView
            case .playing, .buzzed: playing
            case .reveal:   revealView
            case .finished: standings
            }
        }
        .onChange(of: host.currentWinnerSeat) { _, w in
            if w != nil, phase == .playing { wrongFeedback = nil; phase = .buzzed }
        }
        .onChange(of: host.pendingAnswerSeat) { _, s in
            if s != nil { judgePhoneAnswer() }
        }
        .task {
            host.start()
            if DebugHooks.autopilot { await beginGame() }   // screenshot the in-game host
        }
        // Per-question buzz clock: when it runs out (or everyone's locked out),
        // reveal the answer and move on — the game never hangs waiting for a buzz.
        .task(id: questionNonce) {
            guard questionNonce > 0 else { return }
            buzzSecondsLeft = buzzBudget
            while buzzSecondsLeft > 0 {
                if phase == .reveal || phase == .finished || phase == .lobby { return }
                if phase == .playing && host.allLockedOut { break }   // no one left to answer
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if phase == .playing { buzzSecondsLeft -= 1 }          // pause while someone's answering
            }
            // Out of time with no winner: a true timeout only if nobody ever
            // locked out by answering wrong (otherwise "everyone got it wrong").
            if phase == .playing { revealNoOne(timedOut: !host.allLockedOut) }
        }
        .onExitCommand { host.stop(); dismiss() }
    }

    // MARK: Lobby

    private var lobby: some View {
        VStack(spacing: 40) {
            Text("TRIVIA NIGHT").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(.white)
            VStack(spacing: 12) {
                Text("Join from your phone").font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Text("Open Tidbits → Join a TV Game → enter")
                    .font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Text(host.roomCode.isEmpty ? "····" : host.roomCode)
                    .font(.system(size: 130, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    .kerning(12)
                if !host.isListening {
                    Text("Starting room…").font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
            }
            rosterStrip
            Button("Start Game") { Task { await beginGame() } }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
            Text("\(host.players.count) player\(host.players.count == 1 ? "" : "s") joined")
                .font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
        .padding(90)
    }

    private var rosterStrip: some View {
        HStack(spacing: 16) {
            ForEach(host.players) { p in
                HStack(spacing: 10) {
                    Image(systemName: "person.fill").font(.system(size: 22, weight: .bold))
                    Text(p.name).font(.system(size: 25, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Capsule().fill(TVTheme.panel))
            }
        }
        .frame(minHeight: 60)
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.extraLarge).tint(.white)
            Text("Setting up the night…").font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }

    // MARK: Playing / buzzed

    private var playing: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    if let round = roundFor(current) {
                        Text("ROUND \((current?.roundIndex ?? 0) + 1) · \(round.title.uppercased())")
                            .font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    }
                    Text("Q\(index + 1)/\(questions.count)")
                        .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    Spacer()
                    if phase == .playing {
                        Label("\(buzzSecondsLeft)s", systemImage: "timer")
                            .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(buzzSecondsLeft <= 5 ? Tidbits.Palette.coral : TVTheme.textSoft)
                    }
                }
                if let q = current {
                    if let img = q.imageURL { buzzImage(img) }
                    Text(q.prompt).font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    statusBanner
                    optionsGrid(q)
                    if phase == .playing {
                        Button("Nobody's got it — reveal answer") { revealNoOne(timedOut: false) }
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                            .padding(.top, 8)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 24) {
                joinChip
                scoreboard
            }.frame(width: 420)
        }
        .padding(70)
    }

    /// The live activity line — who's buzzed in, or who just missed.
    @ViewBuilder private var statusBanner: some View {
        if phase == .buzzed, let seat = host.currentWinnerSeat {
            Label("\(host.name(forSeat: seat)) buzzed — answering on their phone…", systemImage: "bell.fill")
                .font(.system(size: 29, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.yellow)
        } else if let wrong = wrongFeedback {
            Label(wrong, systemImage: "xmark.circle.fill")
                .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
        } else {
            Label("Buzzers open — first to buzz answers on their phone", systemImage: "bell.badge.fill")
                .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
        }
    }

    /// The room code stays on screen the whole game so a new player can join and
    /// a dropped phone can rejoin (device-keyed — same seat + score).
    private var joinChip: some View {
        VStack(spacing: 4) {
            Text("JOIN / REJOIN").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            Text(host.roomCode).font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral).kerning(4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(TVTheme.panel))
    }

    /// Options are DISPLAY-ONLY on the TV — the buzz-winner answers on their
    /// phone. Lettering matches the phone's buttons so the room reads along.
    private func optionsGrid(_ q: Question) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 24) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                HStack(spacing: 16) {
                    Text(String(UnicodeScalar(65 + idx)!))
                        .font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                    Text(opt).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 96).padding(.horizontal, 24)
                .background(RoundedRectangle(cornerRadius: 20).fill(TVTheme.panel))
            }
        }
        .frame(maxWidth: 1100)
    }

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SCOREBOARD").font(.system(size: 23, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(host.players.sorted { $0.score > $1.score }) { p in
                scoreRow(p, highlight: false)
            }
            if host.players.isEmpty {
                Text("No phones connected").font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
    }

    private func scoreRow(_ p: BuzzerPlayer, highlight: Bool) -> some View {
        HStack {
            if host.leaderSeat == p.seat {
                Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow)
            }
            Text(p.name).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Text("\(p.score)").font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(highlight ? Tidbits.Palette.mint.opacity(0.3) : TVTheme.panel))
    }

    private func buzzImage(_ url: URL) -> some View {
        AsyncImage(url: url) { p in
            if let img = p.image { img.resizable().aspectRatio(contentMode: .fit) }
            else { Color.clear }
        }
        .frame(maxWidth: 600, maxHeight: 280, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Reveal (celebrate + between-question scoreboard)

    private var revealView: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 22) {
                if let name = lastScorerName {
                    Label("\(name) got it!  +\(lastScorerPoints)", systemImage: "party.popper.fill")
                        .font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                } else {
                    Label(lastTimedOut ? "Time's up — nobody buzzed in" : "Nobody got it right",
                          systemImage: lastTimedOut ? "clock.badge.xmark.fill" : "xmark.circle.fill")
                        .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.yellow)
                }
                if let q = current {
                    Text("Answer").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    Text(q.correctAnswer).font(.system(size: 52, weight: .black, design: .rounded)).foregroundStyle(.white)
                    if !q.explanation.isEmpty {
                        Text(q.explanation).font(.system(size: 27, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(index + 1 >= questions.count ? "Final Standings" : "Next Question") { advance() }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The leaderboard moment between questions.
            VStack(alignment: .leading, spacing: 14) {
                Text("STANDINGS").font(.system(size: 23, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                ForEach(host.players.sorted { $0.score > $1.score }) { p in
                    scoreRow(p, highlight: p.name == lastScorerName)
                }
                if host.players.isEmpty {
                    Text("No phones connected").font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
            }.frame(width: 420)
        }
        .padding(70)
    }

    // MARK: Standings (final)

    private var standings: some View {
        VStack(spacing: 28) {
            Text("FINAL STANDINGS").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.white)
            ForEach(Array(host.players.sorted { $0.score > $1.score }.enumerated()), id: \.element.id) { rank, p in
                HStack(spacing: 20) {
                    Text("\(rank + 1)").font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral).frame(width: 60)
                    Text(p.name).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text("\(p.score)").font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(rank == 0 ? Tidbits.Palette.coral.opacity(0.25) : TVTheme.panel))
                .frame(maxWidth: 900)
            }
            Button("Done") { host.stop(); dismiss() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                .padding(.top, 12)
        }
        .padding(90)
    }

    // MARK: Game flow

    private func beginGame() async {
        phase = .loading
        if !loaded {
            let all = await QuestionProvider.shared.nightQuestions(plan: plan, category: category)
            // Buzzable = a tappable MCQ (a phone can't drive a slider/board).
            questions = all.filter {
                $0.closest == nil && $0.ordering == nil && $0.matching == nil &&
                $0.accepted == nil && $0.enumerate == nil && $0.options.count >= 2
            }
            loaded = true
        }
        guard !questions.isEmpty else { phase = .finished; return }
        index = 0
        startQuestion()
    }

    private func startQuestion() {
        wrongFeedback = nil; wrongCount = 0
        lastScorerName = nil; lastScorerPoints = 0
        phase = .playing
        if let q = current { host.broadcastQuestion(prompt: q.prompt, options: q.options, imageURL: q.imageURL?.absoluteString, index: index) }
        host.beginQuestion(index: index)
        questionNonce += 1   // (re)start the buzz clock
    }

    /// The buzz-winner answered on THEIR phone; the TV judges it. Correct →
    /// celebrate + reveal; wrong → lock them out, buzzing re-opens (or, if that
    /// was the last player, reveal so the game doesn't hang).
    private func judgePhoneAnswer() {
        guard phase == .buzzed, let q = current, let chosen = host.pendingAnswerIndex else { return }
        let who = host.currentWinnerSeat.map { host.name(forSeat: $0) } ?? "Someone"
        if chosen == q.correctIndex {
            lastScorerName = who; lastScorerPoints = awardPoints
            host.acceptAnswer(points: awardPoints, correctIndex: q.correctIndex)
            phase = .reveal
        } else {
            // Never name the option they picked — on a 2-option that gives the
            // answer away. Lock them out (without revealing the pick), then either
            // move on (the answer is determined by elimination) or reopen so the
            // others can still guess without influence.
            wrongCount += 1
            host.lockOutWinner()
            let n = q.options.count
            // A 4-option (≥3) question with all-but-one option eliminated has an
            // obvious answer — just move on. A 2-option keeps going (hidden picks).
            if (n >= 3 && wrongCount >= n - 1) || host.allLockedOut {
                revealNoOne(timedOut: false)
            } else {
                wrongFeedback = "\(who) buzzed wrong — buzzers reopen!"
                host.reopen()
                phase = .playing
            }
        }
    }

    /// Reveal with no winner. `timedOut`: the clock ran out with nobody buzzing
    /// (vs everyone answered wrong) — drives honest wording on every device.
    private func revealNoOne(timedOut: Bool) {
        guard phase != .reveal, let q = current else { return }
        lastScorerName = nil
        lastTimedOut = timedOut
        host.revealNoWinner(correctIndex: q.correctIndex, timedOut: timedOut)
        missed.append(AnsweredQuestion(question: q, chosenIndex: nil, secondsTaken: 0))
        phase = .reveal
    }

    private func advance() {
        index += 1
        if index >= questions.count { finish() } else { startQuestion() }
    }

    private func finish() {
        phase = .finished
        // Record the host's own learning recap (the missed facts) so a hosted
        // night still feeds the records loop, even though scoring is per-seat.
        let summary = GameSummary(mode: .barTrivia, category: category, score: 0,
                                  correct: questions.count - missed.count, total: questions.count,
                                  maxStreak: 0, answered: missed)
        RecordsStore.record(summary, in: modelContext)
    }

    private func roundFor(_ q: Question?) -> NightRound? {
        guard let ri = q?.roundIndex, plan.rounds.indices.contains(ri) else { return nil }
        return plan.rounds[ri]
    }
}
#endif
