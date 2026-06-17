import Foundation
import SwiftData

/// One completed game. The personal-record spine — "compete against your
/// past self" reads from these. Kept deliberately flat for fast queries.
@Model
final class GameRecord {
    var id: UUID
    var modeRaw: String
    var categoryID: String
    var score: Int
    var correct: Int
    var total: Int
    var maxStreak: Int
    var date: Date

    init(mode: GameMode, categoryID: String, score: Int, correct: Int, total: Int, maxStreak: Int, date: Date = .now) {
        self.id = UUID()
        self.modeRaw = mode.rawValue
        self.categoryID = categoryID
        self.score = score
        self.correct = correct
        self.total = total
        self.maxStreak = maxStreak
        self.date = date
    }

    var mode: GameMode { GameMode(rawValue: modeRaw) ?? .classic }
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

/// A question the player got wrong, kept so the engine can re-ask it
/// later (the testing effect / spaced retrieval — turns a miss into
/// learning, the core of the learning-orientation mandate).
@Model
final class MissedFact {
    var questionID: String
    var prompt: String
    var correctAnswer: String
    var explanation: String
    var categoryID: String
    var missCount: Int
    var lastSeen: Date
    var resolved: Bool   // answered correctly on a later re-ask

    init(question: Question, date: Date = .now) {
        self.questionID = question.id
        self.prompt = question.prompt
        self.correctAnswer = question.correctAnswer
        self.explanation = question.explanation
        self.categoryID = question.categoryID
        self.missCount = 1
        self.lastSeen = date
        self.resolved = false
    }
}

/// Tracks the Daily streak independent of any single game record.
@Model
final class DailyStreak {
    var current: Int
    var best: Int
    var lastPlayedDay: String   // yyyy-MM-dd in the user's calendar

    init(current: Int = 0, best: Int = 0, lastPlayedDay: String = "") {
        self.current = current
        self.best = best
        self.lastPlayedDay = lastPlayedDay
    }
}
