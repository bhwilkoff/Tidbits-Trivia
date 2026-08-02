using Tidbits.Core.Data;
using Tidbits.Core.Engine;

namespace Tidbits.HeadlessTests;

/// Validates the shared-corpus loader: the positional-array parser reads every
/// question, and the daily selection still matches the cross-platform golden when
/// driven end-to-end through CorpusDatabase (not just a pre-extracted id list).
public class CorpusLoad
{
    private static CorpusDatabase LoadCorpus()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "corpus.json");
        using var fs = File.OpenRead(path);
        return CorpusDatabase.Load(fs);
    }

    [Fact]
    public void Parser_loads_the_whole_corpus()
    {
        var corpus = LoadCorpus();
        // Floor, not exact — the corpus grows (2026-07 expansion toward 100k); it
        // must never regress below the shipped baseline.
        Assert.True(corpus.Count >= 20318, $"corpus shrank to {corpus.Count}");
    }

    [Fact]
    public void Daily_matches_golden_end_to_end_through_the_loader()
    {
        var corpus = LoadCorpus();
        var ids = corpus.OrderedIds("mixed");
        Assert.True(ids.Count > 100);
        // TWO tests read this golden — this one and DailyParityGolden. When the
        // pick changed, updating only the other left this one asserting the old
        // output and CI caught it. A shared fixture has to be honoured
        // everywhere it is read.
        var rows = corpus.OrderedIdsWithCategory("mixed");
        var cats = rows.Select(r => r.Category).ToList();
        foreach (var line in File.ReadAllLines(Path.Combine(AppContext.BaseDirectory, "Fixtures", "daily-golden.txt")))
        {
            if (line.Length == 0) continue;
            var parts = line.Split(' ');
            var got = DailyPick.PickBalanced(ids, cats, parts[0], "mixed", 7).ToArray();
            Assert.Equal(parts.Skip(1).ToArray(), got);
        }
    }
}
