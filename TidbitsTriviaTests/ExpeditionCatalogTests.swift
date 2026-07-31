import Testing

/// Expeditions are a multi-week commitment, so a malformed stage (out-of-order
/// index, an unreachable pass bar) strands a player mid-campaign with progress
/// they cannot advance. The catalog is additive by design, so this guards every
/// future expedition too, not just the three that ship today.
@Suite("Expedition catalog")
struct ExpeditionCatalogTests {

    @Test func catalogIsNotEmpty() {
        #expect(!Expedition.all.isEmpty)
    }

    @Test func expeditionIDsAreUnique() {
        let ids = Expedition.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func stageIndicesAreContiguousFromZero() {
        for e in Expedition.all {
            #expect(e.stages.map(\.index) == Array(0..<e.stages.count), "\(e.id) has non-contiguous stages")
        }
    }

    @Test func stageCountMatchesTheStageList() {
        for e in Expedition.all { #expect(e.stageCount == e.stages.count) }
    }

    /// A pass bar above the question count can never be met.
    @Test func everyPassBarIsReachable() {
        for e in Expedition.all {
            for s in e.stages {
                #expect(s.passBar <= s.questionCount, "\(e.id) stage \(s.index) is unpassable")
                #expect(s.passBar > 0)
                #expect(s.questionCount > 0)
            }
        }
    }

    @Test func everyStageHasTitleAndBlurb() {
        for e in Expedition.all {
            #expect(!e.title.isEmpty)
            #expect(!e.subtitle.isEmpty)
            for s in e.stages {
                #expect(!s.title.isEmpty)
                #expect(!s.blurb.isEmpty)
            }
        }
    }

    /// Stages differentiate by difficulty band (the taxonomy is flat), so the
    /// bands must actually be valid ranges within the corpus's 1...5 scale.
    @Test func difficultyBandsAreWithinTheCorpusScale() {
        for e in Expedition.all {
            for s in e.stages {
                #expect(s.difficultyRange.lowerBound >= 1, "\(e.id) stage \(s.index) band too low")
                #expect(s.difficultyRange.upperBound <= 5, "\(e.id) stage \(s.index) band too high")
            }
        }
    }

    @Test func everyStageNamesARealCategory() {
        let known = Set(TriviaCategory.all.map(\.id))
        for e in Expedition.all {
            for s in e.stages {
                #expect(known.contains(s.categoryID), "\(e.id) stage \(s.index) -> unknown category \(s.categoryID)")
            }
        }
    }
}
