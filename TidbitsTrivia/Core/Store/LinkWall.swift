import Foundation

/// Link Wall (Club Feature 6, **Stage 1 prototype**, quality-gate fixes in
/// **Stage 1.5**) — a NYT-Connections-style daily puzzle: 16 tiles hiding 4
/// groups of 4. Built entirely from the corpus's EXISTING structured relation
/// data — the same `match.json` blocks that already back the Matching (Q5)
/// game mode — so no new corpus work was needed to prototype this. See
/// docs/CLUB-FEATURES-BUILD.md → "Feature 6 — Link Wall" → Stage 1 / 1.5.
///
/// Deterministic like `DailyPick`/`Marathon`: a `day` string hash-ranks first
/// the THEMES, then the specific candidate BLOCK within each theme, then the
/// tile shuffle — same day → same puzzle, everywhere, no stored state.
///
/// **Cross-group collision guard**: a tile that could plausibly belong to two
/// of the day's groups makes the puzzle unfair (unsolvable/ambiguous), not
/// cleverly hard. `puzzle(for:)` walks the day's ranked theme list and, for
/// each theme, the day's ranked candidate-block list, skipping any candidate
/// whose members are an exact OR near-duplicate (substring/prefix match after
/// lowercasing — catches e.g. "Declaration of Independence" vs "Declaration
/// of Independence signed") of a tile already placed — so the assembled 16
/// are guaranteed distinct AND unambiguous.
///
/// **Stage 1.5 quality gate (docs/CLUB-FEATURES-BUILD.md § Stage 1 RESULT)**:
/// `match.json`'s `capital`/`author`/`director`/`currency`/`composer` pools
/// were built for the Matching mode, where an impure decoy doesn't matter —
/// Link Wall's labeled-group promise exposes them. `candidates()` purifies
/// each:
/// - `capital`/`composer`: essentially NO single block yields 4 clean
///   members (capital mixes in US states, UK county towns, historical/
///   dynastic seats, disputed territories; composer is dominated by film/TV/
///   video-game scores and pop/rock/folk/anthem songs sharing the same
///   prompt as the real classical works) — so clean (work, credit) PAIRS are
///   pooled across every block for each theme and re-chunked into synthetic
///   4-groups instead. `composer`'s label widens to "Composers & Their
///   Works" since the clean pool includes operetta alongside symphony/opera.
/// - `currency`: requires all 4 keys be modern sovereign countries (also
///   catches the "bimetallism" policy-not-currency entry, since its paired
///   key — "Ming dynasty" — already fails the sovereignty check).
/// - `author`/`director`: a member allow/deny filter (`isRealBook`/
///   `isRealFilm`) drops scripture, founding/legal documents, hymns, and
///   mismatched TV/video-game/film entries; `author`'s label widens to
///   "Books & Their Authors" since the clean pool still includes plays and
///   poems, not just novels.
/// Thin themes (the 20 sports/history prompts, each backed by exactly ONE
/// `match.json` block — always the same 4 tiles) are DOWNWEIGHTED, not
/// excluded, in the daily theme ranking (`rankedThemes`) so they surface less
/// often relative to the six many-block themes.
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
        var sovereignCapitalPairs: [(country: String, capital: String)] = []
        var classicalWorkPairs: [(work: String, composer: String)] = []

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

            // World Capitals: no single match.json block yields 4 modern
            // sovereign capitals (see the Stage 1.5 note above) — pool every
            // clean (country, capital) pair across ALL blocks instead and
            // re-chunk below, so this block itself contributes no Candidate.
            // The SAME country can legitimately appear in multiple match.json blocks
            // (each independently correct), so dedupe by country here — otherwise two
            // identical pairs can land in the same re-chunked group of 4, producing a
            // duplicate tile.
            if q.prompt == capitalPrompt {
                for (country, capital) in zip(keys, values)
                where sovereignCountries.contains(country) && !sovereignCapitalPairs.contains(where: { $0.country == country }) {
                    sovereignCapitalPairs.append((country, capital))
                }
                continue
            }

            // Composers & Their Works: even sparser than World Capitals —
            // essentially no block is 4-for-4 real classical works (the pool
            // is dominated by film/TV/video-game scores and pop/rock songs
            // sharing the same "Match each work to its composer." prompt).
            // Same pool-and-re-chunk treatment, same dedupe need.
            if q.prompt == composerPrompt {
                for (work, composer) in zip(keys, values)
                where isRealClassical(work) && !classicalWorkPairs.contains(where: { $0.work == work }) {
                    classicalWorkPairs.append((work, composer))
                }
                continue
            }

            let members = theme.useKeys ? keys : values
            let deduped = Set(members.map { $0.lowercased() })
            guard members.count == 4, deduped.count == 4 else { continue }

            if q.prompt == currencyPrompt {
                // Same impurity as capitals, plus one outright wrong value
                // ("bimetallism" is a monetary POLICY, not a currency) —
                // require every key be a modern sovereign country (which also
                // catches bimetallism's paired key, "Ming dynasty") and
                // reject that value explicitly as a second, explicit guard.
                guard keys.allSatisfy({ sovereignCountries.contains($0) }),
                      !values.contains(where: { $0.caseInsensitiveCompare("bimetallism") == .orderedSame })
                else { continue }
            }
            if q.prompt == authorPrompt {
                guard members.allSatisfy(isRealBook) else { continue }
            }
            if q.prompt == directorPrompt {
                guard members.allSatisfy(isRealFilm) else { continue }
            }

            let pairs = zip(keys, values).map { "\($0) → \($1)" }.joined(separator: " · ")
            out.append(Candidate(id: q.id, theme: theme, members: members, why: pairs))
        }

        // Re-chunk the clean capital pairs into synthetic 4-member blocks.
        // Sorted order keeps the chunking itself deterministic and stable
        // across app launches; the day-keyed block ranking below still
        // decides WHICH chunk (and whether the theme appears at all) shows
        // on a given day.
        if let capitalTheme = themeTable[capitalPrompt] {
            let ordered = sovereignCapitalPairs.sorted { $0.country < $1.country }
            let usableCount = ordered.count - (ordered.count % 4)
            var chunkIndex = 0
            var start = 0
            while start < usableCount {
                let chunk = ordered[start..<(start + 4)]
                let why = chunk.map { "\($0.country) → \($0.capital)" }.joined(separator: " · ")
                out.append(Candidate(
                    id: "match:capital:clean:\(chunkIndex)", theme: capitalTheme,
                    members: chunk.map(\.capital), why: why))
                chunkIndex += 1
                start += 4
            }
        }

        if let composerTheme = themeTable[composerPrompt] {
            let ordered = classicalWorkPairs.sorted { $0.work < $1.work }
            let usableCount = ordered.count - (ordered.count % 4)
            var chunkIndex = 0
            var start = 0
            while start < usableCount {
                let chunk = ordered[start..<(start + 4)]
                let why = chunk.map { "\($0.work) → \($0.composer)" }.joined(separator: " · ")
                out.append(Candidate(
                    id: "match:composer:clean:\(chunkIndex)", theme: composerTheme,
                    members: chunk.map(\.work), why: why))
                chunkIndex += 1
                start += 4
            }
        }

        return out
    }

    // MARK: - Stage 1.5 purity filters

    private static let capitalPrompt = "Match each country to its capital."
    private static let currencyPrompt = "Match each country to its currency."
    private static let authorPrompt = "Match each book to its author."
    private static let directorPrompt = "Match each film to its director."
    private static let composerPrompt = "Match each work to its composer."

    /// Modern UN-member sovereign states (plus Vatican City and the State of
    /// Palestine, both UN observer states) — the exact name strings as they
    /// appear as `match.json` keys. Deliberately excludes historical/dynastic
    /// polities, colonial empires, US states, UK home-nation subdivisions,
    /// and disputed/self-declared territories (Northern Cyprus, Republic of
    /// Artsakh, Somaliland, Gilgit-Baltistan, West Bank, Gaza Strip) — the
    /// exact impurity the Stage 1 sample caught.
    private static let sovereignCountries: Set<String> = [
        "Afghanistan", "Albania", "Algeria", "Angola", "Armenia", "Australia",
        "Azerbaijan", "Bahrain", "Bangladesh", "Barbados", "Belarus", "Belize",
        "Benin", "Bhutan", "Bolivia", "Bosnia and Herzegovina", "Botswana",
        "Brunei", "Bulgaria", "Burkina Faso", "Burundi", "Cambodia", "Cameroon",
        "Canada", "Cape Verde", "Central African Republic", "Chad", "Chile",
        "China", "Colombia", "Comoros", "Costa Rica", "Croatia", "Cuba",
        "Democratic Republic of the Congo", "Denmark", "Djibouti", "Dominica",
        "Ecuador", "El Salvador", "Equatorial Guinea", "Eritrea", "Eswatini",
        "Ethiopia", "Fiji", "France", "Gabon", "Georgia (country)", "Germany",
        "Ghana", "Grenada", "Guatemala", "Guinea-Bissau", "Guyana", "Haiti",
        "Honduras", "Hungary", "Iceland", "India", "Iraq", "Israel",
        "Ivory Coast", "Jamaica", "Japan", "Jordan", "Kazakhstan", "Kenya",
        "Kingdom of the Netherlands", "Kiribati", "Kuwait", "Kyrgyzstan",
        "Laos", "Latvia", "Lesotho", "Liberia", "Libya", "Liechtenstein",
        "Lithuania", "Madagascar", "Malawi", "Maldives", "Mali",
        "Marshall Islands", "Mauritania", "Mauritius", "Mexico", "Moldova",
        "Mongolia", "Montenegro", "Mozambique", "Myanmar", "Namibia", "Nauru",
        "Nepal", "New Zealand", "Nicaragua", "Niger", "Nigeria",
        "North Macedonia", "Oman", "Palau", "Palestine", "Panama",
        "Papua New Guinea", "Paraguay", "Peru", "Philippines", "Qatar",
        "Republic of Ireland", "Republic of the Congo", "Romania", "Russia",
        "Rwanda", "Saint Kitts and Nevis", "Saint Lucia", "Samoa",
        "San Marino", "São Tomé and Príncipe", "Senegal", "Serbia",
        "Seychelles", "Sierra Leone", "Slovakia", "Slovenia",
        "Solomon Islands", "Somalia", "South Sudan", "Sudan", "Suriname",
        "Sweden", "Syria", "Tajikistan", "Tanzania", "The Bahamas",
        "The Gambia", "Thailand", "Timor-Leste", "Togo", "Tonga",
        "Trinidad and Tobago", "Tunisia", "Turkey", "Turkmenistan", "Tuvalu",
        "Uganda", "Ukraine", "United Arab Emirates", "United Kingdom",
        "United States", "Uruguay", "Uzbekistan", "Vanuatu", "Vatican City",
        "Venezuela", "Vietnam", "Yemen", "Zambia", "Zimbabwe",
    ]

    /// `composer` pool entries that are real classical/operatic compositions
    /// (an ALLOWLIST, not a denylist — the pool is dominated by film/TV/
    /// video-game scores and pop/rock/folk/anthem songs, so listing the
    /// ~40 genuine classical works is far shorter and more robust than
    /// listing everything that ISN'T one). Covers symphonies, concertos,
    /// operas, chamber/piano works, and the operetta repertoire (Gilbert &
    /// Sullivan, Offenbach) — all written by composers working in the
    /// classical tradition, unlike a film cue or a rock anthem.
    private static let classicalWorks: Set<String> = [
        "Fantasia on a Theme by Thomas Tallis", "String Quintet (Schubert)",
        "Magnificat (Bach)", "Grosse Fuge", "Symphony No. 3 (Górecki)",
        "Symphony No. 9 (Bruckner)", "Piano Sonata No. 2 (Chopin)",
        "Pierrot lunaire", "Nixon in China", "Violin Concerto (Mendelssohn)",
        "Requiem (Fauré)", "Symphony No. 5 (Shostakovich)",
        "Symphony No. 8 (Mahler)", "Die Meistersinger von Nürnberg",
        "Enigma Variations", "Suite bergamasque", "L'Orfeo",
        "The Pirates of Penzance", "Scheherazade (Rimsky-Korsakov)",
        "Symphony No. 7 (Shostakovich)", "Der Rosenkavalier",
        "Orpheus in the Underworld", "The Tales of Hoffmann",
        "Goldberg Variations", "Adagio for Strings",
        "Toccata and Fugue in D minor, BWV 565", "Il trovatore",
        "The Firebird", "The Blue Danube", "Das Rheingold", "Porgy and Bess",
        "4′33″", "Parsifal", "Symphony No. 9 (Dvořák)", "The Planets",
        "Pictures at an Exhibition", "Nabucco", "Rigoletto", "Boléro",
        "Carmina Burana (Orff)", "Tosca", "Aida", "Turandot",
    ]

    private static func isRealClassical(_ title: String) -> Bool {
        classicalWorks.contains(title)
    }

    /// `author` pool entries that are real (`prompt`-cited) but are NOT
    /// books: canonical scripture (no single identifiable author, and not
    /// what "Books & Their Authors" promises), founding/legal/institutional
    /// documents, hymns/anthems/oaths (songs and pledges, not books), and
    /// outright wrong-medium or nonsense entries (a video game, a TV spin-off,
    /// a film credited as if it were the book, "Semaglutide" paired with a
    /// newspaper as its "author"). One brand-safety exclusion (Mein Kampf).
    private static let nonBookTitles: Set<String> = [
        "Kesh temple hymn", "Cædmon's Hymn", "Book of Genesis",
        "Epistle to the Romans", "Book of Sirach", "Gospel of Mark",
        "Gospel of Luke", "Gospel of John", "Gospel of Matthew",
        "Acts of the Apostles", "Book of Mormon", "Book of Revelation",
        "Torah", "Old Testament", "New Testament", "Rigveda",
        "Bhagavata Purana",
        "Universal Declaration of Human Rights", "The Federalist Papers",
        "Constitution of the United States", "Constitution of India",
        "Amazing Grace", "Deutschlandlied", "Hippocratic Oath",
        "A Mighty Fortress Is Our God",
        "Deus Ex (video game)", "Elite (video game)", "Portal (video game)",
        "Fate/Stay Night", "LazyTown", "My Sister's Keeper (film)",
        "The Walking Dead: Daryl Dixon", "Fear the Walking Dead",
        "The Marvelous Mrs. Maisel", "Band of Brothers (miniseries)",
        "The Batman (film)", "The Truman Show", "Final Destination (film)",
        "Leila's Brothers", "Semaglutide", "Mein Kampf",
    ]

    private static func isRealBook(_ title: String) -> Bool {
        !nonBookTitles.contains(title)
    }

    /// `director` pool entries that are NOT films: TV series, miniseries,
    /// game shows, and video games (the "Top of the Pops" defect and its
    /// siblings). Checked against both an exact-title denylist (titles that
    /// carry no disambiguating suffix, e.g. "Fawlty Towers") and a
    /// disambiguator-suffix pattern (titles match.json itself already tags
    /// "(TV series)"/"(miniseries)"/"(video game)"/"(musical)").
    private static let nonFilmTitles: Set<String> = [
        "Top of the Pops", "South Pacific (musical)", "Angels in America",
        "GoldenEye 007", "Last of the Summer Wine", "Wolfenstein 3D",
        "The Jeffersons", "The Honeymooners", "Fawlty Towers",
        "The Price Is Right", "I Love Lucy",
        "Castlevania: Symphony of the Night", "Blue's Clues", "American Idiot",
        "Family Feud", "My Love from the Star", "Super Mario 64",
        "Gilligan's Island", "Jeopardy!", "BioShock", "Days of Our Lives",
        "The Fresh Prince of Bel-Air", "Miami Vice", "American Idol",
        "Final Fantasy VII", "Carnival Row", "The Good Bad Mother",
        "Castaway Diva", "Fauda", "Mr. Queen",
        "Gayniggers from Outer Space", "All of Us Are Dead", "Kuruluş: Osman",
        "Doctor Cha", "81st Golden Globes", "The Orville",
        "Extraordinary Attorney Woo", "Star Trek: Discovery",
        "My Life with the Walter Boys", "Ginny & Georgia",
    ]

    private static func isRealFilm(_ title: String) -> Bool {
        if nonFilmTitles.contains(title) { return false }
        let lower = title.lowercased()
        return !(lower.contains("video game") || lower.contains("tv series")
            || lower.contains("miniseries") || lower.contains("(musical)"))
    }

    /// The deterministic Link Wall for a given calendar day (default: today,
    /// `QuestionProvider.dayKey()` format `yyyy-MM-dd`). `nil` only if the
    /// bundled corpus can't fill 4 non-colliding groups (should not happen —
    /// ~28 themes are available for 4 slots).
    static func puzzle(for day: String) -> LinkWallPuzzle? {
        let pool = candidates()
        guard !pool.isEmpty else { return nil }

        let byTheme = Dictionary(grouping: pool, by: \.theme.label)
        let themeRank = rankedThemes(byTheme: byTheme, day: day)

        var usedMembers: [String] = []
        var groups: [LinkWallGroup] = []

        for themeLabel in themeRank {
            guard groups.count < 4, let blocks = byTheme[themeLabel] else { continue }
            let blockRank = DailyPick.pick(
                ids: blocks.map(\.id), day: day, categoryID: "linkwall-block:\(themeLabel)", count: blocks.count)
            let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })

            for id in blockRank {
                guard let candidate = byID[id] else { continue }
                let collides = candidate.members.contains { newMember in
                    usedMembers.contains { isNearDuplicate(newMember, $0) }
                }
                guard !collides else { continue }
                usedMembers.append(contentsOf: candidate.members)
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

    /// Exact match, OR one string is a substring/prefix of the other after
    /// lowercasing (short strings — under 6 characters both sides — require
    /// an exact match only, so common short words don't false-positive).
    /// Catches the Stage 1 near-dup: "Declaration of Independence" vs
    /// "Declaration of Independence signed" (same referent, two tiles).
    private static func isNearDuplicate(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased()
        let y = b.lowercased()
        guard min(x.count, y.count) >= 6 else { return x == y }
        return x.contains(y) || y.contains(x)
    }

    /// Ranks the day's themes, DOWNWEIGHTING (not excluding) themes with a
    /// thin candidate pool (<3 blocks — the 20 sports/history prompts, each
    /// backed by exactly ONE `match.json` block, so unweighted they'd show
    /// up — and repeat — far more than a themepool with dozens of blocks).
    /// `k` skews a thin theme's day-hash toward the back of the day's ranking
    /// (`1 - (1-f)^k` stretches a uniform `f` toward 1 as `k` grows); still a
    /// pure function of `day` + theme label, so still fully deterministic.
    /// `k = 10` was chosen by simulation: with 20 thin / 6 rich themes it
    /// drops thin themes from ~3.1 of the day's 4 slots (unweighted) to
    /// ~1.2 — present most days, no longer dominant.
    private static func rankedThemes(byTheme: [String: [Candidate]], day: String) -> [String] {
        // Broken into a plain loop + named-tuple comparator (rather than one
        // chained map/sorted/map expression) — the chained form triggered
        // "unable to type-check this expression in reasonable time."
        var weighted: [(label: String, key: Double)] = []
        weighted.reserveCapacity(byTheme.count)
        for label in byTheme.keys {
            let base: UInt64 = DailyPick.rank(day: day, categoryID: "linkwall-theme", id: label)
            let normalized: Double = Double(base) / Double(UInt64.max)
            let isThin: Bool = (byTheme[label]?.count ?? 0) < 3
            let k: Double = isThin ? 10.0 : 1.0
            let adjusted: Double = 1 - pow(1 - normalized, k)
            weighted.append((label: label, key: adjusted))
        }
        weighted.sort { lhs, rhs in
            if lhs.key != rhs.key { return lhs.key < rhs.key }
            return lhs.label < rhs.label
        }
        return weighted.map { $0.label }
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
            Theme(label: "Books & Their Authors", difficulty: 2, useKeys: true),
        "Match each work to its composer.":
            Theme(label: "Composers & Their Works", difficulty: 3, useKeys: true),
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
