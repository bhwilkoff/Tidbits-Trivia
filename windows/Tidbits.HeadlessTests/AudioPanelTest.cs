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

public class AudioPanelTest
{
    [AvaloniaFact]
    public void Audio_panel_renders_pa_bed_and_sfx()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);

        var devices = new List<(string, string)> { ("dev1", "Speakers (Realtek)"), ("dev2", "HDMI TV") };
        var pads = new[] { new SfxPad { Label = "Applause", Path = "/a.wav" }, new SfxPad { Label = "Buzzer", Path = "/b.wav" } };

        var panel = AudioPanelUi.BuildPanel(
            devices, "dev2", _ => { },
            bedPlaying: true, bedVolume: 60, onChooseBed: () => { }, onStopBed: () => { }, onBedVolume: _ => { },
            pads, _ => { }, () => { }, _ => { });

        var win = new Window { Width = 480, Height = 620, Content = panel };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();
        Assert.Contains("PA output", texts);
        Assert.Contains("Music bed", texts);
        Assert.Contains("Sound board", texts);
        Assert.Contains("Volume", texts);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "audio-panel.png"));
    }
}
