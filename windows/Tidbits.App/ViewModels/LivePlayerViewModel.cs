using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Networking;

namespace Tidbits.App.ViewModels;

/// Wraps a LivePlayerClient for the join surface. Marshals the client's off-thread
/// SSE updates to the UI thread.
public sealed class LivePlayerViewModel : ObservableObject
{
    public LivePlayerClient Client { get; }

    public LivePlayerViewModel(LivePlayerClient? client = null)
    {
        Client = client ?? new LivePlayerClient();
        Client.Changed += () => Dispatcher.UIThread.Post(() => OnPropertyChanged(string.Empty));
        // The night ended: feed the portable identity (rating + streak + a freeze). The
        // client raised this event since 1.6.x and nothing had ever subscribed.
        Client.NightEnded += (correct, answered, _, _) =>
        {
            Services.LaunchHooks.Diag($"night ended: correct={correct} answered={answered} recorder={(NightRecorded is null ? "unset" : "set")}");
            NightRecorded?.Invoke(correct, answered);
            Dispatcher.UIThread.Post(() => { _counted = true; OnPropertyChanged(string.Empty); });
        };
    }

    /// Set once by GameData; a static seam for the same reason as GameViewModel.GameRecorded.
    public static Action<int, int>? NightRecorded { get; set; }
    private bool _counted;
    public bool Counted => _counted;
    public string CountedLine => NightRecorded is null ? "" : "Counted toward your streak and Tidbits Rating.";

    // Bound as VM properties on purpose: a path through `Client` (`Client.Pub.Prompt`)
    // never re-evaluates once `Client` itself is unchanged — Avalonia re-reads a
    // chain only from the node that changed, and `Client` is not INotifyPropertyChanged.
    // Measured on the real box: a joiner that showed the options and a BLANK band
    // where the question should be, and no room name, all night.
    public string Prompt => Client.Pub?.Prompt ?? "";
    /// A3.14: the room is on a break — say so instead of leaving a stale question up.
    public bool IsOnBreak => Client.Pub?.OnBreak == true;
    public string BreakHeadline => LiveBreak.Headline(Client.Pub?.BreakUntil, LiveClock.HostNow(Client.HostOffsetMs));
    public string BreakSubline
    {
        get
        {
            var clock = LiveBreak.ClockLine(Client.Pub?.BreakUntil, LiveClock.HostNow(Client.HostOffsetMs));
            return clock.Length == 0 ? "Grab a drink — the next round is coming up." : $"Grab a drink — {clock}.";
        }
    }

    /// A2.11: what a question is worth on a double-points round (hidden at 1 pt).
    public string WorthLine => Client.Pub?.Points is int p && p > 1 ? $"WORTH {p} PTS" : "";
    public bool HasWorth => WorthLine.Length > 0 && ShowQuestion;
    public string RoomName => Client.Meta?.Name ?? "";
    public int Score => Client.Score;
    public string? ErrorText => Client.ErrorText;
    public bool HasError => Client.ErrorText is not null;

    public Task Join(string code, string team) => Client.Join(code, team);
    public Task SubmitChoice(int i) => Client.SubmitChoice(i);
    public Task Leave() => Client.Leave();

    // UI state
    public bool NotJoined => !Client.Joined;
    public bool WaitingForStart => Client.Joined && Client.Pub is null && !Client.Ended;   // a torn-down room after the wrap is not a lobby
    public bool ShowQuestion => Client.Pub?.Phase == LiveRoom.Phase.Question;
    public bool ShowReveal => Client.Pub?.Phase == LiveRoom.Phase.Reveal;
    // Final wager round — stake 0…your score before answering.
    public bool IsWager => ShowQuestion && Client.Pub?.Wager == true;

    /// G1: a BUZZ question — the player gets one big BUZZ button instead of the
    /// answer UI, and the FIRST buzz the server sees wins. Hidden once they have
    /// buzzed, so nobody hammers it thinking it did not register.
    public bool IsBuzz => ShowQuestion && Client.Pub?.Buzz == true;
    public bool CanBuzz => IsBuzz && !Client.HasAnswered;
    public bool HasBuzzed => IsBuzz && Client.HasAnswered;
    public int MaxWager => Client.Score;
    public int Wager { get => Client.Wager; set => Client.Wager = value; }
    public bool IsEnded => Client.Ended || Client.Meta?.State == "ended" || Client.Pub?.Phase == LiveRoom.Phase.Ended;
    public string FinalScoreLine => $"Final score: {Client.Score}";
    public System.Collections.Generic.IReadOnlyList<LiveRecapEntry> RecapTough => Client.Recap.Tough;
    public System.Collections.Generic.IReadOnlyList<LiveRecapEntry> RecapToRemember => Client.Recap.ToRemember;
    public bool Answered => Client.HasAnswered;
    /// A buzz is an answer, but it has its own confirmation line, so the
    /// generic "Answer locked" must stand down or the player is told twice.
    public bool AnswerLocked => Client.HasAnswered && !IsBuzz;

    /// G4: the first-letter rule for this round, or null when it has no theme. A
    /// player who joined mid-round never heard the host announce it, so it rides
    /// the wire rather than the room's memory.
    public string? LetterBanner
    {
        get
        {
            var l = Client.Pub?.Letter;
            if (!ShowQuestion || string.IsNullOrWhiteSpace(l)) return null;
            return LiveLetterRound.Banner(l[0]);
        }
    }
    public bool HasLetter => LetterBanner != null;

