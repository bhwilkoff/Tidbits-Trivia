#if os(iOS)
import SwiftUI

/// Local pass-and-play: 2–4 players take turns on ONE device, all
/// answering the SAME question set (fair), with a hand-off screen between
/// turns so nobody sees the next player's answers. Same GameEngine loop as
/// solo — multiplayer is the loop wrapped, not reimplemented (Decision 023).
struct PartyContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var engine = GameEngine()

    enum Phase: Equatable { case setup, loading, handoff, playing, turnDone, scoreboard }
    @State private var phase: Phase = .setup
    @State private var players: [Player] = Player.defaults(2)
    @State private var category: TriviaCategory = .named("mixed")
    @State private var questionCount = 5
    @State private var questions: [Question] = []
    @State private var turn = 0
    @State private var lastTurnScore = 0

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch phase {
            case .setup:      PartySetupView(players: $players, category: $category, questionCount: $questionCount, onStart: start, onCancel: { dismiss() })
            case .loading:    loading
            case .handoff:    handoff
            case .playing:    GamePlayView(game: engine, onQuit: { dismiss() })
            case .turnDone:   turnDone
            case .scoreboard: PartyScoreboardView(players: rankedPlayers, onRematch: rematch, onDone: { dismiss() })
            }
        }
        .onChange(of: engine.phase) { _, newValue in
            if phase == .playing && newValue == .finished {
                lastTurnScore = engine.summary.score
                players[turn].score = lastTurnScore
                phase = .turnDone
                Haptics.success()
            }
        }
        .task(id: phase) {
            // Screenshot/CI autopilot — drives setup→handoff→turnDone→scoreboard.
            guard DebugHooks.autopilot else { return }
            try? await Task.sleep(for: .seconds(0.8))
            switch phase {
            case .setup:    start()
            case .handoff:  beginTurn()
            case .turnDone: advanceTurn()
            default:        break
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            Text("Dealing \(questionCount) questions…").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
        }
    }

    private var handoff: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 54, weight: .bold)).foregroundStyle(players[turn].color.legibleAccent)
            Text("Pass the phone to").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            Text(players[turn].name)
                .font(.system(size: 38, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            Text("Turn \(turn + 1) of \(players.count) · \(questionCount) questions")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Spacer()
            Button("I'm \(players[turn].name) — Start") { beginTurn() }
                .buttonStyle(ChunkyButtonStyle(fill: players[turn].color, textColor: players[turn].color.legibleForeground))
                .padding(.horizontal, Tidbits.Metric.pad)
                .padding(.trailing, Tidbits.Metric.shadowOffset)
            Button("Quit") { dismiss() }.tint(Tidbits.Palette.inkSoft).padding(.bottom, 12)
        }
    }

    private var turnDone: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("\(players[turn].name) scored").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("\(lastTurnScore)").font(.system(size: 60, weight: .black, design: .rounded)).foregroundStyle(players[turn].color.legibleAccent)
            if turn + 1 < players.count {
                runningBoard
            }
            Spacer()
            Button(turn + 1 < players.count ? "Next Player" : "See Results") { advanceTurn() }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.ink, textColor: .white))
                .padding(.horizontal, Tidbits.Metric.pad).padding(.trailing, Tidbits.Metric.shadowOffset)
                .padding(.bottom, 16)
        }
    }

    private var runningBoard: some View {
        VStack(spacing: 8) {
            ForEach(players.prefix(turn + 1)) { p in
                HStack {
                    Circle().fill(p.color).frame(width: 14, height: 14)
                    Text(p.name).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("\(p.score)").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.ink)
                }
            }
        }
        .padding(16).chunkyCard().padding(.horizontal, Tidbits.Metric.pad).padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var rankedPlayers: [Player] { players.sorted { $0.score > $1.score } }

    // MARK: Flow

    private func start() {
        phase = .loading
        Task {
            questions = await QuestionProvider.shared.questions(category: category, count: questionCount)
            for i in players.indices { players[i].score = 0 }
            turn = 0
            phase = questions.count >= 2 ? .handoff : .scoreboard
        }
    }

    private func beginTurn() {
        engine.startCustom(mode: .classic, category: category, questions: questions)
        phase = .playing
    }

    private func advanceTurn() {
        if turn + 1 < players.count { turn += 1; phase = .handoff }
        else { phase = .scoreboard; Haptics.success() }
    }

    private func rematch() {
        for i in players.indices { players[i].score = 0 }
        turn = 0
        phase = .setup
    }
}

