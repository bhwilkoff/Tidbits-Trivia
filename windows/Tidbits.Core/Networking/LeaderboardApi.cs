using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Tidbits.Core.Store;

namespace Tidbits.Core.Networking;

// LeaderboardRow (uid/name/score/nights/venues) is defined in PlayerIdentity.cs.

public sealed record VenueBoard(string Name, IReadOnlyList<LeaderboardRow> Rows);

public sealed record LeaderboardData(string? Season, IReadOnlyList<LeaderboardRow> Overall, IReadOnlyList<VenueBoard> Venues)
{
    public bool IsEmpty => Overall.Count == 0 && Venues.Count == 0;
    public static readonly LeaderboardData Empty = new(null, new List<LeaderboardRow>(), new List<VenueBoard>());
}

/// Reads the season leaderboard from the STATIC JSON the hourly cron commits to
/// data/leaderboard/ (free/cacheable, never RTDB) — twin of web loadLeaderboard /
/// Swift LeaderboardAPI. index.json → {season: [venue,…]}; per season an
/// _overall.json plus one file per venue.
public static class LeaderboardApi
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    public const string BaseUrl = ShareText.SiteUrl + "/data/leaderboard";

    public static async Task<LeaderboardData> LoadAsync(HttpClient http, string baseUrl = BaseUrl)
    {
        try
        {
            var index = await GetJson<Dictionary<string, List<string>>>(http, $"{baseUrl}/index.json");
            var seasons = index?.Keys.OrderDescending().ToList();
            if (seasons is not { Count: > 0 }) return LeaderboardData.Empty;
            var season = seasons[0];

            var overall = await GetJson<List<LeaderboardRow>>(http, $"{baseUrl}/{season}/_overall.json")
                          ?? new List<LeaderboardRow>();
            var venues = new List<VenueBoard>();
            foreach (var venue in index![season])
            {
                var rows = await GetJson<List<LeaderboardRow>>(http, $"{baseUrl}/{season}/{System.Uri.EscapeDataString(venue)}.json")
                           ?? new List<LeaderboardRow>();
                venues.Add(new VenueBoard(venue, rows));
            }
            return new LeaderboardData(season, overall, venues);
        }
        catch
        {
            return LeaderboardData.Empty;
        }
    }

    private static async Task<T?> GetJson<T>(HttpClient http, string url)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
        var resp = await http.SendAsync(req);
        if (!resp.IsSuccessStatusCode) return default;
        return JsonSerializer.Deserialize<T>(await resp.Content.ReadAsStringAsync(), Json);
    }
}
