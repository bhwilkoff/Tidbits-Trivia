using System.Text.Json;
using System.Text.Json.Serialization;

namespace Tidbits.Core.Networking;

/// Shared wire serializer for the RTDB contract: OMITS null optionals (matching
/// Swift's synthesized `encodeIfPresent` + RTDB's "null deletes a key" semantics),
/// camelCase keys as-declared via JsonPropertyName.
public static class Wire
{
    public static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}

/// The Tidbits Live room wire contract over Firebase RTDB (path `live/{code}`).
/// Byte-compatible twin of Core/Networking/LiveRoom.swift — the SAME keys the
/// Apple host, web (js/live.js), and Android (FirebaseNet.kt) read/write.
/// Additive-only: never repurpose a key; add new optional ones.
public static class LiveRoom
{
    public const string BasePath = "live";
    public static string Path(string code) => $"{BasePath}/{code}";

    /// Stable per-question id used to key answers (survives reveal/advance).
    public static string Qid(int round, int question) => $"r{round}q{question}";

    public static class Phase
    {
        public const string Intro = "intro";
        public const string Question = "question";
        public const string Reveal = "reveal";
        public const string Ended = "ended";
    }

    /// Room identity + lifecycle (host-owned).
    public sealed record Meta
    {
        [JsonPropertyName("host")] public string Host { get; init; } = "";
        [JsonPropertyName("createdAt")] public long CreatedAt { get; init; }
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("venue")] public string Venue { get; init; } = "";
        [JsonPropertyName("state")] public string State { get; init; } = "lobby"; // lobby | live | ended
    }

    /// Closest Call bounds a joiner needs (the answer + tolerance stay on the host).
    public sealed record Numeric
    {
        [JsonPropertyName("min")] public double Min { get; init; }
        [JsonPropertyName("max")] public double Max { get; init; }
        [JsonPropertyName("step")] public double Step { get; init; }
        [JsonPropertyName("unit")] public string Unit { get; init; } = "";
    }

    /// The host-published live state — what every joined player renders.
    public sealed record Pub
    {
        [JsonPropertyName("round")] public int Round { get; init; }
        [JsonPropertyName("roundTitle")] public string RoundTitle { get; init; } = "";
        [JsonPropertyName("qid")] public string Qid { get; init; } = "";
        [JsonPropertyName("qNum")] public int QNum { get; init; }
        [JsonPropertyName("qTotal")] public int QTotal { get; init; }
        [JsonPropertyName("phase")] public string Phase { get; init; } = "";
        [JsonPropertyName("prompt")] public string Prompt { get; init; } = "";
        [JsonPropertyName("options")] public IReadOnlyList<string>? Options { get; init; }
        [JsonPropertyName("format")] public string Format { get; init; } = "";
        [JsonPropertyName("answerIndex")] public int? AnswerIndex { get; init; }  // ONLY in reveal
        // Non-MCQ payloads (additive; only the relevant one per `format`). None leak the answer.
        [JsonPropertyName("imageURL")] public string? ImageUrl { get; init; }
        [JsonPropertyName("numeric")] public Numeric? Numeric { get; init; }
        [JsonPropertyName("orderItems")] public IReadOnlyList<string>? OrderItems { get; init; }
        [JsonPropertyName("matchKeys")] public IReadOnlyList<string>? MatchKeys { get; init; }
        [JsonPropertyName("matchValues")] public IReadOnlyList<string>? MatchValues { get; init; }
        [JsonPropertyName("enumTarget")] public int? EnumTarget { get; init; }
        [JsonPropertyName("locked")] public bool? Locked { get; init; }
        [JsonPropertyName("story")] public string? Story { get; init; }
        [JsonPropertyName("deadline")] public long? Deadline { get; init; }
        [JsonPropertyName("wager")] public bool? Wager { get; init; }
    }

    /// A team as the joining player writes it (`teams/{uid}`).
    public sealed record Team
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("joinedAt")] public long JoinedAt { get; init; }
    }

    /// A player's submission for the current question (`answers/{qid}/{uid}`).
    public sealed record Answer
    {
        [JsonPropertyName("choice")] public int? Choice { get; init; }
        [JsonPropertyName("text")] public string? Text { get; init; }
        [JsonPropertyName("number")] public double? Number { get; init; }
        [JsonPropertyName("order")] public IReadOnlyList<int>? Order { get; init; }
        [JsonPropertyName("pairs")] public IReadOnlyList<int>? Pairs { get; init; }
        [JsonPropertyName("list")] public IReadOnlyList<string>? List { get; init; }
        [JsonPropertyName("wager")] public int? Wager { get; init; }
        [JsonPropertyName("blurred")] public bool? Blurred { get; init; }
        [JsonPropertyName("ts")] public long Ts { get; init; }
    }
}
