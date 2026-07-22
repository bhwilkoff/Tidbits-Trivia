using Tidbits.Core.Data;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

/// Builds the Tidbits Club EXCLUSIVE Weak-Spot Arena round entirely from the player's
/// own miss history (`RecordsStore.Missed`) — the deeper layer above the free
/// spaced-review weave (`RecordsStore.DueReview`, PARITY row 214). Transparent by
/// construction: every question carries a plain-language "why you're seeing this"
/// reason, never an opaque model (docs/CLUB-FEATURES-BUILD.md "Feature 1"). Windows
/// mirror of Apple's `WeakSpotArena.swift` / Android's `WeakSpotArena.kt` — pure,
/// UI-agnostic, unit-testable off Windows.
public static class WeakSpotArena
{
    public const int RoundSize = 10;
    /// Below this many true misses, the round is topped up from weak categories.
    public const int TrueMissFloor = 4;
    /// Target size when topping up with category-fill (not the full 10 — a round
    /// mostly "shoring up X" stops being a *weak-spot* arena).
    public const int FillTarget = 8;
    /// Below this many built questions, the caller shows the empty state instead of
    /// starting a round (mirrors iOS/web/Android's ">= 2" floor).
    public const int PlayableFloor = 2;

    /// Build one round. Never throws; a thin history just yields a short (possibly
    /// empty) round — the caller shows the "play a few rounds first" empty state
    /// below `PlayableFloor`.
    public static WeakSpotRound Build(RecordsStore records, CorpusDatabase corpus)
    {
        var questions = new List<Question>();
        var reasons = new Dictionary<string, string>();
        var pickedIds = new HashSet<string>();

        var misses = records.Missed.Where(m => !m.Resolved)
            .OrderByDescending(m => m.MissCount).ThenBy(m => m.LastSeen);

        foreach (var m in misses)
        {
            if (questions.Count >= RoundSize) break;
            if (pickedIds.Contains(m.QuestionId)) continue;
            if (m.Question is not { } q) continue;
            questions.Add(q);
            pickedIds.Add(q.Id);
            reasons[q.Id] = $"Missed {Relative(m.LastSeen)} · ×{m.MissCount}";
        }
        var trueMissCount = questions.Count;

        if (trueMissCount < TrueMissFloor)
        {
            var rows = records.Games.Select(g => (g.CategoryId, g.Correct, g.Total));
            var weakest = DomainProgress.Summarize(rows)
                .Where(d => d.Total >= 3)
                .OrderBy(d => d.Accuracy);
            foreach (var domain in weakest)
            {
                if (questions.Count >= FillTarget) break;
                var pool = corpus.Questions(domain.CategoryId, pickedIds, FillTarget - questions.Count);
                foreach (var q in pool)
                {
                    if (questions.Count >= FillTarget) break;
                    if (!pickedIds.Add(q.Id)) continue;
                    questions.Add(q);
                    reasons[q.Id] = $"Shoring up {TriviaCategory.Named(domain.CategoryId).Name}";
                }
            }
        }

        return new WeakSpotRound(questions, reasons, trueMissCount);
    }

    /// A genuine one-line sample from the player's own misses (MONETIZATION §4a: "a
    /// real preview, never a nag") — the non-member Home-card pitch. Null once there's
    /// no local miss to show (an honest static line covers that case in the caller).
    public static string? PreviewLine(RecordsStore records)
    {
        var top = records.Missed.Where(m => !m.Resolved)
            .OrderByDescending(m => m.MissCount).ThenBy(m => m.LastSeen).FirstOrDefault();
        if (top is null) return null;
        return $"Missed: “{top.Prompt}” — Club turns misses like this into a round.";
    }

    private static string Relative(DateTime lastSeen)
    {
        var span = DateTime.UtcNow - lastSeen;
        if (span.TotalSeconds < 90) return "just now";
        if (span.TotalMinutes < 60) return $"{Math.Max(1, (int)span.TotalMinutes)} min ago";
        if (span.TotalHours < 24) return $"{(int)span.TotalHours} hr ago";
        if (span.TotalDays < 7) return $"{(int)span.TotalDays} days ago";
        if (span.TotalDays < 30) return $"{(int)(span.TotalDays / 7)} wk ago";
        if (span.TotalDays < 365) return $"{(int)(span.TotalDays / 30)} mo ago";
        return $"{(int)(span.TotalDays / 365)} yr ago";
    }
}

/// One generated Weak-Spot round: the questions, a why-you're-seeing-this reason per
/// question ID, and how many are true misses (vs. category-fill) — the count the round
/// stays honest about its make-up with.
public sealed record WeakSpotRound(IReadOnlyList<Question> Questions, IReadOnlyDictionary<string, string> Reasons, int MissCount);
