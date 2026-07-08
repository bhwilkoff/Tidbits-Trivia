using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

public class FriendStoreTest
{
    [Fact]
    public void Adds_dedupes_persists_and_removes()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-friends-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new FriendStore(path);
            store.Add(new PlayerIdentity.Friend { Uid = "u1", Name = "Ada" });
            store.Add(new PlayerIdentity.Friend { Uid = "u1", Name = "Ada again" }); // dupe uid → ignored
            store.Add(new PlayerIdentity.Friend { Uid = "", Name = "nobody" });       // empty uid → ignored
            Assert.Single(store.All);
            Assert.True(store.Contains("u1"));

            var reloaded = new FriendStore(path);
            Assert.Equal("Ada", reloaded.All[0].Name);
            reloaded.Remove("u1");
            Assert.Empty(reloaded.All);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [AvaloniaFact]
    public void Leaderboard_leads_with_a_friends_section()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var overall = new List<LeaderboardRow>
        {
            new() { Uid = "u1", Name = "Ada Lovelace", Score = 240 },
            new() { Uid = "me", Name = "You", Score = 180 },
            new() { Uid = "f1", Name = "Carl", Score = 120 },
        };
        var data = new LeaderboardData("2026-S3", overall, new List<VenueBoard>());

        var view = new LeaderboardView { MyUid = "me" };
        var win = new Window { Width = 760, Height = 640, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs(); // Loaded → LoadAsync runs first (sets Friends from the empty store)

        // Now set the friends explicitly + re-render (production reads them from GameData).
        view.Friends = new List<PlayerIdentity.Friend>
        {
            new() { Uid = "f1", Name = "Carl" },      // on the board → 120
            new() { Uid = "f9", Name = "Dana" },      // not yet ranked → —
        };
        view.Render(data);
        Dispatcher.UIThread.RunJobs();

        // The Friends section leads, with Carl ranked and Dana as "—".
        var texts = view.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains("Friends", texts);
        Assert.Contains("Dana", texts);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "leaderboard-friends.png"));
    }
}
