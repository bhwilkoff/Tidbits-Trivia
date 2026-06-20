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
    var imageURL: URL? = nil   // Picture ID (Q7): the Commons image to identify
    var closest: ClosestSpec? = nil   // Closest Call (M5): numeric estimation
    var ordering: [String]? = nil     // Ordering (Q4): the items in CORRECT order
    var matching: MatchSpec? = nil    // Matching (Q5): keys ↔ correct values
    var accepted: [String]? = nil     // Type-the-answer (Q6): accepted free-text answers

    var correctAnswer: String {
        if options.indices.contains(correctIndex) { return options[correctIndex] }
        return closest?.formattedAnswer ?? ""
    }

    /// Stable share text — never leaks the answer when used pre-reveal.
    func shareTeaser() -> String {
        "🧠 Tidbits Trivia\n\(prompt)\n\nThink you know it? Play at tidbits.trivia"
    }
}

/// Closest Call (M5) numeric question: estimate a value on a linear slider over
/// [min, max]; scored by proximity to `answer` within `tolerance` (adds-only).
nonisolated struct ClosestSpec: Hashable, Codable, Sendable {
    let answer: Double
    let min: Double
    let max: Double
    let step: Double
    let tolerance: Double
    let unit: String

    /// Points (0…maxPoints) for a guess — full at exact, 0 at/over tolerance.
    static let maxPoints = 50
    func points(for guess: Double) -> Int {
        let error = abs(guess - answer)
        guard error < tolerance else { return 0 }
        return Int((Double(Self.maxPoints) * (1 - error / tolerance)).rounded())
    }
    /// "Close enough" to count as correct for streaks / the emoji grid.
    func isClose(_ guess: Double) -> Bool { abs(guess - answer) <= tolerance / 2 }
    var formattedAnswer: String {
        let n = answer == answer.rounded() ? String(Int(answer)) : String(answer)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}

/// Matching (Q5): link each key to its value. `values[i]` is the correct match
/// for `keys[i]`; the client shuffles the values for display.
nonisolated struct MatchSpec: Hashable, Codable, Sendable {
    let keys: [String]
    let values: [String]
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