    /// G5: the pick-a-category grid is up, so no question is being asked. The
    /// answer surface must be GONE, not disabled — otherwise this phone can still
    /// answer the PREVIOUS question while the room is choosing.
    /// G7: the room's tables, offered on the join screen so a second phone can
    /// join its table instead of starting a near-identical second team.
    private IReadOnlyList<RosterTeam> _roomTeams = new List<RosterTeam>();
    public IReadOnlyList<RosterTeam> RoomTeams
    {
        get => _roomTeams;
        private set { _roomTeams = value; OnPropertyChanged(nameof(RoomTeams)); OnPropertyChanged(nameof(HasRoomTeams)); }
    }
    public bool HasRoomTeams => RoomTeams.Count > 0;

    /// Look the room up once the code is complete, so the tables are on screen
    /// BEFORE the player commits to a name.
    public async Task LoadRoomTeams(string code)
    {
        RoomTeams = code.Length == 4 ? await Client.ExistingTeams(code) : new List<RosterTeam>();
    }

    public bool IsBoard => Client.Pub?.Phase == LiveRoom.Phase.Board && Client.Pub?.Board is not null;
    /// The prompt only when a question is actually being asked.
    /// The prompt stays through the REVEAL (every other joiner keeps it; the room is
    /// still talking about the question) — only the board phase hides it.
    public bool ShowQuestionOnly => (ShowQuestion || ShowReveal) && !IsBoard && !IsOnBreak;
    /// Answer buttons: never on a buzz round, never while the grid is up.
    public bool ShowOptions => !IsBuzz && !IsBoard && !IsOnBreak;
    public string BoardHeadline =>
        Client.Pub?.Board?.Chooser is { Length: > 0 } who ? $"{who} picks" : "Pick a category";
    public string BoardSummary =>
        Client.Pub?.Board is { } b ? $"{b.Remaining} left · {b.Points:N0} points on the board" : "";

    // L5 social graph — "add the people you played with" at the wrap.
    // Decision 060: the host's clip, offered here too. Nothing plays until the
    // player clicks; the host's cue readies it and positions it where the room is.
    public LiveRoom.Media? Media => Client.Pub?.Phase is LiveRoom.Phase.Question or LiveRoom.Phase.Reveal ? Client.Pub?.Media : null;
    public bool HasMedia => Media is not null;
    public string MediaTitle => Media?.Kind == "video" ? "Watch the clip" : "Listen to the clip";
    public string MediaSubtitle
    {
        get
        {
            var m = Media; if (m is null) return "";
            if (m.StartedAt is not null) return "Playing in the room now — click to hear it here";
            var size = m.Bytes is { } b ? (b >= 1_000_000 ? $" · {b / 1_000_000.0:F1} MB" : $" · {System.Math.Max(1, b / 1000)} KB") : "";
            return (m.Name ?? (m.Kind == "video" ? "Video" : "Audio")) + size;
        }
    }
    public string MediaKey => Media is { } m ? $"{Client.Pub?.Qid}|{m.Url}" : "";
    /// The question's picture: the small fallback now, the room node's full
    /// version once fetched (Decision 060). The Windows joiner never showed a
    /// picture at all before this.
    public string? PictureFallback => Client.Pub?.ImageUrl;
    public LiveRoom.Media? Picture => Client.Pub?.Picture;
    public bool HasPicture => !string.IsNullOrWhiteSpace(PictureFallback) || Picture is not null;
    public string PictureKey => $"{Client.Pub?.Qid}|{Picture?.Url}|{(PictureFallback ?? "").Length}";
    public System.Collections.Generic.IReadOnlyList<PlayerIdentity.Friend> Coplayers => Client.Coplayers;
    public bool HasCoplayers => IsEnded && Client.Coplayers.Count > 0;
    public bool IsFriend(string uid) { try { return Services.GameData.Shared.Value.Friends.Contains(uid); } catch { return false; } }
    public void AddFriend(PlayerIdentity.Friend f) { try { Services.GameData.Shared.Value.Friends.Add(f); } catch { } }

    /// Seconds left on the host's published deadline (Wave A join display), or null
    /// when no timer is running / not on a live question.
    public int? SecondsRemaining
    {
        get
        {
            if (!ShowQuestion) return null;
            return LiveClock.SecondsRemaining(Client.Pub?.Deadline, Client.HostOffsetMs);
        }
    }

    /// On reveal: the correct option text + the host's "story behind the answer".
    public string? RevealAnswerLine
    {
        get
        {
            var p = Client.Pub;
            if (!ShowReveal || p?.AnswerIndex is not { } ai || p.Options is not { } opts
                || ai < 0 || ai >= opts.Count) return null;
            return opts[ai];
        }
    }
    public bool HasRevealAnswer => RevealAnswerLine is not null;
    /// A2.10: a poll's reveal thanks the room instead of naming an answer.
    public bool IsPollReveal => ShowReveal && Client.Pub?.Poll == true;
    public string? Story => Client.Pub?.Story;
    public bool HasStory => ShowReveal && !string.IsNullOrEmpty(Client.Pub?.Story);
    /// The charter: where the fact came from (reveal only).
    public bool HasSource => ShowReveal && !string.IsNullOrWhiteSpace(Client.Pub?.Source?.Title);
    public string SourceLine => Client.Pub?.Source is { } s
        ? (string.IsNullOrWhiteSpace(s.Url) ? $"From Wikipedia · {s.Title}" : $"Learn more on Wikipedia · {s.Title}") : "";
    public string? SourceUrl => Client.Pub?.Source?.Url;
}
