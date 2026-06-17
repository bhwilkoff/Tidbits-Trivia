import SwiftUI

/// A single trivia question. Produced by the template engine — whether
/// pre-baked into the bundled corpus or generated live from a Wikipedia
/// article. The shape is identical for both paths so the game loop never
/// cares where a question came from.
nonisolated struct Question: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let prompt: String
    let options: [String]      // exactly 4; index 0..3
    let correctIndex: Int
    let categoryID: String
    let difficulty: Int        // 1 (easy) … 5 (hard) — see DifficultyModel
    let explanation: String    // the "learn the fact" payload, shown after answering
    let sourceTitle: String    // Wikipedia article title
    let sourceURL: URL?
    let templateID: String

    var correctAnswer: String { options[correctIndex] }

    /// Stable share text — never leaks the answer when used pre-reveal.
    func shareTeaser() -> String {
        "🧠 Tidbits Trivia\n\(prompt)\n\nThink you know it? Play at tidbits.trivia"
    }
}

/// Whether the player got it right, and how fast — drives speed scoring,
/// streaks, and the spaced re-ask of missed questions.
nonisolated struct AnsweredQuestion: Identifiable, Hashable, Sendable {
    let question: Question
    let chosenIndex: Int?      // nil = timed out
    let secondsTaken: Double
    var id: String { question.id }
    var isCorrect: Bool { chosenIndex == question.correctIndex }
}
