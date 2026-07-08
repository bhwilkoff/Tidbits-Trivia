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
    public bool IsEnded => Client.Meta?.State == "ended" || Client.Pub?.Phase == LiveRoom.Phase.Ended;
    public bool Answered => Client.HasAnswered;

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
