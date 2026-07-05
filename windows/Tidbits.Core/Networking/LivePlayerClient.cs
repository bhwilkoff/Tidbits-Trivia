using System.Text.Json;

namespace Tidbits.Core.Networking;

/// A player joining a hosted Tidbits Live / Trivia Night room (the LiveRoom contract
/// over RTDB). Port of LivePlayerClient.swift. The player owns teams/{uid} +
/// answers/{qid}/{uid}; it streams the host's pub, meta, and its own score.
/// `Changed` fires (off the UI thread) after any update — the consumer marshals.
public sealed class LivePlayerClient
{
    private readonly FirebaseRtdb _db;

    public LivePlayerClient(FirebaseRtdb? db = null) => _db = db ?? new FirebaseRtdb();

    public string Code { get; private set; } = "";
    public bool Joined { get; private set; }
    public bool Joining { get; private set; }
    public LiveRoom.Pub? Pub { get; private set; }
    public LiveRoom.Meta? Meta { get; private set; }
    public int Score { get; private set; }
    public int Wager { get; set; }
    public bool Blurred { get; set; }
    public string? SubmittedQid { get; private set; }
    public int? Chosen { get; private set; }
    public string? ErrorText { get; private set; }
    public IReadOnlyList<PlayerIdentity.Friend> Coplayers { get; private set; } = [];

    public event Action? Changed;
    /// Fired once when the night ends (correct, answered, venue, nightScore) — the app
    /// wires this to PlayerIdentityStore (Wave E standing + rating) once that's ported.
    public event Action<int, int, string, int>? NightEnded;

    public bool HasAnswered => Pub is not null && SubmittedQid == Pub.Qid;

    private string? _uid;
    private readonly List<CancellationTokenSource> _tasks = new();
    private int _liveAnswered, _liveCorrect;
    private string? _talliedQid;
    private bool _recordedEnd;

    public static string LastCode { get; private set; } = "";
    public static string LastTeam { get; private set; } = "";

    public async Task Join(string rawCode, string rawTeam)
    {
        var code = new string(rawCode.ToUpperInvariant().Where(char.IsLetterOrDigit).ToArray());
        var team = rawTeam.Trim();
        if (code.Length < 4) { ErrorText = "Enter the 4-letter code from the screen."; return; }
        if (team.Length == 0) { ErrorText = "Enter a team name."; return; }

        Joining = true; ErrorText = null; Changed?.Invoke();
        try
        {
            var uid = await _db.EnsureAuth();
            _uid = uid;
            await _db.Put($"{LiveRoom.Path(code)}/teams/{uid}", new LiveRoom.Team { Name = team, JoinedAt = NowMs() });
            Code = code; Joined = true; Joining = false;
            _liveAnswered = 0; _liveCorrect = 0; _talliedQid = null; _recordedEnd = false;
            LastCode = code; LastTeam = team;
            Watch(code, uid);
            Changed?.Invoke();
        }
        catch
        {
            Joining = false;
            ErrorText = "Couldn't join. Check the code and your connection.";
            Changed?.Invoke();
        }
    }

    public Task SubmitChoice(int choice) { Chosen = choice; return Send(new LiveRoom.Answer { Choice = choice, Ts = NowMs() }); }
    public Task SubmitNumber(double number) => Send(new LiveRoom.Answer { Number = number, Ts = NowMs() });
    public Task SubmitText(string text) => Send(new LiveRoom.Answer { Text = text, Ts = NowMs() });
    public Task SubmitOrder(IReadOnlyList<int> order) => Send(new LiveRoom.Answer { Order = order, Ts = NowMs() });
    public Task SubmitPairs(IReadOnlyList<int> pairs) => Send(new LiveRoom.Answer { Pairs = pairs, Ts = NowMs() });
    public Task SubmitList(IReadOnlyList<string> list) => Send(new LiveRoom.Answer { List = list, Ts = NowMs() });

