#if os(macOS)
import SwiftUI
import SwiftData

/// Mac Create (macOS-DESIGN Part B). "Make a quiz on the fly" — type any
/// Wikipedia topic; the shared template/corpus engine turns it into a playable
/// round. Same generation path as iOS (corpus MCQ + a couple of topic-matched
/// shapes, live Wikipedia only when the corpus is thin); only the presentation
/// is Mac-native.
struct CreateView_macOS: View {
    let onPlayCustom: (String, [Question]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var store
    @Query(sort: \SavedQuizRecord.createdAt, order: .reverse) private var saved: [SavedQuizRecord]
    /// Set briefly after a successful publish. A share that silently does nothing
    /// is worse than one that says what happened, and on a Mac the useful outcome
    /// is "the link is on your clipboard" — ShareLink can't be used because the URL
    /// doesn't exist until the publish round trip completes.
    @State private var shareNote: String?
    @State private var topic = ""
    /// The mode this quiz plays as. Rides with the quiz (`m` in the contract), so a
    /// shared quiz arrives as the game its author meant.
    @State private var playMode: GameMode = .mix
    @State private var isWorking = false
    @State private var error: String?
    @State private var stageIndex = 0
    @FocusState private var topicFocused: Bool

    private let suggestions = ["The Solar System", "Ancient Rome", "Jazz", "Volcanoes", "The Olympics", "Marie Curie"]
    private let stages = ["Searching Wikipedia…", "Pulling out the facts…",
                          "Writing your questions…", "Double-checking the answers…"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick any subject. We'll pull it straight from Wikipedia and build you a quiz.")
                    .font(Tidbits.TypeRamp.l3).foregroundStyle(Tidbits.Palette.ink)
                inputCard
                modePicker
                if let error { errorBanner(error) }
                if let shareNote {
                    Label(shareNote, systemImage: "checkmark.circle.fill")
                        .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
                        .padding(12).chunkyCard(fill: Tidbits.Palette.mint.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Need a spark?").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { topic = s; generate() } label: {
                                Text(s).font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Capsule().fill(Tidbits.Palette.surface))
                                    .overlay(Capsule().strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                savedSection
            }
            .padding(28)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tidbits.Palette.bg)
        .navigationTitle("Create")
        .task {
            if let t = DebugHooks.autoCreate, topic.isEmpty { topic = t; generate() }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("e.g. The Renaissance", text: $topic)
                .textFieldStyle(.plain).font(Tidbits.TypeRamp.l3)
                .focused($topicFocused).onSubmit(generate)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tidbits.Palette.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tidbits.Palette.border, lineWidth: 2.5))
            if isWorking {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().progressViewStyle(.linear).tint(Tidbits.Palette.grape)
                    Text(stages[stageIndex]).font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.inkSoft).contentTransition(.opacity)
                }
            } else {
                Button("Generate Quiz", action: generate)
                    .buttonStyle(ChunkyButtonStyle(fill: Tidbits.Palette.grape, textColor: .white))
                    .disabled(topic.trimmingCharacters(in: .whitespaces).count < 2)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).chunkyCard()
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).chunkyCard(fill: Tidbits.Palette.coral.opacity(0.25))
    }

    /// Every quiz you make is kept — the owner's rule is "all created quizzes should
    /// be saved to your account", so this is automatic. The empty line teaches the
    /// mechanic on first run rather than leaving a blank wall.
    /// A created quiz is a fixed set of questions, so the mode is a real choice: the
    /// same eight questions play very differently as Survival than as Time Attack.
    private var modePicker: some View {
        HStack(spacing: 12) {
            Text("Play it as").font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            Picker("Mode", selection: $playMode) {
                ForEach(SavedQuiz.playableModes, id: \.self) { m in
                    Text(SavedQuiz.modeLabel(m)).tag(m)
                }
            }
            .labelsHidden().frame(maxWidth: 220)
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your quizzes").font(Tidbits.TypeRamp.l2).foregroundStyle(Tidbits.Palette.ink)
            if saved.isEmpty {
                Text("Quizzes you make are saved here automatically, ready to replay.")
                    .font(Tidbits.TypeRamp.l5).foregroundStyle(Tidbits.Palette.inkSoft)
            } else {
                ForEach(saved) { record in
                    SavedQuizRow_macOS(
                        record: record,
                        onPlay: { play(record) },
                        onShare: { share(record) },
                        onDelete: { QuizStore.delete(id: record.quizID, in: modelContext) })
                }
            }
        }
    }

    /// Replaying resolves the quiz's refs against what THIS build ships. A quiz can
    /// legitimately come up short, so the shortfall is surfaced rather than padded.
    private func play(_ record: SavedQuizRecord) {
        guard let quiz = record.quiz else { return }
        let resolution = quiz.resolveAgainstBundle()
        guard resolution.isPlayable else {
            error = "This quiz needs questions your version doesn't have yet. Try creating it again from \u{201C}\(quiz.topic)\u{201D}."
            return
        }
        QuizStore.markPlayed(id: quiz.id, in: modelContext)
        // Honour the mode the quiz was saved with, not whatever the picker happens
        // to show — a quiz saved as Survival must replay as Survival.
        playMode = quiz.gameMode
        onPlayCustom(quiz.title, resolution.questions)
    }

    private func share(_ record: SavedQuizRecord) {
        guard let quiz = record.quiz else { return }
        Task {
            do {
                if let url = try await QuizSharing.publish(quiz, in: modelContext) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    shareNote = "Link copied — anyone can play it."
                    try? await Task.sleep(for: .seconds(3))
                    shareNote = nil
                }
            } catch {
                self.error = "Couldn't share that quiz just now. Check your connection and try again."
            }
        }
    }

    private func generate() {
        let q = topic.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !isWorking else { return }
        topic = q; error = nil; topicFocused = false; stageIndex = 0; isWorking = true
        Task {
            var i = 0
            while isWorking {
                try? await Task.sleep(for: .seconds(0.9))
                i += 1
                withAnimation { stageIndex = min(i, stages.count - 1) }
            }
        }
        Task {
            let result = await QuestionProvider.shared.createSet(topic: q)
            isWorking = false
            if result.count >= 3 {
                // Every created quiz is saved automatically — no Save button to miss.
                let quiz = SavedQuiz.from(
                    questions: result, topic: q, mode: playMode.rawValue,
                    creatorID: PlayerIdentityStore.shared.profileId ?? "local",
                    creatorName: PlayerIdentityStore.shared.profile?.name ?? "")
                QuizStore.save(quiz, in: modelContext)
                onPlayCustom(q, result)
            } else {
                error = "Couldn't build a good quiz for \u{201C}\(q)\u{201D}. Try a broader or more famous subject."
            }
        }
    }
}


/// One row on the Mac Create shelf. Pointer-first: Share and Delete are visible
/// buttons rather than a long-press menu, because a Mac user expects to see the
/// verbs (macos-platform-patterns).
private struct SavedQuizRow_macOS: View {
    let record: SavedQuizRecord
    let onPlay: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title).font(Tidbits.TypeRamp.l3)
                        .foregroundStyle(Tidbits.Palette.ink).lineLimit(1)
                    Text(subtitle).font(Tidbits.TypeRamp.l5)
                        .foregroundStyle(Tidbits.Palette.inkSoft).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Share", action: onShare).buttonStyle(CompactButtonStyle())
            Button("Delete") { confirmingDelete = true }
                .buttonStyle(CompactButtonStyle())
            Image(systemName: "play.circle.fill")
                .font(.system(size: 22)).foregroundStyle(Tidbits.Palette.grape)
        }
        .padding(14)
        .chunkyCard()
        .confirmationDialog("Delete \u{201C}\(record.title)\u{201D}?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var subtitle: String {
        var parts = ["\(record.questionCount) questions"]
        if record.playCount == 1 { parts.append("played once") }
        else if record.playCount > 1 { parts.append("played \(record.playCount)x") }
        if record.isShared { parts.append("shared") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

#endif
