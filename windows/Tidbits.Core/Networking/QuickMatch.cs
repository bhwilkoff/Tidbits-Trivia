using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// Online Quick Match (2.21) wire types + pure logic. Byte-keyed to the web/Android
/// Firebase RTDB schema so a Windows player matches a web/phone player:
///   queue/mixed              -> QuickQueueEntry (the advertised waiting room)
///   rooms/{id}/meta          -> QuickRoomMeta   (lobby -> playing[+questions] -> finished)
///   rooms/{id}/players/{uid} -> QuickPlayer     (name/score/joinedAt/done)
/// Contract mirrors js/firebase.js quickMatch/onRoster/onMeta/reportScore.

public sealed record QuickQueueEntry
{
    [JsonPropertyName("roomId")] public string RoomId { get; init; } = "";
    [JsonPropertyName("host")] public string Host { get; init; } = "";
    [JsonPropertyName("ts")] public long Ts { get; init; }
}

public sealed record QuickRoomMeta
{
    [JsonPropertyName("host")] public string Host { get; init; } = "";
    [JsonPropertyName("createdAt")] public long CreatedAt { get; init; }
    /// lobby -> playing -> finished.
    [JsonPropertyName("state")] public string State { get; init; } = "lobby";
    [JsonPropertyName("startedAt")] public long? StartedAt { get; init; }
    /// The shared question set, JSON-stringified (the leader writes it; both parse it).
    [JsonPropertyName("questions")] public string? Questions { get; init; }
}

public sealed record QuickPlayer
{
    [JsonPropertyName("name")] public string Name { get; init; } = "Player";
    [JsonPropertyName("score")] public int Score { get; init; }
    [JsonPropertyName("joinedAt")] public long JoinedAt { get; init; }
    [JsonPropertyName("done")] public bool Done { get; init; }
}

public enum QuickOutcome { Win, Lose, Tie }

public static class QuickMatch
{
    public const string QueuePath = "queue/mixed";
    public const string State_Lobby = "lobby";
    public const string State_Playing = "playing";
    public const string State_Finished = "finished";

    /// Claim an advertised room iff one is waiting and it isn't mine (web tx parity).
    public static bool ShouldClaim(QuickQueueEntry? queue, string myUid) =>
        queue is { } q && !string.IsNullOrEmpty(q.RoomId) && q.Host != myUid;

    /// The result vs the opponent's score (best score wins; equal = tie).
    public static QuickOutcome Result(int myScore, int oppScore) =>
        myScore > oppScore ? QuickOutcome.Win : myScore < oppScore ? QuickOutcome.Lose : QuickOutcome.Tie;

    /// The shared question set is stored JSON-stringified in meta (the leader writes
    /// it; both parse it) — matching the web JSON.stringify(qs.map(toWire)).
    public static string SerializeQuestions(IReadOnlyList<Question> questions) =>
        JsonSerializer.Serialize(questions, Wire.Json);

    public static List<Question> ParseQuestions(string? json)
    {
        if (string.IsNullOrEmpty(json)) return new();
        try { return JsonSerializer.Deserialize<List<Question>>(json, Wire.Json) ?? new(); }
        catch { return new(); }
    }

    /// The opponent = any roster entry that isn't me (2-player match).
    public static KeyValuePair<string, QuickPlayer>? OpponentOf(
        IReadOnlyDictionary<string, QuickPlayer> roster, string myUid)
    {
        foreach (var kv in roster)
            if (kv.Key != myUid) return kv;
        return null;
    }
}
