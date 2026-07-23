package com.learningischange.tidbitstrivia.data

/**
 * Link Wall (Tidbits Club EXCLUSIVE — docs/CLUB-FEATURES-BUILD.md "Feature 6") — a
 * NYT-Connections-style SECOND daily: 16 tiles hide 4 themed groups of 4. Faithful
 * Kotlin port of `Core/Store/LinkWall.swift`'s Stage 1.5/1.6 content-clean generator
 * (also mirrored verbatim in js/store.js's `LinkWall`) — same deterministic
 * day->theme->block ranking ([dailyRank]/[pickDailyIds], the SAME cross-platform hash
 * this file's Daily/Marathon already use), same allowlist/denylist purity filters over
 * match.json's capital/currency/author/director/composer pools (built for the Matching
 * mode, where an impure decoy doesn't matter — Link Wall's labeled-group promise
 * exposes them), same near-duplicate collision guard, same singleton-theme
 * downweighting. Do NOT edit match.json for this — it serves Matching correctly as-is;
 * all purification lives here, mirroring the Swift/JS files.
 *
 * Deterministic like [pickDailyIds]/Marathon's seed: a `day` string hash-ranks first
 * the THEMES, then the specific candidate BLOCK within each theme — same day => same
 * puzzle, everywhere, no stored state (only the player's progress THROUGH it is
 * persisted, via [Store.linkWallResult]).
 */
object LinkWall {

    data class LinkWallGroup(
        val label: String,       // the theme, e.g. "World Capitals"
        val why: String,         // cited "key → value" pairs from the corpus source
        val members: List<String>, // exactly 4
        val difficulty: Int,     // 1 (yellow, easiest) ... 4 (purple, hardest)
    )

    data class LinkWallPuzzle(
        val day: String,
        val groups: List<LinkWallGroup>, // exactly 4, ascending difficulty
        val tiles: List<String>,         // the 16 members, shuffled for display
    )

    /** Persisted outcome of one day's Link Wall — SharedPreferences mirror of the
     *  Swift SwiftData `LinkWallResult` / web's `tidbits.linkwall[day]` row (one row
     *  per day, keyed by day; reopening a completed OR in-progress day resumes this
     *  row, never a fresh board). See [Store.linkWallResult] for the persisted JSON
     *  shape (the shared contract for the Windows port too). */
    data class LinkWallResult(
        val mistakes: Int = 0,
        val completed: Boolean = false,
        val won: Boolean = false,
        val date: Long = System.currentTimeMillis(),
        // one row per guess, IN ORDER, each of the 4 tapped tiles' TRUE group
        // difficulty (1..4) at guess time — exactly what the share grid renders.
        val guessHistory: List<List<Int>> = emptyList(),
        val solvedLabels: List<String> = emptyList(), // solved group labels, in SOLVE order
    )

    private data class Theme(val label: String, val difficulty: Int, val useKeys: Boolean)

    /** One qualifying match.json block, tagged with its theme. */
    private data class Candidate(val id: String, val theme: Theme, val members: List<String>, val why: String)

    private const val CAPITAL_PROMPT = "Match each country to its capital."
    private const val CURRENCY_PROMPT = "Match each country to its currency."
    private const val AUTHOR_PROMPT = "Match each book to its author."
    private const val DIRECTOR_PROMPT = "Match each film to its director."
    private const val COMPOSER_PROMPT = "Match each work to its composer."

    /** Modern UN-member sovereign states (plus Vatican City and the State of
     *  Palestine, both UN observer states) — the exact name strings as they appear as
     *  match.json keys. Deliberately excludes historical/dynastic polities, colonial
     *  empires, US states, UK home-nation subdivisions, and disputed/self-declared
     *  territories (Northern Cyprus, Republic of Artsakh, Somaliland,
     *  Gilgit-Baltistan, West Bank, Gaza Strip) — the exact impurity the Stage 1
     *  sample caught. Verbatim port of `sovereignCountries`. */
    private val sovereignCountries: Set<String> = setOf(
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
    )

    /** `composer` pool entries that are real classical/operatic compositions (an
     *  ALLOWLIST, not a denylist — the pool is dominated by film/TV/video-game scores
     *  and pop/rock/folk/anthem songs, so listing the ~40 genuine classical works is
     *  far shorter and more robust than listing everything that ISN'T one). Verbatim
     *  port of `classicalWorks`. */
    private val classicalWorks: Set<String> = setOf(
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
    )

    /** `author` pool entries that are real (`prompt`-cited) but are NOT books: canonical
     *  scripture (no single identifiable author), founding/legal/institutional
     *  documents, hymns/anthems/oaths, and outright wrong-medium/nonsense entries. One
     *  brand-safety exclusion (Mein Kampf). Verbatim port of `nonBookTitles`. */
    private val nonBookTitles: Set<String> = setOf(
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
    )

