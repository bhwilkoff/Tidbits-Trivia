#if os(tvOS)
import SwiftUI
import SwiftData

/// Runs a Trivia Night on Apple TV — builds the round-tagged mixed question
/// list from the plan, starts the engine in `.barTrivia`, then reuses the SAME
/// ten-foot play + results views every other mode uses.
struct TVNightContainer: View {
    let plan: NightPlan
    let category: TriviaCategory
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                if game.loadFailed { errorState } else { loading }
            case .playing, .reveal:
                TVGamePlayView(onQuit: close)
            case .finished:
                TVResultsView(summary: game.summary, onPlayAgain: replay, onDone: close)
                    .onAppear(perform: persist)
            }
        }
        .task { if game.phase == .idle { await begin() } }
        .onExitCommand(perform: close)
    }

    private func begin() async {
        let qs = await QuestionProvider.shared.nightQuestions(plan: plan, category: category)
        game.startNight(plan: plan, category: category, questions: qs)
    }

    private var loading: some View {
        VStack(spacing: 28) {
            ProgressView().controlSize(.extraLarge).tint(.white)
            Text("Setting up your night…").font(.system(size: 31, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
        }
    }
    private var errorState: some View {
        VStack(spacing: 24) {
            Text("Couldn't build the night").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Some rounds need fresh data we couldn't reach.").font(.system(size: 29)).foregroundStyle(TVTheme.textSoft)
            Button("Back", action: close).buttonStyle(.bordered)
        }
    }

    private func persist() {
        guard !recorded else { return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }
    private func replay() { recorded = false; Task { await begin() } }
    private func close() { game.quit(); dismiss() }
}

// MARK: - Setup (ten-foot config)

/// Configure the night on the TV — pick a preset (length + which rounds) and a
/// category, then start. Presets-first keeps it one focus-hop on the couch; the
/// fine-grained per-round editor lives on the phone (where a Siri Remote isn't).
struct NightSetupView_tvOS: View {
    let onStart: (NightPlan, TriviaCategory, NightStartMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var presetIndex = 1   // Pub Night
    @State private var category: TriviaCategory = .named("mixed")
    @FocusState private var focus: Field?
    private enum Field: Hashable { case preset(Int), category(Int), start, host }

    private var plan: NightPlan { NightPlan.presets[presetIndex].plan }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRIVIA NIGHT").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("A night of mixed rounds — every kind of question. Each answer ends on a fact to learn.")
                            .font(.system(size: 29, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                    }
                    presetRow
                    categoryRow
                    HStack(spacing: 24) {
                        Button("Play on this TV · \(plan.totalQuestions) Questions") {
                            dismiss(); onStart(plan, category, .solo)
                        }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: false))
                        .focused($focus, equals: .start)
                        Button {
                            dismiss(); onStart(plan, category, .host)
                        } label: {
                            Label("Host for Other Devices", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(TVChipStyle(accent: Tidbits.Palette.grape, selected: false))
                        .focused($focus, equals: .host)
                    }
                    Text("Host a night and everyone joins on their own iPhone or iPad — the TV shows a join code and the standings, and you play along with the remote.")
                        .font(.system(size: 23, weight: .medium, design: .rounded)).foregroundStyle(TVTheme.textSoft)
                }
                .padding(90)
            }
        }
        .defaultFocus($focus, .preset(1))
        .onExitCommand { dismiss() }
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Format").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            HStack(spacing: 30) {
                ForEach(Array(NightPlan.presets.enumerated()), id: \.offset) { i, preset in
                    Button { presetIndex = i } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(preset.name).font(.system(size: 31, weight: .black, design: .rounded))
                            Text(preset.blurb).font(.system(size: 23, weight: .medium, design: .rounded)).opacity(0.85)
                            Spacer()
                            HStack(spacing: 8) {
                                ForEach(preset.plan.rounds) { r in
                                    Image(systemName: r.symbol).font(.system(size: 22, weight: .bold))
                                }
                            }
                        }
                        .frame(width: 360, height: 240, alignment: .leading)
                        .padding(28)
                    }
                    .buttonStyle(TVChipStyle(accent: Tidbits.Palette.coral, selected: presetIndex == i))
                    .focused($focus, equals: .preset(i))
                }
            }
        }
        .focusSection()
    }

    private var categoryRow: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Category").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(TriviaCategory.all.enumerated()), id: \.offset) { i, cat in
                        Button { category = cat } label: {
                            HStack(spacing: 14) {
                                Image(systemName: cat.symbol).font(.system(size: 28, weight: .black))
                                Text(cat.name).font(.system(size: 27, weight: .bold, design: .rounded))
                            }
                            .frame(height: 64).padding(.horizontal, 14)
                        }
                        .buttonStyle(TVChipStyle(accent: cat.color, selected: category.id == cat.id))
                        .focused($focus, equals: .category(i))
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}
#endif
