using System.Text.Json;
using Tidbits.Core.Networking;

namespace Tidbits.HeadlessTests;

/// Wire-contract tests for the Live room types: the serialized JSON uses the EXACT
/// cross-platform keys, omits null optionals (so the answer never leaks pre-reveal
/// and RTDB nulls don't delete keys), and round-trips. Byte-compatible with the
/// Apple/web/Android twins.
public class LiveWireGolden
{
    [Fact]
    public void Question_pub_has_contract_keys_and_omits_nulls()
    {
        var pub = new LiveRoom.Pub
        {
            Round = 1, RoundTitle = "History", Qid = "r0q1", QNum = 1, QTotal = 5,
            Phase = LiveRoom.Phase.Question, Prompt = "Who?",
            Options = new[] { "A", "B", "C", "D" }, Format = "classic",
        };
        var json = JsonSerializer.Serialize(pub, Wire.Json);

        Assert.Contains("\"roundTitle\":\"History\"", json);
        Assert.Contains("\"qNum\":1", json);
        Assert.Contains("\"qTotal\":5", json);
        Assert.Contains("\"options\":[\"A\",\"B\",\"C\",\"D\"]", json);
        // Answer + unused shape payloads must be OMITTED (never leaked pre-reveal).
        Assert.DoesNotContain("answerIndex", json);
        Assert.DoesNotContain("imageURL", json);
        Assert.DoesNotContain("numeric", json);
        Assert.DoesNotContain("locked", json);
    }

    [Fact]
    public void Reveal_pub_includes_answerIndex()
    {
        var pub = new LiveRoom.Pub { Round = 1, Qid = "r0q1", Phase = LiveRoom.Phase.Reveal, Format = "classic", AnswerIndex = 2 };
        Assert.Contains("\"answerIndex\":2", JsonSerializer.Serialize(pub, Wire.Json));
    }

    [Fact]
    public void Answer_omits_unused_shape_fields()
    {
        var json = JsonSerializer.Serialize(new LiveRoom.Answer { Choice = 1, Ts = 123 }, Wire.Json);
        Assert.Contains("\"choice\":1", json);
        Assert.Contains("\"ts\":123", json);
        Assert.DoesNotContain("text", json);
        Assert.DoesNotContain("number", json);
        Assert.DoesNotContain("wager", json);
    }

    [Fact]
    public void Pub_round_trips()
    {
        var pub = new LiveRoom.Pub
        {
            Round = 2, RoundTitle = "Sci", Qid = "r1q3", QNum = 3, QTotal = 4,
            Phase = "question", Prompt = "P", Format = "closestCall",
            Numeric = new LiveRoom.Numeric { Min = 0, Max = 100, Step = 1, Unit = "kg" },
        };
        var back = JsonSerializer.Deserialize<LiveRoom.Pub>(JsonSerializer.Serialize(pub, Wire.Json), Wire.Json)!;
        Assert.Equal("r1q3", back.Qid);
        Assert.Equal("closestCall", back.Format);
        Assert.Equal(100, back.Numeric!.Max);
        Assert.Equal("kg", back.Numeric.Unit);
    }
}
