import Foundation

/// The night, read back (A3.11 / punch list 15, 2026-09-09): which questions
/// the room found hard and easy, how each round went, how many tables were
/// answering — computed from the answer sheet the host already keeps, so it
/// costs nothing, needs no backend, and is exactly as private as the sheet.
/// A poll is not a question anyone got wrong, so polls are left out.
nonisolated struct LiveNightReport: Equatable, Sendable {
    struct QuestionStat: Equatable, Sendable, Identifiable {
        var qid: String
        var round: Int
        var number: Int
        var prompt: String
        var answer: String
        var answered: Int
        var credited: Int
        var accuracy: Double { answered == 0 ? 0 : Double(credited) / Double(answered) }
        var id: String { qid }
    }
    struct RoundStat: Equatable, Sendable, Identifiable {
        var round: Int
        var questions: Int
        var answered: Int
        var credited: Int
        var accuracy: Double { answered == 0 ? 0 : Double(credited) / Double(answered) }
        var id: Int { round }
    }

    var questions: [QuestionStat]
    var rounds: [RoundStat]
    var teams: Int

    var isEmpty: Bool { questions.isEmpty }
    /// The question the fewest answering tables got (ties: the one more tables missed).
    var hardest: QuestionStat? {
        questions.filter { $0.answered > 0 }.min { a, b in
            a.accuracy != b.accuracy ? a.accuracy < b.accuracy : (a.answered - a.credited) > (b.answered - b.credited)
        }
    }
    var easiest: QuestionStat? {
        questions.filter { $0.answered > 0 }.max { a, b in
            a.accuracy != b.accuracy ? a.accuracy < b.accuracy : a.credited < b.credited
        }
    }
    /// Answers per question, as a share of the tables in the room (0…1).
    var participation: Double {
        guard teams > 0, !questions.isEmpty else { return 0 }
        let avg = Double(questions.map(\.answered).reduce(0, +)) / Double(questions.count)
        return min(1, avg / Double(teams))
    }
    var overallAccuracy: Double {
        let a = questions.map(\.answered).reduce(0, +), c = questions.map(\.credited).reduce(0, +)
        return a == 0 ? 0 : Double(c) / Double(a)
    }

    static func from(_ log: [LiveAnswerRecord], teams: Int) -> LiveNightReport {
        let qs = log.filter { $0.answer != "(poll)" }.map { r in
            QuestionStat(qid: r.qid, round: r.round, number: r.number, prompt: r.prompt, answer: r.answer,
                         answered: r.lines.count, credited: r.lines.filter { $0.points > 0 }.count)
        }
        let byRound = Dictionary(grouping: qs, by: \.round)
        let rounds = byRound.keys.sorted().map { rn -> RoundStat in
            let list = byRound[rn] ?? []
            return RoundStat(round: rn, questions: list.count,
                             answered: list.map(\.answered).reduce(0, +), credited: list.map(\.credited).reduce(0, +))
        }
        return LiveNightReport(questions: qs, rounds: rounds, teams: teams)
    }

    static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
