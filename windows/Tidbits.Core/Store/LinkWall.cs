using Tidbits.Core.Engine;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// Link Wall (Club Feature 6, docs/CLUB-FEATURES-BUILD.md) — a NYT-Connections-style
/// daily puzzle: 16 tiles hiding 4 groups of 4. Faithful C# port of
/// `Core/Store/LinkWall.swift`'s Stage 1.5/1.6 content-clean generator (also mirrored
/// verbatim in js/store.js and Android's `data/LinkWall.kt`) — same deterministic
/// day->theme->block ranking (the SAME cross-platform `DailyPick`/`StableSeed` hash
/// Daily/Marathon already use), same allowlist/denylist purity filters over
/// match.json's capital/currency/author/director/composer pools (built for the
/// Matching mode, where an impure decoy doesn't matter — Link Wall's labeled-group
/// promise exposes them), same near-duplicate collision guard, same singleton-theme
/// downweighting. Do NOT edit match.json for this — it serves Matching correctly
/// as-is; all purification lives here, mirroring the Swift/Kotlin/JS files.
///
/// Deterministic like `DailyPick`/Marathon's seed: a `day` string hash-ranks first the
/// THEMES, then the specific candidate BLOCK within each theme — same day => same
/// puzzle, everywhere, no stored state (only the player's progress THROUGH it is
/// persisted, via `RecordsStore.SaveLinkWallResult`).
public static class LinkWall
{
    private sealed record Theme(string Label, int Difficulty, bool UseKeys);

    /// One qualifying match.json block, tagged with its theme.
    private sealed record Candidate(string Id, Theme ThemeInfo, IReadOnlyList<string> Members, string Why);

    private const string CapitalPrompt = "Match each country to its capital.";
    private const string CurrencyPrompt = "Match each country to its currency.";
    private const string AuthorPrompt = "Match each book to its author.";
    private const string DirectorPrompt = "Match each film to its director.";
    private const string ComposerPrompt = "Match each work to its composer.";

    /// Modern UN-member sovereign states (plus Vatican City and the State of
    /// Palestine, both UN observer states) — the exact name strings as they appear as
    /// match.json keys. Deliberately excludes historical/dynastic polities, colonial
    /// empires, US states, UK home-nation subdivisions, and disputed/self-declared
    /// territories (Northern Cyprus, Republic of Artsakh, Somaliland,
    /// Gilgit-Baltistan, West Bank, Gaza Strip) — the exact impurity the Stage 1
    /// sample caught. Verbatim port of `sovereignCountries`.
    private static readonly HashSet<string> SovereignCountries = new()
    {
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
    };

    /// `composer` pool entries that are real classical/operatic compositions (an
    /// ALLOWLIST, not a denylist — the pool is dominated by film/TV/video-game
    /// scores and pop/rock/folk/anthem songs, so listing the ~40 genuine classical
    /// works is far shorter and more robust than listing everything that ISN'T one).
    /// Verbatim port of `classicalWorks`.
    private static readonly HashSet<string> ClassicalWorks = new()
    {
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
    };

    /// `author` pool entries that are real (`prompt`-cited) but are NOT books:
    /// canonical scripture (no single identifiable author, and not what "Books &
    /// Their Authors" promises), founding/legal/institutional documents,
    /// hymns/anthems/oaths (songs and pledges, not books), and outright
    /// wrong-medium or nonsense entries. One brand-safety exclusion (Mein Kampf).
    /// Verbatim port of `nonBookTitles`.
    private static readonly HashSet<string> NonBookTitles = new()
    {
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
    };

    /// `director` pool entries that are NOT films: TV series, miniseries, game
    /// shows, and video games (the "Top of the Pops" defect and its siblings).
    /// Checked against both an exact-title denylist and a disambiguator-suffix
    /// pattern. Verbatim port of `nonFilmTitles`.
    private static readonly HashSet<string> NonFilmTitles = new()
    {
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
    };

    private static bool IsRealClassical(string title) => ClassicalWorks.Contains(title);

    private static bool IsRealBook(string title) => !NonBookTitles.Contains(title);

    private static bool IsRealFilm(string title)
    {
        if (NonFilmTitles.Contains(title)) return false;
        var lower = title.ToLowerInvariant();
        return !(lower.Contains("video game") || lower.Contains("tv series")
            || lower.Contains("miniseries") || lower.Contains("(musical)"));
    }

