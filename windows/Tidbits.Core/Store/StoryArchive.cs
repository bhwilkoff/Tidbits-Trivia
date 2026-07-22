using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// The Club Story Archive's read side (docs/CLUB-FEATURES-BUILD.md "Feature 2") — a
/// plain, transparent view over `RecordsStore.Seen`. No ranking model: search is
/// substring match, filters are simple predicates — exactly like Weak-Spot's reason
/// strings stayed honest about their own make-up. Pure, UI-agnostic, unit-testable
/// off Windows; mirrors Apple's `StoryArchive.swift` / Android's `StoryArchive.kt`.
public static class StoryArchive
{
    /// A genuine one-line sample from the player's own archive for the non-member
    /// preview (MONETIZATION §4a: "a real preview, never a nag") — the most recently
    /// met story. Null once the player has no history yet.
    public static string? PreviewLine(RecordsStore records)
    {
        var top = records.Seen.FirstOrDefault(); // already most-recent-first
        if (top is null) return null;
        return $"“{top.Story}” — Club keeps every story you unlock, searchable forever.";
    }

    /// Total distinct stories collected — the member-facing subtitle.
    public static int Count(RecordsStore records) => records.Seen.Count;

    /// Transparent client-side search + filter over an already most-recent-first
    /// list — no opaque model, just what's on the card.
    public static List<SeenStory> Search(IReadOnlyList<SeenStory> stories, string text, string? domain, StoryFilter filter)
    {
        IEnumerable<SeenStory> results = stories;
        if (domain is not null) results = results.Where(s => s.CategoryId == domain);
        results = filter switch
        {
            StoryFilter.Favorites => results.Where(s => s.Favorite),
            StoryFilter.Missed => results.Where(s => !s.EverCorrect),
            StoryFilter.Mastered => results.Where(s => s.EverCorrect),
            _ => results,
        };

        var q = text.Trim();
        if (q.Length == 0) return results.ToList();
        return results.Where(s =>
            s.Prompt.Contains(q, StringComparison.OrdinalIgnoreCase) ||
            s.CorrectAnswer.Contains(q, StringComparison.OrdinalIgnoreCase) ||
            s.Story.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
    }
}

/// The archive's plain filter set (favorited / missed / mastered), alongside domain +
/// free-text search.
public enum StoryFilter { All, Favorites, Missed, Mastered }

public static class StoryFilterExtensions
{
    public static string Label(this StoryFilter f) => f switch
    {
        StoryFilter.All => "All",
        StoryFilter.Favorites => "Favorites",
        StoryFilter.Missed => "Missed",
        StoryFilter.Mastered => "Got it",
        _ => "All",
    };
}
