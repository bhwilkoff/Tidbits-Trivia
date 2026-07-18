using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Services;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

public class PresetsTest
{
    [Fact]
    public void Save_upserts_by_name_caps_at_5_and_removes()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-presets-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new PresetsStore(path);
            var mine = store.Save("My Mix", new[] { GameMode.Classic, GameMode.Stake }, "history");
            Assert.Single(store.All);
            Assert.Equal(2, store.All[0].Modes.Count);

            // Upsert by name (case-insensitive) — same slot, latest wins.
            store.Save("my mix", new[] { GameMode.ClosestCall }, "science");
            Assert.Single(store.All);
            Assert.Single(store.All[0].Modes);
            Assert.Equal("science", store.All[0].CategoryId);

            // Cap at 5, newest-first.
            for (int i = 0; i < 6; i++) store.Save($"Mix {i}", new[] { GameMode.Classic }, "mixed");
            Assert.Equal(5, store.All.Count);
            Assert.Equal("Mix 5", store.All[0].Name);

            // Persists across instances (enum modes survive as names).
            var reloaded = new PresetsStore(path);
            Assert.Equal("Mix 5", reloaded.All[0].Name);
            Assert.Equal(GameMode.Classic, reloaded.All[0].Modes[0]);

            reloaded.Remove(reloaded.All[0].Id);
            Assert.Equal(4, reloaded.All.Count);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [AvaloniaFact]
    public void Play_landing_lists_a_saved_preset()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var seeded = GameData.Shared.Value.Presets.Save(
            "Speedy Facts", new[] { GameMode.TimeAttack, GameMode.ClosestCall }, "science");
        try
        {
            var win = new Window { Width = 900, Height = 640, Content = new PlayView() };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "play-preset.png"));
            Assert.Contains(GameData.Shared.Value.Presets.All, p => p.Name == "Speedy Facts");
        }
        finally { GameData.Shared.Value.Presets.Remove(seeded.Id); }
    }
}
