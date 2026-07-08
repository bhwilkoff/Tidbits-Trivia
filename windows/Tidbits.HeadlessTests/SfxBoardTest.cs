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

public class SfxBoardTest
{
    [Fact]
    public void Board_adds_labels_dedupes_and_persists()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-sfx-{System.Guid.NewGuid():N}.json");
        try
        {
            var board = new SfxBoard(path);
            board.Add("/clips/big_applause.wav");
            board.Add("/clips/big_applause.wav");  // dupe path ignored
            board.Add("/clips/buzzer.mp3", "Wrong!");
            Assert.Equal(2, board.Pads.Count);
            Assert.Equal("big applause", board.Pads[0].Label); // default label from file name
            Assert.Equal("Wrong!", board.Pads[1].Label);       // explicit label

            var reloaded = new SfxBoard(path);
            Assert.Equal(2, reloaded.Pads.Count);
            reloaded.Remove("/clips/buzzer.mp3");
            Assert.Single(reloaded.Pads);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void Default_label_strips_path_and_extension()
    {
        // Uses Path.GetFileNameWithoutExtension (OS-separator aware) + underscore/dash → space.
        Assert.Equal("air horn", SfxBoard.DefaultLabel("/x/air-horn.mp3"));
        Assert.Equal("drum roll", SfxBoard.DefaultLabel("/x/drum_roll.wav"));
    }

    [AvaloniaFact]
    public void Board_panel_renders_pads()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var pads = new[]
        {
            new SfxPad { Label = "Applause", Path = "/a.wav" },
            new SfxPad { Label = "Buzzer", Path = "/b.wav" },
            new SfxPad { Label = "Drumroll", Path = "/c.wav" },
        };
        var panel = SfxBoardUi.BuildPanel(pads);
        var win = new Window { Width = 460, Height = 300, Content = panel };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains("Sound board", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("Applause"));
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "sfx-board.png"));
    }
}
