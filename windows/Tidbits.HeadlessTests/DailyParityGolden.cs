using Tidbits.Core.Engine;

namespace Tidbits.HeadlessTests;

/// Golden-vector test (WINDOWS-DESIGN §8.7): the C# DailyPick must reproduce the
/// EXACT daily sets the Swift/Kotlin/JS twins produce (tools/daily-parity/golden,
/// all three identical). Proves the FNV-1a64 stable seed + DailyPick rank/pick are
/// byte-exact cross-platform — the determinism guarantee the whole Daily depends on.
public class DailyParityGolden
{
    [Fact]
    public void Daily_pick_matches_the_cross_platform_golden()
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        var ids = File.ReadAllLines(Path.Combine(dir, "corpus-ids.txt"))
                      .Where(l => l.Length > 0).ToList();
        Assert.True(ids.Count > 100, $"expected the full corpus, got {ids.Count} ids");

        foreach (var line in File.ReadAllLines(Path.Combine(dir, "daily-golden.txt")))
        {
            if (line.Length == 0) continue;
            var parts = line.Split(' ');
            var day = parts[0];
            var expected = parts.Skip(1).ToArray();
            var got = DailyPick.Pick(ids, day, "mixed", 7).ToArray();
            Assert.Equal(expected, got);
        }
    }
}
