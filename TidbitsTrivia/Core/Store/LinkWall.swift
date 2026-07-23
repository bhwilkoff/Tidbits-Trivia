import Foundation

/// Link Wall (Club Feature 6, **Stage 1 prototype**) — a NYT-Connections-style
/// daily puzzle: 16 tiles hiding 4 groups of 4. Built entirely from the
/// corpus's EXISTING structured relation data — the same `match.json` blocks
/// that already back the Matching (Q5) game mode — so no new corpus work was
/// needed to prototype this. See docs/CLUB-FEATURES-BUILD.md → "Feature 6 —
/// Link Wall" → Stage 1.
///
/// Deterministic like `DailyPick`/`Marathon`: a `day` string hash-ranks first
/// the THEMES, then the specific candidate BLOCK within each theme, then the
/// tile shuffle — same day → same puzzle, everywhere, no stored state.
///
/// **Cross-group collision guard**: a tile that could plausibly belong to two
/// of the day's groups makes the puzzle unfair (unsolvable/ambiguous), not
/// cleverly hard. `puzzle(for:)` walks the day's ranked theme list and, for
/// each theme, the day's ranked candidate-block list, skipping any candidate
/// whose 4 members collide (case-insensitively) with a tile already placed —
/// so the assembled 16 are guaranteed distinct.
enum LinkWall {

    struct LinkWallGroup: Hashable, Sendable {
        let label: String       // the theme, e.g. "World Capitals"
        let why: String         // cited "key → value" pairs from the corpus source
        let members: [String]   // exactly 4
        let difficulty: Int     // 1 (yellow, easiest) ... 4 (purple, hardest)
    }

    struct LinkWallPuzzle: Hashable, Sendable {
        let day: String
        let groups: [LinkWallGroup]   // exactly 4, ascending difficulty
        let tiles: [String]           // the 16 members, shuffled for display

        fileprivate init(day: String, groups: [LinkWallGroup]) {
            self.day = day
            self.groups = groups
            var rng = SeededRNG(seed: "linkwall:tiles:\(day)".stableSeed)
            self.tiles = groups.flatMap(\.members).shuffled(using: &rng)
        }
    }

    /// One qualifying `match.json` block, tagged with its theme.
    private struct Candidate {
        let id: String
        let theme: Theme
        let members: [String]   // exactly 4, key-order preserved
        let why: String
    }

    private struct Theme {
        let label: String
        let difficulty: Int
        let useKeys: Bool   // true: tiles are MatchSpec.keys; false: .values
    }

    /// The full candidate pool, rebuilt from `match.json` each call (the
    /// underlying `JSONQuestionSource` is already an in-memory singleton, so
    /// this is cheap). Re-sorted by id to undo the source's internal
    /// `.shuffled()` — determinism here comes ONLY from the day-keyed ranking
    /// below, never from array order.
    private static func candidates() -> [Candidate] {
        let source = JSONQuestionSource.matching
        guard source.isAvailable else { return [] }
        let all = source.questions(categoryID: "mixed", excluding: [], limit: 100_000)
            .sorted { $0.id < $1.id }

        var out: [Candidate] = []
        for q in all {
            guard let m = q.matching, m.keys.count == m.values.count, m.keys.count >= 4,
                  let theme = themeTable[q.prompt] else { continue }

            var keys = m.keys
            var values = m.values
            if keys.count > 4 {
                // Deterministically drop one pair down to exactly 4 (some
                // match blocks — sports/history — carry 5). The remaining 4
                // pairs are still individually correct; nothing is invented.
                var rng = SeededRNG(seed: "linkwall:trim:\(q.id)".stableSeed)
                let dropIndex = Int(rng.next() % UInt64(keys.count))
                keys.remove(at: dropIndex)
                values.remove(at: dropIndex)
            }

            let members = theme.useKeys ? keys : values
            let deduped = Set(members.map { $0.lowercased() })
            guard members.count == 4, deduped.count == 4 else { continue }

            let pairs = zip(keys, values).map { "\($0) → \($1)" }.joined(separator: " · ")
            out.append(Candidate(id: q.id, theme: theme, members: members, why: pairs))
        }
        return out
    }

    /// The deterministic Link Wall for a given calendar day (default: today,
    /// `QuestionProvider.dayKey()` format `yyyy-MM-dd`). `nil` only if the
    /// bundled corpus can't fill 4 non-colliding groups (should not happen —
    /// ~28 themes are available for 4 slots).
    static func puzzle(for day: String) -> LinkWallPuzzle? {
        let pool = candidates()
        guard !pool.isEmpty else { return nil }

        let byTheme = Dictionary(grouping: pool, by: \.theme.label)
        let themeRank = DailyPick.pick(
            ids: Array(byTheme.keys), day: day, categoryID: "linkwall-theme", count: byTheme.count)

        var usedMembers = Set<String>()
        var groups: [LinkWallGroup] = []

        for themeLabel in themeRank {
            guard groups.count < 4, let blocks = byTheme[themeLabel] else { continue }
            let blockRank = DailyPick.pick(
                ids: blocks.map(\.id), day: day, categoryID: "linkwall-block:\(themeLabel)", count: blocks.count)
            let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })

