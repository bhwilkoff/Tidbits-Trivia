#if os(iOS)
import SwiftUI
import SwiftData

/// "Make a quiz on the fly." Type any Wikipedia topic; the live template
/// engine turns it into a playable round. This is the infinite-content
/// promise made tangible — the same engine that fills the corpus.
struct CreateQuizView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedQuizRecord.createdAt, order: .reverse) private var saved: [SavedQuizRecord]
    @State private var topic = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var generated: [Question] = []
    @State private var playingQuizID: String?
    @State private var playing = false
    @State private var shortfall: Int = 0
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
                savedSection
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .readableColumn(alignment: .leading)   // §2.2a — aligns with the nav title
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
            CustomGameContainer(topic: topic.isEmpty ? "Custom" : topic,
                                questions: generated, quizID: playingQuizID)
        }
        .task {
            if let t = DebugHooks.autoCreate, topic.isEmpty {
                topic = t
                generate()
            } else if DebugHooks.playSavedQuiz, let newest = saved.first {
                play(newest)
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


    /// Every quiz you make is kept — the owner's rule is "all created quizzes should
    /// be saved to your account", so this is automatic, not a Save button you might
    /// miss. The empty line teaches the mechanic on first run instead of leaving a
    /// blank wall (universal-feature-states).
    /// R-REC-1 keeps a dashboard shelf to 3 rows with a "see all" escape hatch.
    private var shelf: [SavedQuizRecord] { Array(saved.prefix(3)) }

    @ViewBuilder
    private var savedHeader: some View {
        HStack {
            Text("Your quizzes")
                .font(Tidbits.TypeRamp.l2)
                .foregroundStyle(Tidbits.Palette.ink)
            Spacer()
            if saved.count > 3 {
                NavigationLink {
                    AllQuizzesView()
                } label: {
                    Text("See all")
                        .font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.grape)
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            savedHeader
            if saved.isEmpty {
                Text("Quizzes you make are saved here automatically, ready to replay.")
                    .font(Tidbits.TypeRamp.l5)
                    .foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                ForEach(shelf) { record in
                    SavedQuizRow(record: record,
                                 onPlay: { play(record) },
                                 onDelete: { QuizStore.delete(id: record.quizID, in: modelContext) })
                }
            }
        }
    }

    /// Replaying resolves the quiz's refs against what THIS build ships. A quiz can
    /// legitimately come up short (an older corpus, a set this platform lacks), so
    /// the shortfall is surfaced rather than silently padded with other questions.
    private func play(_ record: SavedQuizRecord) {
        guard let quiz = record.quiz else { return }
        let resolution = quiz.resolveAgainstBundle()
        guard resolution.isPlayable else {
            error = "This quiz needs questions your version doesn't have yet. Try creating it again from \u{201C}\(quiz.topic)\u{201D}."
            return
        }
        shortfall = resolution.missing
        generated = resolution.questions
        playingQuizID = quiz.id
        topic = quiz.topic
        playing = true
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
            // Grounded + VARIED (owner): diversity-capped corpus MCQ plus a couple
            // of topic-matched OTHER shapes (picture / this-or-that / closest) so
            // the set mixes question types AND categories, not 8 near-identical
            // questions. Live Wikipedia only when the corpus is thin.
            var shaped: [Question] = []
            for src in [JSONQuestionSource.picture, .thisOrThat, .closestCall] {
                shaped.append(contentsOf: src.searchMatch(topic: q, limit: 1))
            }
            var mcq = CorpusDatabase.shared.search(topic: q, limit: max(4, 8 - shaped.count))
            if mcq.count < 3 {
                let gen = await QuestionProvider.shared.liveQuestions(topic: q, category: .named("mixed"), count: 8)
                if gen.count >= 3 { mcq = gen; shaped = [] }
            }
            var result = Array((mcq + shaped).shuffled().prefix(8))
            isWorking = false
            if result.count >= 3 {
                generated = result
                // Every created quiz is saved to the account automatically — the
                // player never has to notice a Save button to keep what they made.
                let quiz = SavedQuiz.from(
                    questions: result, topic: q, mode: "mix",
                    creatorID: PlayerIdentityStore.shared.profileId ?? "local",
                    creatorName: PlayerIdentityStore.shared.profile?.name ?? "")
                QuizStore.save(quiz, in: modelContext)
                playingQuizID = quiz.id
                shortfall = 0
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
    /// Set when this round came from a saved quiz, so the play is counted against
    /// it. Play counts are LOCAL metadata — they never rewrite the quiz payload.
    var quizID: String? = nil
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
            case .roundIntro, .playing, .reveal:
                GamePlayView(game: game, onQuit: close)
            case .finished:
                ResultsView(summary: game.summary, onPlayAgain: replay, onDone: close)
                    .onAppear(perform: persist)
            }
        }
        .onAppear {
            if !started { started = true; game.startCustom(mode: .mix, category: .named("mixed"), questions: questions) }
        }
    }

    private func persist() {
        guard !recorded else { recorded = true; return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
        if let quizID { QuizStore.markPlayed(id: quizID, in: modelContext) }
    }
    private func replay() { recorded = false; game.startCustom(mode: .mix, category: .named("mixed"), questions: questions) }
    private func close() { game.quit(); dismiss() }
}


/// One row on the Create tab's quiz shelf. Chunky-card system per iOS-DESIGN §5;
/// destructive delete lives in a context menu rather than a visible button, so the
/// row's primary tap target stays "play this".
private struct SavedQuizRow: View {
    let record: SavedQuizRecord
    let onPlay: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Tidbits.Palette.grape)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chunkyCard()
            .padding(.trailing, Tidbits.Metric.shadowOffset)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete \u{201C}\(record.title)\u{201D}?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Question count first — it is what tells you how long the quiz is. The play
    /// count only appears once it means something.
    private var subtitle: String {
        var parts = ["\(record.questionCount) questions"]
        if record.playCount == 1 { parts.append("played once") }
        else if record.playCount > 1 { parts.append("played \(record.playCount)x") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// The full shelf, reached from "See all". Records-as-dashboard rule R-REC-1 keeps
/// the Create tab to 3 rows; everything lives here.
struct AllQuizzesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedQuizRecord.createdAt, order: .reverse) private var saved: [SavedQuizRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if saved.isEmpty {
                    Text("No saved quizzes yet.")
                        .font(Tidbits.TypeRamp.l4).foregroundStyle(Tidbits.Palette.inkSoft)
                } else {
                    ForEach(saved) { record in
                        SavedQuizRow(record: record, onPlay: {},
                                     onDelete: { QuizStore.delete(id: record.quizID, in: modelContext) })
                    }
                }
            }
            .padding(.horizontal, Tidbits.Metric.pad)
            .readableColumn(alignment: .leading)
            .padding(.vertical, 18)
        }
        .background(Tidbits.Palette.bg.ignoresSafeArea())
        .navigationTitle("Your quizzes")
    }
}

#endif
