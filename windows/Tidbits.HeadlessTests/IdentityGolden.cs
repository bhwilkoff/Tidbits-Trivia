using System.Text.Json;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// Golden tests for the determinism-critical identity helpers — these MUST be
/// byte-identical across Swift/Kotlin/JS/C# or a cross-platform profile lands on the
/// wrong key or diverges. Values pinned to known outputs.
public class IdentityGolden
{
    [Fact]
    public void AccountKey_is_sha256_of_normalized_email()
    {
        // shasum -a 256 of "test@example.com"
        const string expected = "973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b";
        Assert.Equal(expected, PlayerIdentity.AccountKey("test@example.com"));
        Assert.Equal(expected, PlayerIdentity.AccountKey("  Test@Example.COM  ")); // trim + lowercase
    }

    [Fact]
    public void VenueKey_collapses_non_alnum_runs()
    {
        Assert.Equal("the-rusty-anchor", PlayerIdentity.VenueKey("The Rusty Anchor!!"));
        Assert.Equal("o-brien-s-pub-42", PlayerIdentity.VenueKey("  O'Brien's Pub #42 "));
    }

    [Fact]
    public void CurrentSeason_is_calendar_quarter()
    {
        Assert.Equal("2026-S3", PlayerIdentity.CurrentSeason(new DateTime(2026, 7, 5)));
        Assert.Equal("2026-S1", PlayerIdentity.CurrentSeason(new DateTime(2026, 1, 1)));
        Assert.Equal("2026-S4", PlayerIdentity.CurrentSeason(new DateTime(2026, 12, 31)));
    }

    [Fact]
    public void AvatarHue_is_djb2()
    {
        // djb2("abc") = 193485963 → % 360 = 3 → 3/360
        Assert.Equal(3.0 / 360.0, PlayerIdentity.AvatarHue("abc"), 6);
        var h = PlayerIdentity.AvatarHue("Tidbits");
        Assert.InRange(h, 0.0, 1.0);
    }

    [Fact]
    public void Rating_update_is_elo()
    {
        var r = new PlayerIdentity.Rating(); // 1000, provisional (K=64)
        var updated = r.Updated(accuracy: 1.0, field: 1200);
        Assert.Equal(1, updated.Games);
        Assert.True(updated.Provisional);
        Assert.Equal(1049, updated.Value); // 1000 + 64*(1 - 0.2402) = 1048.6 → 1049
    }

    [Fact]
    public void Streak_play_progression()
    {
        var s0 = new PlayerIdentity.Streak();
        var s1 = s0.Played("2026-07-05");
        Assert.Equal(1, s1.Current);
        var s2 = s1.Played("2026-07-06"); // consecutive
        Assert.Equal(2, s2.Current);
        var s3 = s2.Played("2026-07-10"); // gap 4, no freeze → reset
        Assert.Equal(1, s3.Current);
        Assert.Equal(2, s3.Longest);
    }

    [Fact]
    public void Profile_round_trips_with_contract_keys()
    {
        var p = new PlayerIdentity.Profile
        {
            Name = "Ada", CreatedAt = 123, AvatarSeed = "seed",
            Rating = new PlayerIdentity.Rating { Value = 1200, Games = 20, Provisional = false },
            Streak = new PlayerIdentity.Streak { Current = 3, Longest = 5, LastPlayedDay = "2026-07-05", Freezes = 1 },
            Stats = new PlayerIdentity.Stats { GamesPlayed = 20, QuestionsAnswered = 200, Correct = 150, LiveNights = 2, VenuesVisited = 1 },
        };
        var json = JsonSerializer.Serialize(p, Wire.Json);
        Assert.Contains("\"avatarSeed\":\"seed\"", json);
        Assert.Contains("\"gamesPlayed\":20", json);
        var back = JsonSerializer.Deserialize<PlayerIdentity.Profile>(json, Wire.Json)!;
        Assert.Equal(1200, back.Rating.Value);
        Assert.Equal("2026-07-05", back.Streak.LastPlayedDay);
        Assert.Equal(150, back.Stats.Correct);
    }
}
