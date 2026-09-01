import SwiftUI

/// The extension's palette.
///
/// Deliberately a local copy of the four tokens this feature uses rather than an
/// import of Core's `Design.swift`: linking Core into an extension drags SwiftData,
/// StoreKit and the networking stack in with it, and an app extension is the one place
/// where that weight is genuinely dangerous. Four hex values are the cheaper honesty.
/// If the brand moves, `docs/DESIGN-TOKENS` is the source and these follow.
enum MsgPalette {
    static let bg = Color(red: 0.98, green: 0.96, blue: 0.92)      // cream paper
    static let ink = Color(red: 0.14, green: 0.12, blue: 0.10)
    static let inkSoft = Color(red: 0.42, green: 0.39, blue: 0.36)
    static let coral = Color(red: 1.0, green: 0.36, blue: 0.21)    // #FF5C35
    static let mint = Color(red: 0.12, green: 0.62, blue: 0.42)
}

/// Constrain content to a readable measure and centre it.
///
/// The extension's expanded presentation is as wide as the sheet, which on a 13"
/// iPad is over 2,000 points. Text set edge-to-edge at that width is unreadable —
/// a line runs to 200 characters against the ~65 a reader can track — and the
/// screen reads as broken rather than roomy. Phones are unaffected: they are
/// narrower than the cap, so the frame is a no-op there.
private struct ReadableColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)     // centre the capped column in the sheet
    }
}

private extension View {
    func readableColumn() -> some View { modifier(ReadableColumn()) }
}

/// The drawer. A few hundred points tall — one line and one button, nothing more.
struct CompactPromptView: View {
    let headline: String
    let subhead: String
    let action: () -> Void

    var body: some View {
        ZStack {
            MsgPalette.bg.ignoresSafeArea()
            VStack(spacing: 6) {
                Text(headline)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(MsgPalette.ink)
                Text(subhead)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MsgPalette.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
        }
    }
}

/// Start a round: pick a category, say who you are, send it to the thread.
struct StartRoundView: View {
    let compact: Bool
    let onExpand: () -> Void
    let onStart: (String?, String) -> Void

    @State private var name = UserDefaults.standard.string(forKey: "tidbits.msg.name") ?? ""
    @State private var category: String? = nil

    private let categories: [(String, String)] = [
        ("Surprise me", ""), ("Screen", "screen"), ("Geography", "geography"),
        ("Music", "music"), ("History", "history"), ("Sports", "sports"),
        ("Arts", "arts"), ("Science", "science"), ("Business", "business"),
    ]

