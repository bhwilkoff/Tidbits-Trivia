using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Xunit;

public class RecordsBannerTest
{
    [AvaloniaFact]
    public void Records_shows_the_profile_banner()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var view = new RecordsView();
        var win = new Window { Width = 780, Height = 620, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        // The "Playing as {name}" banner is present (default profile → "Player").
        var texts = view.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains(texts, t => t is not null && t.StartsWith("Playing as"));
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "records-profile-banner.png"));
    }
}
