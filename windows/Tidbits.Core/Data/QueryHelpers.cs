using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Tidbits.Core.Data;

internal static class QueryHelpers
{
    /// Lowercase + strip diacritics, so "beyonce" finds "Beyoncé". Mirrors the corpus
    /// build's sparse `search_text` column and the Swift/Kotlin/JS `fold` — all must
    /// agree or the same topic returns different questions per platform.
    public static string Fold(string s)
    {
        var d = s.Normalize(NormalizationForm.FormKD);
        var sb = new StringBuilder(d.Length);
        foreach (var ch in d)
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
                sb.Append(ch);
        return sb.ToString().ToLowerInvariant();
    }

    /// Words too common to narrow anything — they made the pre-filter match nearly the
    /// whole corpus, crowding out real hits before ranking. Dropped, not merely
    /// short-filtered: the ≥3 rule kept "the", which matches almost every row, so any
    /// topic containing it ("The Beatles", "The Simpsons") filled the cap with noise.
    private static readonly HashSet<string> Stopwords =
    [
        "the", "and", "for", "with", "from", "that", "this", "his", "her", "its",
        "was", "were", "are", "who", "what", "which", "how", "why", "all", "any",
    ];

    /// Topic → folded tokens (≥3 chars, split on non-alphanumeric, stopwords dropped)
    /// — matches Swift's `fold(topic).split { !isLetter && !isNumber }`. Falls back to
    /// the raw tokens when a topic is nothing but stopwords, so a query is never empty.
    public static List<string> Tokenize(string topic)
    {
        var raw = Flatten(StripParens(topic)).Split(' ')
                       .Where(t => t.Length >= 3)
                       .ToList();
        var kept = raw.Where(t => !Stopwords.Contains(t)).ToList();
        return kept.Count > 0 ? kept : raw;
    }

    /// Word-bounded containment — the single most load-bearing rule in Create.
    /// Plain Contains matched the typed word INSIDE longer words, so "Ansel Adams"
    /// returned Hansel and Gretel, "Harry Kane" returned Spokane, "India" returned
    /// Indianapolis. Mirrors Swift CorpusDatabase.ContainsWord.
    public static bool ContainsWord(string text, string token)
    {
        if (string.IsNullOrEmpty(token)) return false;
        int from = 0;
        while (true)
        {
            int i = text.IndexOf(token, from, StringComparison.Ordinal);
            if (i < 0) return false;
            int end = i + token.Length;
            bool beforeOk = i == 0 || !char.IsLetterOrDigit(text[i - 1]);
            bool afterOk = end == text.Length || !char.IsLetterOrDigit(text[end]);
            if (beforeOk && afterOk) return true;
            from = i + 1;
        }
    }

