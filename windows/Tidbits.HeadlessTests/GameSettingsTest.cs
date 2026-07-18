using System.IO;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

public class GameSettingsTest
{
    [Fact]
    public void QuickPlay_memory_and_review_toggle_persist()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-settings-{System.Guid.NewGuid():N}.json");
        try
        {
            var s = new GameSettings(path);
            Assert.True(s.ReviewEnabled);           // default on
            Assert.Null(s.LastMode);                // no memory on a fresh install

            s.ReviewEnabled = false;
            s.LastMode = "Stake";
            s.LastCategoryId = "science";
            s.Save();

            var reloaded = new GameSettings(path);
            Assert.False(reloaded.ReviewEnabled);
            Assert.Equal("Stake", reloaded.LastMode);
            Assert.Equal("science", reloaded.LastCategoryId);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
