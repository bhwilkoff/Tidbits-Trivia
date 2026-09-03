using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G7 — several phones, one team. The SAME cases as Swift
/// TidbitsTriviaTests/LiveTeamRosterTests.swift: a Mac host and a Windows host
/// must group the same typings into the same teams and agree on who leads.
public class LiveTeamRosterTest
{
    private static LiveMember M(string uid, string team, long at) =>
        new() { Uid = uid, TeamName = team, JoinedAt = at };

    [Fact]
    public void The_same_name_typed_differently_is_one_team()
    {
        var teams = LiveTeamRoster.Teams(new[]
        {
            M("a", "The Quizzinators", 100),
            M("b", "the  quizzinators ", 200),
            M("c", "THE QUIZZINATORS", 300),
        });
        Assert.Single(teams);
        Assert.Equal(3, teams[0].Size);
    }

    [Fact]
    public void The_display_name_is_the_leaders_spelling()
    {
        var teams = LiveTeamRoster.Teams(new[] { M("a", "The Quizzinators", 100), M("b", "the quizzinators", 200) });
        Assert.Equal("The Quizzinators", teams[0].Name);
    }

    [Fact]
    public void Punctuation_is_not_folded()
    {
        // Merging is destructive in a way splitting is not.
        Assert.Equal(2, LiveTeamRoster.Teams(new[] { M("a", "St. Elmo", 100), M("b", "St Elmo", 200) }).Count);
    }

    [Fact]
    public void The_earliest_joiner_leads() =>
        Assert.Equal("early", LiveTeamRoster.Teams(new[] { M("late", "Table 4", 900), M("early", "Table 4", 100) })[0].Leader!.Uid);

    [Fact]
    public void A_same_millisecond_tie_breaks_on_uid()
    {
        var a = LiveTeamRoster.Teams(new[] { M("zeta", "T", 500), M("alpha", "T", 500) });
        var b = LiveTeamRoster.Teams(new[] { M("alpha", "T", 500), M("zeta", "T", 500) });
        Assert.Equal("alpha", a[0].Leader!.Uid);
        Assert.Equal("alpha", b[0].Leader!.Uid);   // input order must not matter
    }

    [Fact]
    public void A_blank_team_name_joins_nothing() =>
        Assert.Empty(LiveTeamRoster.Teams(new[] { M("a", "   ", 100), M("b", "", 200) }));

    [Fact]
    public void The_first_answer_stands()
    {
        var team = LiveTeamRoster.Teams(new[] { M("a", "T", 100), M("b", "T", 200) })[0];
        var who = LiveTeamRoster.AnsweringMember(team, new Dictionary<string, long> { ["b"] = 10, ["a"] = 40 });
        Assert.Equal("b", who);
    }

    [Fact]
    public void A_team_nobody_answered_for_has_no_answer()
    {
        var team = LiveTeamRoster.Teams(new[] { M("a", "T", 100) })[0];
        Assert.Null(LiveTeamRoster.AnsweringMember(team, new Dictionary<string, long>()));
    }

    [Fact]
    public void Answers_from_other_teams_never_count()
    {
        var ours = LiveTeamRoster.Teams(new[] { M("a", "Ours", 100), M("x", "Theirs", 100) })
                                 .First(t => t.Name == "Ours");
        Assert.Null(LiveTeamRoster.AnsweringMember(ours, new Dictionary<string, long> { ["x"] = 5 }));
    }

    [Fact]
    public void When_the_leader_leaves_the_next_member_leads()
    {
        var team = LiveTeamRoster.Teams(new[] { M("a", "T", 100), M("b", "T", 200), M("c", "T", 300) })[0];
        Assert.Equal("b", LiveTeamRoster.LeaderAfterDepartures(team, new HashSet<string> { "a" })!.Uid);
        Assert.Equal("c", LiveTeamRoster.LeaderAfterDepartures(team, new HashSet<string> { "a", "b" })!.Uid);
        Assert.Null(LiveTeamRoster.LeaderAfterDepartures(team, new HashSet<string> { "a", "b", "c" }));
    }

    [Fact]
    public void A_uid_resolves_to_its_own_team()
    {
        var members = new[] { M("a", "Ours", 100), M("x", "Theirs", 100) };
        Assert.Equal("Theirs", LiveTeamRoster.TeamOf("x", members)!.Name);
        Assert.Null(LiveTeamRoster.TeamOf("nobody", members));
    }
}
