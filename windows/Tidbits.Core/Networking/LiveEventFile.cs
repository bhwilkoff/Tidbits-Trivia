using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// The portable Tidbits Live event document — `docs/LIVE-EVENT-FILE.md`.
///
/// This is NOT `LiveEvent`'s own serialization. The two platforms' internal
/// models differ (macOS keeps `{title, format, categoryID, questions}` per
/// round; Windows keeps `NightRound {kind, count}` plus index-aligned side
/// arrays, because `NightRound` is the wire type published to every joiner and
/// Apple pins its CodingKeys to `{kind, count}` with golden coverage on it).
/// Exporting either internal shape would produce a file the other side cannot
/// read and would bake one platform's storage decisions into a user's document,
/// so both write this contract instead.
public static class LiveEventFile
{
    public const string FormatIdentifier = "com.learningischange.tidbits.live-event";
    public const int FormatVersion = 1;

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public sealed record Document
    {
        [JsonPropertyName("format")] public string Format { get; init; } = FormatIdentifier;
        [JsonPropertyName("version")] public int Version { get; init; } = FormatVersion;
        [JsonPropertyName("exportedAt")] public DateTimeOffset ExportedAt { get; init; } = DateTimeOffset.UtcNow;
        [JsonPropertyName("app")] public string App { get; init; } = "Tidbits Trivia (Windows)";
        [JsonPropertyName("droppedClipCount")] public int DroppedClipCount { get; init; }
        [JsonPropertyName("event")] public required PortableEvent Event { get; init; }
    }

    public sealed record PortableEvent
    {
        [JsonPropertyName("id")] public string Id { get; init; } = "";
        [JsonPropertyName("name")] public string Name { get; init; } = "Trivia Night";
        [JsonPropertyName("venue")] public string Venue { get; init; } = "";
        [JsonPropertyName("createdAt")] public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
        [JsonPropertyName("sponsor")] public string Sponsor { get; init; } = "";
        [JsonPropertyName("leadCaptureURL")] public string LeadCaptureUrl { get; init; } = "";
        [JsonPropertyName("brandHex")] public string BrandHex { get; init; } = "";
        [JsonPropertyName("weekday")] public int? Weekday { get; init; }
        [JsonPropertyName("rounds")] public IReadOnlyList<PortableRound> Rounds { get; init; } = [];
    }

