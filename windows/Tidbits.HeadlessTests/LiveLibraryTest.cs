using System;
using System.IO;
using System.Linq;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// LIVE-PACKAGE-FORMAT §6 — the host's own question bank across nights. The Mac
/// suite asserts the same rules (TidbitsTriviaTests/LiveLibraryTests.swift).
public class LiveLibraryTest
{
    private static Question Q(string id, string prompt, string answer, string category = "history", string? image = null) =>
        new() { Id = id, Prompt = prompt, Options = new[] { answer, "b", "c", "d" }, CorrectIndex = 0, CategoryId = category, Difficulty = 3, ImageUrl = image };
    private static LibraryItem Item(Question q, string source = "Friday") => new() { Id = q.Id, Question = q, Source = source };

    [Fact]
    public void Every_search_term_must_hit_and_category_narrows_first()
    {
        var coins = Item(Q("1", "Which kingdom minted the first coins?", "Lydia") with { Tags = new[] { "money" } });
        var flags = Item(Q("2", "Which flag is this?", "Chad", "geography", "tidbits-media:abc"));
        Assert.True(LiveLibrary.Matches(coins, "coins lydia", null));
        Assert.True(LiveLibrary.Matches(coins, "money", null));
        Assert.True(LiveLibrary.Matches(coins, "friday", null));
        Assert.False(LiveLibrary.Matches(coins, "coins flag", null));
        Assert.False(LiveLibrary.Matches(coins, "", "geography"));
        Assert.True(LiveLibrary.Matches(flags, "", "geography"));
    }

    [Fact]
    public void Saving_is_keyed_by_prompt_and_answer()
    {
        var path = Path.Combine(Path.GetTempPath(), "tidbits-lib-" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            var lib = new LiveLibraryStore(path);
            Assert.True(lib.Add(Q("1", "Which kingdom minted the first coins?", "Lydia"), "Friday"));
            Assert.False(lib.Add(Q("99", "which kingdom minted the first coins?  ", "lydia"), "Saturday"));
            Assert.Single(lib.All);
            Assert.Equal("Saturday", lib.All[0].Source);
            Assert.Equal(1, lib.Add(new[] { Q("1", "Which kingdom minted the first coins?", "Lydia"), Q("3", "Capital of Peru?", "Lima") }, "Sunday"));
            Assert.Equal(2, lib.All.Count);
            // It persists: a new store on the same path reads it back.
            Assert.Equal(2, new LiveLibraryStore(path).All.Count);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void A_bank_event_groups_by_category_in_first_seen_order_and_round_trips_as_a_package()
    {
        var items = new[] { Item(Q("1", "A?", "a", "history")), Item(Q("2", "B?", "b", "geography")), Item(Q("3", "C?", "c", "history")) };
        var ev = LiveLibrary.BankEvent(items, "Question library");
        Assert.Equal(new[] { 2, 1 }, ev.Rounds.Select(r => r.Count).ToArray());
        Assert.Equal(new[] { "1", "3" }, ev.QuestionsFor(0).Select(q => q.Id).ToArray());
        using var ms = new MemoryStream();
        LivePackage.Write(ms, ev, "test", "", packageKind: "bank");
        ms.Position = 0;
        var back = LivePackage.Read(ms);
        Assert.Equal("bank", back.Manifest.Kind);
        Assert.Equal(new[] { "A?", "C?", "B?" }, back.Document.Event.Rounds.SelectMany(r => r.Questions).Select(q => q.Prompt).ToArray());
    }
}
