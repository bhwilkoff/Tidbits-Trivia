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
        Assert.Equal(20318, corpus.Count); // "count" declared in corpus.json
    }

    [Fact]
    public void Daily_matches_golden_end_to_end_through_the_loader()
    {
        var ids = LoadCorpus().OrderedIds("mixed");
        Assert.True(ids.Count > 100);
        foreach (var line in File.ReadAllLines(Path.Combine(AppContext.BaseDirectory, "Fixtures", "daily-golden.txt")))
        {
            if (line.Length == 0) continue;
            var parts = line.Split(' ');
            var got = DailyPick.Pick(ids, parts[0], "mixed", 7).ToArray();
            Assert.Equal(parts.Skip(1).ToArray(), got);
        }
    }
}
