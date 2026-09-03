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
    }

    public Task Join(string code, string team) => Client.Join(code, team);
    public Task SubmitChoice(int i) => Client.SubmitChoice(i);
    public Task Leave() => Client.Leave();

    // UI state
    public bool NotJoined => !Client.Joined;
    public bool WaitingForStart => Client.Joined && Client.Pub is null;
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
    public bool IsEnded => Client.Meta?.State == "ended" || Client.Pub?.Phase == LiveRoom.Phase.Ended;
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
    public bool IsBoard => Client.Pub?.Phase == LiveRoom.Phase.Board && Client.Pub?.Board is not null;
    /// The prompt only when a question is actually being asked.
    public bool ShowQuestionOnly => ShowQuestion && !IsBoard;
    /// Answer buttons: never on a buzz round, never while the grid is up.
    public bool ShowOptions => !IsBuzz && !IsBoard;
    public string BoardHeadline =>
        Client.Pub?.Board?.Chooser is { Length: > 0 } who ? $"{who} picks" : "Pick a category";
    public string BoardSummary =>
        Client.Pub?.Board is { } b ? $"{b.Remaining} left · {b.Points:N0} points on the board" : "";

    // L5 social graph — "add the people you played with" at the wrap.
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
            if (!ShowQuestion || Client.Pub?.Deadline is not { } d) return null;
            var now = System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            return (int)System.Math.Max(0, (d - now) / 1000);
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
    public string? Story => Client.Pub?.Story;
    public bool HasStory => ShowReveal && !string.IsNullOrEmpty(Client.Pub?.Story);
}
