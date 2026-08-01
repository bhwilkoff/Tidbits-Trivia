#if os(tvOS)
import SwiftUI
import SwiftData

/// Create in the living room.
///
/// This is deliberately NOT the iOS screen scaled up. Three tvOS realities drive it
/// (tvos-platform-patterns):
///
/// 1. **Typing on a Siri Remote is hostile**, so the suggestion chips are the primary
///    path and the text field is the escape hatch — the opposite weighting to phone.
/// 2. **Focus does the work.** A row doesn't carry Share/Delete buttons; selecting a
///    quiz opens a detail where those verbs get room. Every card stays focusable, so
///    no `.buttonStyle(.plain)` anywhere.
/// 3. **A QR is the only way a link leaves a TV.** There's no clipboard worth using,
///    no share sheet and no browser, so sharing shows a code a phone in the room can
///    scan. On the other five platforms sharing hands over a URL; here the screen IS
///    the transport.
///
/// Quizzes made on a phone appear here because the shelf syncs through the account
/// bucket (QuizSync) — which is what makes a TV shelf worth having at all.
struct CreateView_tvOS: View {
    /// Carries the MODE too: a saved quiz replays as the game it was saved as, and
    /// the tvOS container would otherwise default every round to mix.
    let onPlay: (String, [Question], GameMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedQuizRecord.createdAt, order: .reverse) private var saved: [SavedQuizRecord]

    @State private var topic = ""
    @State private var playMode: GameMode = .mix
    @State private var isWorking = false
    @State private var error: String?
    @State private var detail: SavedQuizRecord?
    @State private var syncNote: String?
    @FocusState private var firstChipFocused: Bool
    @State private var hasClaimedInitialFocus = false

