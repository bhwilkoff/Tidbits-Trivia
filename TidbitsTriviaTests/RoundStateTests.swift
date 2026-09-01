import Foundation
import Testing

/// The iMessage wire format.
///
/// `RoundState` is encoded into `MSMessage.url` and decoded by every other device in
/// the thread — including devices running a DIFFERENT app version, because a message
/// thread has no deployment window. That makes this a compatibility surface, and the
/// golden strings below exist so a change to the encoding cannot be made by accident.
///
/// The 5,000-character cap is the hard platform limit (`urlExceedsMaxSize`); there is
/// no server-free way around it, so the budget tests are ship-blocking rather than
/// nice-to-have.
struct RoundStateTests {

    private func sample() -> RoundState {
        RoundState(
            questionIDs: ["src:cloze:A", "src:cloze:B", "num:P2046:Q1", "rel:P17:Q2", "wd:director:Q3"],
            players: [
                .init(id: "1A2B3C4D", name: "Ben", answers: [0, 3, nil, nil, nil]),
                .init(id: "9F8E7D6C", name: "Sam", answers: [2, 3, nil, nil, nil]),
            ],
            index: 2)
    }

    @Test func encodesToTheExactGoldenString() {
        // Pinned deliberately. If this changes, a thread containing one old and one
        // new build stops agreeing about the game — so the change must be a conscious
        // version bump, not a refactor's side effect.
        #expect(sample().encoded() ==
            "tidbits://round?v=1&i=2&q=src:cloze:A~src:cloze:B~num:P2046:Q1~rel:P17:Q2~wd:director:Q3"
            + "&p=1A2B3C4D:Ben:03---%7C9F8E7D6C:Sam:23---")
    }

    @Test func roundTripsThroughAURL() throws {
        let original = sample()
        let url = try #require(URL(string: original.encoded()))
        let decoded = try #require(RoundState(url: url))
        #expect(decoded == original)
    }

    @Test func rejectsAFutureWireVersion() {
        // A newer build's message must decode to nil so the UI can say "you need a
        // newer Tidbits" rather than rendering a half-understood round as a real one.
        let url = URL(string: "tidbits://round?v=99&i=0&q=a&p=X:Y:-")!
        #expect(RoundState(url: url) == nil)
    }

    @Test func rejectsForeignAndTruncatedURLs() {
        #expect(RoundState(url: URL(string: "https://example.com/")!) == nil)
        #expect(RoundState(url: URL(string: "tidbits://round?v=1&i=0")!) == nil)   // no questions
    }

    @Test func namesCannotBreakTheFieldSeparators() {
        // ':' and '|' delimit fields and records. A name containing either would
        // corrupt every player after it — the bug that only appears when someone in
        // the group is called "A|B".
        let hostile = RoundState.sanitize("Ann:Marie|Smith~x&y")
        #expect(!hostile.contains(":"))
        #expect(!hostile.contains("|"))
        #expect(!hostile.contains("~"))
        #expect(!hostile.contains("&"))
    }

    @Test func namesAreLengthCapped() {
        let long = RoundState.sanitize(String(repeating: "x", count: 200))
        #expect(long.count == RoundState.maxNameLength)
    }

    @Test func aFullThreadStaysUnderTheFiveThousandCharacterCap() {
        // 20 players is a big group chat. If this ever exceeds the cap the send
        // throws and a player's answer disappears with no message, so the ceiling is
        // asserted rather than assumed.
        var state = RoundState(
            questionIDs: (0..<RoundState.questionCount).map { "src:describe:Some_Long_Article_Title_\($0)" },
            players: [], index: 0)
        for i in 0..<20 {
            state.upsert(playerID: String(format: "%08X", i), name: "Player\(i)")
            state.answer(playerID: String(format: "%08X", i), choice: i % 4)
        }
        #expect(state.encoded().count < 5_000)
    }

    @Test func firstAnswerStandsSoTheRevealCannotBeGamed() {
        var state = sample()
        state.index = 2
        state.answer(playerID: "1A2B3C4D", choice: 1)
        state.answer(playerID: "1A2B3C4D", choice: 3)   // second attempt ignored
        #expect(state.players[0].answers[2] == 1)
    }

    @Test func aRoundIsCompleteOnlyWhenEveryoneHasAnswered() {
        var state = sample()
        state.index = 2
        #expect(!state.currentQuestionComplete)
        state.answer(playerID: "1A2B3C4D", choice: 0)
        #expect(!state.currentQuestionComplete)         // one of two
        state.answer(playerID: "9F8E7D6C", choice: 1)
        #expect(state.currentQuestionComplete)
    }

    @Test func scoringCountsOnlyMatchesAgainstTheKey() {
        let state = sample()
        // Key: question A's answer is 0, B's is 3, the rest unanswered.
        let key: (String) -> Int? = { id in
            ["src:cloze:A": 0, "src:cloze:B": 3][id]
        }
        #expect(state.score(state.players[0], correctIndexFor: key) == 2)  // 0 and 3
        #expect(state.score(state.players[1], correctIndexFor: key) == 1)  // only 3
    }
}
