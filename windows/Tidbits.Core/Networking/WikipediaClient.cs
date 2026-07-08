using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace Tidbits.Core.Networking;

/// Read-only client for the open Wikipedia REST + Action APIs (no key, no auth).
/// Port of Core/Networking/WikipediaClient.swift — feeds the TemplateEngine's
/// live question generation (1.11/1.12). The moat is the FILTER, not the fetch.
public sealed class WikipediaClient
{
    private const string RestBase = "https://en.wikipedia.org/api/rest_v1";
    private const string ActionBase = "https://en.wikipedia.org/w/api.php";
    private const string UA = "TidbitsTrivia/1.0 (learning trivia app)";

    private readonly HttpClient _http;
    public WikipediaClient(HttpClient? http = null)
    {
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
    }

    public sealed record Summary
    {
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("description")] public string? Description { get; init; }
        [JsonPropertyName("extract")] public string? Extract { get; init; }
        [JsonPropertyName("type")] public string? Type { get; init; } // "standard" | "disambiguation" | …
        [JsonPropertyName("thumbnail")] public Thumb? Thumbnail { get; init; }
        [JsonPropertyName("content_urls")] public Urls? ContentUrls { get; init; }

        public sealed record Thumb { [JsonPropertyName("source")] public string? Source { get; init; } }
        public sealed record Urls
        {
            [JsonPropertyName("desktop")] public Page? Desktop { get; init; }
            public sealed record Page { [JsonPropertyName("page")] public string? PageUrl { get; init; } }
        }

        [JsonIgnore] public string? PageUrl => ContentUrls?.Desktop?.PageUrl;
        [JsonIgnore] public string? ImageUrl => Thumbnail?.Source;
    }

    /// Fetch a single article summary by exact title.
    public async Task<Summary?> GetSummary(string title)
    {
        var path = Uri.EscapeDataString(title.Replace(' ', '_'));
        using var req = new HttpRequestMessage(HttpMethod.Get, $"{RestBase}/page/summary/{path}");
        req.Headers.TryAddWithoutValidation("User-Agent", UA);
        using var resp = await _http.SendAsync(req);
        if (!resp.IsSuccessStatusCode) return null;
        var json = await resp.Content.ReadAsStringAsync();
        return Parse(json);
    }

    /// Parse a REST summary JSON body (extracted so it's unit-testable offline).
    public static Summary? Parse(string json)
    {
        try { return JsonSerializer.Deserialize<Summary>(json); }
        catch { return null; }
    }

    private sealed record SearchEnvelope
    {
        [JsonPropertyName("query")] public Query? Q { get; init; }
        public sealed record Query { [JsonPropertyName("search")] public List<Hit> Search { get; init; } = new(); }
        public sealed record Hit { [JsonPropertyName("title")] public string Title { get; init; } = ""; }
    }

    /// Candidate article titles for a free-text topic (Action API search).
    public async Task<List<string>> Search(string topic, int limit = 30)
    {
        var url = $"{ActionBase}?action=query&list=search&srsearch={Uri.EscapeDataString(topic)}" +
                  $"&srlimit={limit}&srnamespace=0&format=json";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("User-Agent", UA);
        using var resp = await _http.SendAsync(req);
        if (!resp.IsSuccessStatusCode) return new();
        var json = await resp.Content.ReadAsStringAsync();
        return ParseSearch(json);
    }

    /// Parse an Action-API search body into titles (unit-testable offline).
    public static List<string> ParseSearch(string json)
    {
        try { return JsonSerializer.Deserialize<SearchEnvelope>(json)?.Q?.Search.Select(h => h.Title).ToList() ?? new(); }
        catch { return new(); }
    }

    /// Fetch summaries for many titles concurrently, dropping failures.
    public async Task<List<Summary>> Summaries(IEnumerable<string> titles)
    {
        var tasks = titles.Select(GetSummary).ToList();
        var results = await Task.WhenAll(tasks);
        return results.Where(s => s is not null).Select(s => s!).ToList();
    }
}
