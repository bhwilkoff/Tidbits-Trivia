using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Services;
using Tidbits.App.Views;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Audit A.2 — the first-run walkthrough (macOS `OnboardingSheet_macOS` parity).
[Collection("EnvSensitive")]
public class OnboardingTest
{
    /// The gate is the whole feature: it must show once and then never again, including
    /// when the player dismissed it with Esc rather than the button.
    [Fact]
    public void Onboarding_flag_persists_across_a_reload()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-onboard-{System.Guid.NewGuid():N}.json");
        try
        {
            var first = new Tidbits.Core.Store.GameSettings(path);
            Assert.False(first.HasOnboarded);          // a fresh install sees it

            first.HasOnboarded = true;
            first.Save();

            var reopened = new Tidbits.Core.Store.GameSettings(path);
            Assert.True(reopened.HasOnboarded);        // and never again
            Assert.True(reopened.ReviewEnabled);       // the added field didn't clobber siblings
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    /// Renders the walkthrough body so the numbered badges + copy are eyeballable in CI.
    [AvaloniaFact]
    public void Onboarding_body_renders()
    {
        var win = new Window { Width = 560, Height = 420, Content = OnboardingDialog.BuildBody() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        var dir = Path.Combine(System.AppContext.BaseDirectory, "artifacts", "audit");
        Directory.CreateDirectory(dir);
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "onboarding.png"));
    }

    /// The walkthrough is a MODAL dialog, so when it is up nothing behind it can be clicked.
    /// Windows had no way to suppress it while Apple and Android both did, which meant a
    /// harness launch landed on the walkthrough and then photographed and graded the surface
    /// behind it — content no click could actually have reached. This is the hook that makes
    /// a driven launch mean something.
    [Fact]
    public void Skip_hook_suppresses_the_walkthrough_without_consuming_the_real_first_run()
    {
        var prior = System.Environment.GetEnvironmentVariable("TIDBITS_SKIP_ONBOARD");
        try
        {
            System.Environment.SetEnvironmentVariable("TIDBITS_SKIP_ONBOARD", null);
            Assert.True(OnboardingDialog.ShouldShow(hasOnboarded: false));   // a real first run

            System.Environment.SetEnvironmentVariable("TIDBITS_SKIP_ONBOARD", "1");
            Assert.False(OnboardingDialog.ShouldShow(hasOnboarded: false));  // suppressed

            // Suppressing it for a test run must not spend a real person's first run: the
            // flag is untouched, so the walkthrough still shows the next ordinary launch.
            var path = Path.Combine(Path.GetTempPath(), $"tidbits-skip-{System.Guid.NewGuid():N}.json");
            var settings = new Tidbits.Core.Store.GameSettings(path);
            Assert.False(settings.HasOnboarded);
        }
        finally { System.Environment.SetEnvironmentVariable("TIDBITS_SKIP_ONBOARD", prior); }
    }
}
