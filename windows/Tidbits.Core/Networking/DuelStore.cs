using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

// L5 async friend duels (port of js/duels.js): challenge a friend to the SAME
// question set, answer on your own time, higher score wins. Serverless — a duel
// lives at duels/{id} (create-once + per-player score slots); the challenger drops
// an invite into the friend's private duelInbox/{uid}.

/// Compact question form stored in a duel (byte-keyed to the JS twin: p/o/c/e).
public sealed record DuelQuestion
{
    [JsonPropertyName("p")] public string P { get; init; } = "";
    [JsonPropertyName("o")] public IReadOnlyList<string> O { get; init; } = new List<string>();
    [JsonPropertyName("c")] public int C { get; init; }
    [JsonPropertyName("e")] public string E { get; init; } = "";
}

public sealed record DuelPlayer
{
    [JsonPropertyName("name")] public string Name { get; init; } = "";
    [JsonPropertyName("done")] public bool Done { get; init; }
    [JsonPropertyName("score")] public int Score { get; init; }
}

public sealed record Duel
{
    [JsonPropertyName("createdBy")] public string CreatedBy { get; init; } = "";
    [JsonPropertyName("createdAt")] public long CreatedAt { get; init; }
    [JsonPropertyName("challenged")] public string Challenged { get; init; } = "";
    [JsonPropertyName("questions")] public IReadOnlyList<DuelQuestion> Questions { get; init; } = new List<DuelQuestion>();
    [JsonPropertyName("players")] public Dictionary<string, DuelPlayer> Players { get; init; } = new();
}

public sealed record DuelInvite
{
    [JsonPropertyName("from")] public string From { get; init; } = "";
    [JsonPropertyName("fromName")] public string FromName { get; init; } = "A friend";
    [JsonPropertyName("at")] public long At { get; init; }
    [JsonIgnore] public string Id { get; set; } = "";
}

/// One of my active duels, classified for the list UI.
public sealed record DuelSummary(string Id, bool MyDone, int MyScore, string OppUid, string OppName, bool OppDone, int OppScore)
{
    public DuelOutcome Outcome => DuelStore.Classify(MyDone, OppDone, MyScore, OppScore);
}

public enum DuelOutcome { YourTurn, WaitingOnThem, YouWon, YouLost, Tie }

public sealed class DuelStore
{
    private readonly string _path;
    private List<string> _ids = new();

    public DuelStore(string path)
    {
        _path = path;
        try
        {
            if (System.IO.File.Exists(path))
                _ids = JsonSerializer.Deserialize<List<string>>(System.IO.File.ReadAllText(path)) ?? new();
        }
        catch { _ids = new(); }
    }

    public IReadOnlyList<string> Ids => _ids;

    /// Track a duel id I'm participating in (newest-first, capped at 40 — there's no
    /// server-side "my duels" query, so this is the local index).
    public void Track(string id)
    {
        if (string.IsNullOrEmpty(id) || _ids.Contains(id)) return;
        _ids = new[] { id }.Concat(_ids).Take(40).ToList();
        Persist();
    }

