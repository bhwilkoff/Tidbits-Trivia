#if os(macOS)
import SwiftUI

/// Local pass-and-play on the Mac: 2–4 players take turns at ONE machine, all
/// answering the SAME question set (fair), with a hand-off screen between turns
/// so nobody sees the next player's answers. Same GameEngine loop as solo —
/// multiplayer is the loop wrapped, not reimplemented (Decision 023).
///
/// Mirrors `iOS/Views/PartyContainerView.swift` and the Windows `PartyView`;
/// only the shell is new (macos-platform-patterns). Like Versus, this REPLACES
/// the window root rather than presenting a sheet, so the split-view toolbar
/// and sidebar toggle don't bleed through a game in progress.
struct PartyContainer_macOS: View {
    let onClose: () -> Void

    @Environment(AppStore.self) private var store

    enum Phase: Equatable { case setup, loading, handoff, playing, turnDone, scoreboard }
    @State private var phase: Phase = .setup
    @State private var players: [Player] = Player.defaults(2)
    @State private var category: TriviaCategory = .named("mixed")
    @State private var questionCount = 5
    @State private var questions: [Question] = []
    @State private var turn = 0
    @State private var lastTurnScore = 0

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch phase {
            case .setup:
                PartySetupView_macOS(players: $players, category: $category,
                                     questionCount: $questionCount, onStart: start, onCancel: quit)
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Dealing \(questionCount) questions…")
                        .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            case .handoff:    handoff
            case .playing:    GameView_macOS(game: game, onQuit: quit)
            case .turnDone:   turnDone
            case .scoreboard: PartyScoreboard_macOS(players: rankedPlayers, onRematch: rematch, onDone: quit)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: game.phase) { _, newValue in
            guard phase == .playing, newValue == .finished else { return }
            lastTurnScore = game.summary.score
            players[turn].score = lastTurnScore
            phase = .turnDone
        }
        .task(id: phase) {
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

    // MARK: Phases

    private var handoff: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(players[turn].color.legibleAccent)
            Text("Pass the Mac to").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            Text(players[turn].name)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
            Text("Turn \(turn + 1) of \(players.count) · \(questionCount) questions")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Spacer()
            HStack(spacing: 12) {
                Button("Quit", action: quit)
                    .buttonStyle(CompactButtonStyle()).keyboardShortcut(.cancelAction)
                Button("I'm \(players[turn].name) — Start", action: beginTurn)
                    .buttonStyle(CompactButtonStyle(fill: players[turn].color,
                                                    textColor: players[turn].color.legibleForeground,
                                                    prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)
        }
    }

    private var turnDone: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("\(players[turn].name) scored")
                .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            Text("\(lastTurnScore)")
                .font(.system(size: 60, weight: .black, design: .rounded))
                .foregroundStyle(players[turn].color.legibleAccent)
            if turn + 1 < players.count { runningBoard }
            Spacer()
            Button(turn + 1 < players.count ? "Next Player" : "See Results", action: advanceTurn)
                .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.ink, textColor: .white, prominent: true))
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 24)
        }
    }

    private var runningBoard: some View {
        VStack(spacing: 8) {
            ForEach(players.prefix(turn + 1)) { p in
                HStack(spacing: 10) {
                    Circle().fill(p.color).frame(width: 14, height: 14)
                    Text(p.name).font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.ink)
                    Spacer()
                    Text("\(p.score)").font(Tidbits.TypeRamp.l6).foregroundStyle(Tidbits.Palette.ink)
                }
            }
        }
        .padding(16).frame(width: 340).chunkyCard()
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
        game.startCustom(mode: .classic, category: category, questions: questions)
        phase = .playing
    }

    private func advanceTurn() {
        if turn + 1 < players.count { turn += 1; phase = .handoff }
        else { phase = .scoreboard }
    }

    private func rematch() {
        for i in players.indices { players[i].score = 0 }
        turn = 0
        phase = .setup
    }

    /// Pass-and-play turns must never write a solo record (same rule as Versus).
    private func quit() { game.quit(); onClose() }
}

