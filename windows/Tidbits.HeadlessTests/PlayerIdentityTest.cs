using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;
using Tidbits.Core.Networking;
using Xunit;

public class PlayerIdentityTest
{
    [Fact]
    public void Profile_renames_rerolls_and_persists()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-profile-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new PlayerIdentityStore(path);
            Assert.Equal("Player", store.Current.Name);
            Assert.NotEqual("", store.Current.AvatarSeed);
            var seed0 = store.Current.AvatarSeed;

            store.Rename("  Ada  ");                 // trimmed
            Assert.Equal("Ada", store.Current.Name);
            store.Rename("");                         // empty ignored
            Assert.Equal("Ada", store.Current.Name);
            store.Rename(new string('x', 40));        // capped at 24
            Assert.Equal(24, store.Current.Name.Length);

            store.Rename("Ada");
            store.RerollAvatar();
            Assert.NotEqual(seed0, store.Current.AvatarSeed); // new seed
            var seed1 = store.Current.AvatarSeed;

            // Persisted across instances.
            var reloaded = new PlayerIdentityStore(path);
            Assert.Equal("Ada", reloaded.Current.Name);
            Assert.Equal(seed1, reloaded.Current.AvatarSeed);
            Assert.InRange(reloaded.Current.AvatarHue, 0.0, 1.0); // deterministic hue
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [AvaloniaFact]
    public void Settings_profile_renders()
    {
        var dir = System.Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(System.AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        var win = new Window { Width = 640, Height = 700, Content = new SettingsView() };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(dir, "settings-profile.png"));
    }
}
