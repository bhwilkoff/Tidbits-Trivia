using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Data;
using Tidbits.Core.Engine;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.Core.Networking;

/// The Daily's global board — the $0 layer that ranks everyone who played today's Daily
/// (docs/DAILY-BOARD-CONTRACT.md). A LAYER on the Daily, never a separate mode. The READ
/// side is a static-JSON fetch (twin of LeaderboardApi / Swift DailyBoard); the WRITE side
/// is one authed RTDB put to dailyBoard/{day}/{authUid}. Clients read the static JSON the
/// hourly cron publishes — never the live DB (R-NET-1).
public static class DailyBoardApi
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    public const string BaseUrl = ShareText.SiteUrl + "/data/dailyboard";

    /// The published board for a day, or null if the cron hasn't published it yet.
    public static async Task<Board?> ResultsAsync(HttpClient http, string day, string baseUrl = BaseUrl)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/{day}.json");
            req.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
            var resp = await http.SendAsync(req);
            if (!resp.IsSuccessStatusCode) return null;
            return JsonSerializer.Deserialize<Board>(await resp.Content.ReadAsStringAsync(), Json);
        }
        catch { return null; }
    }

    /// Your percentile from the published histogram — the share of players you strictly
    /// beat. Pure; matches js/api.js DailyBoard.percentile and the Swift version. Null when
    /// the histogram is empty (you'd be the first player).
    public static int? Percentile(IReadOnlyDictionary<string, int> hist, int myScore)
    {
        if (hist is null) return null;
        int below = 0, total = 0;
        foreach (var (score, count) in hist)
        {
            total += count;
            if (int.TryParse(score, out var s) && s < myScore) below += count;
        }
        return total > 0 ? (int)Math.Round((double)below / total * 100) : null;
    }

    /// The 7-char "0/1" marks string aligned to the SHARED pickDaily order (by qid), NOT
    /// the play order — so per-question accuracy is comparable across every player.
    public static string Marks(IReadOnlyList<AnsweredQuestion> answered, IReadOnlyList<string> qids)
    {
        var correctById = answered
            .GroupBy(a => a.Question.Id)
            .ToDictionary(g => g.Key, g => g.First().IsCorrect);
        return string.Concat(qids.Select(id => correctById.TryGetValue(id, out var ok) && ok ? '1' : '0'));
    }

    /// After finishing TODAY's Daily (archive replays excluded), write this player's one row
    /// so the cron can rank the field. Keyed by the AUTH uid (the rule requires
    /// auth.uid === $uid). Free — sign-in not required. No-ops on any non-today-Daily.
    public static async Task SubmitAsync(FirebaseRtdb db, CorpusDatabase corpus,
                                         GameSummary summary, string name, string avatarSeed)
    {
        if (summary.Mode != GameMode.Daily || summary.DailyDay is not null) return;
        var uid = await db.EnsureAuth();
        if (string.IsNullOrEmpty(uid)) return;

        var day = QuestionProvider.DayKey();
        var ids = corpus.OrderedIds("mixed");
        var qids = DailyPick.Pick(ids, day, "mixed", GameMode.Daily.QuestionCount());
        var entry = new Entry
        {
            Name = name,
            AvatarSeed = avatarSeed,
            Score = summary.Score,
            Correct = summary.Correct,
            Marks = Marks(summary.Answered, qids),
            Ms = (int)(summary.Answered.Sum(a => a.SecondsTaken) * 1000),
            At = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
        };
        try { await db.Put($"dailyBoard/{day}/{uid}", entry); } catch { /* offline: best-effort */ }
    }

    // MARK: - Wire (matches the cron's published shape)

    public sealed record Board
    {
        [JsonPropertyName("day")] public string Day { get; init; } = "";
        [JsonPropertyName("qids")] public List<string> Qids { get; init; } = new();
        [JsonPropertyName("n")] public int N { get; init; }
        [JsonPropertyName("hist")] public Dictionary<string, int> Hist { get; init; } = new();
        [JsonPropertyName("perQ")] public List<double> PerQ { get; init; } = new();
        [JsonPropertyName("top")] public List<Row> Top { get; init; } = new();
    }

    public sealed record Row
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("avatarSeed")] public string AvatarSeed { get; init; } = "";
        [JsonPropertyName("score")] public int Score { get; init; }
        [JsonPropertyName("correct")] public int Correct { get; init; }
    }

    public sealed record Entry
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("avatarSeed")] public string AvatarSeed { get; init; } = "";
        [JsonPropertyName("score")] public int Score { get; init; }
        [JsonPropertyName("correct")] public int Correct { get; init; }
        [JsonPropertyName("marks")] public string Marks { get; init; } = "";
        [JsonPropertyName("ms")] public int Ms { get; init; }
        [JsonPropertyName("at")] public long At { get; init; }
    }
}
