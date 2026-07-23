namespace Tidbits.Core.Models;

/// One of a day's 4 hidden groups (Club Feature 6, docs/CLUB-FEATURES-BUILD.md
/// "Feature 6 — Link Wall"). Windows mirror of Apple's `LinkWall.LinkWallGroup`
/// (Core/Store/LinkWall.swift) / Android's `LinkWall.LinkWallGroup`.
public sealed record LinkWallGroup(
    string Label,                    // the theme, e.g. "World Capitals"
    string Why,                      // cited "key → value" pairs from the corpus source
    IReadOnlyList<string> Members,   // exactly 4
    int Difficulty);                 // 1 (yellow, easiest) ... 4 (purple, hardest)

/// The deterministic daily puzzle: 16 tiles hiding 4 groups of 4. Windows mirror of
/// Apple's `LinkWall.LinkWallPuzzle` / Android's `LinkWall.LinkWallPuzzle`.
public sealed record LinkWallPuzzle(
    string Day,
    IReadOnlyList<LinkWallGroup> Groups,   // exactly 4, ascending difficulty
    IReadOnlyList<string> Tiles);          // the 16 members, shuffled for display

/// Persisted outcome of one day's Link Wall — JSON-file-backed via `RecordsStore`,
/// keyed by day in a dictionary (several days can sit in progress/completed at once,
/// unlike Marathon's single in-progress slot — mirrors `ExpeditionProgress`'s per-key
/// dictionary shape). Windows mirror of Apple's SwiftData `LinkWallResult` /
/// Android's `LinkWall.LinkWallResult` / web's `tidbits.linkwall[day]` row. Reopening
/// an in-progress OR completed day resumes THIS row, never a fresh board.
public sealed class LinkWallResult
{
    public string Day { get; set; } = "";
    public int Mistakes { get; set; }
    public bool Completed { get; set; }
    public bool Won { get; set; }
    public DateTime Date { get; set; } = DateTime.UtcNow;

    /// One row per guess, IN ORDER, each the 4 tapped tiles' TRUE group difficulty
    /// (1 yellow ... 4 purple) at guess time — exactly what the share grid renders,
    /// independent of whether the guess was correct (a wrong guess still gets a row).
    public List<List<int>> GuessHistory { get; set; } = new();

    /// The solved group labels, in SOLVE order (a player can clear purple before
    /// yellow) — drives the collapsed-row order and which groups still remain.
    public List<string> SolvedLabels { get; set; } = new();

    /// Appends one guess row, correct or not — called immediately on every submit so
    /// a crash/quit never loses progress (same discipline as `Marathon.Record`).
    public void RecordGuess(IReadOnlyList<int> difficulties) => GuessHistory.Add(difficulties.ToList());

    public void RecordSolvedGroup(string label)
    {
        if (!SolvedLabels.Contains(label)) SolvedLabels.Add(label);
    }
}
