using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// An authored Tidbits Live event — a named sequence of rounds the host builds
/// ahead of time (vs the fixed NightPlan presets). Rounds reuse NightRound
/// (kind + count) so an event converts straight to a NightPlan for the host.
public sealed record LiveEvent
{
    [JsonPropertyName("id")] public string Id { get; init; } = Guid.NewGuid().ToString("N");
    [JsonPropertyName("name")] public string Name { get; init; } = "Trivia Night";
    [JsonPropertyName("rounds")] public IReadOnlyList<NightRound> Rounds { get; init; } = new List<NightRound>();
    [JsonPropertyName("sponsor")] public string? Sponsor { get; init; }   // Wave D sponsor kit
    [JsonPropertyName("brandHex")] public string? BrandHex { get; init; } // Wave D white-label accent
    [JsonPropertyName("leadCaptureURL")] public string? LeadCaptureUrl { get; init; } // Wave D lead capture
    [JsonPropertyName("weekday")] public int? Weekday { get; init; } // Wave D recurring (0=Sun..6=Sat), null = one-off
    [JsonPropertyName("wagerFinal")] public bool WagerFinalRound { get; init; } // Wave A final wager round
    [JsonPropertyName("roundNotes")] public IReadOnlyList<string> RoundNotes { get; init; } = new List<string>(); // Wave A per-round host notes (index-aligned)
    // Wave A per-round countdown, index-aligned, 0 = untimed. Deliberately on the EVENT and
    // not on NightRound: NightRound is the wire type serialized to every joiner, Apple pins
    // its CodingKeys to {kind, count}, and there is golden coverage on it. The timer is a
    // host authoring concern — joiners already learn the deadline from the published pub.
    [JsonPropertyName("roundTimers")] public IReadOnlyList<int> RoundTimers { get; init; } = new List<int>();
    // Wave-premier: the AUTHORED questions of each round, index-aligned with Rounds.
    // An empty inner list means "pull this round from the corpus at host time", which
    // is what every round did before — so old saved events decode unchanged.
    //
    // Until this existed a Windows round was {kind, count} and nothing more, which is
    // precisely why the host could not edit or add a single question: there were no
    // questions in the model to open (WINDOWS-DESIGN §6.6).
    [JsonPropertyName("roundQuestions")]
    public IReadOnlyList<IReadOnlyList<Question>> RoundQuestions { get; init; } = new List<IReadOnlyList<Question>>();

    // Wave-premier: the media clip attached to each authored question, index-aligned
    // with RoundQuestions. Plain paths, not macOS's security-scoped bookmarks —
    // Windows has no sandbox scope to preserve, so a path IS the reference.
    //
    // Deliberately NOT part of the portable event document (LIVE-EVENT-FILE §3.1):
    // a Windows path means nothing on the host's Mac, and writing one anyway makes
    // a round look complete and play silent.
    [JsonPropertyName("roundClips")]
    public IReadOnlyList<IReadOnlyList<string>> RoundClips { get; init; } = new List<IReadOnlyList<string>>();

    /// The clip for question `q` of round `i`, or null when there is none.
    public string? ClipFor(int i, int q)
    {
        if (i < 0 || i >= RoundClips.Count) return null;
        var clips = RoundClips[i];
        if (q < 0 || q >= clips.Count) return null;
        return string.IsNullOrWhiteSpace(clips[q]) ? null : clips[q];
    }

    /// Does this round carry clips at all? Drives whether the cockpit offers the
    /// per-question play control for it.
    public bool RoundHasClips(int i) =>
        i >= 0 && i < RoundClips.Count && RoundClips[i].Any(c => !string.IsNullOrWhiteSpace(c));

    /// The authored questions of round `i`, or an empty list when that round is still
    /// corpus-sourced.
    public IReadOnlyList<Question> QuestionsFor(int i) =>
        i >= 0 && i < RoundQuestions.Count ? RoundQuestions[i] : [];