    /// Does `token` occur in the prompt as ITSELF, rather than as part of someone
    /// else's name? Word-bounded matching is not enough inside prose: "Denver"
    /// matched "...and John Denver", "Michael Jackson" matched a Glenda Jackson
    /// biopic. The tell is the word before it — Capitalized and not itself part of
    /// the typed topic means a different proper name. That second half keeps "John
    /// Lennon and Paul McCartney" matching for "Paul McCartney". A possessive is
    /// still the name ("Jackson's"). Mirrors Swift PromptHasWord.
    public static bool PromptHasWord(string raw, string token, IReadOnlyList<string> topic)
    {
        static string BareOf(string w)
        {
            var b = new string(w.Where(c => char.IsLetterOrDigit(c) || c == '\'' || c == '\u2019').ToArray());
            foreach (var suffix in new[] { "'s", "\u2019s" })
                if (b.EndsWith(suffix, StringComparison.Ordinal)) b = b[..^suffix.Length];
            return Fold(new string(b.Where(char.IsLetterOrDigit).ToArray()));
        }
        var words = raw.Split(new[] { ' ', '\n', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        string? previous = null;
        foreach (var w in words)
        {
            if (BareOf(w) == token)
            {
                if (previous is { Length: > 0 } p && char.IsUpper(p[0])
                    && !topic.Contains(Fold(new string(p.Where(char.IsLetterOrDigit).ToArray()))))
                {
                    previous = w;
                    continue;
                }
                return true;
            }
            previous = w;
        }
        // Hyphenated or punctuated forms ("Denver-based") the split cannot see.
        return ContainsWord(Fold(raw), token) && !words.Any(w => BareOf(w) == token);
    }

    /// A Wikipedia disambiguator is not part of what the player means:
    /// "Backrooms (film)", "Masters of the Universe (2026 film)".
    public static string StripParens(string s)
    {
        var sb = new StringBuilder(s.Length);
        int depth = 0;
        foreach (var c in s)
        {
            if (c is '(' or '[') { depth++; continue; }
            if (c is ')' or ']') { depth = Math.Max(0, depth - 1); continue; }
            if (depth == 0) sb.Append(c);
        }
        return sb.ToString().Trim();
    }

    /// Punctuation flattened to single spaces, nothing dropped — phrase matching
    /// needs the stopwords kept and in order ("masters of the universe"), and needs
    /// the parenthetical kept on ROW titles, where it carries the meaning.
    public static string Flatten(string s) =>
        string.Join(' ', Regex.Split(Fold(s), @"[^\p{L}\p{N}]+").Where(t => t.Length > 0));

    /// The typed topic as a matchable phrase: disambiguator removed, order kept.
    public static string TopicPhrase(string s) => Flatten(StripParens(s));

    /// Is any typed word actually searchable, or is the topic all stopwords?
    public static bool HasSignificantWord(IReadOnlyList<string> tokens) =>
        tokens.Any(t => !Stopwords.Contains(t));

    /// Did the topic lose MEANINGFUL words to the >=3-character rule? "George VI"
    /// reduces to the single token `george`, so every George matched — measured, it
    /// returned George Martin, George Mallory, George Eliot and Paul George; "O. J.
    /// Simpson" reduced to `simpson` and returned Homer and Bart. A regnal numeral
    /// or an initial is short but not insignificant, and the tell is that the phrase
    /// still holds a non-stopword the token list threw away. Does NOT fire for "The
    /// Beatles", where the dropped word is a stopword.
    public static bool PhraseIsRequired(string topic)
    {
        var significant = TopicPhrase(topic).Split(' ')
            .Where(w => w.Length > 0 && !Stopwords.Contains(w)).Count();
        return significant > Tokenize(topic).Count;
    }

    /// Wikipedia categories mean "about" only in their agentive form. "Albums
    /// produced by Michael Jackson" makes a Thriller question an MJ question;
    /// "Actresses from Denver" does not make a Kristin Cavallari birth-year
    /// question a Denver question. Mirrors Swift HasAgentiveTag.
    public static bool HasAgentiveTag(IEnumerable<string> tags, string phrase)
    {
        foreach (var t in tags)
        {
            foreach (var prep in new[] { "by ", "of " })
            {
                int from = 0;
                while (true)
                {
                    int i = t.IndexOf(prep, from, StringComparison.Ordinal);
                    if (i < 0) break;
                    var rest = t[(i + prep.Length)..];
                    if (rest.StartsWith("the ", StringComparison.Ordinal)) rest = rest[4..];
                    if (rest.StartsWith(phrase, StringComparison.Ordinal))
                    {
                        var after = rest[phrase.Length..];
                        if (after.Length == 0 || !char.IsLetterOrDigit(after[0])) return true;
                    }
                    from = i + prep.Length;
                }
            }
        }
        return false;
    }

    /// Relevance TIER, or null to REJECT. A floor, not just a ranking: a topic the
    /// corpus knows nothing about must fall through to live generation rather than
    /// produce eight confident strangers. Mirrors Swift CorpusDatabase.Tier.
    ///
    ///  3 the row's subject IS the topic
    ///  2 the whole typed phrase appears, word-bounded, in the title
    ///  1 every typed word appears, word-bounded, in the title
    ///  0 every typed word appears in the prompt the player reads
    /// -1 an agentive tag only — a real connection the question never shows
    ///
    /// The OPTIONS are deliberately not consulted: that made the topic match as a
    /// DISTRACTOR ("Zlatan Ibrahimovic" returned a picture of Neymar) because the
    /// giveaway rule had already removed every row where it was the right answer.
    public static int? Tier(string title, string prompt, IReadOnlyList<string> tags,
                            IReadOnlyList<string> tokens, string phrase, bool guardNames,
                            bool requirePhrase = false)
    {
        var fTitle = Fold(title);
        var subject = Flatten(title);
        // Identity ignores the disambiguator — "Drake (musician)" IS Drake, and the
        // corpus has no row titled plainly "Drake", so without this the guard never
        // armed and typing "Drake" returned Nick Drake and Drake & Josh.
        if (subject == phrase || Flatten(StripParens(title)) == phrase) return 3;
        if (ContainsWord(subject, phrase))
        {
            // When the typed word is itself a subject here, a bare two-word title
            // that merely contains it is a DIFFERENT named thing: "Bob Denver".
            if (guardNames && subject.Split(' ').Length == 2) return null;
            return 2;
        }
        // A numeral or an initial was dropped as "too short", so the surviving
        // tokens name the wrong thing — only the phrase above could be trusted.
        if (requirePhrase) return ContainsWord(Fold(prompt), phrase) ? 0 : null;
        var need = tokens.Count <= 2 ? tokens.Count : tokens.Count - 1;
        if (tokens.Count(t => ContainsWord(fTitle, t)) >= need) return 1;
        if (tokens.Count(t => ContainsWord(fTitle, t) || PromptHasWord(prompt, t, tokens)) >= need) return 0;
        if (HasAgentiveTag(tags.Select(Fold), phrase)) return -1;
        return null;
    }

    public static List<T> Shuffle<T>(List<T> list)
    {
        for (int i = list.Count - 1; i > 0; i--)
        {
            int j = Random.Shared.Next(i + 1);
            (list[i], list[j]) = (list[j], list[i]);
        }
        return list;
    }
}