    /// Verbatim port of `themeTable` — keyed by the exact match.json prompt string;
    /// picks a display label, which side of the match becomes the tiles, and a
    /// hand-set difficulty (1 easiest/yellow ... 4 hardest/purple, the Connections
    /// convention).
    private static readonly Dictionary<string, Theme> ThemeTable = new()
    {
        [CapitalPrompt] = new Theme("World Capitals", 3, UseKeys: false),
        [CurrencyPrompt] = new Theme("World Currencies", 3, UseKeys: false),
        ["Match each element to its symbol."] = new Theme("Chemical Element Symbols", 4, UseKeys: false),
        [AuthorPrompt] = new Theme("Books & Their Authors", 2, UseKeys: true),
        [ComposerPrompt] = new Theme("Composers & Their Works", 3, UseKeys: true),
        [DirectorPrompt] = new Theme("Iconic Films", 1, UseKeys: true),

        ["Match each Summer Olympic Games to the city that hosted it."] = new Theme("Olympic Host Cities", 2, UseKeys: false),
        ["Match each tennis Grand Slam tournament to the city or country where it is held."] = new Theme("Grand Slam Tennis Tournaments", 2, UseKeys: true),
        ["Match each racing driver or event to its motorsport."] = new Theme("Motorsports", 2, UseKeys: false),
        ["Match each NBA legend to the team he is most associated with."] = new Theme("NBA Legends", 1, UseKeys: true),
        ["Match each NFL quarterback to the team he won a Super Bowl with."] = new Theme("Super Bowl-Winning Quarterbacks", 2, UseKeys: true),
        ["Match each soccer club to the city where it plays."] = new Theme("European Soccer Clubs", 2, UseKeys: true),
        ["Match each footballer to their national team."] = new Theme("World-Class Footballers", 1, UseKeys: true),
        ["Match each athlete to their sport."] = new Theme("Legendary Athletes", 1, UseKeys: true),
        ["Match each Olympic sprinter to the country they represented."] = new Theme("Olympic Sprinters", 2, UseKeys: true),
        ["Match each football stadium to the club that calls it home."] = new Theme("Famous Football Stadiums", 3, UseKeys: true),
        ["Match each MLB player to the team he is most associated with."] = new Theme("MLB Legends", 2, UseKeys: true),

        ["Match each U.S. President to the war fought during his time in office."] = new Theme("U.S. Presidents & Their Wars", 2, UseKeys: true),
        ["Match each revolution or independence movement to its country."] = new Theme("Revolutions & Independence Movements", 2, UseKeys: true),
        ["Match each invention or achievement to the person credited with it."] = new Theme("Landmark Inventions", 2, UseKeys: true),
        ["Match each historical figure to the country they led."] = new Theme("Historical Leaders", 2, UseKeys: true),
        ["Match each explorer to the region they are famous for exploring or reaching."] = new Theme("Famous Explorers", 2, UseKeys: true),
        ["Match each famous battle to the war it was part of."] = new Theme("Famous Battles", 3, UseKeys: true),
        ["Match each major event to the year it occurred."] = new Theme("Major Historical Events", 3, UseKeys: true),
        ["Match each U.S. President to the number of his presidency."] = new Theme("U.S. Presidents by Number", 2, UseKeys: true),
        ["Match each historic document to the country that produced it."] = new Theme("Historic Documents", 2, UseKeys: true),
        ["Match each ancient wonder or landmark to the civilization that built it."] = new Theme("Ancient Wonders & Landmarks", 2, UseKeys: true),
        ["Match each treaty or agreement to what it accomplished."] = new Theme("Treaties & Agreements", 3, UseKeys: true),
    };

    /// Exact match, OR one string is a substring/prefix of the other after
    /// lowercasing (short strings — under 6 characters both sides — require an
    /// exact match only, so common short words don't false-positive). Catches the
    /// Stage 1 near-dup: "Declaration of Independence" vs "Declaration of
    /// Independence signed" (same referent, two tiles). Verbatim port of
    /// `isNearDuplicate`.
    private static bool IsNearDuplicate(string a, string b)
    {
        var x = a.ToLowerInvariant();
        var y = b.ToLowerInvariant();
        if (Math.Min(x.Length, y.Length) < 6) return x == y;
        return x.Contains(y) || y.Contains(x);
    }

