using System;
using System.Collections.Generic;
using System.Linq;

namespace Tidbits.Core.Networking;

/// What a joiner keeps of a live night so the wrap can teach (LIVE-ROOM-CONTRACT
/// "answer + difficulty", 2026-09-09): one entry per revealed question, with the
/// score before it was asked and after it was scored. "Nailed" is decided by the
/// SCORE, not by re-deriving the answer — the host is the scorer, and a typed
/// answer accepted by hand still counts. Mirrors Swift LiveRecapBook.
public sealed class LiveRecapEntry
{
    public required string Qid { get; init; }
    public required string Prompt { get; init; }
    public string? Answer { get; init; }
    public int? Difficulty { get; init; }
    public string? Story { get; init; }
    public string? SourceTitle { get; init; }
    public string? SourceUrl { get; init; }
    public int Before { get; init; }
    public int? After { get; set; }
    public bool Nailed => (After ?? Before) > Before;
    public bool Tough => Nailed && (Difficulty ?? 0) >= 4;
}

public sealed class LiveRecapBook
{
    private readonly List<LiveRecapEntry> _entries = new();
    private string? _openQid;
    private int _scoreAtQuestion;

    public IReadOnlyList<LiveRecapEntry> Entries => _entries;

    /// A pub arrived; `score` is the joiner's score right now.
    public void Observe(LiveRoom.Pub? p, int score)
    {
        if (p is null) return;
        if (p.Qid != _openQid) { Close(score); _openQid = p.Qid; _scoreAtQuestion = score; }
        if (p.Phase == LiveRoom.Phase.Reveal && !_entries.Any(e => e.Qid == p.Qid))
        {
            _entries.Add(new LiveRecapEntry
            {
                Qid = p.Qid, Prompt = p.Prompt, Answer = p.Answer, Difficulty = p.Difficulty, Story = p.Story,
                SourceTitle = p.Source?.Title, SourceUrl = p.Source?.Url, Before = _scoreAtQuestion,
            });
        }
    }

    /// The night ended, or a score landed at the wrap: settle the last question.
    public void Finish(int score)
    {
        Close(score);
        var last = _entries.LastOrDefault();
        if (last is not null) last.After = Math.Max(last.After ?? score, score);   // a late score write belongs to the last question
    }

    private void Close(int score)
    {
        var e = _entries.FirstOrDefault(x => x.Qid == _openQid && x.After is null);
        if (e is not null) e.After = score;
    }

    public IReadOnlyList<LiveRecapEntry> Tough => _entries.Where(e => e.Tough).ToList();
    public IReadOnlyList<LiveRecapEntry> ToRemember => _entries.Where(e => !e.Nailed && !string.IsNullOrEmpty(e.Answer)).ToList();

    public static string HowDidYouKnowText(LiveRecapEntry e) =>
        $"I knew \"{e.Prompt}\" at trivia night — it's {e.Answer ?? ""}. How did YOU know that? \U0001F9E0";
}
