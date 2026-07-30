using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Audit A.3b — the projector is the only surface that shows a Wave B video question.
/// Windows shipped `VideoFrameSink` + `VideoSurface` with nothing wired between them, so a
/// clip played audio-only with the picture going nowhere.
[Collection("EnvSensitive")]
public class ProjectorVideoTest
{
    /// The surface must EXIST in the projector's tree (and start hidden — the big screen
    /// shows the question until a frame actually arrives).
    [AvaloniaFact]
    public void Projector_carries_a_hidden_video_surface()
    {
        var win = new Window { Width = 960, Height = 540, Content = new ProjectorView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var surface = win.GetVisualDescendants().OfType<VideoSurface>().FirstOrDefault();
        Assert.NotNull(surface);
        Assert.False(surface!.IsVisible);
    }

    /// Attaching must not throw where LibVLC has no natives — which is every CI run and
    /// this Mac. A projector that crashes without video is worse than one without video.
    [AvaloniaFact]
    public void Projector_survives_without_libvlc()
    {
        var win = new Window { Width = 640, Height = 360, Content = new ProjectorView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.Content = null;              // forces the detach/dispose path
        Dispatcher.UIThread.RunJobs();

        var dir = Path.Combine(System.AppContext.BaseDirectory, "artifacts", "audit");
        Directory.CreateDirectory(dir);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "projector-video-detached.png"));
    }
}
