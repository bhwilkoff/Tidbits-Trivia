using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

public class LeaderboardTest
{
    /// Serves canned leaderboard JSON so the reader parses without a real network.
    private sealed class FakeHandler : HttpMessageHandler
    {
        private readonly Dictionary<string, string> _routes;
        public FakeHandler(Dictionary<string, string> routes) => _routes = routes;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken ct)
        {
            var path = req.RequestUri!.AbsolutePath;
            return Task.FromResult(_routes.TryGetValue(path, out var body)
                ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) }
                : new HttpResponseMessage(HttpStatusCode.NotFound));
        }
    }

    [Fact]
    public async Task Reads_index_then_overall_and_venues()
    {
        var routes = new Dictionary<string, string>
        {
            ["/data/leaderboard/index.json"] = "{\"2026-Q3\":[\"The Anchor\"],\"2026-Q2\":[]}",
            ["/data/leaderboard/2026-Q3/_overall.json"] =
                "[{\"uid\":\"u1\",\"name\":\"Ada\",\"score\":120},{\"uid\":\"u2\",\"name\":\"Bo\",\"score\":90}]",
            ["/data/leaderboard/2026-Q3/The%20Anchor.json"] =
                "[{\"uid\":\"u2\",\"name\":\"Bo\",\"score\":90}]",
        };
        var http = new HttpClient(new FakeHandler(routes));
        var data = await LeaderboardApi.LoadAsync(http, "https://tidbitstrivia.com/data/leaderboard");

        Assert.Equal("2026-Q3", data.Season);           // latest season wins
        Assert.Equal(2, data.Overall.Count);
        Assert.Equal("Ada", data.Overall[0].Name);       // champion first (as ordered in the file)
        Assert.Single(data.Venues);
        Assert.Equal("The Anchor", data.Venues[0].Name);
        Assert.Equal("Bo", data.Venues[0].Rows[0].Name);
    }

    [Fact]
    public async Task Empty_index_yields_empty_data()
    {
        var http = new HttpClient(new FakeHandler(new()
            { ["/data/leaderboard/index.json"] = "{}" }));
        var data = await LeaderboardApi.LoadAsync(http, "https://tidbitstrivia.com/data/leaderboard");
        Assert.True(data.IsEmpty);
    }

    [AvaloniaFact]
    public void Board_renders_champion_and_you_highlight()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var overall = new List<LeaderboardRow>
        {
            new() { Uid = "u1", Name = "Ada Lovelace", Score = 240 },
            new() { Uid = "me", Name = "You Player", Score = 180 },
            new() { Uid = "u3", Name = "Carl", Score = 120 },
        };
        var data = new LeaderboardData("2026-Q3", overall,
            new List<VenueBoard> { new("The Anchor", overall.GetRange(1, 2)) });

        var view = new LeaderboardView { MyUid = "me", AutoLoad = false };
        var win = new Window { Width = 760, Height = 640, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        view.Render(data);
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "leaderboard.png"));
    }
}