    var body: some View {
        if compact {
            CompactPromptView(headline: "Send a Tidbits round",
                              subhead: "5 questions · everyone plays",
                              action: onExpand)
        } else {
            ZStack {
                MsgPalette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SEND A ROUND")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(MsgPalette.ink)
                        Text("Five questions. Everyone in the chat answers, and you all see the story behind each one.")
                            .font(.system(size: 14))
                            .foregroundStyle(MsgPalette.inkSoft)

                        TextField("Your name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold))
                            // Explicit, never inherited. This palette is fixed cream
                            // and ink; a control that takes its colour from the
                            // environment is one appearance change away from being
                            // invisible, which is exactly what happened here.
                            .foregroundStyle(MsgPalette.ink)
                            .tint(MsgPalette.coral)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(MsgPalette.ink.opacity(0.15), lineWidth: 2))

                        Text("CATEGORY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MsgPalette.inkSoft)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                                  spacing: 8) {
                            ForEach(categories, id: \.1) { label, id in
                                let selected = (category ?? "") == id
                                Button {
                                    category = id.isEmpty ? nil : id
                                } label: {
                                    Text(label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(selected ? .white : MsgPalette.ink)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Capsule().fill(selected ? MsgPalette.coral : .white))
                                        .overlay(Capsule().strokeBorder(
                                            MsgPalette.ink.opacity(selected ? 0 : 0.15), lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            let final = trimmed.isEmpty ? "Player" : trimmed
                            UserDefaults.standard.set(final, forKey: "tidbits.msg.name")
                            onStart(category, final)
                        } label: {
                            Text("Send to the chat")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(MsgPalette.coral))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .readableColumn()
                }
            }
        }
    }
}

/// Playing a round: the current question, your options, and the reveal.
struct RoundView: View {
    let state: RoundState
    let playerID: String
    let onSend: (RoundState, String) -> Void
    let onPlayAgain: () -> Void

    @State private var name = UserDefaults.standard.string(forKey: "tidbits.msg.name") ?? ""
    @State private var joined = false

    private var question: PackQuestion? {
        guard state.index < state.questionIDs.count else { return nil }
        return QuestionPack.shared.question(id: state.questionIDs[state.index])
    }

    private var isPlayer: Bool { state.players.contains { $0.id == playerID } }
    private var answered: Bool { state.hasAnswered(playerID: playerID) }

    var body: some View {
        ZStack {
            MsgPalette.bg.ignoresSafeArea()
            ScrollView {
                // A finished round is its OWN screen, not the last question with a
                // full scoreboard under it. Before this, reaching the end left you
                // looking at question 5 — no result, no winner, and no way to see
                // the four explanations you had already scrolled past.
                if state.isFinished {
                    FinishedRoundView(state: state, playerID: playerID,
                                      onPlayAgain: onPlayAgain)
                } else if let q = question {
                    VStack(alignment: .leading, spacing: 14) {
                        header(q)
                        if !isPlayer && !joined {
                            joinCard
                        } else if answered {
                            reveal(q)
                        } else {
                            options(q)
                        }
                        scoreboard
                    }
                    .padding(20)
                    .readableColumn()
                } else {
                    Text("This round needs a newer version of Tidbits.")
                        .font(.system(size: 15))
                        .foregroundStyle(MsgPalette.inkSoft)
                        .padding(28)
                }
            }
        }
    }

    private func header(_ q: PackQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUESTION \(state.index + 1) OF \(state.questionIDs.count) · \(q.categoryID.uppercased())")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MsgPalette.inkSoft)
            Text(q.prompt)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(MsgPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Someone who was not in the round when it was sent. They can join mid-round —
    /// a group chat is not a lobby and people wander in.
    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Join this round")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MsgPalette.ink)
            TextField("Your name", text: $name)
                .textFieldStyle(.plain)
                .foregroundStyle(MsgPalette.ink)
                .tint(MsgPalette.coral)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(MsgPalette.ink.opacity(0.15), lineWidth: 2))
            if !state.hasRoomForAnotherPlayer {
                // The 5,000-character wire budget is finite and a big group can reach
                // it. Saying so is better than a send that silently fails.
                Text("This round is full — start a new one to play.")
                    .font(.system(size: 13)).foregroundStyle(MsgPalette.coral)
            } else {
                Button(action: joinTapped) {
                    // Broken out of a single long modifier chain: the type-checker
                    // timed out on it ("unable to type-check this expression in
                    // reasonable time"), which is a compile failure, not a warning.
                    Text("Join")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(MsgPalette.coral))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func joinTapped() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let final = trimmed.isEmpty ? "Player" : trimmed
        UserDefaults.standard.set(final, forKey: "tidbits.msg.name")
        joined = true
    }

    private func options(_ q: PackQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                Button {
                    var next = state
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    next.upsert(playerID: playerID, name: trimmed.isEmpty ? "Player" : trimmed)
                    next.answer(playerID: playerID, choice: i)
                    // Advance only when EVERYONE has answered; otherwise the next
                    // person to open the bubble would be shown a question they never
                    // got to answer.
                    var caption = "Tidbits — tap to play"
                    if next.currentQuestionComplete && next.index < next.questionIDs.count - 1 {
                        next.index += 1
                    } else if next.isFinished {
                        caption = "Tidbits — round complete"
                    }
                    onSend(next, caption)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(MsgPalette.ink))
                        Text(opt)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MsgPalette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(MsgPalette.ink.opacity(0.15), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The learning payload. This is the reason the feature exists — the explanation,
    /// not the score, is what makes a trivia habit worth having.
    private func reveal(_ q: PackQuestion) -> some View {
        let mine = state.players.first { $0.id == playerID }?.answers[state.index]
        let right = mine == q.correctIndex
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(right ? "Correct" : "Not quite")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(right ? MsgPalette.mint : MsgPalette.coral)
                Text("· \(q.options[q.correctIndex])")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MsgPalette.ink)
            }
            Text(q.explanation)
                .font(.system(size: 15))
                .foregroundStyle(MsgPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.currentQuestionComplete
                 ? "Everyone has answered."
                 : "Waiting for the others to answer.")
                .font(.system(size: 13))
                .foregroundStyle(MsgPalette.inkSoft)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
    }

    private var scoreboard: some View {
        let key: (String) -> Int? = { QuestionPack.shared.correctIndex(id: $0) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("SCORES").font(.system(size: 11, weight: .bold))
                .foregroundStyle(MsgPalette.inkSoft)
            ForEach(state.players, id: \.id) { p in
                HStack {
                    Text(p.name).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MsgPalette.ink)
                    Spacer()
                    Text("\(state.score(p, correctIndexFor: key))")
                        .font(.system(size: 15, weight: .black).monospacedDigit())
                        .foregroundStyle(MsgPalette.ink)
                }
            }
        }
        .padding(.top, 4)
    }
}

/// The end of a round: who won, the final scores, and every question's answer.
///
/// The recap is the reason this screen is long. A round is five questions delivered
/// one message at a time, often over hours — by the time it ends, the explanations
/// from questions one through four have scrolled out of the thread and out of memory.
/// Showing only the last one (which is what this used to do) throws away four fifths
/// of the point: the explanation, not the score, is what makes a trivia habit worth
/// having.
struct FinishedRoundView: View {
    let state: RoundState
    let playerID: String
    let onPlayAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrated = false

    private var key: (String) -> Int? { { QuestionPack.shared.correctIndex(id: $0) } }

    private var entries: [(name: String, score: Int)] {
        state.players.map { (name: $0.name, score: state.score($0, correctIndexFor: key)) }
    }

    /// The SHARED rule, not a local sort. `StandingsOutcome` is what distinguishes a
    /// win from a tie, and a tie among some players from everyone finishing level —
    /// including the 0–0 board, which ties rather than crowning whoever the sort
    /// happened to put first.
    private var headline: String {
        StandingsOutcome.headline(entries, empty: "That's a round!")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            banner
            scores
            answers
            playAgain
        }
        .padding(20)
        .readableColumn()
    }

    // MARK: - Celebration

    private var banner: some View {
        VStack(spacing: 6) {
            Text("ROUND COMPLETE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(1.2)
            Text(headline)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let mine = myLine {
                Text(mine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(MsgPalette.coral))
        // The celebration is typographic and chromatic, never an emoji: R-ICON-1
        // rules out emoji chrome, and a burst of confetti in a message thread is
        // someone else's app.
        .scaleEffect(celebrated || reduceMotion ? 1 : 0.94)
        .opacity(celebrated || reduceMotion ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: celebrated)
        .onAppear { celebrated = true }
    }

    /// "You got 4 of 5" — the local player's own result, which is the thing they came
    /// back to the thread to find. Absent for a spectator who never joined.
    private var myLine: String? {
        guard let me = state.players.first(where: { $0.id == playerID }) else { return nil }
        return "You got \(state.score(me, correctIndexFor: key)) of \(state.questionIDs.count)"
    }

    // MARK: - Final scores

    private var scores: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FINAL SCORES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MsgPalette.inkSoft)
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.player.id) { i, row in
                    scoreRow(row)
                    if i < ranked.count - 1 {
                        Divider().overlay(MsgPalette.ink.opacity(0.08))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        }
    }

    private struct Row { let player: RoundState.Player; let score: Int; let top: Bool }

    /// Sorted high to low, with EVERY leader marked rather than just the first row.
    private var ranked: [Row] {
        state.players
            .map { p in
                let s = state.score(p, correctIndexFor: key)
                return Row(player: p, score: s, top: StandingsOutcome.isTop(s, in: entries))
            }
            .sorted { $0.score > $1.score }
    }

    private func scoreRow(_ row: Row) -> some View {
        HStack(spacing: 10) {
            // A leader is marked by weight and colour, not a trophy glyph.
            Text(row.top ? "WON" : "")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(MsgPalette.coral)
                .frame(width: 30, alignment: .leading)
            Text(row.player.name)
                .font(.system(size: 16, weight: row.top ? .black : .semibold))
                .foregroundStyle(MsgPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(row.score)")
                .font(.system(size: 17, weight: .black).monospacedDigit())
                .foregroundStyle(row.top ? MsgPalette.coral : MsgPalette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - The answers

    private var answers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE ANSWERS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MsgPalette.inkSoft)
            ForEach(Array(state.questionIDs.enumerated()), id: \.offset) { i, qid in
                if let q = QuestionPack.shared.question(id: qid) {
                    answerCard(index: i, q: q)
                }
            }
        }
    }

    private func answerCard(index: Int, q: PackQuestion) -> some View {
        let mine = state.players.first { $0.id == playerID }?.answers[safe: index] ?? nil
        let right = mine == q.correctIndex
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MsgPalette.inkSoft)
                Text(q.prompt)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MsgPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                // Only claim right/wrong for someone who actually answered. A
                // spectator, or a player who joined after this question, gets the
                // answer without a verdict they never earned.
                if mine != nil {
                    Text(right ? "Correct" : "Missed")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(right ? MsgPalette.mint : MsgPalette.coral)
                }
                Text(q.options[q.correctIndex])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MsgPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(q.explanation)
                .font(.system(size: 14))
                .foregroundStyle(MsgPalette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
    }

    // MARK: - Next

    private var playAgain: some View {
        Button(action: onPlayAgain) {
            Text("Send another round")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(MsgPalette.ink))
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    /// A late joiner's `answers` is sized to the round, but a malformed wire payload
    /// need not be — decoding takes whatever characters arrived. Indexing it blind
    /// would crash inside Messages, which is the worst place to trap.
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