            for id in blockRank {
                guard let candidate = byID[id] else { continue }
                let lowered = Set(candidate.members.map { $0.lowercased() })
                guard lowered.isDisjoint(with: usedMembers) else { continue }
                usedMembers.formUnion(lowered)
                groups.append(LinkWallGroup(
                    label: candidate.theme.label, why: candidate.why,
                    members: candidate.members, difficulty: candidate.theme.difficulty))
                break   // one block per theme per day
            }
        }

        guard groups.count == 4 else { return nil }
        groups.sort { $0.difficulty != $1.difficulty ? $0.difficulty < $1.difficulty : $0.label < $1.label }
        return LinkWallPuzzle(day: day, groups: groups)
    }

    // MARK: - Theme catalog
    //
    // match.json has 6 generic categories (one fixed prompt each, up to 60
    // candidate blocks per theme — e.g. many different capital/currency
    // groupings) plus `sports`/`history`, where EVERY block carries its own
    // unique prompt (one specific theme each, e.g. "NBA Legends"). This table
    // is keyed by that exact prompt string — a closed, finite set (verified
    // against the shipped match.json) — and picks (a) a short display label,
    // (b) which side of the match becomes the tiles, and (c) a hand-set
    // difficulty rating (1 easiest/yellow … 4 hardest/purple). The difficulty
    // numbers are an editorial judgment call for this prototype, not derived
    // from the corpus's own difficulty field (match.json doesn't carry one).
    private static let themeTable: [String: Theme] = [
        "Match each country to its capital.":
            Theme(label: "World Capitals", difficulty: 3, useKeys: false),
        "Match each country to its currency.":
            Theme(label: "World Currencies", difficulty: 3, useKeys: false),
        "Match each element to its symbol.":
            Theme(label: "Chemical Element Symbols", difficulty: 4, useKeys: false),
        "Match each book to its author.":
            Theme(label: "Classic Novels", difficulty: 2, useKeys: true),
        "Match each work to its composer.":
            Theme(label: "Classical Compositions", difficulty: 3, useKeys: true),
        "Match each film to its director.":
            Theme(label: "Iconic Films", difficulty: 1, useKeys: true),

        "Match each Summer Olympic Games to the city that hosted it.":
            Theme(label: "Olympic Host Cities", difficulty: 2, useKeys: false),
        "Match each tennis Grand Slam tournament to the city or country where it is held.":
            Theme(label: "Grand Slam Tennis Tournaments", difficulty: 2, useKeys: true),
        "Match each racing driver or event to its motorsport.":
            Theme(label: "Motorsports", difficulty: 2, useKeys: false),
        "Match each NBA legend to the team he is most associated with.":
            Theme(label: "NBA Legends", difficulty: 1, useKeys: true),
        "Match each NFL quarterback to the team he won a Super Bowl with.":
            Theme(label: "Super Bowl-Winning Quarterbacks", difficulty: 2, useKeys: true),
        "Match each soccer club to the city where it plays.":
            Theme(label: "European Soccer Clubs", difficulty: 2, useKeys: true),
        "Match each footballer to their national team.":
            Theme(label: "World-Class Footballers", difficulty: 1, useKeys: true),
        "Match each athlete to their sport.":
            Theme(label: "Legendary Athletes", difficulty: 1, useKeys: true),
        "Match each Olympic sprinter to the country they represented.":
            Theme(label: "Olympic Sprinters", difficulty: 2, useKeys: true),
        "Match each football stadium to the club that calls it home.":
            Theme(label: "Famous Football Stadiums", difficulty: 3, useKeys: true),
        "Match each MLB player to the team he is most associated with.":
            Theme(label: "MLB Legends", difficulty: 2, useKeys: true),

        "Match each U.S. President to the war fought during his time in office.":
            Theme(label: "U.S. Presidents & Their Wars", difficulty: 2, useKeys: true),
        "Match each revolution or independence movement to its country.":
            Theme(label: "Revolutions & Independence Movements", difficulty: 2, useKeys: true),
        "Match each invention or achievement to the person credited with it.":
            Theme(label: "Landmark Inventions", difficulty: 2, useKeys: true),
        "Match each historical figure to the country they led.":
            Theme(label: "Historical Leaders", difficulty: 2, useKeys: true),
        "Match each explorer to the region they are famous for exploring or reaching.":
            Theme(label: "Famous Explorers", difficulty: 2, useKeys: true),
        "Match each famous battle to the war it was part of.":
            Theme(label: "Famous Battles", difficulty: 3, useKeys: true),
        "Match each major event to the year it occurred.":
            Theme(label: "Major Historical Events", difficulty: 3, useKeys: true),
        "Match each U.S. President to the number of his presidency.":
            Theme(label: "U.S. Presidents by Number", difficulty: 2, useKeys: true),
        "Match each historic document to the country that produced it.":
            Theme(label: "Historic Documents", difficulty: 2, useKeys: true),
        "Match each ancient wonder or landmark to the civilization that built it.":
            Theme(label: "Ancient Wonders & Landmarks", difficulty: 2, useKeys: true),
        "Match each treaty or agreement to what it accomplished.":
            Theme(label: "Treaties & Agreements", difficulty: 3, useKeys: true),
    ]
}
