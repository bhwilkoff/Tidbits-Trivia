using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

public class DailyLogTest
{
    [Fact]
    public void First_completion_wins_and_is_remembered()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-daily-{Guid.NewGuid():N}.json");
        try
        {
            var log = new DailyLog(path);
            Assert.False(log.IsDone("2026-07-08"));

            log.Record("2026-07-08", score: 320, correct: 4, total: 5);
            Assert.True(log.IsDone("2026-07-08"));
            Assert.Equal(320, log.Result("2026-07-08")!.Score);

            // A replay of the same day must NOT overwrite the first result.
            log.Record("2026-07-08", score: 999, correct: 5, total: 5);
            Assert.Equal(320, log.Result("2026-07-08")!.Score);

            // Persisted across instances.
            var reloaded = new DailyLog(path);
            Assert.True(reloaded.IsDone("2026-07-08"));
            Assert.Equal(4, reloaded.Result("2026-07-08")!.Correct);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [AvaloniaFact]
    public void Play_landing_renders_the_daily_archive()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        var win = new Window { Width = 900, Height = 900, Content = new PlayView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "play-landing.png"));
    }
}
