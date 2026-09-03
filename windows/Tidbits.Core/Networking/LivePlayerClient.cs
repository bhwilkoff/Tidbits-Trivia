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

    /// Test seam: put the client into a published-question state without a room.
    /// The join SURFACE is otherwise unreachable offline, and a surface nothing can
    /// drive is untested (hooks-are-coverage).
    public LiveRoom.Pub? PubForTesting { get => Pub; set => Pub = value; }
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

    /// G1: buzz in. The payload is EMPTY on purpose — on a buzz round the answer is
    /// spoken out loud to the room, so all the wire carries is who got here first,
    /// and `Send` stamps that with the SERVER clock.
    public Task SubmitBuzz() => Send(new LiveRoom.Answer { Ts = NowMs() });

    private async Task Send(LiveRoom.Answer ans)
    {
        var pub = Pub;
        if (pub is null || pub.Phase != LiveRoom.Phase.Question || SubmittedQid == pub.Qid || _uid is null) return;
        SubmittedQid = pub.Qid;
        if (pub.Wager == true) ans = ans with { Wager = Math.Max(0, Math.Min(Wager, Score)) };
        if (Blurred) ans = ans with { Blurred = true };
        try { await _db.PutJson($"{LiveRoom.Path(Code)}/answers/{pub.Qid}/{_uid}", WithServerTimestamp(ans)); }
        catch { Chosen = null; SubmittedQid = null; ErrorText = "Answer didn't send — tap again."; Changed?.Invoke(); }
    }

    /// Serialise the answer and add `sv` as the RTDB SERVER timestamp, so the host
    /// ranks submissions by when they ARRIVED at one clock instead of by what each
    /// player's handset thinks the time is. Mirrors Swift
    /// `LivePlayerClient.withServerTimestamp`.
    internal static string WithServerTimestamp(LiveRoom.Answer ans)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(ans);
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        var sb = new System.Text.StringBuilder("{");
        foreach (var prop in doc.RootElement.EnumerateObject())
        {
            if (prop.NameEquals("sv")) continue;          // never send a stale value
            sb.Append(System.Text.Json.JsonSerializer.Serialize(prop.Name)).Append(':')
              .Append(prop.Value.GetRawText()).Append(',');
        }
        sb.Append("\"sv\":{\".sv\":\"timestamp\"}}");
        return sb.ToString();
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
        if (p.Qid != Pub?.Qid) { SubmittedQid = null; Chosen = null; Blurred = false; Wager = 0; }
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
        if (ev.DataJson is not null)
        {
            try
            {
                var m = JsonSerializer.Deserialize<LiveRoom.Meta>(ev.DataJson, Wire.Json);
                // F-010: a host restart on the same code is a new session whose
                // positional qids collide — reset qid-keyed submission state.
                if (m is not null && Meta is not null && m.CreatedAt != Meta.CreatedAt)
                {
                    SubmittedQid = null; Chosen = null;
                }
                Meta = m;
            }
            catch { }
        }
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
        _ = RecordStanding(Meta?.Venue ?? "", Score);
    }

    /// Wave E moat write (3.50): after a live night, add this player's score to
    /// their cumulative per-venue/season standing, keyed by the AUTH uid (the
    /// standings rule requires auth.uid === $uid). The $0 cron aggregates these
    /// into the static cross-venue leaderboard. Byte-identical to web recordStanding.
    private async Task RecordStanding(string venue, int score)
    {
        var vk = PlayerIdentity.VenueKey(venue);
        if (string.IsNullOrEmpty(vk) || score <= 0 || _uid is null) return;
        var path = $"standings/{PlayerIdentity.CurrentSeason()}/{vk}/{_uid}";
        try
        {
            var existing = await _db.Get<StandingWrite>(path);
            await _db.Put(path, new StandingWrite
            {
                Name = LastTeam,
                Score = (existing?.Score ?? 0) + score,
                Nights = (existing?.Nights ?? 0) + 1,
                UpdatedAt = NowMs(),
            });
        }
        catch { /* best-effort; the night's score already showed live */ }
    }

    /// G7: the teams already in a room, so a second phone at a table can JOIN it
    /// instead of quietly starting a near-identical second team.
    ///
    /// No new wire path: this client already read `teams` for the night-end
    /// co-player capture, so the join screen only had to ask earlier.
    public async Task<IReadOnlyList<RosterTeam>> ExistingTeams(string code)
    {
        try
        {
            var teams = await _db.Get<Dictionary<string, LiveRoom.Team>>($"{LiveRoom.Path(code)}/teams");
            if (teams is null) return new List<RosterTeam>();
            var members = teams.Select(kv => new LiveMember
            {
                Uid = kv.Key, TeamName = kv.Value.Name, JoinedAt = kv.Value.JoinedAt,
            }).ToList();
            return LiveTeamRoster.Teams(members);
        }
        catch { return new List<RosterTeam>(); }
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

/// The Wave E standing payload written to standings/{season}/{venue}/{uid} —
/// keys byte-identical to the web/Swift/Kotlin twins so the cron reads them all.
public sealed record StandingWrite
{
    [System.Text.Json.Serialization.JsonPropertyName("name")] public string Name { get; init; } = "";
    [System.Text.Json.Serialization.JsonPropertyName("score")] public int Score { get; init; }
    [System.Text.Json.Serialization.JsonPropertyName("nights")] public int Nights { get; init; }
    [System.Text.Json.Serialization.JsonPropertyName("updatedAt")] public long UpdatedAt { get; init; }
}