    public sealed record PortableRound
    {
        [JsonPropertyName("id")] public string Id { get; init; } = Guid.NewGuid().ToString("N");
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("format")] public string Format { get; init; } = "classic";
        [JsonPropertyName("categoryID")] public string CategoryId { get; init; } = "mixed";
        [JsonPropertyName("timerSeconds")] public int? TimerSeconds { get; init; }
        [JsonPropertyName("hostNote")] public string? HostNote { get; init; }
        [JsonPropertyName("isWager")] public bool? IsWager { get; init; }
        [JsonPropertyName("isSpeed")] public bool? IsSpeed { get; init; }
        [JsonPropertyName("questions")] public IReadOnlyList<Question> Questions { get; init; } = [];
    }

    public sealed class FileFormatException(string message) : Exception(message);

    public static string SuggestedFileName(LiveEvent ev)
    {
        var name = string.IsNullOrWhiteSpace(ev.Name) ? "Tidbits Event" : ev.Name.Trim();
        foreach (var c in System.IO.Path.GetInvalidFileNameChars()) name = name.Replace(c, '-');
        return name + ".tidbitsevent.json";
    }

    // ---------------------------------------------------------------- export

    public static string Encode(LiveEvent ev, string venue = "")
    {
        var rounds = new List<PortableRound>();
        for (int i = 0; i < ev.Rounds.Count; i++)
        {
            var r = ev.Rounds[i];
            var qs = ev.QuestionsFor(i);
            rounds.Add(new PortableRound
            {
                Title = r.Title,
                Format = r.Kind.Id(),
                // A Windows round has no per-round category — the night picks one —
                // so the questions' own category is the honest answer, and "mixed"
                // when the round has not been authored yet.
                CategoryId = qs.Count > 0 ? MajorityCategory(qs) : "mixed",
                TimerSeconds = i < ev.RoundTimers.Count && ev.RoundTimers[i] > 0 ? ev.RoundTimers[i] : null,
                HostNote = i < ev.RoundNotes.Count && !string.IsNullOrWhiteSpace(ev.RoundNotes[i])
                    ? ev.RoundNotes[i] : null,
                // WagerFinalRound is a single flag on the event; it means the LAST round.
                IsWager = ev.WagerFinalRound && i == ev.Rounds.Count - 1 ? true : null,
                Questions = qs,
            });
        }
        var doc = new Document
        {
            // Windows never held a security-scoped bookmark, so nothing is dropped
            // here yet. The field is still written so a Mac reader sees a real 0
            // rather than a missing key it has to guess about.
            DroppedClipCount = 0,
            Event = new PortableEvent
            {
                Id = ev.Id,
                Name = ev.Name,
                Venue = venue,
                Sponsor = ev.Sponsor ?? "",
                LeadCaptureUrl = ev.LeadCaptureUrl ?? "",
                BrandHex = ev.BrandHex ?? "",
                Weekday = ev.Weekday,
                Rounds = rounds,
            },
        };
        return JsonSerializer.Serialize(doc, Options);
    }

    private static string MajorityCategory(IReadOnlyList<Question> qs) =>
        qs.GroupBy(q => q.CategoryId).OrderByDescending(g => g.Count()).First().Key;

    // ---------------------------------------------------------------- import

    public static LiveEvent Decode(string json)
    {
        Document? doc;
        try { doc = JsonSerializer.Deserialize<Document>(json); }
        catch (JsonException e) { throw new FileFormatException($"That file is not valid JSON. ({e.Message})"); }

        if (doc is null || doc.Format != FormatIdentifier)
            throw new FileFormatException("That file is not a Tidbits Live event.");
        if (doc.Version > FormatVersion)
            throw new FileFormatException(
                $"That event was saved by a newer version of Tidbits (format {doc.Version}). Update Tidbits to open it.");

        var ev = doc.Event;
        var rounds = new List<NightRound>();
        var questions = new List<IReadOnlyList<Question>>();
        var notes = new List<string>();
        var timers = new List<int>();
        bool wagerFinal = false;

        for (int i = 0; i < ev.Rounds.Count; i++)
        {
            var r = ev.Rounds[i];
            // §2.5: the round's LENGTH is its count. A `count` read from the file
            // could disagree with the questions actually present and would build a
            // night asking for more than the host authored.
            rounds.Add(new NightRound { Kind = GameModeExtensions.FromId(r.Format) ?? GameMode.Classic, Count = r.Questions.Count });
            questions.Add(r.Questions);
            notes.Add(r.HostNote ?? "");
            timers.Add(r.TimerSeconds ?? 0);
            if (r.IsWager == true && i == ev.Rounds.Count - 1) wagerFinal = true;
        }

        return new LiveEvent
        {
            // §2.3: a NEW id, so importing a co-host's copy adds a night instead of
            // silently overwriting one you already have.
            Id = Guid.NewGuid().ToString("N"),
            Name = ev.Name,
            Rounds = rounds,
            RoundQuestions = questions,
            RoundNotes = notes,
            RoundTimers = timers,
            WagerFinalRound = wagerFinal,
            Sponsor = string.IsNullOrEmpty(ev.Sponsor) ? null : ev.Sponsor,
            BrandHex = string.IsNullOrEmpty(ev.BrandHex) ? null : ev.BrandHex,
            LeadCaptureUrl = string.IsNullOrEmpty(ev.LeadCaptureUrl) ? null : ev.LeadCaptureUrl,
            Weekday = ev.Weekday,
        };
    }
}
