#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Trivia Night setup (solo) — parity

/// Mac Trivia Night setup: pick a format preset + category, then play a
/// multi-round night solo (host/join over the network is a tracked follow-up —
/// it needs the shared mDNS/TCP transport and real-device testing).
struct NightSetupSheet_macOS: View {
    let onStart: (NightPlan, TriviaCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 1   // Pub Night default
    @State private var category: TriviaCategory = .named("mixed")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trivia Night").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider().overlay(Tidbits.Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick a format").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    ForEach(Array(NightPlan.presets.enumerated()), id: \.offset) { i, preset in
                        Button { selected = i } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected == i ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Tidbits.Palette.coral)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                                    Text(preset.blurb).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                                    Text(roundLine(preset.plan)).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .chunkyCard(fill: selected == i ? Tidbits.Palette.coral.opacity(0.15) : Tidbits.Palette.surface)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Category").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(TriviaCategory.all) { c in
                            let on = category.id == c.id
                            Button { category = c } label: {
                                Text(c.name).font(Tidbits.TypeRamp.l3).lineLimit(1)
                                    .foregroundStyle(on ? c.color.legibleForeground : Tidbits.Palette.ink)
                                    .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 11)
                                    .background(Capsule().fill(on ? c.color : Tidbits.Palette.surface))
                                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            Divider().overlay(Tidbits.Palette.border)
            Button {
                onStart(NightPlan.presets[selected].plan, category); dismiss()
            } label: {
                Label("Start the night", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
            .keyboardShortcut(.defaultAction)
            .padding()
        }
        .frame(width: 520, height: 640)
        .background(Tidbits.Palette.bg)
    }

    private func roundLine(_ plan: NightPlan) -> String {
        let n = plan.rounds.count
        let qs = plan.rounds.reduce(0) { $0 + $1.count }
        return "\(n) rounds · \(qs) questions"
    }
}

// MARK: - Night container (solo)

struct NightContainer_macOS: View {
    let plan: NightPlan
    let category: TriviaCategory
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var started = false
    @State private var recorded = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Building your night…").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
                }
            case .roundIntro:
                RoundIntroView_macOS(game: game, onQuit: close)
            case .playing, .reveal:
                GameView_macOS(game: game, onQuit: close)
            case .finished:
                ResultsView_macOS(summary: game.summary, onPlayAgain: nil, onDone: close)
                    .onAppear(perform: persist)
            }
        }
        .task {
            if !started {
                started = true
                let qs = await QuestionProvider.shared.nightQuestions(plan: plan, category: category)
                game.startNight(plan: plan, category: category, questions: qs, hostPaced: false)
            }
        }
    }

    private func persist() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }
    private func close() { game.quit(); onClose() }
}

// MARK: - Round intro beat (a round must be FELT)

struct RoundIntroView_macOS: View {
    @Bindable var game: GameEngine
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button(action: onQuit) { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
            Spacer()
            Text("ROUND \(game.currentRoundNumber) OF \(game.roundCount)")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Image(systemName: game.introRound?.symbol ?? "party.popper.fill")
                .font(.system(size: 44, weight: .black)).foregroundStyle(Tidbits.Palette.coral)
            Text(game.introRound?.title ?? "Round")
                .font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(Tidbits.Palette.ink)
            if let c = game.introRound?.count {
                Text("\(c) question\(c == 1 ? "" : "s")").font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.inkSoft)
            }
            Button("Start round") { game.startRound() }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.coral, textColor: .white))
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tidbits.Palette.bg)
    }
}
#endif
