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
        var raw = Regex.Split(Fold(topic), @"[^\p{L}\p{N}]+")
                       .Where(t => t.Length >= 3)
                       .ToList();
        var kept = raw.Where(t => !Stopwords.Contains(t)).ToList();
        return kept.Count > 0 ? kept : raw;
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
