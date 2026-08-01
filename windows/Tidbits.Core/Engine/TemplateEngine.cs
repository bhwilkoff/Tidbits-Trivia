using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.Core.Engine;

/// Turns Wikipedia article summaries into trivia questions (port of
/// Core/Engine/TemplateEngine.swift). The product's moat is the FILTER, not the
/// fetch: "describe & identify" + a cloze variety, gated by a fame floor + a
/// richness check so we never ship an obscure subject or a content-free clue.
public static class TemplateEngine
{
    // MARK: Quality gates

    public static bool IsUsable(WikipediaClient.Summary s) => IsUsable(s, false);

    /// `relaxed` is the LIVE path (Create), where the fame floor means something
    /// different. Sweeping the corpus, a 600-character intro is a free notability
    /// proxy over millions of candidates. Sweeping the results of a topic the
    /// PLAYER typed it is just a rejection — Folarin Balogun's whole summary is
    /// 137 characters and makes a perfectly good clue, and a topic needs four
    /// usable articles to produce anything. Mirrors Swift/Kotlin/JS.
    public static bool IsUsable(WikipediaClient.Summary s, bool relaxed)
    {
        if (s.Type == "disambiguation") return false;
        var d = s.Description;
        if (d is null || d.Length < 6 || d.Length > 90) return false;
        var e = s.Extract;
        if (e is null || e.Length < (relaxed ? 120 : 600)) return false;
        var lowerTitle = s.Title.ToLowerInvariant();
        if (lowerTitle.StartsWith("list of") || lowerTitle.Contains("(disambiguation)")) return false;
        if (e.ToLowerInvariant().Contains("may refer to")) return false;
        return true;
    }

    // MARK: Rotating stems (one %@ slot each)

    private static readonly Dictionary<string, string[]> Stems = new()
    {
        ["describe_person"] = new[] { "This %@ — who is this?", "Name this %@.", "Who is the %@?", "Which %@?" },
        ["describe_thing"] = new[] { "Name this %@.", "Which %@?", "Name the %@." },
        ["cloze"] = new[] { "Fill in the blank: “%@”", "Complete it: “%@”", "Which name completes this? “%@”" },
    };
    private static readonly string[] ShapeRotation = { "describe", "cloze", "describe", "describe", "cloze" };

    // MARK: Generation

    /// `distractors` defaults to `pool`, and separating them is what makes live
    /// Create work at all. The SUBJECT of a question must be about the topic the
    /// player typed, which leaves only a handful of articles — and a handful can
    /// never supply three same-class siblings, so every question was dropped for
    /// want of options ("Jalen Brunson" reduced to 4 usable articles, 2 of them
    /// people, and produced nothing). A distractor only has to be a plausible wrong
    /// answer of the same kind, so it comes from the whole search result.
    public static List<Question> MakeQuestions(IReadOnlyList<WikipediaClient.Summary> pool, string categoryId, int count, ulong seed,
        bool relaxed = false, IReadOnlyList<WikipediaClient.Summary>? distractors = null)
    {
        var usable = pool.Where(x => IsUsable(x, relaxed)).ToList();
        if (usable.Count < (relaxed ? 1 : 4)) return new();
        var dPool = (distractors ?? pool).Where(x => IsUsable(x, relaxed)).ToList();
        var rng = new SeededRng(seed);
        var subjects = Shuffle(usable, ref rng);
        var questions = new List<Question>();
        int gi = 0;
        foreach (var subject in subjects)
        {
            if (questions.Count >= count) break;
            var q = Build(subject, dPool, categoryId, gi, relaxed, ref rng);
            if (q is not null) questions.Add(q);
            gi++;
        }
        return questions;
    }

