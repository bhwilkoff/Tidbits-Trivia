namespace Tidbits.Core.Models;

/// One question's outcome inside a Marathon run — enough to rebuild the domain
/// scorecard without re-fetching the corpus (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3"). Captured at answer-time, same spirit as `AnswerDetail`. Windows
/// mirror of Apple's `MarathonAnswerRecord` / Android's `MarathonAnswerRecord`.
public sealed class MarathonAnswerRecord
{
    public string QuestionId { get; set; } = "";
    public string CategoryId { get; set; } = "";
    public int Difficulty { get; set; }
    public bool Correct { get; set; }
}

/// The AT-MOST-ONE in-progress Marathon run — the load-bearing new mechanic
/// (resume across sessions). A fixed, ordered question-id list is drawn once
/// (deterministic from `Seed`, mirroring `DailyPick`'s rank-and-slice) so a
/// resume always continues into the SAME set. Persisted after every single
/// answer (`Marathon.Record`) so a crash/quit never loses progress. Held as a
/// single nullable slot in `RecordsStore` (no fetch-by-type needed, unlike
/// SwiftData's `MarathonRun?` query).
public sealed class MarathonRun
{
    public string Seed { get; set; } = "";
    public List<string> QuestionIds { get; set; } = new();
    /// How many of `QuestionIds` have been answered so far (across every session).
    public int CurrentIndex { get; set; }
    public List<MarathonAnswerRecord> Results { get; set; } = new();
    public DateTime StartedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastPlayedAt { get; set; } = DateTime.UtcNow;

    public int Total => QuestionIds.Count;

    public MarathonRun() { }

    public MarathonRun(string seed, IReadOnlyList<string> questionIds, DateTime? date = null)
    {
        Seed = seed;
        QuestionIds = questionIds.ToList();
        var now = date ?? DateTime.UtcNow;
        StartedAt = now;
        LastPlayedAt = now;
    }

    /// Append one answer and advance — called once per submitted answer so
    /// progress survives a crash/quit mid-run (the whole point of Marathon).
    public void Append(MarathonAnswerRecord record, DateTime? date = null)
    {
        Results.Add(record);
        CurrentIndex = Results.Count;
        LastPlayedAt = date ?? DateTime.UtcNow;
    }
}

/// One domain's tally inside a completed Marathon — the scorecard's per-row
/// unit (mirrors `DomainProgress` but scoped to a single run, not lifetime).
public sealed record MarathonDomainStat(string CategoryId, int Correct, int Total)
{
    public double Accuracy => Total == 0 ? 0 : (double)Correct / Total;
}

/// A completed Marathon — permanent history (docs/CLUB-FEATURES-BUILD.md
/// "Feature 3"). The scorecard reads straight off this: score, correct/total,
/// and the per-domain breakdown, plus how it compares to the player's other runs.
public sealed class MarathonScore
{
    public DateTime Date { get; set; } = DateTime.UtcNow;
    public int Score { get; set; }
    public int Correct { get; set; }
    public int Total { get; set; }
    public double DurationSeconds { get; set; }
    public List<MarathonDomainStat> DomainBreakdown { get; set; } = new();

    public double Accuracy => Total == 0 ? 0 : (double)Correct / Total;
}