    /// The full candidate pool, built from the injected match.json rows. Re-sorted
    /// by id to undo the source's internal shuffle — determinism here comes ONLY
    /// from the day-keyed ranking below, never from array order. Verbatim port of
    /// `candidates()`, including the Stage 1.5 pool-and-recombine for
    /// capital/composer and the purity filters for currency/author/director.
    private static List<Candidate> Candidates(IReadOnlyList<Question> matchQuestions)
    {
        var all = matchQuestions.OrderBy(q => q.Id, StringComparer.Ordinal).ToList();
        var outList = new List<Candidate>();
        var sovereignCapitalPairs = new List<(string Country, string Capital)>();
        var classicalWorkPairs = new List<(string Work, string Composer)>();

        foreach (var q in all)
        {
            var m = q.Matching;
            if (m is null || m.Keys.Count != m.Values.Count || m.Keys.Count < 4) continue;
            if (!ThemeTable.TryGetValue(q.Prompt, out var theme)) continue;

            var keys = m.Keys.ToList();
            var values = m.Values.ToList();
            if (keys.Count > 4)
            {
                // Deterministically drop one pair down to exactly 4 (some match
                // blocks — sports/history — carry 5). The remaining 4 pairs are
                // still individually correct; nothing is invented.
                var rng = new SeededRng(StableSeed.Of($"linkwall:trim:{q.Id}"));
                var dropIndex = (int)(rng.Next() % (ulong)keys.Count);
                keys.RemoveAt(dropIndex);
                values.RemoveAt(dropIndex);
            }

            // World Capitals: pool every clean (country, capital) pair across ALL
            // blocks instead — no single block yields 4 modern sovereign capitals.
            if (q.Prompt == CapitalPrompt)
            {
                for (int i = 0; i < keys.Count; i++)
                    if (SovereignCountries.Contains(keys[i])) sovereignCapitalPairs.Add((keys[i], values[i]));
                continue;
            }
            // Composers & Their Works: same pool-and-re-chunk treatment.
            if (q.Prompt == ComposerPrompt)
            {
                for (int i = 0; i < keys.Count; i++)
                    if (IsRealClassical(keys[i])) classicalWorkPairs.Add((keys[i], values[i]));
                continue;
            }

            var members = theme.UseKeys ? keys : values;
            var deduped = members.Select(x => x.ToLowerInvariant()).ToHashSet();
            if (members.Count != 4 || deduped.Count != 4) continue;

            if (q.Prompt == CurrencyPrompt)
            {
                // Every key must be a modern sovereign country (also catches the
                // "bimetallism" policy-not-currency entry via its paired key "Ming
                // dynasty"), plus an explicit second guard on that exact value.
                if (!keys.All(SovereignCountries.Contains)) continue;
                if (values.Any(v => string.Equals(v, "bimetallism", StringComparison.OrdinalIgnoreCase))) continue;
            }
            if (q.Prompt == AuthorPrompt && !members.All(IsRealBook)) continue;
            if (q.Prompt == DirectorPrompt && !members.All(IsRealFilm)) continue;

            var why = string.Join(" · ", keys.Zip(values, (k, v) => $"{k} → {v}"));
            outList.Add(new Candidate(q.Id, theme, members, why));
        }

        // Re-chunk the clean capital pairs into synthetic 4-member blocks. Sorted
        // order keeps the chunking itself deterministic and stable across app
        // launches; the day-keyed block ranking below still decides WHICH chunk
        // (and whether the theme appears at all) shows on a given day.
        if (ThemeTable.TryGetValue(CapitalPrompt, out var capitalTheme))
        {
            var ordered = sovereignCapitalPairs.OrderBy(p => p.Country, StringComparer.Ordinal).ToList();
            var usable = ordered.Count - (ordered.Count % 4);
            int chunkIndex = 0;
            for (int start = 0; start < usable; start += 4)
            {
                var chunk = ordered.Skip(start).Take(4).ToList();
                var why = string.Join(" · ", chunk.Select(p => $"{p.Country} → {p.Capital}"));
                outList.Add(new Candidate($"match:capital:clean:{chunkIndex}", capitalTheme, chunk.Select(p => p.Capital).ToList(), why));
                chunkIndex++;
            }
        }
        if (ThemeTable.TryGetValue(ComposerPrompt, out var composerTheme))
        {
            var ordered = classicalWorkPairs.OrderBy(p => p.Work, StringComparer.Ordinal).ToList();
            var usable = ordered.Count - (ordered.Count % 4);
            int chunkIndex = 0;
            for (int start = 0; start < usable; start += 4)
            {
                var chunk = ordered.Skip(start).Take(4).ToList();
                var why = string.Join(" · ", chunk.Select(p => $"{p.Work} → {p.Composer}"));
                outList.Add(new Candidate($"match:composer:clean:{chunkIndex}", composerTheme, chunk.Select(p => p.Work).ToList(), why));
                chunkIndex++;
            }
        }
        return outList;
    }

