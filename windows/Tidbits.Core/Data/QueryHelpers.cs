using System.Text.RegularExpressions;

namespace Tidbits.Core.Data;

internal static class QueryHelpers
{
    /// Topic → tokens (lowercased, ≥3 chars, split on non-alphanumeric) — matches
    /// Swift's `split { !isLetter && !isNumber }.filter { count >= 3 }`.
    public static List<string> Tokenize(string topic) =>
        Regex.Split(topic.ToLowerInvariant(), @"[^\p{L}\p{N}]+")
             .Where(t => t.Length >= 3)
             .ToList();

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
