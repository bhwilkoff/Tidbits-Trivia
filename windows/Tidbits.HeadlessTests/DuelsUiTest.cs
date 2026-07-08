using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

public class DuelsUiTest
{
    [Fact]
    public void Outcome_chips_read_correctly()
    {
        DuelSummary D(bool md, bool od, int ms, int os) => new("id", md, ms, "u", "Sam", od, os);
        Assert.Equal("Your turn", DuelsUi.OutcomeChip(D(false, false, 0, 0)).label);
        Assert.Equal("Waiting on Sam", DuelsUi.OutcomeChip(D(true, false, 5, 0)).label);
        Assert.Equal("You won 7–4", DuelsUi.OutcomeChip(D(true, true, 7, 4)).label);
        Assert.Equal("You lost 3–8", DuelsUi.OutcomeChip(D(true, true, 3, 8)).label);
        Assert.Equal("Tie 5–5", DuelsUi.OutcomeChip(D(true, true, 5, 5)).label);
    }

    [AvaloniaFact]
    public void Panel_renders_inbox_and_duels()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var mine = new List<DuelSummary>
        {
            new("d1", false, 0, "u1", "Ada", false, 0),   // your turn
            new("d2", true, 6, "u2", "Grace", false, 0),  // waiting
            new("d3", true, 9, "u3", "Alan", true, 5),    // you won
            new("d4", true, 2, "u4", "Kurt", true, 7),    // you lost
        };
        var inbox = new List<DuelInvite> { new() { From = "u9", FromName = "Marie", At = 1, Id = "d9" } };

        var panel = DuelsUi.BuildPanel(mine, inbox);
        var win = new Window { Width = 460, Height = 620, Content = panel };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains("Challenges (1)", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("Marie challenged"));
        Assert.Contains("Your turn", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("You won 9–5"));
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "duels-panel.png"));
    }
}
