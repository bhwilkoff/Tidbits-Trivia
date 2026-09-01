using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// LIVE-EVENT-FILE §5.1 — the golden document both stacks must round-trip.
///
/// A host's night has to move between their Mac and their Windows box. Nothing
/// enforced that before this: each platform could quietly change its export and
/// the break would only show up when a real host's file failed to open, in a bar,
/// on a Friday. The Apple side runs the same assertions against the same file
/// (TidbitsTriviaTests/LiveEventFileGoldenTests.swift).
public class LiveEventFileGoldenTest
{
    private static string GoldenPath =>
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "live-event-golden.json");

    private static string GoldenJson() => File.ReadAllText(GoldenPath);

    [Fact]
    public void Decodes_the_golden_document()
    {
        var ev = LiveEventFile.Decode(GoldenJson());

        Assert.Equal("Friday Pub Quiz", ev.Name);
        Assert.Equal(2, ev.Rounds.Count);
        Assert.Equal("The Anchor Brewery", ev.Sponsor);
        Assert.Equal("#FF5C35", ev.BrandHex);
        Assert.Equal("https://example.test/list", ev.LeadCaptureUrl);
        Assert.Equal(6, ev.Weekday);

        Assert.Equal(GameMode.Classic, ev.Rounds[0].Kind);
        Assert.Equal(GameMode.TypeAnswer, ev.Rounds[1].Kind);

        // §2.5: a round's COUNT is the length of its questions, never a field read
        // from the file. A count that disagreed would build a night asking for more
        // questions than the host authored.
        Assert.Equal(2, ev.Rounds[0].Count);
        Assert.Equal(1, ev.Rounds[1].Count);
        Assert.Equal(2, ev.QuestionsFor(0).Count);
        Assert.Equal(1, ev.QuestionsFor(1).Count);

        Assert.Equal("Read the first one slowly.", ev.RoundNotes[0]);
        Assert.Equal("", ev.RoundNotes[1]);
        Assert.Equal(60, ev.RoundTimers[0]);
        Assert.Equal(0, ev.RoundTimers[1]);
        Assert.True(ev.WagerFinalRound);   // isWager on the LAST round (§4 mapping)

        var q = ev.QuestionsFor(0)[0];
        Assert.Equal("golden:q1", q.Id);
        Assert.Equal("Lydia", q.CorrectAnswer);
        Assert.Equal(3, q.Difficulty);
        Assert.Equal(4, q.Options.Count);

        var typed = ev.QuestionsFor(1)[0];
        Assert.NotNull(typed.Accepted);
        Assert.Equal("Bohemian Rhapsody", typed.Accepted![0]);
    }

    [Fact]
    public void Round_trips_the_contract_fields()
    {
        var once = LiveEventFile.Decode(GoldenJson());
        var twice = LiveEventFile.Decode(LiveEventFile.Encode(once, venue: "The Anchor"));

        Assert.Equal(once.Name, twice.Name);
        Assert.Equal(once.Rounds.Count, twice.Rounds.Count);
        Assert.Equal(once.WagerFinalRound, twice.WagerFinalRound);
        Assert.Equal(once.RoundTimers, twice.RoundTimers);
        Assert.Equal(once.RoundNotes, twice.RoundNotes);
        for (int i = 0; i < once.Rounds.Count; i++)
        {
            Assert.Equal(once.Rounds[i].Kind, twice.Rounds[i].Kind);
            Assert.Equal(once.Rounds[i].Count, twice.Rounds[i].Count);
            Assert.Equal(once.QuestionsFor(i).Select(q => q.Id),
                         twice.QuestionsFor(i).Select(q => q.Id));
            Assert.Equal(once.QuestionsFor(i).Select(q => q.CorrectAnswer),
                         twice.QuestionsFor(i).Select(q => q.CorrectAnswer));
        }
    }

    [Fact]
    public void Import_assigns_a_new_id_so_it_never_overwrites_an_existing_night()
    {
        // §2.3. Two imports of the SAME co-host file must land as two nights, not
        // one silently replacing the other in the upsert-by-id store.
        var a = LiveEventFile.Decode(GoldenJson());
        var b = LiveEventFile.Decode(GoldenJson());
        Assert.NotEqual(a.Id, b.Id);
        Assert.NotEqual("11111111-2222-3333-4444-555555555555", a.Id);
    }

    [Fact]
    public void Refuses_a_file_that_is_not_a_tidbits_event()
    {
        var ex = Assert.Throws<LiveEventFile.FileFormatException>(
            () => LiveEventFile.Decode("""{"format":"com.example.other","version":1,"event":{}}"""));
        Assert.Contains("not a Tidbits Live event", ex.Message);
    }

    [Fact]
    public void Refuses_a_newer_format_version_by_name()
    {
        var bumped = GoldenJson().Replace("\"version\" : 1", "\"version\" : 99");
        var ex = Assert.Throws<LiveEventFile.FileFormatException>(() => LiveEventFile.Decode(bumped));
        Assert.Contains("99", ex.Message);
    }

    [Fact]
    public void Ignores_unknown_keys_so_additive_fields_need_no_version_bump()
    {
        // §2.4. Without this the forward-compat policy in §1.2 would be unusable:
        // every new optional field would break every older reader.
        var doc = JsonDocument.Parse(GoldenJson());
        var withExtra = GoldenJson().Replace("\"version\" : 1", "\"somethingNew\" : 42,\n  \"version\" : 1");
        var ev = LiveEventFile.Decode(withExtra);
        Assert.Equal(2, ev.Rounds.Count);
        doc.Dispose();
    }

    [Fact]
    public void Question_count_follows_the_authored_list_when_a_round_is_edited()
    {
        var ev = LiveEventFile.Decode(GoldenJson());
        var trimmed = ev.WithQuestions(0, ev.QuestionsFor(0).Take(1).ToList());
        Assert.Equal(1, trimmed.Rounds[0].Count);
        Assert.Equal(1, trimmed.QuestionsFor(0).Count);
        // The other round is untouched.
        Assert.Equal(1, trimmed.Rounds[1].Count);
        Assert.Equal(ev.QuestionsFor(1).Select(q => q.Id), trimmed.QuestionsFor(1).Select(q => q.Id));
    }
}