    /** `director` pool entries that are NOT films: TV series, miniseries, game shows,
     *  and video games (the "Top of the Pops" defect and its siblings). Verbatim port
     *  of `nonFilmTitles` + the disambiguator-suffix pattern (`isRealFilm`). */
    private val nonFilmTitles: Set<String> = setOf(
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
    )

    private fun isRealClassical(title: String): Boolean = classicalWorks.contains(title)
    private fun isRealBook(title: String): Boolean = !nonBookTitles.contains(title)
    private fun isRealFilm(title: String): Boolean {
        if (nonFilmTitles.contains(title)) return false
        val lower = title.lowercase()
        return !(lower.contains("video game") || lower.contains("tv series")
            || lower.contains("miniseries") || lower.contains("(musical)"))
    }

    /** Verbatim port of `themeTable` — keyed by the exact match.json prompt string;
     *  picks a display label, which side of the match becomes the tiles, and a
     *  hand-set difficulty (1 easiest/yellow ... 4 hardest/purple, the Connections
     *  convention). */
    private val themeTable: Map<String, Theme> = mapOf(
        CAPITAL_PROMPT to Theme("World Capitals", 3, useKeys = false),
        CURRENCY_PROMPT to Theme("World Currencies", 3, useKeys = false),
        "Match each element to its symbol." to Theme("Chemical Element Symbols", 4, useKeys = false),
        AUTHOR_PROMPT to Theme("Books & Their Authors", 2, useKeys = true),
        COMPOSER_PROMPT to Theme("Composers & Their Works", 3, useKeys = true),
        DIRECTOR_PROMPT to Theme("Iconic Films", 1, useKeys = true),

        "Match each Summer Olympic Games to the city that hosted it." to Theme("Olympic Host Cities", 2, useKeys = false),
        "Match each tennis Grand Slam tournament to the city or country where it is held." to Theme("Grand Slam Tennis Tournaments", 2, useKeys = true),
        "Match each racing driver or event to its motorsport." to Theme("Motorsports", 2, useKeys = false),
        "Match each NBA legend to the team he is most associated with." to Theme("NBA Legends", 1, useKeys = true),
        "Match each NFL quarterback to the team he won a Super Bowl with." to Theme("Super Bowl-Winning Quarterbacks", 2, useKeys = true),
        "Match each soccer club to the city where it plays." to Theme("European Soccer Clubs", 2, useKeys = true),
        "Match each footballer to their national team." to Theme("World-Class Footballers", 1, useKeys = true),
        "Match each athlete to their sport." to Theme("Legendary Athletes", 1, useKeys = true),
        "Match each Olympic sprinter to the country they represented." to Theme("Olympic Sprinters", 2, useKeys = true),
        "Match each football stadium to the club that calls it home." to Theme("Famous Football Stadiums", 3, useKeys = true),
        "Match each MLB player to the team he is most associated with." to Theme("MLB Legends", 2, useKeys = true),

        "Match each U.S. President to the war fought during his time in office." to Theme("U.S. Presidents & Their Wars", 2, useKeys = true),
        "Match each revolution or independence movement to its country." to Theme("Revolutions & Independence Movements", 2, useKeys = true),
        "Match each invention or achievement to the person credited with it." to Theme("Landmark Inventions", 2, useKeys = true),
        "Match each historical figure to the country they led." to Theme("Historical Leaders", 2, useKeys = true),
        "Match each explorer to the region they are famous for exploring or reaching." to Theme("Famous Explorers", 2, useKeys = true),
        "Match each famous battle to the war it was part of." to Theme("Famous Battles", 3, useKeys = true),
        "Match each major event to the year it occurred." to Theme("Major Historical Events", 3, useKeys = true),
        "Match each U.S. President to the number of his presidency." to Theme("U.S. Presidents by Number", 2, useKeys = true),
        "Match each historic document to the country that produced it." to Theme("Historic Documents", 2, useKeys = true),
        "Match each ancient wonder or landmark to the civilization that built it." to Theme("Ancient Wonders & Landmarks", 2, useKeys = true),
        "Match each treaty or agreement to what it accomplished." to Theme("Treaties & Agreements", 3, useKeys = true),
    )

    /** Splitmix64 raw draw (bit-identical to Swift's `SeededRNG.next()`: state =
     *  seed+phi at init, then state += phi before the first hash) seeded from the
     *  exact same [stableSeed] FNV-1a `DailyPick`/Marathon already use — only used for
     *  the "drop one of 5 keys down to 4" trim, where LinkWall.swift calls
     *  `rng.next() % UInt64(count)` once. Returns the raw 64-bit word (as the bit
     *  pattern of a signed [Long]) — callers reinterpret via [ULong] for the modulo. */
    private fun splitmix64Draw(seedStr: String): Long {
        val phi = -0x61c8864680b583ebL // 0x9E3779B97F4A7C15
        var state = stableSeed(seedStr) + phi
        state += phi
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L // 0xBF58476D1CE4E5B9
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L // 0x94D049BB133111EB
        return z xor (z ushr 31)
    }

