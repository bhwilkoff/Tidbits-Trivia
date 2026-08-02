using System.Text.Json;
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

        // v2 lines (Decision 050) need each id's CATEGORY. The csproj already
        // links assets/corpus.json in, so read it rather than add a fixture that
        // could drift from the ids file beside it.
        List<string>? cats = null;
        List<string> Cats()
        {
            if (cats is not null) return cats;
            using var doc = JsonDocument.Parse(
                File.ReadAllText(Path.Combine(dir, "corpus.json")));
            cats = doc.RootElement.GetProperty("questions").EnumerateArray()
                      .Select(q => q[4].GetString() ?? "").ToList();
            Assert.Equal(ids.Count, cats.Count);
            return cats;
        }

        var seenV2 = 0;
        foreach (var line in File.ReadAllLines(Path.Combine(dir, "daily-golden.txt")))
        {
            if (line.Length == 0) continue;
            var parts = line.Split(' ');
            var day = parts[0];
            var expected = parts.Skip(1).ToArray();

            string[] got;
            if (day.StartsWith("v2:", StringComparison.Ordinal))
            {
                day = day[3..];
                got = DailyPick.PickBalanced(ids, Cats(), day, "mixed", 7).ToArray();
                seenV2++;
            }
            else
            {
                got = DailyPick.Pick(ids, day, "mixed", 7).ToArray();
            }
            Assert.Equal(expected, got);
        }
        // The golden carries v2 days; if this file ever stops seeing them the
        // C# mirror has silently dropped out of the contract.
        Assert.True(seenV2 > 0, "golden has no v2 days — the C# mirror is unverified");
    }
}