// MARK: - Setup

private struct PartySetupView_macOS: View {
    @Binding var players: [Player]
    @Binding var category: TriviaCategory
    @Binding var questionCount: Int
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pass & Play").font(Tidbits.TypeRamp.l1).foregroundStyle(Tidbits.Palette.ink)
                Text("Everyone shares one Mac. Same questions, fair and square.")
                    .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)

                playerStepper
                ForEach($players) { $player in
                    HStack(spacing: 12) {
                        Circle().fill(player.color).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        TextField("Name", text: $player.name)
                            .textFieldStyle(.plain).font(Tidbits.TypeRamp.l3)
                            .foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(12).chunkyCard()
                }

                Text("Questions each").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Picker("Questions", selection: $questionCount) {
                    ForEach([3, 5, 7, 10], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)

                Text("Category").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Picker("Category", selection: $category) {
                    ForEach(TriviaCategory.all) { c in Text(c.name).tag(c) }
                }
                .labelsHidden().frame(maxWidth: 320)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(CompactButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Start Game", action: onStart)
                        .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var playerStepper: some View {
        HStack(spacing: 12) {
            Text("Players").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
            Spacer()
            Button {
                if players.count > 2 { players.removeLast() }
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 22))
                    .foregroundStyle(players.count > 2 ? Tidbits.Palette.coral : Tidbits.Palette.inkSoft.opacity(0.4))
            }
            .buttonStyle(.plain).disabled(players.count <= 2)
            Text("\(players.count)").font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink).frame(minWidth: 28)
            Button {
                if players.count < 4 { players.append(Player(name: "Player \(players.count + 1)", colorIndex: players.count)) }
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 22))
                    .foregroundStyle(players.count < 4 ? Tidbits.Palette.mint : Tidbits.Palette.inkSoft.opacity(0.4))
            }
            .buttonStyle(.plain).disabled(players.count >= 4)
        }
        .padding(12).chunkyCard(fill: Tidbits.Palette.bgDeep)
    }
}

// MARK: - Scoreboard

private struct PartyScoreboard_macOS: View {
    let players: [Player]   // already ranked
    let onRematch: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(headline)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Tidbits.Palette.ink)
                ForEach(Array(players.enumerated()), id: \.element.id) { rank, p in
                    HStack(spacing: 14) {
                        Text("\(rank + 1)").font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(Tidbits.Palette.inkSoft).frame(width: 24)
                        Circle().fill(p.color).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                        Text(p.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        Spacer()
                        Text("\(p.score)").font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(Tidbits.Palette.ink)
                    }
                    .padding(14)
                    .chunkyCard(fill: isTop(p) ? Tidbits.Palette.yellow : Tidbits.Palette.surface)
                }
                HStack(spacing: 12) {
                    ShareLink(item: shareText) { Text("Share Result") }
                        .buttonStyle(CompactButtonStyle())
                    Button("Rematch", action: onRematch)
                        .buttonStyle(CompactButtonStyle(fill: Tidbits.Palette.coral, textColor: .white, prominent: true))
                    Button("Done", action: onDone)
                        .buttonStyle(CompactButtonStyle()).keyboardShortcut(.cancelAction)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 460)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    /// Ties are announced by the shared rule (Core/StandingsOutcome) so the
    /// Pass & Play board and a hosted Trivia Night never disagree.
    private var entries: [(name: String, score: Int)] { players.map { ($0.name, $0.score) } }
    private func isTop(_ p: Player) -> Bool { StandingsOutcome.isTop(p.score, in: entries) }
    private var headline: String { StandingsOutcome.headline(entries, empty: "Winner") }

    private var shareText: String {
        let line = players.map { "\($0.name): \($0.score)" }.joined(separator: " · ")
        return "Tidbits Pass & Play — \(headline)\n\(line)\nTrivia from all of Wikipedia."
    }
}
#endif