    /// Ten-foot suggestions: broad, recognisable subjects that fill a quiz. Typing is
    /// the fallback, so these have to be genuinely good rather than decorative.
    private let suggestions = ["Space exploration", "Ancient Rome", "Jazz", "Volcanoes",
                               "The Olympics", "Marie Curie", "Dinosaurs", "The Beatles"]

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 50) {
                    header
                    if isWorking { workingRow } else { chipGrid }
                    if let error { errorRow(error) }
                    typeRow
                    modeRow
                    shelf
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
            }
        }
        .fullScreenCover(item: $detail) { record in
            TVQuizDetail(record: record,
                         onPlay: { play(record) },
                         onDeleted: { detail = nil })
        }
        .task {
            // Claimed exactly once: a bare `.task { focused = true }` re-fires when
            // lazy rows recycle and yanks focus back mid-browse.
            if !hasClaimedInitialFocus { hasClaimedInitialFocus = true; firstChipFocused = true }
            // TIDBITS_AUTOCREATE drives generation without the remote — the tvOS
            // simulator doesn't take synthesised button presses from the CLI.
            if let t = DebugHooks.autoCreate, topic.isEmpty { topic = t; generate(t) }
            if DebugHooks.tvShareNewest, let newest = saved.first { detail = newest }
            let result = await QuizSync.sync(in: modelContext)
            if result.pulled > 0 {
                syncNote = "\(result.pulled) quiz\(result.pulled == 1 ? "" : "zes") from your other devices"
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create").font(.largeTitle).foregroundStyle(TVTheme.text)
            Text("Pick a subject and we'll build a quiz from the whole of Wikipedia.")
                .font(.body).foregroundStyle(TVTheme.textSoft)
        }
    }

    private var workingRow: some View {
        HStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Building your quiz…").font(.headline).foregroundStyle(TVTheme.textSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.body).foregroundStyle(TVTheme.text)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 18).fill(TVTheme.panelFocused))
    }

    // MARK: Input — chips first, typing second

    private var chipGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 24)], alignment: .leading, spacing: 24) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, subject in
                Button { generate(subject) } label: {
                    Text(subject)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 92)
                }
                .buttonStyle(.card)
                .focused($firstChipFocused, equals: index == 0)
            }
        }
    }

    /// Focusable chips rather than a Picker — on tvOS focus IS the selection model,
    /// and a menu-style Picker is a fiddly two-step with a remote.
    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Play it as").font(.title3).foregroundStyle(TVTheme.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], alignment: .leading, spacing: 20) {
                ForEach(SavedQuiz.playableModes, id: \.self) { m in
                    Button { playMode = m } label: {
                        HStack(spacing: 12) {
                            Image(systemName: playMode == m ? "checkmark.circle.fill" : "circle")
                            Text(SavedQuiz.modeLabel(m))
                        }
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 74)
                    }
                    .buttonStyle(.card)
                }
            }
        }
    }

    /// The escape hatch. tvOS puts up its own full-screen keyboard, which is slow but
    /// occasionally the only way to ask for something specific.
    private var typeRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Something else?").font(.title3).foregroundStyle(TVTheme.text)
            TextField("Type a subject", text: $topic)
                .textFieldStyle(.plain)
                .font(.headline)
                .onSubmit { generate(topic) }
        }
    }

    // MARK: Shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Your quizzes").font(.title3).foregroundStyle(TVTheme.text)
                if let syncNote {
                    Text("· \(syncNote)").font(.caption).foregroundStyle(TVTheme.textSoft)
                }
            }
            if saved.isEmpty {
                // Says where they come FROM, because on a TV most of them will have
                // been made somewhere else.
                Text("Quizzes you make here — or on your phone — are saved to your account and show up in this list.")
                    .font(.body).foregroundStyle(TVTheme.textSoft)
                    .frame(maxWidth: 900, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 24)], alignment: .leading, spacing: 24) {
                    ForEach(saved) { record in
                        Button { detail = record } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(record.title)
                                    .font(.headline).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(subtitle(record))
                                    .font(.caption).foregroundStyle(TVTheme.textSoft)
                            }
                            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
    }

    private func subtitle(_ record: SavedQuizRecord) -> String {
        var parts = ["\(record.questionCount) questions"]
        if record.playCount > 0 { parts.append("played \(record.playCount)x") }
        if record.isShared { parts.append("shared") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func generate(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !isWorking else { return }
        error = nil
        isWorking = true
        Task {
            var shaped: [Question] = []
            for src in [JSONQuestionSource.picture, .thisOrThat, .closestCall] {
                shaped.append(contentsOf: src.searchMatch(topic: q, limit: 1))
            }
            var mcq = CorpusDatabase.shared.search(topic: q, limit: max(4, 8 - shaped.count))
            if mcq.count < 3 {
                let gen = await QuestionProvider.shared.liveQuestions(topic: q, category: .named("mixed"), count: 8)
                if gen.count >= 3 { mcq = gen; shaped = [] }
            }
            let result = Array((mcq + shaped).shuffled().prefix(8))
            isWorking = false
            guard result.count >= 3 else {
                error = "Couldn't build a good quiz for \u{201C}\(q)\u{201D}. Try a broader subject."
                return
            }
            let quiz = SavedQuiz.from(
                questions: result, topic: q, mode: playMode.rawValue,
                creatorID: PlayerIdentityStore.shared.profileId ?? "local",
                creatorName: PlayerIdentityStore.shared.profile?.name ?? "")
            QuizStore.save(quiz, in: modelContext)
            Task { await QuizSync.push(in: modelContext) }   // available on the phone too
            onPlay(q, result, playMode)
        }
    }

    private func play(_ record: SavedQuizRecord) {
        guard let quiz = record.quiz else { return }
        let resolution = quiz.resolveAgainstBundle()
        guard resolution.isPlayable else {
            detail = nil
            error = "This quiz needs questions your Apple TV doesn't have yet. Try making one on the same subject."
            return
        }
        QuizStore.markPlayed(id: quiz.id, in: modelContext)
        detail = nil
        onPlay(quiz.title, resolution.questions, quiz.gameMode)
    }
}

// MARK: - Quiz detail (play / share / delete)

/// Selecting a quiz opens this rather than crowding verbs onto every shelf card —
/// at ten feet a row with three controls is three chances to focus the wrong one.
private struct TVQuizDetail: View {
    let record: SavedQuizRecord
    let onPlay: () -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var shareURL: URL?
    @State private var isSharing = false
    @State private var shareError: String?
    @State private var confirmingDelete = false
    @FocusState private var playFocused: Bool

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()
            HStack(alignment: .top, spacing: 70) {
                VStack(alignment: .leading, spacing: 26) {
                    Text(record.title).font(.largeTitle).foregroundStyle(TVTheme.text)
                    Text("\(record.questionCount) questions")
                        .font(.body).foregroundStyle(TVTheme.textSoft)
                    Spacer().frame(height: 10)
                    // `.card` sizes to its label, so a bare Button in a narrow column
                    // collapses to a clipped pill — at ten feet the verbs were
                    // unreadable and the focus ring had nothing to sit on. Each label
                    // gets a real target: full column width and a ten-foot height.
                    Button(action: onPlay) { detailLabel("Play") }
                        .buttonStyle(.card).focused($playFocused)
                    Button(action: share) { detailLabel(isSharing ? "Sharing…" : "Share") }
                        .buttonStyle(.card).disabled(isSharing)
                    Button { confirmingDelete = true } label: { detailLabel("Delete") }
                        .buttonStyle(.card)
                    Button { dismiss() } label: { detailLabel("Back") }
                        .buttonStyle(.card)
                    if let shareError {
                        Text(shareError).font(.caption).foregroundStyle(TVTheme.textSoft)
                            .frame(maxWidth: 480, alignment: .leading)
                    }
                }
                .frame(width: 460, alignment: .leading)

                if let shareURL { qrPanel(shareURL) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 70)
        }
        .task {
            playFocused = true
            if DebugHooks.tvShareNewest { share() }
        }
        .alert("Delete \u{201C}\(record.title)\u{201D}?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                let id = record.quizID
                // Deletes from the account bucket too, or the next sync would pull it
                // straight back and it would read as a haunting.
                Task { await QuizSync.delete(id: id, in: modelContext); onDeleted() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from your account, on every device.")
        }
    }

    /// One shape for every verb in the column, so focus moves between equals.
    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 76)
    }

    /// The QR IS the share on tvOS. Big, high-contrast, on white — a code rendered on
    /// a dark surface is unreadable to most phone cameras, so this panel keeps its own
    /// white background regardless of the app's dark-first theme.
    private func qrPanel(_ url: URL) -> some View {
        VStack(spacing: 22) {
            if let cg = QRCode.image(for: url.absoluteString, scale: 20) {
                Image(decorative: cg, scale: 1)
                    .interpolation(.none)          // keep the modules crisp when scaled
                    .resizable()
                    .frame(width: 420, height: 420)
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 24).fill(.white))
            }
            Text("Scan to play on your phone")
                .font(.headline).foregroundStyle(TVTheme.text)
            Text(url.absoluteString)
                .font(.caption).foregroundStyle(TVTheme.textSoft)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 480)
        }
    }

    private func share() {
        guard let quiz = record.quiz else { return }
        isSharing = true
        shareError = nil
        Task {
            do {
                shareURL = try await QuizSharing.publish(quiz, in: modelContext)
            } catch {
                // Surface the real cause on screen: a TV has no console anyone will
                // read, so an invisible failure is an undiagnosable one (CLAUDE.md
                // debugging philosophy — render the numbers you need).
                shareError = "Couldn't share that just now. Check the network and try again."
                print("[Tidbits] tvOS share failed: \(error)")
            }
            isSharing = false
        }
    }
}
#endif
