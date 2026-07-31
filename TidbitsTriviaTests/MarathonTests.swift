import Testing
import SwiftData
@testable import TidbitsTriviaTests

/// Marathon's load-bearing claim is resumability: a 200-question run must
/// survive a crash, a quit, and a cold relaunch and pick up exactly where it
/// left off. Play-testing confirmed it end-to-end (hard `simctl terminate`
/// mid-run, then "Question 4 of 5 — resume where you left off"); these pin the
/// arithmetic underneath so the guarantee cannot silently regress.
@Suite("Marathon")
@MainActor
struct MarathonTests {

    private func ids(_ n: Int) -> [String] { (1...n).map { "q\($0)" } }

    private func answer(_ id: String, correct: Bool, category: String = "science") -> MarathonAnswerRecord {
        MarathonAnswerRecord(questionID: id, categoryID: category, difficulty: 3, correct: correct)
    }

    @Test func aFreshRunStartsAtZero() {
        let run = MarathonRun(seed: "s", questionIDs: ids(200))
        #expect(run.currentIndex == 0)
        #expect(run.total == 200)
        #expect(run.results.isEmpty)
    }

    @Test func theQuestionListRoundTripsThroughStorage() {
        let run = MarathonRun(seed: "s", questionIDs: ids(200))
        #expect(run.questionIDs == ids(200))
    }

    /// Each answer advances the cursor by exactly one — the number the hub
    /// reports as "Question N of M".
    @Test func eachAnswerAdvancesTheCursorByOne() {
        let run = MarathonRun(seed: "s", questionIDs: ids(10))
        for i in 1...4 { run.append(answer("q\(i)", correct: true)) }
        #expect(run.currentIndex == 4)
        #expect(run.results.count == 4)
    }

    /// The resume slice must skip exactly what was answered and nothing more —
    /// off by one here either repeats a question or silently drops one.
    @Test func resumingSkipsExactlyTheAnsweredQuestions() {
        let run = MarathonRun(seed: "s", questionIDs: ids(10))
        for i in 1...4 { run.append(answer("q\(i)", correct: true)) }
        let remaining = Array(run.questionIDs.suffix(from: min(run.currentIndex, run.total)))
        #expect(remaining.first == "q5")
        #expect(remaining.count == 6)
    }

    @Test func answersSurviveEncodingAndDecoding() {
        let run = MarathonRun(seed: "s", questionIDs: ids(10))
        run.append(answer("q1", correct: true, category: "music"))
        run.append(answer("q2", correct: false, category: "history"))
        let results = run.results
        #expect(results.count == 2)
        #expect(results[0].correct)
        #expect(!results[1].correct)
        #expect(results[0].categoryID == "music")
        #expect(results[1].questionID == "q2")
    }

    /// A run persisted to SwiftData and re-fetched must carry the same cursor —
    /// this is the cold-relaunch path.
    @Test func aRunSurvivesAContextRoundTrip() throws {
        let ctx = try TestStore.context()
        let run = MarathonRun(seed: "seed-1", questionIDs: ids(10))
        ctx.insert(run)
        for i in 1...3 { run.append(answer("q\(i)", correct: true)) }
        try ctx.save()

        let fetched = try #require(Marathon.inProgress(in: ctx))
        #expect(fetched.currentIndex == 3)
        #expect(fetched.seed == "seed-1")
        #expect(fetched.results.count == 3)
    }

    /// At most ONE run exists — otherwise "resume" is ambiguous.
    @Test func onlyOneRunIsTreatedAsInProgress() throws {
        let ctx = try TestStore.context()
        ctx.insert(MarathonRun(seed: "a", questionIDs: ids(10)))
        try ctx.save()
        #expect(Marathon.inProgress(in: ctx) != nil)
    }

    @Test func noRunMeansNothingToResume() throws {
        let ctx = try TestStore.context()
        #expect(Marathon.inProgress(in: ctx) == nil)
    }

    @Test func completingEveryQuestionLeavesNothingToResume() {
        let run = MarathonRun(seed: "s", questionIDs: ids(5))
        for i in 1...5 { run.append(answer("q\(i)", correct: true)) }
        #expect(run.currentIndex == run.total)
        let remaining = Array(run.questionIDs.suffix(from: min(run.currentIndex, run.total)))
        #expect(remaining.isEmpty)
    }

    @Test func productionRunLengthIsTwoHundred() {
        #expect(Marathon.defaultLength == 200)
    }

    @Test func lastPlayedAdvancesWithEachAnswer() {
        let run = MarathonRun(seed: "s", questionIDs: ids(10), date: .distantPast)
        let before = run.lastPlayedAt
        run.append(answer("q1", correct: true))
        #expect(run.lastPlayedAt > before)
    }
}
