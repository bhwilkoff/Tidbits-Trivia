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
                if let q = question {
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
