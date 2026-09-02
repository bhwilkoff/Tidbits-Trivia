using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// G4 — the first-letter round, pub trivia's most common themed format and
/// SpeedQuizzing's "First Letter of the Answer": the host announces a letter and
/// EVERY answer in the round begins with it.
///
/// The C# mirror of Swift `LiveLetterRound`. Six stacks have to agree on which
/// answers count as a "B" — a Windows host and a Mac host reading the same event
/// file must theme it identically — so the rule is written once per stack and
/// pinned by the same cases on both.
public static class LiveLetterRound
{
    /// Leading articles do not count. A pub quiz that announces "B" accepts
    /// "The Beatles", and a host who has to explain otherwise has lost the room.
    private static readonly HashSet<string> Articles =
        new(StringComparer.OrdinalIgnoreCase) { "the", "a", "an" };

    /// The letter an answer counts as, or null when it has no letter to offer
    /// (a number, a symbol, an empty string) and so can never belong to a round.
    ///
    /// Diacritics fold: "Edith Piaf" spelled with an accent is still an E, because
    /// the host says E and the room writes E.
    public static char? Initial(string? answer)
    {
        if (string.IsNullOrWhiteSpace(answer)) return null;
        var words = answer.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var i = 0;
        // Drop leading articles, but never ALL the words: an answer that is only
        // the word "The" still has to resolve to T rather than to nothing.
        while (i < words.Length - 1 && Articles.Contains(words[i])) i++;
        // The first LETTER, not the first character: "'Round Midnight" is an R and
        // "2001" is not any letter at all.
        foreach (var ch in words[i].Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            if (char.IsLetter(ch)) return char.ToUpperInvariant(ch);
        }
        return null;
    }

    /// Whether a question may sit in a round themed on <paramref name="letter"/>.
    public static bool Matches(Question q, char letter)
    {
        var want = Initial(letter.ToString());
        return want != null && Initial(q.CorrectAnswer) == want;
    }

    /// The questions in a round that BREAK its letter theme. The builder SHOWS
    /// these rather than refusing the edit: a host mid-build has a half-built
    /// round, and a format that fights them is a format they abandon.
    public static IReadOnlyList<Question> Violations(IEnumerable<Question> questions, char letter) =>
        questions.Where(q => !Matches(q, letter)).ToList();

    /// Questions from the pool that fit the letter, in pool order, capped at
    /// <paramref name="limit"/>. A repeated ANSWER is dropped: a round that asks
    /// for the same answer twice reads as a mistake even when both are fair.
    public static IReadOnlyList<Question> Candidates(IEnumerable<Question> pool, char letter, int limit)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var outp = new List<Question>();
        foreach (var q in pool)
        {
            if (!Matches(q, letter)) continue;
            if (!seen.Add(q.CorrectAnswer)) continue;
            outp.Add(q);
            if (outp.Count == limit) break;
        }
        return outp;
    }

    /// How many questions the pool could supply for each letter — what the builder
    /// needs to grey out the letters it cannot fill.
    public static IReadOnlyDictionary<char, int> Availability(IEnumerable<Question> pool)
    {
        var counts = new Dictionary<char, int>();
        foreach (var q in pool)
        {
            var c = Initial(q.CorrectAnswer);
            if (c is char ch) counts[ch] = counts.TryGetValue(ch, out var n) ? n + 1 : 1;
        }
        return counts;
    }

    /// The line the room reads off the big screen.
    public static string Banner(char letter) =>
        $"EVERY ANSWER BEGINS WITH {char.ToUpperInvariant(letter)}";
}
