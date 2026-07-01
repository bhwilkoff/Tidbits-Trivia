#if os(iOS)
import SwiftUI
import SwiftData

/// "Make a quiz on the fly." Type any Wikipedia topic; the live template
/// engine turns it into a playable round. This is the infinite-content
/// promise made tangible — the same engine that fills the corpus.
struct CreateQuizView: View {
    @Environment(AppStore.self) private var store
    @State private var topic = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var generated: [Question] = []
    @State private var playing = false
    @FocusState private var topicFocused: Bool
    @State private var stageIndex = 0

    private let suggestions = ["Space exploration", "Ancient Rome", "Jazz", "Volcanoes", "The Olympics", "Marie Curie"]
    private let stages = ["Searching Wikipedia…", "Pulling out the facts…",
                          "Writing your questions…", "Double-checking the answers…"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                inputCard
                if let error { errorBanner(error) }
                suggestionsSection
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .padding(.vertical, 18)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .navigationTitle("Create")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { topicFocused = false }
            }
        }
        .fullScreenCover(isPresented: $playing) {
            CustomGameContainer(topic: topic.isEmpty ? "Custom" : topic, questions: generated)
        }
        .task {
            if let t = DebugHooks.autoCreate, topic.isEmpty {
                topic = t
                generate()
            }
        }
    }

    private var intro: some View {
        Text("Pick any subject. We'll pull it straight from Wikipedia and build you a quiz.")
            .font(Tidbits.TypeRamp.l3)
            .foregroundStyle(Tidbits.Palette.ink)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("e.g. The Renaissance", text: $topic)
                .font(Tidbits.TypeRamp.l3)
                .textInputAutocapitalization(.words)
                .submitLabel(.go)
                .focused($topicFocused)
                .onSubmit(generate)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            if isWorking {
                progressCard
            } else {
                Button(action: generate) { Text("Generate Quiz") }
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.grape, textColor: .white))
                    .disabled(topic.trimmingCharacters(in: .whitespaces).count < 2)
            }
        }
        .padding(16)
        .chunkyCard()
        .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    /// Generation is a single opaque async call, so an honest indeterminate bar
    /// plus a cycling status beats a fake percentage — it tells the user work is
    /// happening and what stage it's at, which is what a long wait needs.
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Tidbits.Palette.grape)
            Text(stages[stageIndex])
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Tidbits.TypeRamp.l5)
            .foregroundStyle(Tidbits.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .chunkyCard(fill: Tidbits.Palette.coral.opacity(0.25))
            .padding(.trailing, Tidbits.Metric.shadowOffset)
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Need a spark?").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            FlowChips(items: suggestions) { topic = $0; generate() }
        }
    }

    private func generate() {
        let q = topic.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !isWorking else { return }
        topic = q
        error = nil
        topicFocused = false   // drop the keyboard so the progress is visible
        stageIndex = 0
        isWorking = true
        // Cycle the status text while the (opaque) generation runs.
        Task {
            var i = 0
            while isWorking {
                try? await Task.sleep(for: .seconds(0.9))
                i += 1
                withAnimation { stageIndex = min(i, stages.count - 1) }
            }
        }
        Task {
            let result = await QuestionProvider.shared.liveQuestions(
                topic: q, category: .named("mixed"), count: 8)
            isWorking = false
            if result.count >= 3 {
                generated = result
                playing = true
            } else {
                error = "Couldn't build a good quiz for \u{201C}\(q)\u{201D}. Try a broader or more famous subject."
            }
        }
    }
}

/// Simple wrapping chip row for suggestions.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(Tidbits.Palette.surface))
                        .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Runs a custom (live-generated) question set through the same engine.
struct CustomGameContainer: View {
    let topic: String
    let questions: [Question]
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var started = false
    @State private var recorded = false

    private var game: GameEngine { store.game }

    var body: some View {
        ZStack {
            Tidbits.Palette.bg.ignoresSafeArea()
            switch game.phase {
            case .idle, .loading:
                ProgressView().controlSize(.large).tint(Tidbits.Palette.ink)
            case .playing, .reveal:
                GamePlayView(game: game, onQuit: close)
            case .finished:
                ResultsView(summary: game.summary, onPlayAgain: replay, onDone: close)
                    .onAppear(perform: persist)
            }
        }
        .onAppear {
            if !started { started = true; game.startCustom(mode: .classic, category: .named("mixed"), questions: questions) }
        }
    }

    private func persist() {
        guard !recorded else { recorded = true; return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
    }
    private func replay() { recorded = false; game.startCustom(mode: .classic, category: .named("mixed"), questions: questions) }
    private func close() { game.quit(); dismiss() }
}
#endif
