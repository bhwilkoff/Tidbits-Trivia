import Testing
import Foundation

/// G5 — the pick-your-category board. These pin the rules that decide whether a
/// night stalls in front of a room.
@Suite("Live pick-your-category board")
struct LiveBoardTests {

    private func q(_ id: String, _ cat: String, _ diff: Int) -> Question {
        Question(id: id, prompt: "p", options: ["a", "b", "c", "d"], correctIndex: 0,
                 categoryID: cat, difficulty: diff, explanation: "",
                 sourceTitle: "", sourceURL: nil, templateID: "test")
    }

    /// A pool with every (category, tier) filled.
    private func fullPool(_ cats: [String]) -> [Question] {
        cats.flatMap { c in (1...5).map { t in q("\(c)-\(t)", c, t) } }
    }

    @Test("a full pool builds every cell of the grid")
    func full() {
        let b = LiveBoardBuilder.build(from: fullPool(["history", "music"]),
                                       categories: ["history", "music"])
        #expect(b.cells.count == 10)
        #expect(b.cell("history", 3)?.questionID == "history-3")
    }

    @Test("points come from the TIER, not the question")
    func points() {
        let b = LiveBoardBuilder.build(from: fullPool(["history"]), categories: ["history"])
        #expect(b.cell("history", 1)?.points == 100)
        #expect(b.cell("history", 5)?.points == 500)
    }

    @Test("a cell the pool cannot fill is ABSENT, not a dead button")
    func hole() {
        // No difficulty-4 history question anywhere in the pool.
        let pool = fullPool(["history"]).filter { $0.difficulty != 4 }
        let b = LiveBoardBuilder.build(from: pool, categories: ["history"])
        #expect(b.cells.count == 4)
        #expect(b.cell("history", 4) == nil)
    }

    @Test("no question is used twice, even across categories")
    func noReuse() {
        // One question, tagged history, is the only row available at tier 1.
        let shared = q("shared", "history", 1)
        let b = LiveBoardBuilder.build(from: [shared], categories: ["history", "history"])
        #expect(b.cells.count == 1)
    }

    @Test("taking a cell marks it, and taking it twice is refused")
    func take() {
        var b = LiveBoardBuilder.build(from: fullPool(["history"]), categories: ["history"])
        #expect(b.take("history", 2) == true)
        #expect(b.cell("history", 2)?.taken == true)
        // The second click on the same cell must not advance the night.
        #expect(b.take("history", 2) == false)
    }

    @Test("taking a cell that does not exist is refused rather than crashing")
    func takeMissing() {
        var b = LiveBoardBuilder.build(from: fullPool(["history"]), categories: ["history"])
        #expect(b.take("music", 3) == false)
        #expect(b.take("history", 9) == false)
    }

    @Test("remaining and completion track the picks")
    func remaining() {
        var b = LiveBoardBuilder.build(from: fullPool(["history"]), categories: ["history"])
        #expect(b.remaining.count == 5)
        #expect(b.pointsRemaining == 1500)   // 100+200+300+400+500
        for t in 1...5 { _ = b.take("history", t) }
        #expect(b.isComplete)
        #expect(b.pointsRemaining == 0)
    }

    @Test("only fully fillable categories are offered to the host")
    func fillable() {
        var pool = fullPool(["history", "music"])
        pool.removeAll { $0.categoryID == "music" && $0.difficulty == 5 }
        #expect(LiveBoardBuilder.fillableCategories(in: pool) == ["history"])
    }

    @Test("the team that answered correctly picks next")
    func chooserCorrect() {
        let teams = ["Alpha", "Bravo", "Charlie"]
        #expect(LiveBoardBuilder.nextChooser(current: "Alpha", correct: "Charlie", teams: teams) == "Charlie")
    }

    @Test("when nobody is right the pick ROTATES, so one table cannot drive the board")
    func chooserRotates() {
        let teams = ["Alpha", "Bravo", "Charlie"]
        #expect(LiveBoardBuilder.nextChooser(current: "Alpha", correct: nil, teams: teams) == "Bravo")
        #expect(LiveBoardBuilder.nextChooser(current: "Charlie", correct: nil, teams: teams) == "Alpha")
    }

    @Test("a correct answer from a team that has since left falls back to rotation")
    func chooserGoneTeam() {
        let teams = ["Alpha", "Bravo"]
        #expect(LiveBoardBuilder.nextChooser(current: "Alpha", correct: "Ghost", teams: teams) == "Bravo")
    }

    @Test("an empty room has no chooser rather than a phantom one")
    func chooserEmpty() {
        #expect(LiveBoardBuilder.nextChooser(current: nil, correct: nil, teams: []) == nil)
    }
}
