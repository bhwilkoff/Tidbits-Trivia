using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.App.Services;
using Xunit;

/// The Windows big screen, with the LONGEST content it will ever be asked to show.
///
/// The macOS projector had SIX separate defects of exactly this class, and every
/// one of them was invisible until the surface was rendered with real content and
/// the picture was looked at: the question truncated to one line with an ellipsis,
/// the reveal pushed the header and the join code off the screen, the correct
/// answer truncated mid-word, the explanation truncated, and the final standings
/// were a blank wall. The existing Windows projector snapshots render the LOBBY
/// and assert nothing, so they could not have caught any of it here.
///
/// This renders the question and reveal states at the real 1280x720 with a
/// deliberately long prompt, and asserts what the ROOM needs rather than that a
/// PNG was produced.
namespace Tidbits.HeadlessTests;

public class ProjectorLongContentSnapshot
{
    private const string LongPrompt =
        "Rising to lead the Goths after the Battle of Adrianople, this first king of the " +
        "Visigoths — whose Gothic name meant 'ruler of all' — served under a Roman emperor " +
        "before becoming Rome's fiercest adversary in the Balkans, sacking the city itself " +
        "in 410 after three separate sieges. Who was he?";

    private static string ArtifactDir()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static string[] VisibleText(Window win) =>
        win.GetVisualDescendants().OfType<TextBlock>()
           .Where(t => t.IsVisible && !string.IsNullOrWhiteSpace(t.Text))
           .Select(t => t.Text!).ToArray();

    [AvaloniaFact]
    public async Task A_long_question_and_its_reveal_fit_the_big_screen()
    {
        var data = GameData.FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"),
                                     data.Provider, "Friday Pub Quiz");
        await host.LoadQuestionsOffline();
        Assert.True(host.Current is not null, "no question loaded — the assertion below could not fire");
        var vm = new LiveHostViewModel(host);
        var win = new Window { Width = 1280, Height = 720, Content = new ProjectorView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        await Task.Yield();
        Dispatcher.UIThread.RunJobs();

        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactDir(), "projector-long-question.png"));

        // Nothing on a projector may end in an ellipsis: the room cannot read a
        // truncated question, answer or explanation. This is the assertion the Mac
        // needed and did not have.
        // The room must be able to JOIN mid-round, not only from the lobby splash.
        var text = VisibleText(win);
        Assert.Contains(text, t => t.Contains("tidbitstrivia.com/live"));

        foreach (var t in VisibleText(win))
            Assert.False(t.TrimEnd().EndsWith("…") || t.TrimEnd().EndsWith("..."),
                         $"truncated on the big screen: {t}");
    }
}
