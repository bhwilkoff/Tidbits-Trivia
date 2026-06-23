#if os(tvOS)
import SwiftUI
import SwiftData

/// Buzz Night — the living-room "bar trivia" show. The Apple TV is the stage +
/// scoreboard; phones are the buzzers (the Phase-1 Bonjour host, Decision 030).
/// Flow per question: the TV reads it, buzzing opens, the first phone to buzz
/// (RTT-compensated, host-arbitrated) claims it and calls out an answer; the host
/// taps the option they said. Right = points; wrong = locked out and buzzing
/// re-opens to everyone else. Every question ends on the shared Learn-the-fact
/// reveal — a wrong buzz is a teaching moment, never an elimination (the mission).
///
/// Buzzable MCQ rounds only: a phone can buzz but can't drive a slider / ordering
/// board, so the input-required night rounds are filtered out for this mode.
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

    private enum Phase { case lobby, loading, playing, buzzed, reveal, finished }
    private let awardPoints = 10

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
            if w != nil, phase == .playing { phase = .buzzed }
        }
        .task {
            host.start()
            if DebugHooks.autopilot { await beginGame() }   // screenshot the in-game host
        }
        .onExitCommand { host.stop(); dismiss() }
    }

    // MARK: Lobby

    private var lobby: some View {
        VStack(spacing: 40) {
            Text("BUZZ NIGHT").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(.white)
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
            VStack(alignment: .leading, spacing: 28) {
                if let round = roundFor(current) {
                    Text("ROUND \((current?.roundIndex ?? 0) + 1) · \(round.title.uppercased())")
                        .font(.system(size: 25, weight: .heavy, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                }
                Text("Question \(index + 1) of \(questions.count)")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                if let q = current {
                    if let img = q.imageURL { buzzImage(img) }
                    Text(q.prompt).font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if phase == .buzzed, let seat = host.currentWinnerSeat {
                        Label("\(host.name(forSeat: seat)) buzzed — tap what they answered", systemImage: "bell.fill")
                            .font(.system(size: 29, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.yellow)
                    } else {
                        Label("Buzzers open", systemImage: "bell.badge.fill")
                            .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                    }
                    optionsGrid(q)
                    if phase == .playing {
                        Button("No one — reveal answer") { reveal(awardedCorrect: false) }
                            .buttonStyle(TVChipStyle(accent: Tidbits.Palette.blue, selected: false))
                            .padding(.top, 8)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            scoreboard.frame(width: 420)
        }
        .padding(70)
    }

    private func optionsGrid(_ q: Question) -> some View {
        // The host taps an option only AFTER a phone has buzzed (in .buzzed).
        let tappable = phase == .buzzed
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 24) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                Button { if tappable { tapOption(idx, q) } } label: {
                    HStack(spacing: 16) {
                        Text(String(UnicodeScalar(65 + idx)!))
                            .font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.coral)
                        Text(opt).font(.system(size: 29, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(.horizontal, 24)
                }
                .buttonStyle(TVAnswerStyle(state: .idle))
                .disabled(!tappable)
                .opacity(tappable ? 1 : 0.5)
            }
        }
        .frame(maxWidth: 1100)
    }

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SCOREBOARD").font(.system(size: 23, weight: .heavy, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            ForEach(host.players.sorted { $0.score > $1.score }) { p in
                HStack {
                    if host.leaderSeat == p.seat {
                        Image(systemName: "crown.fill").foregroundStyle(Tidbits.Palette.yellow)
                    }
                    Text(p.name).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text("\(p.score)").font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(TVTheme.panel))
            }
            if host.players.isEmpty {
                Text("No phones connected").font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
            }
        }
    }

    private func buzzImage(_ url: URL) -> some View {
        AsyncImage(url: url) { p in
            if let img = p.image { img.resizable().aspectRatio(contentMode: .fit) }
            else { Color.clear }
        }
        .frame(maxWidth: 600, maxHeight: 280, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Reveal

    private var revealView: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let q = current {
                Text("Answer").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                Text(q.correctAnswer).font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.mint)
                if !q.explanation.isEmpty {
                    Text(q.explanation).font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(index + 1 >= questions.count ? "Final Standings" : "Next Question") { advance() }
                .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                .padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(90)
    }

    // MARK: Standings

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
        phase = .playing
        host.beginQuestion(index: index)
    }

    private func tapOption(_ idx: Int, _ q: Question) {
        if idx == q.correctIndex {
            host.awardWinner(points: awardPoints)
            reveal(awardedCorrect: true)
        } else {
            // Wrong call — that seat is locked out, buzzing re-opens to others.
            host.rejectWinnerAndReopen()
            phase = .playing
        }
    }

    private func reveal(awardedCorrect: Bool) {
        host.lock()
        if !awardedCorrect, let q = current {
            missed.append(AnsweredQuestion(question: q, chosenIndex: nil, secondsTaken: 0))
        }
        phase = .reveal
    }

    private func advance() {
        index += 1
        if index >= questions.count { finish() } else { startQuestion() }
    }

    private func finish() {
        phase = .finished
        // Record the host's own learning recap (the missed facts) so Buzz Night
        // still feeds the records loop, even though scoring is per-phone-seat.
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