    /// True when EVERY round carries its own questions, so the night needs no corpus pull.
    [JsonIgnore] public bool IsFullyAuthored =>
        Rounds.Count > 0 && Enumerable.Range(0, Rounds.Count).All(i => QuestionsFor(i).Count > 0);

    /// A copy with round `i`'s questions replaced, keeping `NightRound.Count` in step —
    /// the round's length IS its count (LIVE-EVENT-FILE §2.5); letting the two disagree
    /// would build a night that asks for more questions than the host authored.
    public LiveEvent WithQuestions(int i, IReadOnlyList<Question> questions)
    {
        if (i < 0 || i >= Rounds.Count) return this;
        var rq = Enumerable.Range(0, Rounds.Count)
                           .Select(k => k == i ? questions : QuestionsFor(k))
                           .ToList();
        var rounds = Rounds.Select((r, k) => k == i && questions.Count > 0
                                       ? r with { Count = questions.Count } : r).ToList();
        // The clip list must stay the same length as the question list, or clip N
        // slides onto question N+1 the first time a host deletes one.
        var rc = Enumerable.Range(0, Rounds.Count).Select(k =>
        {
            var existing = k < RoundClips.Count ? RoundClips[k].ToList() : new List<string>();
            if (k != i) return (IReadOnlyList<string>)existing;
            while (existing.Count < questions.Count) existing.Add("");
            return (IReadOnlyList<string>)existing.Take(questions.Count).ToList();
        }).ToList();
        return this with { Rounds = rounds, RoundQuestions = rq, RoundClips = rc };
    }

    [JsonIgnore] public int TotalQuestions => Rounds.Sum(r => r.Count);
    [JsonIgnore] public bool IsRecurring => Weekday is >= 0 and <= 6;
    [JsonIgnore] public string Summary =>
        $"{Rounds.Count} round{(Rounds.Count == 1 ? "" : "s")} · {TotalQuestions} questions";

    /// "Every Monday · next Jul 14" for a recurring event, else "" (needs `now`
    /// passed so it's deterministic/testable).
    public string ScheduleLine(DateTime now) =>
        IsRecurring ? RecurringSchedule.Display((DayOfWeek)Weekday!.Value, now) : "";

    public NightPlan ToPlan() => new() { Rounds = Rounds.ToList() };
}

/// Recurring-series date math (Wave D). Pure so it can be unit-tested.
public static class RecurringSchedule
{
    /// The next date (today counts) that falls on `weekday`, on/after `from`.
    public static DateTime NextOccurrence(DayOfWeek weekday, DateTime from)
    {
        int delta = ((int)weekday - (int)from.DayOfWeek + 7) % 7; // 0 = today
        return from.Date.AddDays(delta);
    }

    public static string Display(DayOfWeek weekday, DateTime from) =>
        $"Every {weekday} · next {NextOccurrence(weekday, from):MMM d}";
}

/// Persisted authored events (host-side). JSON-file-backed, newest-first.
public sealed class LiveEventStore
{
    private readonly string _path;
    private List<LiveEvent> _events = new();

    public LiveEventStore(string path)
    {
        _path = path;
        try
        {
            if (System.IO.File.Exists(path))
                _events = JsonSerializer.Deserialize<List<LiveEvent>>(System.IO.File.ReadAllText(path)) ?? new();
        }
        catch { _events = new(); }
    }

    public IReadOnlyList<LiveEvent> All => _events;

    public LiveEvent Save(LiveEvent ev)
    {
        _events.RemoveAll(e => e.Id == ev.Id);   // upsert
        _events.Insert(0, ev);
        Persist();
        return ev;
    }

    public void Remove(string id)
    {
        _events.RemoveAll(e => e.Id == id);
        Persist();
    }

    private void Persist()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_path, JsonSerializer.Serialize(_events));
        }
        catch { /* best-effort */ }
    }
}
