using System.Collections.Generic;
using System.Text.Json;
using Tidbits.Core.Models;
using Tidbits.App.Services;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Audit A.6 — the Wave A per-round countdown (macOS `LiveRound.timerSeconds` parity).
///
/// The timer rides `LiveEvent.RoundTimers`, index-aligned like `RoundNotes`, and NOT
/// `NightRound`: that is the wire type serialized to every joiner, Apple pins its
/// CodingKeys to {kind, count}, and there is golden coverage on it.
public class RoundTimerTest
{
    [Fact]
    public void Round_timer_is_read_by_round_index_and_defaults_to_untimed()
    {
        var data = GameData.FromDirectory(
            System.IO.Path.Combine(System.AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"),
                                     data.Provider, "Quick Night")
        {
            RoundTimers = new List<int> { 60, 0, 90 },
        };
        // No question on screen yet -> RoundIndex 0.
        Assert.Equal(60, host.RoundTimerSeconds);

        host.RoundTimers = new List<int>();          // authored nothing
        Assert.Equal(0, host.RoundTimerSeconds);     // untimed, never an exception
    }

    /// An older saved event has no roundTimers key at all; it must still decode.
    [Fact]
    public void Saved_events_without_round_timers_still_decode()
    {
        const string legacy = """
        {"id":"abc","name":"Pub Night","rounds":[{"kind":"classic","count":5}],"roundNotes":["x"]}
        """;
        var ev = JsonSerializer.Deserialize<LiveEvent>(legacy);
        Assert.NotNull(ev);
        Assert.Empty(ev!.RoundTimers);               // absent -> untimed, not a crash
        Assert.Single(ev.Rounds);
        Assert.Equal("Pub Night", ev.Name);
    }

    /// And a round-trip keeps them.
    [Fact]
    public void Round_timers_survive_a_save_and_reload()
    {
        var ev = new LiveEvent
        {
            Name = "Timed Night",
            Rounds = new List<NightRound> { new() { Kind = GameMode.Classic, Count = 4 } },
            RoundTimers = new List<int> { 45 },
        };
        var back = JsonSerializer.Deserialize<LiveEvent>(JsonSerializer.Serialize(ev))!;
        Assert.Equal(new[] { 45 }, back.RoundTimers);
    }

    /// The wire type stays clean — a joiner must not start receiving a new key.
    [Fact]
    public void NightRound_wire_shape_is_unchanged()
    {
        var json = JsonSerializer.Serialize(new NightRound { Kind = GameMode.Classic, Count = 5 });
        Assert.Contains("\"kind\"", json);
        Assert.Contains("\"count\"", json);
        Assert.DoesNotContain("timer", json, System.StringComparison.OrdinalIgnoreCase);
    }
}