    /// Ranks the day's themes, DOWNWEIGHTING (not excluding) themes with a thin
    /// candidate pool (&lt;3 blocks — the ~20 sports/history prompts, each backed by
    /// exactly ONE match.json block, so unweighted they'd show up — and repeat — far
    /// more than a theme pool with dozens of blocks). `k` skews a thin theme's
    /// day-hash toward the back of the day's ranking (`1 - (1-f)^k` stretches a
    /// uniform `f` toward 1 as `k` grows); still a pure function of `day` + theme
    /// label, so still fully deterministic. `k = 10` (chosen by Apple's
    /// simulation). Verbatim port of `rankedThemes`.
    private static List<string> RankedThemes(Dictionary<string, List<Candidate>> byTheme, string day)
    {
        var weighted = new List<(string Label, double Key)>();
        foreach (var label in byTheme.Keys)
        {
            var baseRank = DailyPick.Rank(day, "linkwall-theme", label);
            var normalized = (double)baseRank / ulong.MaxValue;
            var isThin = (byTheme.TryGetValue(label, out var blocks) ? blocks.Count : 0) < 3;
            var k = isThin ? 10.0 : 1.0;
            var adjusted = 1 - Math.Pow(1 - normalized, k);
            weighted.Add((label, adjusted));
        }
        weighted.Sort((a, b) => a.Key != b.Key ? a.Key.CompareTo(b.Key) : string.CompareOrdinal(a.Label, b.Label));
        return weighted.Select(w => w.Label).ToList();
    }

    /// The deterministic Link Wall for a given calendar day (see `QuestionProvider.DayKey`).
    /// `null` only if the bundled corpus can't fill 4 non-colliding groups (should not
    /// happen — ~28 themes are available for 4 slots) — including when `matchQuestions`
    /// hasn't loaded yet (an empty pool). `matchQuestions` is the app's bundled
    /// match.json rows (`QuestionSources.Enrich(GameMode.Matching)`), injected so this
    /// generator is unit-testable without touching the app's Data/ dir. Verbatim port
    /// of `puzzle(for:)`.
    public static LinkWallPuzzle? Puzzle(string day, IReadOnlyList<Question> matchQuestions)
    {
        var pool = Candidates(matchQuestions);
        if (pool.Count == 0) return null;

        var byTheme = pool.GroupBy(c => c.ThemeInfo.Label).ToDictionary(g => g.Key, g => g.ToList());
        var themeRank = RankedThemes(byTheme, day);

        var usedMembers = new List<string>();
        var groups = new List<LinkWallGroup>();

        foreach (var themeLabel in themeRank)
        {
            if (groups.Count >= 4) break;
            if (!byTheme.TryGetValue(themeLabel, out var blocks)) continue;
            var blockRank = DailyPick.Pick(blocks.Select(b => b.Id).ToList(), day, $"linkwall-block:{themeLabel}", blocks.Count);
            var byId = blocks.ToDictionary(b => b.Id);

            foreach (var id in blockRank)
            {
                if (!byId.TryGetValue(id, out var candidate)) continue;
                var collides = candidate.Members.Any(nm => usedMembers.Any(um => IsNearDuplicate(nm, um)));
                if (collides) continue;
                usedMembers.AddRange(candidate.Members);
                groups.Add(new LinkWallGroup(candidate.ThemeInfo.Label, candidate.Why, candidate.Members, candidate.ThemeInfo.Difficulty));
                break; // one block per theme per day
            }
        }

        if (groups.Count != 4) return null;
        groups = groups
            .OrderBy(g => g.Difficulty)
            .ThenBy(g => g.Label, StringComparer.Ordinal)
            .ToList();

        var rng = new SeededRng(StableSeed.Of($"linkwall:tiles:{day}"));
        var tiles = ShuffleDeterministic(groups.SelectMany(g => g.Members).ToList(), ref rng);
        return new LinkWallPuzzle(day, groups, tiles);
    }

    /// Fisher-Yates driven by the seeded RNG — a pure display shuffle (which theme's
    /// 4 members land where), not something the other platforms need to reproduce
    /// bit-for-bit (only the GROUP content/day-determinism does).
    private static List<string> ShuffleDeterministic(List<string> items, ref SeededRng rng)
    {
        for (int i = items.Count - 1; i > 0; i--)
        {
            int j = (int)(rng.Next() % (ulong)(i + 1));
            (items[i], items[j]) = (items[j], items[i]);
        }
        return items;
    }

    /// Link Wall is curated-by-generator CONTENT, not player data (unlike Weak-Spot/
    /// Story Archive) — so, like Marathon, the non-member pitch is an honest,
    /// concrete illustration rather than a computed sample (MONETIZATION §4a: "a
    /// real preview, never a nag"). Verbatim of Apple/web/Android copy.
    public static string PreviewLine() =>
        "16 tiles hide 4 groups of 4 — solve things like World Capitals or Iconic Films before 4 mistakes. A brand-new wall every day.";
}
