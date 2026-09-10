import Testing
import Foundation

/// A2.13 — a night the host's app died in the middle of survives a relaunch with
/// everything the host held, and is never offered once it ended properly or went stale.
@Suite("Live night resume")
@MainActor
struct LiveNightResumeTests {
    private func store(suite: String = UUID().uuidString) -> LiveNightResume {
        LiveNightResume(defaults: UserDefaults(suiteName: "tidbits.tests.resume.\(suite)")!, key: "tidbits.liveResume")
    }

    private func snapshot(index: Int = 3, at: Date = .now) -> LiveNightSnapshot {
        var event = LiveEvent(name: "Tuesday Quiz")
        event.rounds = [LiveRound(title: "R1", format: .classic, categoryID: "mixed", questions: (0..<12).map { i in
            Question(id: "q\(i)", prompt: "Q\(i)?", options: ["A", "B", "C", "D"], correctIndex: 0, categoryID: "mixed",
                     difficulty: 3, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "t")
        })]
        return LiveNightSnapshot(code: "AB12", event: event, index: index, revealed: true, scoredIndices: [0, 1, 2],
                                 paperTeams: [.init(name: "The Bar", score: 4)], blockedTeams: ["rude-uid"],
                                 pointsPerCorrect: 2, wrongAnswerPenalty: 1, answerLog: [], savedAt: at)
    }

    @Test func aSavedNightSurvivesARelaunchWithEverythingTheHostHeld() {
        let suite = UUID().uuidString
        store(suite: suite).save(snapshot())
        let again = store(suite: suite).pending()
        #expect(again?.code == "AB12")
        #expect(again?.index == 3)
        #expect(again?.revealed == true)
        #expect(again?.scoredIndices == [0, 1, 2])
        #expect(again?.paperTeams == [.init(name: "The Bar", score: 4)])
        #expect(again?.blockedTeams == ["rude-uid"])
        #expect(again?.pointsPerCorrect == 2)
        #expect(again?.wrongAnswerPenalty == 1)
        #expect(again?.event.name == "Tuesday Quiz")
    }

    @Test func theCardSaysWhereTheHostWas() {
        #expect(snapshot().positionLine == "question 4 of 12")
        // Never "question 13 of 12" — the last question is where a finished night sits.
        #expect(snapshot(index: 40).positionLine == "question 12 of 12")
        var empty = snapshot(); empty.event.rounds = []
        #expect(empty.positionLine == "not started")
    }

    @Test func lastWeeksNightIsNotOffered() {
        let s = store()
        s.save(snapshot(at: .now.addingTimeInterval(-7 * 3600)))
        #expect(s.pending() == nil)
        s.save(snapshot(at: .now.addingTimeInterval(-20 * 60)))
        #expect(s.pending() != nil)
    }

    @Test func aNightThatEndedProperlyNeverOffersToResume() {
        let suite = UUID().uuidString
        let s = store(suite: suite)
        s.save(snapshot())
        s.clear()
        #expect(s.pending() == nil)
        #expect(store(suite: suite).pending() == nil)   // and it stays gone across a relaunch
    }
}
