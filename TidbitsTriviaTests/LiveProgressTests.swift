import Testing

/// A8.11 — the big screen's "answers in" line. Pure, so the Mac and Windows projectors
/// cannot word it differently, and so the Mac side is provable without photographing a
/// screen (a full-desktop grab photographs whatever is frontmost, not the app).
@Suite("Live progress")
struct LiveProgressTests {
    @Test func anEmptyLobbyShowsNothing() {
        // "0 of 0 answered" on a projector is noise, and a lobby is not a question.
        #expect(LiveProgress.answersIn(answered: 0, joined: 0) == nil)
    }

    @Test func itCountsTablesInAndOut() {
        #expect(LiveProgress.answersIn(answered: 0, joined: 8) == "0 of 8 answered")
        #expect(LiveProgress.answersIn(answered: 3, joined: 8) == "3 of 8 answered")
        #expect(LiveProgress.answersIn(answered: 8, joined: 8) == "8 of 8 answered")
    }

    @Test func aCountThatOverrunsIsClamped() {
        // G7: several phones on one table answer, and a miscount must never read
        // "9 of 8 answered" across a room.
        #expect(LiveProgress.answersIn(answered: 9, joined: 8) == "8 of 8 answered")
        #expect(LiveProgress.answersIn(answered: -1, joined: 8) == "0 of 8 answered")
    }
}