    private static Question? Build(WikipediaClient.Summary s, List<WikipediaClient.Summary> pool, string categoryId, int gi, bool relaxed, ref SeededRng rng)
    {
        int n = ShapeRotation.Length;
        bool person = IsPerson(s);
        for (int off = 0; off < n; off++)
        {
            var shape = ShapeRotation[(gi + off) % n];
            var bank = shape == "describe" ? (person ? Stems["describe_person"] : Stems["describe_thing"]) : Stems[shape];
            var stem = bank[(gi / n) % bank.Length];
            var built = Builder(shape, s, pool, stem, relaxed, ref rng);
            if (built is not { } b) continue;
            var (prompt, options, answer) = b;
            if (Leaks(answer, prompt)) continue;                 // answer must not leak into the prompt
            if (prompt.Length > 320 || HasForeignScript(prompt)) continue;
            var opts = Shuffle(options, ref rng);
            var ci = opts.IndexOf(answer);
            if (ci < 0) ci = 0;
            return new Question
            {
                Id = $"live:{shape}:{s.Title}".Replace(" ", "_"),
                Prompt = prompt,
                Options = opts,
                CorrectIndex = ci,
                CategoryId = categoryId,
                Difficulty = Difficulty(s),
                Explanation = CleanClue(FirstSentence(s.Extract ?? s.Description ?? "")),
                SourceTitle = s.Title,
                SourceUrl = s.PageUrl,
                TemplateId = shape,
            };
        }
        return null;
    }

