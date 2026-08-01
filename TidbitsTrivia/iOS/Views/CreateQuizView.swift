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
    /// The mode this round plays as. Set from the picker when creating, and from the
    /// quiz's own `m` when replaying — a quiz saved as Survival must replay as
    /// Survival, not as the mixed round every surface used to hardcode.
    @State private var playMode: GameMode = .mix
    @State private var shareURL: URL?
    @State private var incoming: SavedQuiz?
    @State private var incomingState: IncomingState = .idle

    /// Opening a shared link has real states, and "gone" is NOT "couldn't load":
    /// telling someone with a working link that it was deleted stops them retrying.
    enum IncomingState: Equatable { case idle, loading, notFound, failed(String), ready }
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
                                questions: generated, quizID: playingQuizID, mode: playMode)
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .sheet(item: $incoming) { quiz in
            SharedQuizSheet(quiz: quiz, onPlay: { playShared(quiz) })
        }
        .onChange(of: store.pendingSharedQuizID) { _, id in
            if let id { openShared(id) }
        }
        .task(id: store.pendingSharedQuizID) {
            if let id = store.pendingSharedQuizID { openShared(id) }
        }
        .task {
            if let t = DebugHooks.autoCreate, topic.isEmpty {
                topic = t
                generate()
            } else if let shared = DebugHooks.sharedQuizID {
                openShared(shared)
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
            modePicker
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

    /// A created quiz is a fixed set of questions, so the mode is a genuine choice
    /// rather than a detail: the same eight questions play very differently as
    /// Survival than as Time Attack. It rides with the quiz (`m` in the contract), so
    /// a shared quiz arrives as the game its author meant.
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How do you want to play it?")
                .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Picker("Mode", selection: $playMode) {
                ForEach(SavedQuiz.playableModes, id: \.self) { m in
                    Text(SavedQuiz.modeLabel(m)).tag(m)
                }
            }
            .pickerStyle(.menu)
            .tint(Tidbits.Palette.ink)
        }
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
                                 onDelete: { QuizStore.delete(id: record.quizID, in: modelContext) },
                                 onShare: { share(record) })
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
        playMode = quiz.gameMode
        playingQuizID = quiz.id
        topic = quiz.topic
        playing = true
    }

    /// Fetch a shared quiz, keep it, and offer to play. Keeping on arrival is
    /// deliberate: a link someone sent you should end up on your shelf, not vanish
    /// when you close the sheet.
    private func openShared(_ id: String) {
        store.pendingSharedQuizID = nil          // consume once
        guard QuizStore.quiz(id: id, in: modelContext) == nil else {
            if let mine = QuizStore.quiz(id: id, in: modelContext) { incoming = mine }
            return
        }
        incomingState = .loading
        Task {
            switch await QuizSharing.fetch(id: id) {
            case .found(let quiz):
                QuizStore.save(quiz, in: modelContext)
                incomingState = .ready
                incoming = quiz
            case .notFound:
                incomingState = .notFound
                error = "That link doesn’t point at a quiz any more. It may have been deleted by whoever made it."
            case .failed(let message):
                incomingState = .failed(message)
                error = message
            }
        }
    }

    /// Publish, then hand the link to the system share sheet. A share that quietly
    /// does nothing is worse than one that admits it failed.
    private func share(_ record: SavedQuizRecord) {
        guard let quiz = record.quiz else { return }
        Task {
            do {
                if let url = try await QuizSharing.publish(quiz, in: modelContext) {
                    shareURL = url
                }
            } catch {
                self.error = "Couldn’t share that quiz just now. Check your connection and try again."
            }
        }
    }

    private func playShared(_ quiz: SavedQuiz) {
        incoming = nil
        guard let record = QuizStore.record(id: quiz.id, in: modelContext) else { return }
        play(record)
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
                    questions: result, topic: q, mode: playMode.rawValue,
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
    var mode: GameMode = .mix
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
            if !started { started = true; game.startCustom(mode: mode, category: .named("mixed"), questions: questions) }
        }
    }

    private func persist() {
        guard !recorded else { recorded = true; return }
        recorded = true
        RecordsStore.record(game.summary, in: modelContext)
        if let quizID { QuizStore.markPlayed(id: quizID, in: modelContext) }
    }
    private func replay() { recorded = false; game.startCustom(mode: mode, category: .named("mixed"), questions: questions) }
    private func close() { game.quit(); dismiss() }
}


/// One row on the Create tab's quiz shelf. Chunky-card system per iOS-DESIGN §5;
/// destructive delete lives in a context menu rather than a visible button, so the
/// row's primary tap target stays "play this".
private struct SavedQuizRow: View {
    let record: SavedQuizRecord
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onShare: () -> Void = {}
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
            Button { onShare() } label: { Label("Share", systemImage: "square.and.arrow.up") }
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



/// `sheet(item:)` needs Identifiable; URL isn't. Wrapping it here keeps the share
/// flow to one line at the call site.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The system share sheet. UIActivityViewController rather than SwiftUI's
/// ShareLink because the URL only exists AFTER the publish round trip completes —
/// ShareLink needs its payload up front.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// What you see when someone sends you a quiz. It is already saved to your shelf by
/// the time this appears — a link a friend sent shouldn't evaporate when you close
/// the sheet.
private struct SharedQuizSheet: View {
    let quiz: SavedQuiz
    let onPlay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(Tidbits.Palette.grape)
            Text(quiz.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Tidbits.Palette.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            Text("Saved to your quizzes.")
                .font(Tidbits.TypeRamp.l5)
                .foregroundStyle(Tidbits.Palette.inkSoft)
            Spacer()
            Button(action: onPlay) { Text("Play this quiz") }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.grape, textColor: .white))
            Button("Later") { dismiss() }
                .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.surface, textColor: Tidbits.Palette.ink))
        }
        .padding(24)
        .background(Tidbits.Palette.bg.ignoresSafeArea())
    }

    private var subtitle: String {
        let by = quiz.creatorName.isEmpty ? "" : "Made by \(quiz.creatorName) · "
        return "\(by)\(quiz.questionCount) questions"
    }
}

#endif
