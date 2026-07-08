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
