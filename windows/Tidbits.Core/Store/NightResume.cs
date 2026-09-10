using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.Core.Store;

/// A2.13 — a night the host was in the MIDDLE of, kept so a crash or a closed lid is not
/// the end of the evening. Mirror of Swift's `LiveNightResume`.
///
/// Everything the room can see already survives on the wire: the phones' scores live in
/// `live/{code}/scores`. What died with the app was everything the HOST held — where in
/// the night they were, the paper teams and their scores, the names they had hidden, the
/// answer sheet. A host standing in front of sixty people cannot reconstruct that.
public sealed record ResumedNight
{
    public sealed record Team
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("score")] public int Score { get; init; }
    }

    [JsonPropertyName("code")] public string Code { get; init; } = "";
    [JsonPropertyName("eventId")] public string? EventId { get; init; }
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    [JsonPropertyName("index")] public int Index { get; init; }
    [JsonPropertyName("revealed")] public bool Revealed { get; init; }
    [JsonPropertyName("paperTeams")] public IReadOnlyList<Team> PaperTeams { get; init; } = new List<Team>();
    /// The networked uids the host hid from the big screen (3.26) — host-side only.
    [JsonPropertyName("hidden")] public IReadOnlyList<string> Hidden { get; init; } = new List<string>();
    /// A2.14: the jokers locked per round (key = round index) and the paper tables' jokers by name.
    [JsonPropertyName("jokersPlayed")] public IReadOnlyDictionary<string, IReadOnlyList<string>> JokersPlayed { get; init; } = new Dictionary<string, IReadOnlyList<string>>();
    [JsonPropertyName("paperJokers")] public IReadOnlyDictionary<string, int> PaperJokers { get; init; } = new Dictionary<string, int>();
    [JsonPropertyName("pointsPerCorrect")] public int PointsPerCorrect { get; init; } = 1;
    [JsonPropertyName("wrongAnswerPenalty")] public int WrongAnswerPenalty { get; init; }
    [JsonPropertyName("answerLog")] public IReadOnlyList<LiveAnswerRecord> AnswerLog { get; init; } = new List<LiveAnswerRecord>();
    [JsonPropertyName("total")] public int Total { get; init; }
    /// The night's ACTUAL questions. A corpus-sourced round is drawn fresh on every
    /// Start(), so rebuilding from the plan would hand the room a different night.
    [JsonPropertyName("questions")] public IReadOnlyList<Question> Questions { get; init; } = new List<Question>();
    [JsonPropertyName("event")] public LiveEvent? Event { get; init; }
    [JsonPropertyName("plan")] public NightPlan? Plan { get; init; }
    [JsonPropertyName("savedAt")] public DateTimeOffset SavedAt { get; init; }

    /// "question 4 of 12" — what the resume card says, so the host knows what they are
    /// walking back into before they commit.
    [JsonIgnore]
    public string PositionLine => Total > 0 ? $"question {Math.Min(Index + 1, Total)} of {Total}" : "not started";
}

public sealed class NightResume
{
    /// A night older than this is not "in progress" — it is last week's.
    public static readonly TimeSpan MaxAge = TimeSpan.FromHours(6);

    private readonly string _path;
    private ResumedNight? _snapshot;

    public static readonly Lazy<NightResume> Shared = new(() => new NightResume(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia", "live-resume.json")));

    public NightResume(string path)
    {
        _path = path;
        try
        {
            if (File.Exists(path)) _snapshot = JsonSerializer.Deserialize<ResumedNight>(File.ReadAllText(path), Wire.Json);
        }
        catch { _snapshot = null; }
    }

    /// The night worth offering to resume, if there is one.
    public ResumedNight? Pending(DateTimeOffset? now = null) =>
        _snapshot is { } s && (now ?? DateTimeOffset.Now) - s.SavedAt < MaxAge ? s : null;

    public void Save(ResumedNight s)
    {
        _snapshot = s;
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(s, Wire.Json));
        }
        catch { /* best-effort: a snapshot that cannot be written must not break the night */ }
    }

    /// The night ended properly (or the host discarded it) — stop offering it.
    public void Clear()
    {
        _snapshot = null;
        try { if (File.Exists(_path)) File.Delete(_path); } catch { }
    }
}
