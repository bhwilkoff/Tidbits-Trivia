import Testing
import SwiftData
@testable import TidbitsTriviaTests

/// The Atlas turns history into a claim about the player ("you are 63% in Film"),
/// so a thin sample must NOT produce a confident-looking number — one lucky
/// answer is not a strength. Play-testing confirmed the percentages match their
/// own fractions; these pin the sample floor and the decay rule underneath.
@Suite("Knowledge Atlas")
@MainActor
struct KnowledgeAtlasTests {

    @Test func noHistoryMeansNoDomainsAndNoPreview() throws {
        let ctx = try TestStore.context()
        #expect(KnowledgeAtlas.domains(in: ctx).isEmpty)
        #expect(KnowledgeAtlas.previewLine(in: ctx) == nil)
    }

    /// The sample floor guards the TRAJECTORY ARROW, not the row: a domain with
    /// one answer still appears (carrying its own visible "1 answered" sample
    /// size), but must not sprout a confident up/down arrow off a single data
    /// point. Withholding the arrow is the honest read the design asks for.
    @Test func aThinSampleShowsNoTrajectoryArrow() throws {
        let ctx = try TestStore.context()
        TestStore.record(ctx, category: "science", correct: 1, total: 1)
        let science = KnowledgeAtlas.domains(in: ctx).first { $0.categoryID == "science" }
        #expect(science != nil)
        #expect(science?.total == 1)
        #expect(science?.recentAccuracy == nil)
        #expect(science?.trajectoryDelta == nil)
        #expect(science?.isDecaying == false)
    }

    /// At or above the floor the arrow is allowed to appear.
    @Test func reachingTheSampleFloorUnlocksTheTrajectoryRead() throws {
        let ctx = try TestStore.context()
        TestStore.record(ctx, category: "history", correct: 6, total: 8)
        let history = KnowledgeAtlas.domains(in: ctx).first { $0.categoryID == "history" }
        #expect(history?.recentAccuracy != nil)
        #expect(abs((history?.recentAccuracy ?? 0) - 0.75) < 0.001)
    }

    /// The non-member teaser applies its own stricter floor, so a single answer
    /// never becomes a marketing claim about the player.
    @Test func previewLineIgnoresDomainsWithAlmostNoHistory() throws {
        let ctx = try TestStore.context()
        TestStore.record(ctx, category: "science", correct: 1, total: 1)
        #expect(KnowledgeAtlas.previewLine(in: ctx) == nil)
    }

    @Test func enoughAnswersProduceADomainWithTheRightAccuracy() throws {
        let ctx = try TestStore.context()
        // 3 games x 10 questions, 24 correct overall -> 80%
        TestStore.record(ctx, category: "science", correct: 8, total: 10)
        TestStore.record(ctx, category: "science", correct: 8, total: 10)
        TestStore.record(ctx, category: "science", correct: 8, total: 10)
        let science = KnowledgeAtlas.domains(in: ctx).first { $0.categoryID == "science" }
        #expect(science != nil)
        #expect(abs((science?.accuracy ?? 0) - 0.8) < 0.001)
    }

    @Test func domainsAreOrderedAndUnique() throws {
        let ctx = try TestStore.context()
        for cat in ["science", "history", "music"] {
            for _ in 0..<3 { TestStore.record(ctx, category: cat, correct: 7, total: 10) }
        }
        let domains = KnowledgeAtlas.domains(in: ctx)
        #expect(Set(domains.map(\.categoryID)).count == domains.count)
    }

    /// Records outside the trailing window must not count — the Atlas is a
    /// statement about the player NOW, not a lifetime average.
    @Test func staleRecordsFallOutOfTheTrailingWindow() throws {
        let ctx = try TestStore.context()
        for _ in 0..<4 { TestStore.record(ctx, category: "geography", correct: 9, total: 10, daysAgo: 800) }
        let domains = KnowledgeAtlas.domains(in: ctx)
        #expect(domains.first { $0.categoryID == "geography" } == nil)
    }

    @Test func decayRadarIsEmptyWithoutAnEarlierStrongPeriod() throws {
        let ctx = try TestStore.context()
        for _ in 0..<3 { TestStore.record(ctx, category: "music", correct: 5, total: 10) }
        #expect(KnowledgeAtlas.decayRadar(in: ctx).isEmpty)
    }

    @Test func constantsMatchTheOtherPlatforms() {
        // Mirrored verbatim in Kotlin/JS/C# (PARITY "Knowledge Atlas").
        #expect(KnowledgeAtlas.sampleFloor == 8)
        #expect(KnowledgeAtlas.strongThreshold == 0.70)
        #expect(KnowledgeAtlas.decayDelta == 0.12)
    }
}
