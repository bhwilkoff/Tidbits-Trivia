using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// The online Quick Match client (2.21): claim-or-create a room in the shared
/// matchmaking queue, then both players answer the SAME question set and the higher
/// score wins. Byte-compatible with the web/Android FirebaseNet.quickMatch flow, so
/// a Windows player matches a phone/web player. The live 2-player round-trip is
/// gated (needs a second client); the wire + pure logic are unit-tested.
public sealed class QuickMatchClient
{
    private readonly FirebaseRtdb _db;
    private readonly List<CancellationTokenSource> _tasks = new();

    public QuickMatchClient(FirebaseRtdb? db = null) => _db = db ?? new FirebaseRtdb();

    public string RoomId { get; private set; } = "";
    public bool IsLeader { get; private set; }
    public bool Joined { get; private set; }
    public string Uid { get; private set; } = "";
    public QuickRoomMeta? Meta { get; private set; }
    public IReadOnlyDictionary<string, QuickPlayer> Roster { get; private set; } = new Dictionary<string, QuickPlayer>();
    public event Action? Changed;

    public bool EnoughPlayers => Roster.Count >= 2;
    public bool IsPlaying => Meta?.State == QuickMatch.State_Playing;
    public bool IsFinished => Meta?.State == QuickMatch.State_Finished;

    public int MyScore => Roster.TryGetValue(Uid, out var me) ? me.Score : 0;
    private QuickPlayer? Opp => QuickMatch.OpponentOf(Roster, Uid)?.Value;
    public int OpponentScore => Opp?.Score ?? 0;
    public string OpponentName => Opp?.Name ?? "Opponent";
    public bool OpponentDone => Opp?.Done ?? false;

    /// Claim an advertised waiting room, or create + advertise one (web-tx parity via
    /// an ETag compare-and-set so two players never both claim the same room).
    public async Task FindMatch(string name)
    {
        Uid = await _db.EnsureAuth();
        var who = string.IsNullOrWhiteSpace(name) ? "Player" : name;

        for (int attempt = 0; attempt < 4; attempt++)
        {
            var (queue, etag) = await _db.GetWithEtag<QuickQueueEntry>(QuickMatch.QueuePath);
            if (QuickMatch.ShouldClaim(queue, Uid))
            {
                // Claim: clear the queue (CAS). If we win the race, join that room.
                if (await _db.CasPut<QuickQueueEntry?>(QuickMatch.QueuePath, null, etag))
                {
                    RoomId = queue!.RoomId; IsLeader = false;
                    await JoinSelf(who);
                    Begin();
                    return;
                }
            }
            else
            {
                // Create + advertise (CAS so two creators don't collide on the queue).
                var roomId = FirebaseRtdb.NewRoomCode();
                var now = NowMs();
                await _db.Put($"rooms/{roomId}/meta",
                    new QuickRoomMeta { Host = Uid, CreatedAt = now, State = QuickMatch.State_Lobby });
                RoomId = roomId; IsLeader = true;
                await JoinSelf(who);
                if (await _db.CasPut(QuickMatch.QueuePath, new QuickQueueEntry { RoomId = roomId, Host = Uid, Ts = now }, etag))
                {
                    Begin();
                    return;
                }
                try { await _db.Delete($"rooms/{roomId}/players/{Uid}"); } catch { /* lost the race; retry */ }
            }
        }

        // Fallback: create unconditionally (rare — repeated CAS contention).
        RoomId = FirebaseRtdb.NewRoomCode(); IsLeader = true;
        await _db.Put($"rooms/{RoomId}/meta",
            new QuickRoomMeta { Host = Uid, CreatedAt = NowMs(), State = QuickMatch.State_Lobby });
        await JoinSelf(who);
        Begin();
    }

    private Task JoinSelf(string name) =>
        _db.Put($"rooms/{RoomId}/players/{Uid}",
            new QuickPlayer { Name = name, Score = 0, JoinedAt = NowMs() });

    private void Begin() { Watch(); Joined = true; Changed?.Invoke(); }

    /// Leader publishes the shared set + flips the room to playing.
    public Task PublishQuestions(IReadOnlyList<Question> questions) =>
        _db.Patch($"rooms/{RoomId}/meta", new QuickRoomMeta
        {
            Host = Uid, CreatedAt = Meta?.CreatedAt ?? NowMs(),
            State = QuickMatch.State_Playing, StartedAt = NowMs(),
            Questions = QuickMatch.SerializeQuestions(questions),
        });

    /// Both players read the same set from meta.
    public List<Question> Questions() => QuickMatch.ParseQuestions(Meta?.Questions);

    public async Task ReportScore(int score, bool done)
    {
        // Full PUT of the player (not a partial patch) so the roster stream carries
        // the complete entry — keeps name/joinedAt intact for the other client.
        var joined = Roster.TryGetValue(Uid, out var me) ? me.JoinedAt : NowMs();
        var name = me?.Name ?? "Player";
        try { await _db.Put($"rooms/{RoomId}/players/{Uid}", new QuickPlayer { Name = name, Score = score, JoinedAt = joined, Done = done }); }
        catch { }
        if (done && IsLeader)
            try { await _db.Patch($"rooms/{RoomId}/meta", new { state = QuickMatch.State_Finished }); } catch { }
    }

    public QuickOutcome Outcome() => QuickMatch.Result(MyScore, OpponentScore);

    public async Task Leave()
    {
        foreach (var t in _tasks) t.Cancel();
        _tasks.Clear();
        if (Joined) { try { await _db.Delete($"rooms/{RoomId}/players/{Uid}"); } catch { } }
        Joined = false; RoomId = ""; IsLeader = false; Meta = null;
        Roster = new Dictionary<string, QuickPlayer>();
        Changed?.Invoke();
    }

    // The SSE stream is used purely as a change-TRIGGER; each event re-fetches the
    // authoritative full node. Robust against RTDB incremental put/patch nuance.
    private void Watch()
    {
        _tasks.Add(TriggerTask($"rooms/{RoomId}/players", async () =>
        {
            var r = await _db.Get<Dictionary<string, QuickPlayer>>($"rooms/{RoomId}/players");
            Roster = r ?? new Dictionary<string, QuickPlayer>();
        }));
        _tasks.Add(TriggerTask($"rooms/{RoomId}/meta", async () =>
        {
            Meta = await _db.Get<QuickRoomMeta>($"rooms/{RoomId}/meta");
        }));
    }

    private CancellationTokenSource TriggerTask(string path, Func<Task> refresh)
    {
        var cts = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                try
                {
                    await foreach (var _ in _db.Stream(path, cts.Token))
                    {
                        try { await refresh(); } catch { }
                        Changed?.Invoke();
                    }
                }
                catch { }
                if (!cts.IsCancellationRequested) { try { await Task.Delay(1500, cts.Token); } catch { } }
            }
        }, cts.Token);
        return cts;
    }

    public static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}
