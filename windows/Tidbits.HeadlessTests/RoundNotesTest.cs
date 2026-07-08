using System.Collections.Generic;
using System.IO;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

public class RoundNotesTest
{
    [Fact]
    public void Round_notes_persist_index_aligned()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-notes-{System.Guid.NewGuid():N}.json");
        try
        {
            var store = new LiveEventStore(path);
            store.Save(new LiveEvent
            {
                Name = "Pub Quiz",
                Rounds = new List<NightRound>
                {
                    new() { Kind = GameMode.Classic, Count = 5 },
                    new() { Kind = GameMode.Classic, Count = 5 },
                },
                RoundNotes = new List<string> { "warm-up, keep it light", "" },
            });
            var reloaded = new LiveEventStore(path).All[0];
            Assert.Equal(2, reloaded.RoundNotes.Count);
            Assert.Equal("warm-up, keep it light", reloaded.RoundNotes[0]);
            Assert.Equal("", reloaded.RoundNotes[1]);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public void Host_current_round_note_null_without_a_live_question()
    {
        var data = Tidbits.App.Services.GameData.Shared.Value;
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "N")
        {
            RoundNotes = new List<string> { "a note" },
        };
        Assert.Null(host.CurrentRoundNote); // no Current question (no room) → null, cockpit hides it
    }
}
