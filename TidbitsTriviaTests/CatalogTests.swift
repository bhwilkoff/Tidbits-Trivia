import Testing

/// Catalog integrity. These are the tables every platform mirrors by hand, so a
/// duplicate id or an unreachable mode is the kind of fault that shows up as a
/// blank screen for a player rather than as a compile error.
@Suite("Catalogs")
struct CatalogTests {

    @Test func everyGameModeHasATitle() {
        for mode in GameMode.allCases {
            #expect(!mode.title.isEmpty, "\(mode) has no title")
        }
    }

    @Test func gameModeTitlesAreUnique() {
        let titles = GameMode.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func gameModeRawValuesAreStable() {
        // Raw values are persisted in records and sent over the Live wire, so a
        // rename silently orphans history on every platform.
        #expect(GameMode.classic.rawValue == "classic")
        #expect(GameMode.daily.rawValue == "daily")
        #expect(GameMode.weakSpot.rawValue == "weakSpot")
        #expect(GameMode.marathon.rawValue == "marathon")
    }

    @Test func categoryIDsAreUnique() {
        let ids = TriviaCategory.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyCategoryHasANameAndSymbol() {
        for c in TriviaCategory.all {
            #expect(!c.name.isEmpty)
            #expect(!c.symbol.isEmpty)
        }
    }

    /// An unknown id must degrade to a usable category rather than crash or
    /// produce an empty pool — deep links and old records carry stale ids.
    @Test func unknownCategoryFallsBackGracefully() {
        let c = TriviaCategory.named("not-a-real-category")
        #expect(!c.name.isEmpty)
    }

    @Test func namedResolvesKnownCategories() {
        for c in TriviaCategory.all {
            #expect(TriviaCategory.named(c.id).id == c.id)
        }
    }
}
