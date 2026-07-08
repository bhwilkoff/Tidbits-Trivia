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

public class SavedSetsTest
{
    private static List<Question> Qs(int n) => Enumerable.Range(0, n).Select(i => new Question
    {
        Id = $"q{i}", Prompt = $"Prompt {i}", CategoryId = "history", CorrectIndex = 0,
        Options = new List<string> { "a", "b", "c", "d" }, Difficulty = 3,
    }).ToList();

    [Fact]
    public void Add_persists_newest_first_and_removes()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-sets-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new SavedSetsStore(path);
            store.Add("Rome", Qs(8));
            var jazz = store.Add("Jazz", Qs(10));

            Assert.Equal(2, store.All.Count);
            Assert.Equal("Jazz", store.All[0].Label);   // newest first
            Assert.Equal(10, store.All[0].Count);

            // Persisted with questions intact across instances.
            var reloaded = new SavedSetsStore(path);
            Assert.Equal("Jazz", reloaded.All[0].Label);
            Assert.Equal("q0", reloaded.All[0].Questions[0].Id);

            reloaded.Remove(jazz.Id);
            Assert.Single(reloaded.All);
            Assert.Equal("Rome", reloaded.All[0].Label);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [AvaloniaFact]
    public void Create_lists_a_saved_set()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var seeded = GameData.Shared.Value.SavedSets.Add("The Renaissance", Qs(10));
        try
        {
            var win = new Window { Width = 620, Height = 520, Content = new CreateView() };
            win.Show();
            Dispatcher.UIThread.RunJobs();
            win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "create-saved.png"));
        }
        finally { GameData.Shared.Value.SavedSets.Remove(seeded.Id); }
    }
}