    private async Task Send(LiveRoom.Answer ans)
    {
        var pub = Pub;
        if (pub is null || pub.Phase != LiveRoom.Phase.Question || SubmittedQid == pub.Qid || _uid is null) return;
        SubmittedQid = pub.Qid;
        if (pub.Wager == true) ans = ans with { Wager = Math.Max(0, Math.Min(Wager, Score)) };
        if (Blurred) ans = ans with { Blurred = true };
        try { await _db.Put($"{LiveRoom.Path(Code)}/answers/{pub.Qid}/{_uid}", ans); }
        catch { Chosen = null; SubmittedQid = null; ErrorText = "Answer didn't send — tap again."; Changed?.Invoke(); }
    }

    public async Task Leave()
    {
        foreach (var t in _tasks) t.Cancel();
        _tasks.Clear();
        if (Joined && _uid is not null) { try { await _db.Delete($"{LiveRoom.Path(Code)}/teams/{_uid}"); } catch { } }
        Joined = false; Pub = null; Meta = null; Score = 0; Code = ""; SubmittedQid = null; Chosen = null;
        Changed?.Invoke();
    }

    private void Watch(string code, string uid)
    {
        _tasks.Add(StreamTask($"{LiveRoom.Path(code)}/pub", ApplyPub));
        _tasks.Add(StreamTask($"{LiveRoom.Path(code)}/meta", ApplyMeta));
        _tasks.Add(StreamTask($"{LiveRoom.Path(code)}/scores/{uid}", ApplyScore));
    }

    private CancellationTokenSource StreamTask(string path, Action<FirebaseRtdb.StreamEvent> apply)
    {
        var cts = new CancellationTokenSource();
        _ = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                try { await foreach (var ev in _db.Stream(path, cts.Token)) { apply(ev); Changed?.Invoke(); } }
                catch { }
                if (!cts.IsCancellationRequested) { try { await Task.Delay(1500, cts.Token); } catch { } }
            }
        }, cts.Token);
        return cts;
    }

    private void ApplyPub(FirebaseRtdb.StreamEvent ev)
    {
        LiveRoom.Pub? p = null;
        if (ev.DataJson is not null) { try { p = JsonSerializer.Deserialize<LiveRoom.Pub>(ev.DataJson, Wire.Json); } catch { } }
        if (p is null) { Pub = null; return; }
        if (p.Qid != Pub?.Qid) { SubmittedQid = null; Chosen = null; Blurred = false; }
        Pub = p;
        if (p.Phase == LiveRoom.Phase.Reveal && _talliedQid != p.Qid)
        {
            _talliedQid = p.Qid;
            if (p.Options is not null && SubmittedQid == p.Qid)
            {
                _liveAnswered++;
                if (Chosen == p.AnswerIndex) _liveCorrect++;
            }
        }
        RecordIfEnded();
    }

    private void ApplyMeta(FirebaseRtdb.StreamEvent ev)
    {
        if (ev.DataJson is not null) { try { Meta = JsonSerializer.Deserialize<LiveRoom.Meta>(ev.DataJson, Wire.Json); } catch { } }
        RecordIfEnded();
    }

    private void ApplyScore(FirebaseRtdb.StreamEvent ev)
    {
        Score = ev.DataJson is not null && int.TryParse(ev.DataJson, out var v) ? v : 0;
    }

    private void RecordIfEnded()
    {
        if (!Joined || _recordedEnd) return;
        if (Meta?.State != "ended" && Pub?.Phase != LiveRoom.Phase.Ended) return;
        _recordedEnd = true;
        NightEnded?.Invoke(_liveCorrect, _liveAnswered, Meta?.Venue ?? "", Score);
        _ = CaptureCoplayers();
    }

    private async Task CaptureCoplayers()
    {
        if (_uid is null) return;
        try
        {
            var teams = await _db.Get<Dictionary<string, LiveRoom.Team>>($"{LiveRoom.Path(Code)}/teams");
            if (teams is null) return;
            Coplayers = teams.Where(kv => kv.Key != _uid)
                             .Select(kv => new PlayerIdentity.Friend { Uid = kv.Key, Name = kv.Value.Name }).ToList();
        }
        catch { }
    }

    public static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}
