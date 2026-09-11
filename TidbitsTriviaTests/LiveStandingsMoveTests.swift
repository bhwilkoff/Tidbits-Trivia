import Testing
import Foundation

/// A2.15 — how far a table moved since the last round's scoreboard.
@Suite("Live standings movement")
struct LiveStandingsMoveTests {
    typealias M = LiveStandingsMove.Move

    @Test func aTableThatClimbsReadsAsAClimb() {
        let m = LiveStandingsMove.moves(previous: ["A", "B", "C", "D"], current: ["D", "A", "B", "C"])
        #expect(m["D"] == M.up(3))
        #expect(m["A"] == M.down(1))
        #expect(m["B"] == M.down(1))
        #expect(m["C"] == M.down(1))
    }

    @Test func nobodyMovingSaysSoRatherThanNothing() {
        let m = LiveStandingsMove.moves(previous: ["A", "B"], current: ["A", "B"])
        #expect(m["A"] == M.same)
        #expect(m["B"] == M.same)
        #expect(LiveStandingsMove.biggestClimb(m) == nil)   // a quiet round is quiet
    }

    @Test func aTableThatJoinedMidNightIsNew() {
        let m = LiveStandingsMove.moves(previous: ["A"], current: ["A", "Latecomers"])
        #expect(m["Latecomers"] == M.new)
        #expect(LiveStandingsMove.label(m["Latecomers"]) == "NEW")
    }

    @Test func theChipReadsTheWayTheRoomDoes() {
        #expect(LiveStandingsMove.label(nil) == nil)          // the FIRST scoreboard says nothing
        #expect(LiveStandingsMove.label(.same) == "—")
        #expect(LiveStandingsMove.label(.up(2)) == "▲2")
        #expect(LiveStandingsMove.label(.down(1)) == "▼1")
    }

    @Test func theBiggestClimbIsNamedOnceAndDeterministically() {
        let m = LiveStandingsMove.moves(previous: ["A", "B", "C", "D"], current: ["C", "D", "A", "B"])
        #expect(LiveStandingsMove.biggestClimb(m) == "Biggest climb: C up 2")
        // A tie is broken by name, so two stacks (and two runs) cannot disagree.
        let tie: [String: M] = ["Zed": .up(2), "Amy": .up(2)]
        #expect(LiveStandingsMove.biggestClimb(tie) == "Biggest climb: Amy up 2")
    }

    @Test func aDuplicateNameKeepsItsBestPreviousRank() {
        // Two paper teams typed the same name: the earlier (better) rank wins, so the
        // pair cannot report a phantom fall.
        let m = LiveStandingsMove.moves(previous: ["A", "A", "B"], current: ["A", "B"])
        #expect(m["A"] == M.same)
        #expect(m["B"] == M.up(1))
    }
}