    private static (string, List<string>, string)? Builder(string shape, WikipediaClient.Summary s, List<WikipediaClient.Summary> pool, string stem, bool relaxed, ref SeededRng rng)
    {
        switch (shape)
        {
            case "describe":
            {
                var reframed = Reframe(CleanClue(FirstSentence(s.Extract ?? "")), s.Title);
                if (reframed is not { } c || c.Length < 30 || InformativeTokens(c) < 2) return null;
                var cl = Regex.Replace(c, @"[.\s]+$", "").Trim();
                var ds = TitleDistractors(s, pool, relaxed, ref rng);
                if (ds.Count != 3) return null;
                var ans = DisplayTitle(s.Title);
                var opts = new List<string> { ans };
                opts.AddRange(ds);
                return (Fill(stem, cl), opts, ans);
            }
            case "cloze":
            {
                var sent = CleanClue(FirstSentence(s.Extract ?? ""));
                var bare = DisplayTitle(s.Title);
                string? clozed = null;
                foreach (var needle in new[] { s.Title, bare })
                {
                    if (needle.Length > 0 && sent.IndexOf(needle, System.StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        clozed = ReplaceCaseInsensitive(sent, needle, "_____");
                        break;
                    }
                }
                if (clozed is null) // full birth name differs from title → blank the leading name run
                {
                    var m = LeadRE.Match(sent);
                    if (m.Success) clozed = sent.Substring(0, m.Groups[1].Index) + "_____" + sent.Substring(m.Groups[1].Index + m.Groups[1].Length);
                }
                if (clozed is not { } cz || cz.Length < 30 || InformativeTokens(cz) < 2) return null;
                var ds = TitleDistractors(s, pool, relaxed, ref rng);
                if (ds.Count != 3) return null;
                var opts = new List<string> { bare };
                opts.AddRange(ds);
                return (Fill(stem, cz), opts, bare);
            }
            default: return null;
        }
    }

    private static string Fill(string stem, string value)
    {
        int i = stem.IndexOf("%@", System.StringComparison.Ordinal);
        return i < 0 ? stem : stem.Substring(0, i) + value + stem.Substring(i + 2);
    }

    // MARK: Type / person detection

    private static readonly HashSet<string> Months = Words("january february march april may june july august september october november december");
    private static readonly HashSet<string> TypeNouns = Words("actor actress singer musician composer songwriter rapper band writer author poet novelist playwright journalist artist painter sculptor director filmmaker producer scientist physicist chemist biologist mathematician astronomer economist politician philosopher activist explorer inventor architect dancer comedian footballer player athlete cyclist swimmer boxer golfer film movie television series show novel book album song single painting sculpture poem play opera symphony team club city town country river mountain lake dynasty empire");
    private static readonly HashSet<string> Nationalities = Words("polish french american british english german italian russian japanese chinese spanish dutch canadian australian indian brazilian mexican swedish norwegian danish finnish greek roman egyptian persian turkish irish scottish welsh austrian swiss belgian portuguese hungarian czech romanian korean vietnamese thai argentine chilean colombian peruvian israeli iranian iraqi syrian lebanese moroccan nigerian kenyan ethiopian ukrainian serbian croatian bulgarian icelandic");
    private static readonly HashSet<string> PersonTypeKeys = Words("actor actress musician writer scientist athlete director painter singer composer poet novelist author journalist sculptor architect engineer politician philosopher economist historian activist explorer inventor dancer comedian model conductor pianist guitarist rapper businessman entrepreneur king queen emperor empress monarch president general admiral saint pope sultan tsar duke earl baron knight prince princess priest bishop rabbi imam nun monk lawyer diplomat soldier aristocrat theologian");
    private static readonly HashSet<string> TypeLeading = Words("american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western central ancient modern medieval former national international royal imperial classical contemporary professional famous notable major minor large small great greater lesser old new young senior junior fictional mythological historical traditional popular official public private federal scottish irish welsh dutch swedish norwegian danish polish turkish greek roman egyptian persian arab arabic jewish canadian australian mexican brazilian argentine chilean austrian swiss belgian portuguese finnish hungarian czech romanian indonesian filipino vietnamese thai largest smallest oldest");
    private static readonly HashSet<string> TypeStop = new() { "in", "of", "from", "for", "by", "on", "at", "near", "during", "between", "that", "which", "who", "known", "with", "to", "and", "or", "located", "based", "set" };
    private static readonly Dictionary<string, string> TypeFold = new()
    {
        ["singer"] = "musician", ["songwriter"] = "musician", ["singer-songwriter"] = "musician", ["rapper"] = "musician", ["guitarist"] = "musician", ["pianist"] = "musician", ["drummer"] = "musician", ["bassist"] = "musician", ["vocalist"] = "musician", ["band"] = "musician", ["duo"] = "musician", ["composer"] = "musician",
        ["actress"] = "actor", ["filmmaker"] = "director", ["novelist"] = "writer", ["author"] = "writer", ["poet"] = "writer", ["playwright"] = "writer", ["screenwriter"] = "writer", ["essayist"] = "writer", ["journalist"] = "writer",
        ["physicist"] = "scientist", ["chemist"] = "scientist", ["biologist"] = "scientist", ["mathematician"] = "scientist", ["astronomer"] = "scientist", ["geologist"] = "scientist", ["economist"] = "scientist", ["psychologist"] = "scientist", ["inventor"] = "scientist",
        ["footballer"] = "athlete", ["player"] = "athlete", ["cyclist"] = "athlete", ["swimmer"] = "athlete", ["boxer"] = "athlete", ["wrestler"] = "athlete", ["sprinter"] = "athlete", ["runner"] = "athlete", ["golfer"] = "athlete",
        ["village"] = "settlement", ["town"] = "settlement", ["city"] = "settlement", ["municipality"] = "settlement", ["commune"] = "settlement", ["capital"] = "settlement", ["mountain"] = "peak", ["volcano"] = "peak",
    };
    private static readonly HashSet<string> FunctionWords = new() { "the", "of", "and", "a", "an", "in", "on", "at", "to", "for", "by", "with", "from", "as", "or", "de", "von", "van", "al" };
    private static readonly HashSet<string> CommonWords = Words("empire battle war wars kingdom dynasty republic treaty river mountain mountains lake island islands city town county state states united nation national american english british french german italian spanish russian chinese japanese korean indian european african asian north south east west northern southern eastern western great greater new saint university college school company group band series film movie novel book award club team teams league party system century world people region province district area force army navy air language family order house song album season game games sport sports festival prize federal royal international association federation union organization museum park station bridge building tower palace castle church cathedral temple championship cup first second");
    private static readonly HashSet<string> Abbrev = new() { "lit", "e.g", "i.e", "approx", "no", "vs", "etc", "st", "mt", "mr", "mrs", "ms", "dr", "fl", "ca", "jr", "sr", "col", "gen", "gov", "sen", "rep", "prof", "rev", "inc", "ltd", "co", "u.s", "u.k" };

    private static readonly HashSet<string> ClueGeneric = new HashSet<string>(
        CommonWords.Concat(TypeLeading).Concat(TypeNouns).Concat(Nationalities)
            .Concat(new[] { "this", "the", "a", "an", "was", "is", "were", "are", "best", "known", "famous", "noted", "also", "who", "which", "that", "based", "located", "near", "former" }));

    // The `(?:,[^,]{0,80},)?` clause is an APPOSITIVE between the name and the verb,
    // and without it a large share of Wikipedia leads simply do not parse: "Jalen
    // Marquis Brunson, nicknamed "Captain Clutch", is an American professional
    // basketball player..." failed both shapes, so a topic with four perfectly good
    // usable articles produced nothing.
    private static readonly Regex LeadRE = new(@"^\s*((?:[A-Z][\w’'.\-]*)(?:[ \-]+(?:of|the|and|de|von|van|al|da|di)?\s*[A-Z][\w’'.\-]*)*)\s*(?:\([^)]*\))?\s*(?:,[^,]{0,80},)?\s*(?:was|is|were|are)\s+(?:a|an|the)\s+(.+)$", RegexOptions.Compiled);
    private static readonly Regex ProperRE = new(@"\b[A-Z][A-Za-z’'\-]{2,}\b", RegexOptions.Compiled);
    private static readonly Regex YearRE = new(@"\b(?:1\d{3}|20\d{2})\b", RegexOptions.Compiled);
    private static readonly Regex ParenRE = new(@"\s*\(([^()]*)\)", RegexOptions.Compiled);
    private static readonly Regex BracketRE = new(@"\s*\[([^\[\]]*)\]", RegexOptions.Compiled);

    public static int InformativeTokens(string clue)
    {
        var c = Regex.Replace(clue, @"\([^)]*\)", ""); // strip parentheticals (dates = not quizzable)
        var proper = new HashSet<string>();
        foreach (Match m in ProperRE.Matches(c))
        {
            var w = m.Value.ToLowerInvariant();
            if (!ClueGeneric.Contains(w) && !Months.Contains(w)) proper.Add(w);
        }
        var years = new HashSet<string>();
        foreach (Match m in YearRE.Matches(c)) years.Add(m.Value);
        return proper.Count + years.Count;
    }

    public static bool IsPerson(WikipediaClient.Summary s)
    {
        var k = TypeKey(s);
        if (k is not null && PersonTypeKeys.Contains(k)) return true;
        if (k is not null) return false; // typed as a non-person thing
        return Regex.IsMatch(s.Extract ?? "", @"\(\s*\d{3,4}\s*[–-]|\bborn\b");
    }

    public static string? TypeKey(WikipediaClient.Summary s)
    {
        var d = Regex.Replace(s.Description ?? "", @"\([^)]*\)", "");
        d = (d.Split(',').FirstOrDefault() ?? d).Trim(' ', '.').ToLowerInvariant();
        var toks = new List<string>();
        foreach (var w in Regex.Split(d, @"[^\p{L}\-]+").Where(x => x.Length > 0))
        {
            if (TypeStop.Contains(w)) break;
            toks.Add(w);
        }
        while (toks.Count > 0 && TypeLeading.Contains(toks[0])) toks.RemoveAt(0);
        if (toks.Count == 0) return null;
        var last = toks[^1];
        return TypeFold.TryGetValue(last, out var folded) ? folded : last;
    }

    // MARK: Describe helpers

    private static string? Reframe(string sentence, string title)
    {
        var m = LeadRE.Match(sentence);
        if (!m.Success) return null;
        var rest = m.Groups[2].Value.Trim();
        return BlankName(rest, title);
    }

    private static string BlankName(string text, string title)
    {
        var outp = text;
        var bare = Regex.Replace(title, @"\s*\([^)]*\)", "").Trim();
        foreach (var needle in new HashSet<string> { title, bare })
        {
            if (needle.Length > 0) outp = ReplaceCaseInsensitive(outp, needle, "—————");
        }
        foreach (var w in Regex.Split(bare, @"[^\p{L}'’\-]+").Where(x => x.Length > 0))
        {
            if (w.Length < 3 || FunctionWords.Contains(w.ToLowerInvariant())) continue;
            var pat = @"\b" + Regex.Escape(w) + @"(?:’s|'s|s|es)?\b";
            outp = Regex.Replace(outp, pat, "—————", RegexOptions.IgnoreCase);
        }
        outp = Regex.Replace(outp, @"—————(?:[\s,’'.\–\-]+(?:of|the|and)?\s*—————)+", "—————", RegexOptions.IgnoreCase);
        return Regex.Replace(outp, @"\s{2,}", " ").Trim();
    }

    // MARK: Distractors (typed siblings)

    /// The coarse kind of thing a subject is. Exact TypeKey equality is right when
    /// drawing from a whole corpus, where there are always more footballers. A
    /// Create topic supplies at most 35 articles and they are deliberately
    /// heterogeneous — measured, a topic's usable results split as
    /// `subgenre:1, series:1, internet:1, genre:1`, so three same-type siblings
    /// never existed and every question was dropped for want of distractors.
    private static readonly HashSet<string> WorkTypes = new("film movie series show sitcom season episode album song single novel book poem play opera musical game franchise character comic manga anime documentary".Split(' '));
    private static readonly HashSet<string> PlaceTypes = new("settlement peak country state province region district county island river lake sea ocean desert park building bridge stadium airport museum palace castle".Split(' '));

    public static string CoarseClass(WikipediaClient.Summary s)
    {
        if (IsPerson(s)) return "person";
        var k = TypeKey(s);
        if (k is null) return "thing";
        if (WorkTypes.Contains(k)) return "work";
        if (PlaceTypes.Contains(k)) return "place";
        return "thing";
    }

    private static List<string> TypedDistractors(WikipediaClient.Summary s, List<WikipediaClient.Summary> pool, bool relaxed, ref SeededRng rng,
        System.Func<WikipediaClient.Summary, string?> value, string exclude, int? lengthMatch)
    {
        List<string> Gather(System.Func<WikipediaClient.Summary, bool> matches, ref SeededRng r)
        {
            var seen = new HashSet<string>();
            var cands = new List<(int score, string val)>();
            foreach (var c in pool)
            {
                if (c.Title == s.Title || !matches(c)) continue;
                var v0 = value(c)?.Trim();
                if (string.IsNullOrEmpty(v0) || string.Equals(v0, exclude, System.StringComparison.OrdinalIgnoreCase)) continue;
                if (!seen.Add(v0!.ToLowerInvariant())) continue;
                int score = lengthMatch is { } lm ? -System.Math.Abs(v0.Length - lm) : 0;
                cands.Add((score, v0));
            }
            if (cands.Count < 3) return new();
            var top = cands.OrderByDescending(t => t.score).Take(System.Math.Max(9, 8)).Select(t => t.val).ToList();
            return Shuffle(top, ref r).Take(3).ToList();
        }
        var kt = TypeKey(s);
        if (kt is not null)
        {
            var exact = Gather(c => TypeKey(c) == kt, ref rng);
            if (exact.Count > 0) return exact;
        }
        if (!relaxed) return new();
        var kc = CoarseClass(s);
        return Gather(c => CoarseClass(c) == kc, ref rng);
    }

    private static List<string> TitleDistractors(WikipediaClient.Summary s, List<WikipediaClient.Summary> pool, bool relaxed, ref SeededRng rng) =>
        TypedDistractors(s, pool, relaxed, ref rng, c => DisplayTitle(c.Title), DisplayTitle(s.Title), null);

    // MARK: Clue cleaning

    public static string CleanClue(string text)
    {
        var outp = text; var prev = "";
        while (outp != prev)
        {
            prev = outp;
            foreach (var re in new[] { ParenRE, BracketRE })
                outp = re.Replace(outp, m => ShouldDropParen(m.Groups[1].Value) ? "" : m.Value);
        }
        while (outp.Contains("  ")) outp = outp.Replace("  ", " ");
        return outp.Replace(" ,", ",").Replace(" .", ".").Trim();
    }

    private static bool ShouldDropParen(string inner)
    {
        var t = inner.Trim();
        if (t.Length == 0) return true;
        if (t.Any(ch => ch > 127)) return true;
        var langs = new[] { "romaniz", "pronounc", "ipa", "listen", "lit.", "russian", "greek", "latin", "arabic", "chinese", "japanese", "hebrew", "hindi", "persian", "german", "french", "spanish", "italian", "korean", "portuguese", "turkish", "polish", "dutch", "sanskrit" };
        var lower = t.ToLowerInvariant();
        if (langs.Any(l => lower.Contains(l))) return true;
        var firstChunk = t.Split(';').FirstOrDefault() ?? t;
        var tok = new string((firstChunk.Split(' ').FirstOrDefault() ?? "").Where(char.IsLetter).ToArray());
        if (tok.Length is >= 2 and <= 6 && tok == tok.ToUpperInvariant() && tok != tok.ToLowerInvariant()) return true;
        return false;
    }

    // MARK: Misc helpers

    private static bool HasForeignScript(string s) => s.Any(ch =>
    {
        int n = ch;
        return (n is >= 0x0370 and <= 0x06FF) || (n is >= 0x3040 and <= 0x9FFF)
            || (n is >= 0xAC00 and <= 0xD7AF) || (n is >= 0x2200 and <= 0x22FF) || (n is >= 0x27E8 and <= 0x27EF);
    });

    public static bool Leaks(string answer, string prompt)
    {
        var p = prompt.ToLowerInvariant();
        var toks = Regex.Split(answer.ToLowerInvariant(), @"[^\p{L}]+")
            .Where(w => w.Length >= 4).ToHashSet();
        toks.ExceptWith(CommonWords);
        return toks.Any(t => p.Contains(t));
    }

    private static int Difficulty(WikipediaClient.Summary s)
    {
        var len = s.Extract?.Length ?? 0;
        return len >= 2000 ? 2 : (len >= 1000 ? 3 : 4);
    }

    public static string FirstSentence(string text)
    {
        var t = text.Trim().ToCharArray();
        int depth = 0, i = 0;
        while (i < t.Length)
        {
            var ch = t[i];
            if (ch is '(' or '[') depth++;
            else if (ch is ')' or ']' && depth > 0) depth--;
            else if (ch == '.' && depth == 0 && i + 1 < t.Length && t[i + 1] == ' ')
            {
                int k = i + 1;
                while (k < t.Length && t[k] == ' ') k++;
                char? nxt2 = k < t.Length ? t[k] : null;
                if (nxt2 is null || char.IsUpper(nxt2.Value) || "“”\"'‘’".Contains(nxt2.Value))
                {
                    int j = i - 1;
                    while (j >= 0 && (char.IsLetter(t[j]) || char.IsDigit(t[j]) || t[j] == '.' || t[j] == '\'' || t[j] == '-')) j--;
                    var tok = new string(t, j + 1, i - (j + 1));
                    var letters = tok.Where(char.IsLetter).ToArray();
                    bool hasDigit = tok.Any(char.IsDigit);
                    bool isAbbrev = letters.Length > 0 && !hasDigit && (letters.Length <= 1 || Abbrev.Contains(tok.ToLowerInvariant().Trim('.')));
                    if (!isAbbrev) return new string(t, 0, i + 1);
                }
            }
            i++;
        }
        return new string(t);
    }

    private static string DisplayTitle(string t) => Regex.Replace(t, @"\s*\([^)]*\)", "");

    // Deterministic Fisher-Yates using the shared splitmix64 RNG.
    private static List<T> Shuffle<T>(IReadOnlyList<T> list, ref SeededRng rng)
    {
        var a = list.ToList();
        for (int i = a.Count - 1; i > 0; i--)
        {
            int j = (int)(rng.Next() % (ulong)(i + 1));
            (a[i], a[j]) = (a[j], a[i]);
        }
        return a;
    }

    private static string ReplaceCaseInsensitive(string haystack, string needle, string replacement) =>
        Regex.Replace(haystack, Regex.Escape(needle), replacement.Replace("$", "$$"), RegexOptions.IgnoreCase);

    private static HashSet<string> Words(string spaceSeparated) =>
        spaceSeparated.Split(' ', System.StringSplitOptions.RemoveEmptyEntries).ToHashSet();
}