    /** Exact match, OR one string is a substring/prefix of the other after
     *  lowercasing (short strings — under 6 characters both sides — require an exact
     *  match only, so common short words don't false-positive). Catches the Stage 1
     *  near-dup: "Declaration of Independence" vs "Declaration of Independence
     *  signed" (same referent, two tiles). Verbatim port of `isNearDuplicate`. */
    private fun isNearDuplicate(a: String, b: String): Boolean {
        val x = a.lowercase(); val y = b.lowercase()
        if (minOf(x.length, y.length) < 6) return x == y
        return x.contains(y) || y.contains(x)
    }

    /** The full candidate pool, built from the injected match.json rows (cheap — ~350
     *  rows). Re-sorted by id to undo [JsonQuestionSet.pull]'s internal `.shuffled()`
     *  — determinism here comes ONLY from the day-keyed ranking below, never from
     *  array order. Verbatim port of `candidates()`, including the Stage 1.5
     *  pool-and-recombine for capital/composer and the purity filters for
     *  currency/author/director. */
    private fun candidates(matchQuestions: List<Question>): List<Candidate> {
        val all = matchQuestions.sortedBy { it.id }
        val out = mutableListOf<Candidate>()
        val sovereignCapitalPairs = mutableListOf<Pair<String, String>>()   // country, capital
        val classicalWorkPairs = mutableListOf<Pair<String, String>>()     // work, composer

        for (q in all) {
            val m = q.matching ?: continue
            if (m.keys.size != m.values.size || m.keys.size < 4) continue
            val theme = themeTable[q.prompt] ?: continue

            var keys = m.keys
            var values = m.values
            if (keys.size > 4) {
                // Deterministically drop one pair down to exactly 4 (some match blocks
                // — sports/history — carry 5). The remaining 4 pairs are still
                // individually correct; nothing is invented.
                val z = splitmix64Draw("linkwall:trim:${q.id}").toULong()
                val dropIndex = (z % keys.size.toULong()).toInt()
                keys = keys.toMutableList().also { it.removeAt(dropIndex) }
                values = values.toMutableList().also { it.removeAt(dropIndex) }
            }

            // World Capitals: pool every clean (country, capital) pair across ALL
            // blocks instead — no single block yields 4 modern sovereign capitals.
            if (q.prompt == CAPITAL_PROMPT) {
                keys.indices.forEach { i -> if (sovereignCountries.contains(keys[i])) sovereignCapitalPairs.add(keys[i] to values[i]) }
                continue
            }
            // Composers & Their Works: same pool-and-re-chunk treatment.
            if (q.prompt == COMPOSER_PROMPT) {
                keys.indices.forEach { i -> if (isRealClassical(keys[i])) classicalWorkPairs.add(keys[i] to values[i]) }
                continue
            }

            val members = if (theme.useKeys) keys else values
            val deduped = members.map { it.lowercase() }.toSet()
            if (members.size != 4 || deduped.size != 4) continue

            if (q.prompt == CURRENCY_PROMPT) {
                // Every key must be a modern sovereign country (also catches the
                // "bimetallism" policy-not-currency entry via its paired key "Ming
                // dynasty"), plus an explicit second guard on that exact value.
                if (!keys.all { sovereignCountries.contains(it) }) continue
                if (values.any { it.equals("bimetallism", ignoreCase = true) }) continue
            }
            if (q.prompt == AUTHOR_PROMPT && !members.all(::isRealBook)) continue
            if (q.prompt == DIRECTOR_PROMPT && !members.all(::isRealFilm)) continue

            val why = keys.indices.joinToString(" · ") { "${keys[it]} → ${values[it]}" }
            out.add(Candidate(q.id, theme, members, why))
        }

        // Re-chunk the clean capital pairs into synthetic 4-member blocks. Sorted
        // order keeps the chunking itself deterministic and stable across app
        // launches; the day-keyed block ranking below still decides WHICH chunk (and
        // whether the theme appears at all) shows on a given day.
        themeTable[CAPITAL_PROMPT]?.let { capitalTheme ->
            val ordered = sovereignCapitalPairs.sortedBy { it.first }
            val usable = ordered.size - (ordered.size % 4)
            var chunkIndex = 0; var start = 0
            while (start < usable) {
                val chunk = ordered.subList(start, start + 4)
                val why = chunk.joinToString(" · ") { "${it.first} → ${it.second}" }
                out.add(Candidate("match:capital:clean:$chunkIndex", capitalTheme, chunk.map { it.second }, why))
                chunkIndex++; start += 4
            }
        }
        themeTable[COMPOSER_PROMPT]?.let { composerTheme ->
            val ordered = classicalWorkPairs.sortedBy { it.first }
            val usable = ordered.size - (ordered.size % 4)
            var chunkIndex = 0; var start = 0
            while (start < usable) {
                val chunk = ordered.subList(start, start + 4)
                val why = chunk.joinToString(" · ") { "${it.first} → ${it.second}" }
                out.add(Candidate("match:composer:clean:$chunkIndex", composerTheme, chunk.map { it.first }, why))
                chunkIndex++; start += 4
            }
        }
        return out
    }

