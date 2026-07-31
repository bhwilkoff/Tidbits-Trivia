import Foundation
import SwiftData
@testable import TidbitsTriviaTests

/// An in-memory SwiftData stack for the store-backed tests.
///
/// Same schema as the app so a model that fails to migrate here would fail on a
/// device too — the point is to exercise the REAL container, not a stand-in.
@MainActor
enum TestStore {
    static let schema = Schema([
        GameRecord.self, MissedFact.self, DailyStreak.self, CalibrationTally.self, SeenStory.self,
        MarathonRun.self, MarathonScore.self,
        ExpeditionProgress.self, ExpeditionCertificate.self,
        LinkWallResult.self, SavedQuizRecord.self,
    ])

    /// A fresh, isolated context per test — no cross-test bleed.
    static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// A question shaped like a real corpus row (4 options, a real explanation),
    /// so MissedFact round-trips exercise the actual rebuild path.
    static func question(_ id: String,
                         category: String = "science",
                         difficulty: Int = 3) -> Question {
        Question(
            id: id,
            prompt: "Prompt for \(id)?",
            options: ["\(id)-a", "\(id)-b", "\(id)-c", "\(id)-d"],
            correctIndex: 1,
            categoryID: category,
            difficulty: difficulty,
            explanation: "Because of \(id).",
            sourceTitle: "Source \(id)",
            sourceURL: URL(string: "https://en.wikipedia.org/wiki/\(id)"),
            templateID: "tpl:\(id)")
    }

    @discardableResult
    static func record(_ context: ModelContext,
                       mode: GameMode = .classic,
                       category: String = "science",
                       correct: Int, total: Int,
                       daysAgo: Int = 0,
                       score: Int = 500) -> GameRecord {
        let r = GameRecord(mode: mode, categoryID: category, score: score,
                           correct: correct, total: total, maxStreak: correct,
                           date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now)
        context.insert(r)
        return r
    }
}