// MARK: - Setup

private struct PartySetupView: View {
    @Binding var players: [Player]
    @Binding var category: TriviaCategory
    @Binding var questionCount: Int
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Pass & Play").font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Button { onCancel() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundStyle(Tidbits.Palette.ink) }
                }
                Text("Everyone shares one phone. Same questions, fair and square.")
                    .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)

                stepperCard
                ForEach($players) { $player in
                    HStack(spacing: 12) {
                        Circle().fill(player.color).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        TextField("Name", text: $player.name).font(Tidbits.TypeRamp.l3)
                    }
                    .padding(14).chunkyCard().padding(.trailing, Tidbits.Metric.shadowOffset)
                }

                Text("Questions each").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Picker("Questions", selection: $questionCount) {
                    ForEach([3, 5, 7, 10], id: \.self) { Text("\($0)").tag($0) }
                }.pickerStyle(.segmented)

                Text("Category").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Menu {
                    ForEach(TriviaCategory.all) { c in Button(c.name) { category = c } }
                } label: {
                    HStack {
                        Image(systemName: category.symbol).foregroundStyle(category.color.legibleAccent)
                        Text(category.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer(); Image(systemName: "chevron.up.chevron.down").foregroundStyle(Tidbits.Palette.inkSoft)
                    }
                    .padding(14).chunkyCard().padding(.trailing, Tidbits.Metric.shadowOffset)
                }

                Button("Start Game", action: onStart)
                    .buttonStyle(ChunkyButtonStyle())
                    .padding(.trailing, Tidbits.Metric.shadowOffset).padding(.top, 4)
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var stepperCard: some View {
        HStack {
            Text("Players").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            Spacer()
            Button { if players.count > 2 { players.removeLast() } } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 28)).foregroundStyle(players.count > 2 ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft.opacity(0.4))
            }
            Text("\(players.count)").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink).frame(minWidth: 32)
            Button { if players.count < 4 { players.append(Player(name: "Player \(players.count + 1)", colorIndex: players.count)) } } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 28)).foregroundStyle(players.count < 4 ? Tidbits.Palette.mint : Tidbits.Palette.inkSoft.opacity(0.4))
            }
        }
        .padding(14).chunkyCard(fill: Tidbits.Palette.bgDeep).padding(.trailing, Tidbits.Metric.shadowOffset)
    }
}

// MARK: - Scoreboard

private struct PartyScoreboardView: View {
    let players: [Player]   // already ranked
    let onRematch: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("🏆").font(.system(size: 56))
                Text("\(players.first?.name ?? "Winner") wins!")
                    .font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                ForEach(Array(players.enumerated()), id: \.element.id) { rank, p in
                    HStack(spacing: 14) {
                        Text("\(rank + 1)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 28)
                        Circle().fill(p.color).frame(width: 26, height: 26).overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        Text(p.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Text("\(p.score)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(16)
                    .chunkyCard(fill: rank == 0 ? Tidbits.Palette.yellow : Tidbits.Palette.surface)
                    .padding(.trailing, Tidbits.Metric.shadowOffset)
                }
                ShareLink(item: shareText) {
                    Label("Share Result", systemImage: "square.and.arrow.up")
                        .font(Tidbits.TypeRamp.l3).frame(maxWidth: .infinity).foregroundStyle(.white).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: Tidbits.Metric.radius).fill(Tidbits.Palette.blue))
                        .overlay(RoundedRectangle(cornerRadius: Tidbits.Metric.radius).strokeBorder(Tidbits.Palette.border, lineWidth: 3))
                }.padding(.trailing, Tidbits.Metric.shadowOffset)
                Button("Rematch", action: onRematch).buttonStyle(ChunkyButtonStyle()).padding(.trailing, Tidbits.Metric.shadowOffset)
                Button("Done", action: onDone).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            .padding(Tidbits.Metric.pad)
        }
    }

    private var shareText: String {
        let line = players.map { "\($0.name): \($0.score)" }.joined(separator: " · ")
        return "🧠 Tidbits Pass & Play — \(players.first?.name ?? "") took the crown!\n\(line)\nTrivia from all of Wikipedia."
    }
}
#endif