    /** Ranks the day's themes, DOWNWEIGHTING (not excluding) themes with a thin
     *  candidate pool (<3 blocks — the ~20 sports/history prompts, each backed by
     *  exactly ONE match.json block, so unweighted they'd show up — and repeat — far
     *  more than a theme pool with dozens of blocks). `k` skews a thin theme's
     *  day-hash toward the back of the day's ranking (`1 - (1-f)^k` stretches a
     *  uniform `f` toward 1 as `k` grows); still a pure function of `day` + theme
     *  label, so still fully deterministic. `k = 10` (chosen by Apple's simulation).
     *  Verbatim port of `rankedThemes`. */
    private fun rankedThemes(byTheme: Map<String, List<Candidate>>, day: String): List<String> {
        val weighted = byTheme.keys.map { label ->
            val base = dailyRank(day, "linkwall-theme", label)
            val normalized = base.toDouble() / ULong.MAX_VALUE.toDouble()
            val isThin = (byTheme[label]?.size ?: 0) < 3
            val k = if (isThin) 10.0 else 1.0
            val adjusted = 1 - Math.pow(1 - normalized, k)
            label to adjusted
        }
        return weighted.sortedWith(compareBy({ it.second }, { it.first })).map { it.first }
    }

    /** The deterministic Link Wall for a given calendar day (see [dayKey]). `null`
     *  only if the bundled corpus can't fill 4 non-colliding groups (should not happen
     *  — ~28 themes are available for 4 slots) — including when [MatchingSet] hasn't
     *  loaded yet (an empty pool, same as an empty [matchQuestions]). [matchQuestions]
     *  defaults to the app's own bundled match.json (mirrors Marathon reading Corpus
     *  directly) but is injectable — the same seam web's `LinkWall.puzzle(day,
     *  matchQuestions)` uses — so this generator is unit-testable on the plain JVM
     *  without an Android Context (see `LinkWallTest`). Verbatim port of
     *  `puzzle(for:)`. */
    fun puzzle(day: String, matchQuestions: List<Question> = MatchingSet.pull("mixed", emptySet(), 100_000)): LinkWallPuzzle? {
        val pool = candidates(matchQuestions)
        if (pool.isEmpty()) return null

        val byTheme = pool.groupBy { it.theme.label }
        val themeRank = rankedThemes(byTheme, day)

        val usedMembers = mutableListOf<String>()
        val groups = mutableListOf<LinkWallGroup>()

        for (themeLabel in themeRank) {
            if (groups.size >= 4) break
            val blocks = byTheme[themeLabel] ?: continue
            val blockRank = pickDailyIds(blocks.map { it.id }, day, "linkwall-block:$themeLabel", blocks.size)
            val byId = blocks.associateBy { it.id }
            for (id in blockRank) {
                val candidate = byId[id] ?: continue
                val collides = candidate.members.any { nm -> usedMembers.any { um -> isNearDuplicate(nm, um) } }
                if (collides) continue
                usedMembers.addAll(candidate.members)
                groups.add(LinkWallGroup(candidate.theme.label, candidate.why, candidate.members, candidate.theme.difficulty))
                break // one block per theme per day
            }
        }

        if (groups.size != 4) return null
        val sorted = groups.sortedWith(compareBy({ it.difficulty }, { it.label }))
        val rng = SeededRng(stableSeed("linkwall:tiles:$day"))
        val tiles = sorted.flatMap { it.members }.shuffledWith(rng)
        return LinkWallPuzzle(day, sorted, tiles)
    }

    /** Link Wall is curated-by-generator CONTENT, not player data (unlike Weak-Spot/
     *  Story Archive) — so, like Marathon, the non-member pitch is an honest, concrete
     *  illustration rather than a computed sample (MONETIZATION §4a: "a real preview,
     *  never a nag"). Verbatim of Apple/web copy. */
    fun previewLine(): String =
        "16 tiles hide 4 groups of 4 — solve things like World Capitals or Iconic Films before 4 mistakes. A brand-new wall every day."
}
