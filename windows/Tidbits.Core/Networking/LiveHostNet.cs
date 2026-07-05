using System.Text.Json;

namespace Tidbits.Core.Networking;

/// The SHARED Firebase RTDB host bridge (the live/{code} contract) — used by both the
/// Tidbits Live cockpit AND the cross-platform Trivia Night host. The host owns the
/// room: publishes `pub` as it advances, streams joined `teams` + their `answers`,
/// writes `scores`. Core — no UI. Port of MacLiveHostNet_macOS.swift.
///
/// Concurrency: SSE watchers run on background tasks and fold events into the state
/// dicts under a lock; `Changed` fires after each apply. The UI consumer marshals to
/// its thread (the dicts are read via snapshot accessors, also locked).
public sealed class LiveHostNet
{
    private readonly FirebaseRtdb _db;
    private readonly object _lock = new();

    public LiveHostNet(FirebaseRtdb? db = null) => _db = db ?? new FirebaseRtdb();

    public string Code { get; private set; } = "";
    public string HostUid { get; private set; } = "";
    public string? LastError { get; private set; }
    public bool IsOpen => Code.Length > 0;

    private readonly Dictionary<string, LiveRoom.Team> _teams = new();
    private readonly Dictionary<string, int> _scores = new();
    private readonly Dictionary<string, LiveRoom.Answer> _answers = new();

    /// Fires (off the UI thread) after any roster/score/answer change — the consumer marshals.
    public event Action? Changed;

    public readonly record struct Joined(string Id, string Name, int Score);

    public IReadOnlyList<Joined> JoinedList()
    {
        lock (_lock)
            return _teams.Select(kv => new Joined(kv.Key, kv.Value.Name, _scores.GetValueOrDefault(kv.Key)))
                         .OrderByDescending(j => j.Score).ThenBy(j => j.Name, StringComparer.Ordinal).ToList();
    }

    public IReadOnlyDictionary<string, LiveRoom.Answer> AnswersSnapshot()
    {
        lock (_lock) return new Dictionary<string, LiveRoom.Answer>(_answers);
    }

    public int ScoreOf(string uid) { lock (_lock) return _scores.GetValueOrDefault(uid); }
    public int PlayerCount { get { lock (_lock) return _teams.Count; } }
    public int AnsweredCount { get { lock (_lock) return _answers.Count; } }

    private readonly List<CancellationTokenSource> _streamCts = new();
    private CancellationTokenSource? _answersCts;
    private string _currentQid = "";

    // MARK: Lifecycle

    /// Open a room and start streaming joins. Returns the code, or null on failure.
    public async Task<string?> Open(string name, string venue = "")
    {
        try
        {
            var host = await _db.EnsureAuth();
            var code = Environment.GetEnvironmentVariable("TIDBITS_LIVE_CODE") ?? FirebaseRtdb.NewRoomCode();
            var meta = new LiveRoom.Meta { Host = host, CreatedAt = NowMs(), Name = name, Venue = venue, State = "lobby" };
            await _db.Put($"{LiveRoom.Path(code)}/meta", meta);
            Code = code;
            HostUid = host;
            _streamCts.Add(StartWatch($"{LiveRoom.Path(code)}/teams", _teams));
            _streamCts.Add(StartWatch($"{LiveRoom.Path(code)}/scores", _scores));
            return code;
        }
        catch (Exception ex)
        {
            LastError = $"Couldn't open a networked room: {ex.Message}";
            return null;
        }
    }

    public async Task Publish(LiveRoom.Pub pub)
    {
        if (!IsOpen) return;
        if (pub.Qid != _currentQid) // new question → re-key the answers watch
        {
            _currentQid = pub.Qid;
            lock (_lock) _answers.Clear();
            _answersCts?.Cancel();
            _answersCts = StartWatch($"{LiveRoom.Path(Code)}/answers/{pub.Qid}", _answers);
        }
        try { await _db.Put($"{LiveRoom.Path(Code)}/pub", pub); } catch { }
    }

    public async Task SetState(string state)
    {
        if (!IsOpen) return;
        try { await _db.Patch($"{LiveRoom.Path(Code)}/meta", new Dictionary<string, string> { ["state"] = state }); } catch { }
    }

    public async Task SetScore(string uid, int score)
    {
        if (!IsOpen) return;
        try { await _db.Put($"{LiveRoom.Path(Code)}/scores/{uid}", Math.Max(0, score)); } catch { }
    }

    public async Task JoinAsHost(string name)
    {
        if (!IsOpen || HostUid.Length == 0) return;
        try { await _db.Put($"{LiveRoom.Path(Code)}/teams/{HostUid}", new LiveRoom.Team { Name = name, JoinedAt = NowMs() }); } catch { }
    }

    public async Task SubmitHostAnswer(string qid, int choice)
    {
        if (!IsOpen || HostUid.Length == 0) return;
        try { await _db.Put($"{LiveRoom.Path(Code)}/answers/{qid}/{HostUid}", new LiveRoom.Answer { Choice = choice, Ts = NowMs() }); } catch { }
    }

    public async Task Close()
    {
        foreach (var cts in _streamCts) cts.Cancel();
        _answersCts?.Cancel();
        _streamCts.Clear(); _answersCts = null;
        var code = Code;
        Code = "";
        if (code.Length == 0) return;
        try { await _db.Delete(LiveRoom.Path(code)); } catch { }
    }

    // MARK: Streams (self-reconnecting — RTDB resends the whole node on re-subscribe)

    private CancellationTokenSource StartWatch<T>(string path, Dictionary<string, T> dict)
    {
        var cts = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                try
                {
                    await foreach (var ev in _db.Stream(path, cts.Token))
                    {
                        Merge(ev, dict);
                        Changed?.Invoke();
                    }
                }
                catch { /* drop → back off + reconnect */ }
                if (!cts.IsCancellationRequested)
                {
                    try { await Task.Delay(1500, cts.Token); } catch { }
                }
            }
        }, cts.Token);
        return cts;
    }

    /// Fold an RTDB SSE event into a [uid: T] dict. Path "/" replaces the whole node;
    /// "/uid" upserts (or removes on null) one child.
    private void Merge<T>(FirebaseRtdb.StreamEvent ev, Dictionary<string, T> dict)
    {
        lock (_lock)
        {
            if (ev.Path == "/")
            {
                dict.Clear();
                if (ev.DataJson is not null)
                {
                    var map = JsonSerializer.Deserialize<Dictionary<string, T>>(ev.DataJson, Wire.Json);
                    if (map is not null) foreach (var kv in map) dict[kv.Key] = kv.Value;
                }
            }
            else
            {
                var key = ev.Path[1..];
                if (ev.DataJson is not null)
                {
                    var v = JsonSerializer.Deserialize<T>(ev.DataJson, Wire.Json);
                    if (v is not null) dict[key] = v;
                }
                else dict.Remove(key);
            }
        }
    }

    public static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}
