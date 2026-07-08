using System;
using System.Text.Json;
using Tidbits.Core.Networking;
using Xunit;

/// Wave E standings write (3.50) — the path pieces + payload must be byte-identical
/// to the web/Swift/Kotlin twins so the $0 cron reads every platform's standings.
public class StandingsWriteTest
{
    [Fact]
    public void Season_id_matches_the_calendar_quarter_format()
    {
        // Web: `${year}-S${floor(month/3)+1}` → Q3 for July.
        Assert.Equal("2026-S3", PlayerIdentity.CurrentSeason(new DateTime(2026, 7, 1)));
        Assert.Equal("2026-S1", PlayerIdentity.CurrentSeason(new DateTime(2026, 1, 31)));
        Assert.Equal("2026-S4", PlayerIdentity.CurrentSeason(new DateTime(2026, 12, 15)));
    }

    [Fact]
    public void Venue_key_is_path_safe()
    {
        var vk = PlayerIdentity.VenueKey("The Anchor & Crown");
        Assert.False(string.IsNullOrEmpty(vk));
        Assert.DoesNotContain(" ", vk);
        Assert.DoesNotContain("/", vk);
        Assert.DoesNotContain("&", vk);
        Assert.Equal("", PlayerIdentity.VenueKey(""));   // empty venue → no standing
    }

    [Fact]
    public void Standing_payload_uses_the_shared_json_keys()
    {
        var json = JsonSerializer.Serialize(new StandingWrite { Name = "Quiz Khalifa", Score = 42, Nights = 3, UpdatedAt = 1720000000000 });
        Assert.Contains("\"name\":\"Quiz Khalifa\"", json);
        Assert.Contains("\"score\":42", json);
        Assert.Contains("\"nights\":3", json);
        Assert.Contains("\"updatedAt\":1720000000000", json);
    }
}
