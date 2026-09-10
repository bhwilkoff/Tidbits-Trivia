using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A2.14 / 3.81 — the joker: one round per table, named before it starts, worth double.
public class LiveJokerTest
{
    private static readonly string[] Titles = { "General", "Music", "Pictures", "Final" };

    [Fact]
    public void A_joker_can_only_be_played_on_a_round_still_ahead()
    {
        Assert.Equal(new[] { 0, 1, 2, 3 }, LiveJoker.Playable(-1, Titles).Select(r => r.Index));
        Assert.Equal(new[] { 1, 2, 3 }, LiveJoker.Playable(0, Titles).Select(r => r.Index));
        Assert.Empty(LiveJoker.Playable(3, Titles));
        Assert.Equal(new[] { 1, 2 }, LiveJoker.Playable(0, Titles, wager: 3).Select(r => r.Index));   // no joker on the wager round
        Assert.Equal("Round 2", LiveJoker.Playable(0, new[] { "", "" }).Single().Title);
    }

    [Fact]
    public void Locking_a_round_keeps_only_the_picks_for_that_round_by_team()
    {
        var picks = new Dictionary<string, int> { ["u1"] = 2, ["u2"] = 1, ["u3"] = 2, ["u4"] = 2 };
        var teams = new Dictionary<string, string> { ["u1"] = "The Bar", ["u2"] = "Corner", ["u3"] = "The Bar" };
        string? TeamOf(string uid) => teams.GetValueOrDefault(uid);
        Assert.Equal(new HashSet<string> { "The Bar" }, LiveJoker.Played(2, picks, TeamOf));   // two phones, one table (G7)
        Assert.Equal(new HashSet<string> { "Corner" }, LiveJoker.Played(1, picks, TeamOf));
        Assert.Empty(LiveJoker.Played(0, picks, TeamOf));
    }

    [Fact]
    public void A_played_joker_doubles_and_nothing_else_does()
    {
        var played = new HashSet<string> { "The Bar" };
        Assert.Equal(2, LiveJoker.Multiplier("The Bar", played));
        Assert.Equal(1, LiveJoker.Multiplier("Corner", played));
        Assert.Equal(1, LiveJoker.Multiplier("Corner", new HashSet<string>()));
    }

    [Fact]
    public void The_big_screen_names_who_played_or_says_nothing()
    {
        Assert.Null(LiveJoker.Line(System.Array.Empty<string>()));
        Assert.Equal("Joker played: The Bar", LiveJoker.Line(new[] { "The Bar" }));
        Assert.Equal("Jokers played: Corner, The Bar", LiveJoker.Line(new[] { "The Bar", "Corner" }));
    }

    [Fact]
    public void The_wire_keys_match_the_other_stacks()
    {
        var pub = new LiveRoom.Pub
        {
            Round = 1, RoundTitle = "R1", Qid = "r0q0", QNum = 1, QTotal = 2, Phase = "question", Prompt = "?", Format = "classic",
            JokerRounds = new[] { new LiveRoom.JokerRound { Index = 1, Title = "Music" } },
        };
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(pub, Wire.Json));
        var jr = doc.RootElement.GetProperty("jokerRounds")[0];
        Assert.Equal(1, jr.GetProperty("index").GetInt32());
        Assert.Equal("Music", jr.GetProperty("title").GetString());
        using var j = JsonDocument.Parse(JsonSerializer.Serialize(new LiveRoom.Joker { Round = 2 }, Wire.Json));
        Assert.Equal(2, j.RootElement.GetProperty("round").GetInt32());
        using var quiet = JsonDocument.Parse(JsonSerializer.Serialize(pub with { JokerRounds = null }, Wire.Json));
        Assert.False(quiet.RootElement.TryGetProperty("jokerRounds", out _));   // older clients never see it
    }

    [Fact]
    public void An_authored_round_title_survives_the_file_and_names_the_round()
    {
        var ev = new LiveEvent { Name = "Friday", Rounds = new[] { new NightRound { Kind = GameMode.TypeAnswer, Count = 0 } }, RoundTitles = new[] { "Round 1 — Movies" } };
        var back = LiveEventFile.Decode(LiveEventFile.Encode(ev));
        Assert.Equal("Round 1 — Movies", back.RoundTitleAt(0));
        Assert.Equal("Name It", (ev with { RoundTitles = new List<string>() }).RoundTitleAt(0));   // no authored title = the kind's name
    }

    [Fact]
    public void The_joker_flag_rides_the_file()
    {
        var ev = new LiveEvent { Name = "Friday", Joker = true, Rounds = new[] { new NightRound { Kind = GameMode.Classic, Count = 0 } } };
        var back = LiveEventFile.Decode(LiveEventFile.Encode(ev));
        Assert.True(back.Joker);
        Assert.False(LiveEventFile.Decode(LiveEventFile.Encode(ev with { Joker = false })).Joker);
    }
}
