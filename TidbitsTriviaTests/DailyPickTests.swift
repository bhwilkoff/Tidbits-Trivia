import Testing

/// The Daily must be the SAME seven questions for every player on every platform
/// — that is the whole premise of a shared daily and of the global board. The
/// owner caught the sets diverging once (2026-07-01) when each platform ran its
/// own seeded shuffle, which is why the rank function, not a shuffle, is the
/// contract. These golden values are FNV-1a64 computed independently of Swift,
/// so a change here fails loudly instead of silently splitting the player base.
@Suite("Daily pick (cross-stack contract)")
struct DailyPickTests {

    @Test func rankMatchesTheIndependentlyComputedGoldenVectors() {
        #expect(DailyPick.rank(day: "2026-07-31", categoryID: "mixed", id: "q1") == 3_292_667_222_318_249_718)
        #expect(DailyPick.rank(day: "2026-07-31", categoryID: "science", id: "q1") == 3_278_188_502_334_156_441)
        #expect(DailyPick.rank(day: "2026-01-01", categoryID: "mixed", id: "abc") == 7_169_114_632_888_205_565)
    }

    @Test func stableSeedIsFnv1a64() {
        #expect("".stableSeed == 0xCBF2_9CE4_8422_2325)
        #expect("a".stableSeed == 0xAF63_DC4C_8601_EC8C)
    }

    /// The point of ranking over shuffling: the INPUT order must not matter, so a
    /// platform that stores its corpus differently still gets the same Daily.
    @Test func resultIsIndependentOfInputOrder() {
        let ids = (1...200).map { "id-\($0)" }
        let forward = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "mixed", count: 7)
        let reversed = DailyPick.pick(ids: ids.reversed(), day: "2026-07-31", categoryID: "mixed", count: 7)
        let shuffled = DailyPick.pick(ids: ids.shuffled(), day: "2026-07-31", categoryID: "mixed", count: 7)
        #expect(forward == reversed)
        #expect(forward == shuffled)
    }

    @Test func differentDaysGiveDifferentSets() {
        let ids = (1...200).map { "id-\($0)" }
        let a = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "mixed", count: 7)
        let b = DailyPick.pick(ids: ids, day: "2026-08-01", categoryID: "mixed", count: 7)
        #expect(a != b)
    }

    @Test func differentCategoriesGiveDifferentSets() {
        let ids = (1...200).map { "id-\($0)" }
        let a = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "mixed", count: 7)
        let b = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "science", count: 7)
        #expect(a != b)
    }

    @Test func returnsExactlyCountAndNoDuplicates() {
        let ids = (1...200).map { "id-\($0)" }
        let picked = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "mixed", count: 7)
        #expect(picked.count == 7)
        #expect(Set(picked).count == 7)
    }

    /// A pool smaller than `count` returns everything rather than padding or crashing.
    @Test func poolSmallerThanCountReturnsWhatExists() {
        let picked = DailyPick.pick(ids: ["a", "b"], day: "2026-07-31", categoryID: "mixed", count: 7)
        #expect(picked.count == 2)
    }

    @Test func emptyPoolReturnsEmpty() {
        #expect(DailyPick.pick(ids: [], day: "2026-07-31", categoryID: "mixed", count: 7).isEmpty)
    }

    @Test func repeatedCallsAreStable() {
        let ids = (1...200).map { "id-\($0)" }
        let a = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "mixed", count: 7)
        let b = DailyPick.pick(ids: ids, day: "2026-07-31", categoryID: "mixed", count: 7)
        #expect(a == b)
    }
}
