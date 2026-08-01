using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Tidbits.Core.Data;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Does the C# ranker select the SAME questions as the shipped Apple one?
///
/// The four engines are unit-tested against the same cases (CreateTopicDriftTest),
/// which is not the same thing as agreeing on a real topic over the real 128k-row
/// corpus. The first end-to-end comparison between Apple and the web found a
/// divergence immediately: Swift's sort is not stable and JavaScript's is, so rows
/// tied on score ordered differently, and `Diversify`'s per-category cap then kept
/// a different SET. This is the Windows side of that check.
///
/// The golden is captured from the Apple simulator — see tools/create/golden/.
/// Order is NOT compared: `Diversify` shuffles on purpose so a quiz does not march
/// category-by-category. Membership is the contract.
public class CreateGoldenTest
{
    static (List<string> topics, Dictionary<string, HashSet<string>> expected) LoadGolden()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Fixtures", "create-golden.txt");
        var topics = new List<string>();
        var expected = new Dictionary<string, HashSet<string>>();
        foreach (var line in File.ReadAllLines(path))
        {
            if (line.Length == 0) continue;
            var tab = line.IndexOf('\t');
            var topic = tab < 0 ? line : line[..tab];
            var ids = tab < 0 ? "" : line[(tab + 1)..];
            topics.Add(topic);
            expected[topic] = new HashSet<string>(
                ids.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        }
        return (topics, expected);
    }

    [Fact]
    public void The_ranker_selects_what_the_Apple_ranker_selects()
    {
        var (topics, expected) = LoadGolden();
        Assert.NotEmpty(topics);

        using var cs = File.OpenRead(Path.Combine(AppContext.BaseDirectory, "Fixtures", "corpus.json"));
        var corpus = CorpusDatabase.Load(cs);

        var differing = new List<string>();
        foreach (var topic in topics)
        {
            var got = corpus.Search(topic, 8).Select(q => q.Id).ToHashSet();
            if (!got.SetEquals(expected[topic]))
            {
                differing.Add($"{topic}: +[{string.Join(", ", got.Except(expected[topic]).Order())}] "
                              + $"-[{string.Join(", ", expected[topic].Except(got).Order())}]");
            }
        }
        Assert.True(differing.Count == 0,
            "C# selects different questions than the Apple ranker:\n  " + string.Join("\n  ", differing));
    }

    /// Nineteen of the golden's topics correctly return NOTHING — "Harry Kane" is
    /// not in this corpus and the honest answer is nothing, not Spokane and Butane.
    /// A golden listing only the topics with results would pass a regression that
    /// brought all of those back.
    [Fact]
    public void The_topics_that_should_return_nothing_still_return_nothing()
    {
        var (_, expected) = LoadGolden();
        var empties = expected.Where(kv => kv.Value.Count == 0).Select(kv => kv.Key).ToList();
        Assert.NotEmpty(empties);

        using var cs = File.OpenRead(Path.Combine(AppContext.BaseDirectory, "Fixtures", "corpus.json"));
        var corpus = CorpusDatabase.Load(cs);
        foreach (var topic in empties)
        {
            Assert.True(corpus.Search(topic, 8).Count == 0,
                $"'{topic}' should return nothing but returned "
                + string.Join(", ", corpus.Search(topic, 8).Select(q => q.SourceTitle)));
        }
    }
}