    private void Persist()
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_path, JsonSerializer.Serialize(_ids));
        }
        catch { /* best-effort */ }
    }

    // MARK: Pure logic (unit-testable without a network)

    public static string NewId() =>
        DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString("x") + Guid.NewGuid().ToString("N")[..6];

    public static List<DuelQuestion> Compact(IEnumerable<Question> questions) =>
        questions.Select(q => new DuelQuestion { P = q.Prompt, O = q.Options, C = q.CorrectIndex, E = q.Explanation }).ToList();

    /// Reconstruct playable questions from a duel's compact set.
    public static List<Question> QuestionsOf(Duel? duel) =>
        (duel?.Questions ?? new List<DuelQuestion>()).Select((q, i) => new Question
        {
            Id = $"duel-{i}", Prompt = q.P, Options = q.O, CorrectIndex = q.C,
            Explanation = q.E, CategoryId = "mixed", Difficulty = 3,
        }).ToList();

    /// Whose turn / who won — the whole duel state machine in one pure function.
    public static DuelOutcome Classify(bool myDone, bool oppDone, int myScore, int oppScore)
    {
        if (!myDone) return DuelOutcome.YourTurn;
        if (!oppDone) return DuelOutcome.WaitingOnThem;
        return myScore > oppScore ? DuelOutcome.YouWon
            : myScore < oppScore ? DuelOutcome.YouLost : DuelOutcome.Tie;
    }

    // MARK: Networked (RTDB) — gated smoke, mirrors js/duels.js

    /// Challenger creates a duel with a shared set + invites the friend. Returns the id.
    public async Task<string?> Challenge(FirebaseRtdb rtdb, PlayerIdentity.Friend friend, string myName, IReadOnlyList<Question> questions)
    {
        var me = await rtdb.EnsureAuth();
        if (string.IsNullOrEmpty(me) || string.IsNullOrEmpty(friend.Uid) || questions.Count == 0) return null;
        var id = NewId();
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        await rtdb.Put($"duels/{id}", new Duel
        {
            CreatedBy = me, CreatedAt = now, Challenged = friend.Uid,
            Questions = Compact(questions),
            Players = new() { [me] = new DuelPlayer { Name = myName, Done = false, Score = 0 } },
        });
        await rtdb.Put($"duelInbox/{friend.Uid}/{id}", new DuelInvite { From = me, FromName = myName, At = now });
        Track(id);
        return id;
    }

    public Task<Duel?> Load(FirebaseRtdb rtdb, string id) => rtdb.Get<Duel>($"duels/{id}");

    /// Write ONLY my own players/{uid} slot (rules-enforced).
    public async Task Submit(FirebaseRtdb rtdb, string id, string myName, int score)
    {
        var me = await rtdb.EnsureAuth();
        if (string.IsNullOrEmpty(me)) return;
        await rtdb.Put($"duels/{id}/players/{me}", new DuelPlayer { Name = myName, Done = true, Score = score });
        Track(id);
    }

    public async Task<List<DuelInvite>> Inbox(FirebaseRtdb rtdb)
    {
        var me = await rtdb.EnsureAuth();
        if (string.IsNullOrEmpty(me)) return new();
        var raw = await rtdb.Get<Dictionary<string, DuelInvite>>($"duelInbox/{me}");
        return (raw ?? new()).Select(kv => { kv.Value.Id = kv.Key; return kv.Value; })
            .OrderByDescending(v => v.At).ToList();
    }

    public async Task Accept(FirebaseRtdb rtdb, string id)
    {
        Track(id);
        var me = await rtdb.EnsureAuth();
        if (!string.IsNullOrEmpty(me)) await rtdb.Delete($"duelInbox/{me}/{id}");
    }

    /// My active duels — fetch each tracked id + classify.
    public async Task<List<DuelSummary>> Mine(FirebaseRtdb rtdb)
    {
        var me = await rtdb.EnsureAuth();
        if (string.IsNullOrEmpty(me)) return new();
        var outp = new List<DuelSummary>();
        foreach (var id in _ids)
        {
            var d = await Load(rtdb, id);
            if (d is null) continue;
            d.Players.TryGetValue(me, out var mine);
            var oppUid = d.Players.Keys.FirstOrDefault(u => u != me) ?? d.Challenged;
            DuelPlayer? opp = !string.IsNullOrEmpty(oppUid) && d.Players.TryGetValue(oppUid, out var o) ? o : null;
            outp.Add(new DuelSummary(id, mine?.Done ?? false, mine?.Score ?? 0,
                oppUid ?? "", opp?.Name ?? "Opponent", opp?.Done ?? false, opp?.Score ?? 0));
        }
        return outp;
    }
}
