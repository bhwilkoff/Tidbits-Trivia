import Foundation

/// What a joiner keeps of a live night so the wrap can teach (LIVE-ROOM-CONTRACT
/// "answer + difficulty", 2026-09-09): one entry per revealed question, with
/// the score before it was asked and after it was scored. "Nailed" is decided
/// by the SCORE, not by re-deriving the answer — the host is the scorer, and
/// a typed answer the host accepted by hand still counts.
nonisolated struct LiveRecapEntry: Identifiable, Equatable, Sendable {
    var qid: String
    var prompt: String
    var answer: String?
    var difficulty: Int?
    var story: String?
    var sourceTitle: String?
    var sourceURL: String?
    var before: Int
    var after: Int?
    var id: String { qid }
    /// The score went UP while this question was on: the host credited it.
    var nailed: Bool { (after ?? before) > before }
    /// Hard (difficulty ≥ 4) and nailed — the win worth talking about.
    var tough: Bool { nailed && (difficulty ?? 0) >= 4 }
}

/// The bookkeeping, pure so it is testable: begin a question with the score at
/// that moment, record the reveal, finish the last one with the score at the
/// wrap. Feed it every pub in order and the score when it changes.
nonisolated struct LiveRecapBook: Equatable, Sendable {
    private(set) var entries: [LiveRecapEntry] = []
    private var openQid: String?
    private var scoreAtQuestion = 0

    /// A pub arrived. `score` is the joiner's score right now.
    mutating func observe(_ p: LiveRoom.Pub, score: Int) {
        if p.qid != openQid {                       // a new question (or the end): close the last one
            close(score: score)
            openQid = p.qid
            scoreAtQuestion = score
        }
        guard p.phase == "reveal", !entries.contains(where: { $0.qid == p.qid }) else { return }   // LiveRoom.Phase is MainActor-isolated; the wire string is the contract
        entries.append(LiveRecapEntry(qid: p.qid, prompt: p.prompt, answer: p.answer, difficulty: p.difficulty,
                                      story: p.story, sourceTitle: p.source?.title, sourceURL: p.source?.url,
                                      before: scoreAtQuestion, after: nil))
    }
    /// The night ended (or the joiner is reading the wrap): settle the open question.
    mutating func finish(score: Int) {
        close(score: score)
        // The host's score write can land AFTER the ended frame; a rise then can
        // only belong to the last question.
        if let i = entries.indices.last { entries[i].after = max(entries[i].after ?? score, score) }
    }

    private mutating func close(score: Int) {
        guard let q = openQid, let i = entries.firstIndex(where: { $0.qid == q && $0.after == nil }) else { return }
        entries[i].after = score
    }

    var tough: [LiveRecapEntry] { entries.filter(\.tough) }
    /// Everything the player did not get credit for, answer known — the learning payoff.
    var toRemember: [LiveRecapEntry] { entries.filter { !$0.nailed && !($0.answer ?? "").isEmpty } }

    /// The conversation opener (the same line the solo results screen shares).
    static func howDidYouKnowText(_ e: LiveRecapEntry) -> String {
        "I knew \"\(e.prompt)\" at trivia night — it's \(e.answer ?? ""). How did YOU know that? 🧠"
    }
}
