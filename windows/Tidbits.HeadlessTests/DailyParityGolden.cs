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

        // Ids AND categories both come from the ONE linked corpus.json, in one pass.
        //
        // They used to come from two places: categories from the live-linked corpus, ids from a
        // committed `corpus-ids.txt` copy beside it. A copy of data that already exists is a
        // copy that drifts, and it did — two corpus commits dropped 16 film-cloze rows without
        // re-running the regeneration step in tools/corpus/resync_corpus.sh, and Windows CI then
        // failed on every subsequent push with "Expected: 110512 / Actual: 110496": a count
        // mismatch between two files, which says nothing about the thing under test.
        //
        // The determinism this guards was never broken (the current corpus still reproduces the
        // golden on every stack). Reading both from the same source means the mismatch it was
        // asserting about can no longer exist, so a red build here means the daily pick really
        // did diverge.
        List<string>? ids = null, cats = null;
        void Load()
        {
            if (ids is not null) return;
            using var doc = JsonDocument.Parse(
                File.ReadAllText(Path.Combine(dir, "corpus.json")));
            var qs = doc.RootElement.GetProperty("questions").EnumerateArray().ToList();
            ids  = qs.Select(q => q[0].GetString() ?? "").ToList();
            cats = qs.Select(q => q[4].GetString() ?? "").ToList();
            Assert.True(ids.Count > 100, $"expected the full corpus, got {ids.Count} ids");
        }
        List<string> Ids()  { Load(); return ids!; }
        List<string> Cats() { Load(); return cats!; }

        var seenV2 = 0;
        foreach (var line in File.ReadAllLines(Path.Combine(dir, "daily-golden.txt")))
        {
            if (line.Length == 0) continue;
            var parts = line.Split(' ');
            var day = parts[0];
            var expected = parts.Skip(1).ToArray();

            var got = DailyPick.PickBalanced(Ids(), Cats(), day, "mixed", 7).ToArray();
            seenV2++;
            Assert.Equal(expected, got);
        }
        // If this file ever stops checking days, the C# mirror is unverified and
        // should say so rather than pass quietly.
        Assert.True(seenV2 > 0, "golden had no days — the C# mirror is unverified");
    }
}
