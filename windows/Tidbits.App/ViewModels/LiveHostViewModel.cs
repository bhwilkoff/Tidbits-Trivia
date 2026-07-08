using System.Threading.Tasks;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Networking;

namespace Tidbits.App.ViewModels;

/// Wraps a LiveNightHost for the cockpit UI. LiveNightHost relays its LiveHostNet
/// changes (which fire on background SSE threads); this marshals them to the UI
/// thread so bindings update safely.
public sealed class LiveHostViewModel : ObservableObject
{
    public LiveNightHost Host { get; }

    public LiveHostViewModel(LiveNightHost host)
    {
        Host = host;
        Host.PropertyChanged += (_, _) => Dispatcher.UIThread.Post(() => OnPropertyChanged(string.Empty));
    }

    public bool IsLobby => Host.CurrentStage == LiveNightHost.Stage.Lobby;
    public bool IsPlaying => Host.CurrentStage == LiveNightHost.Stage.Playing;
    public bool IsEnded => Host.CurrentStage == LiveNightHost.Stage.Ended;
    public bool IsReveal => Host.Revealed;
    /// The correct option text (shown big on the projector at reveal).
    public string? RevealAnswer => Host.Current is { } q ? LiveScoring.AnswerLine(q) : null;

    public bool CanGoBack => Host.CanGoBack;
    public int? SecondsRemaining => Host.SecondsRemaining;

    /// Big-screen chrome (3.42): "Question X of Y · N players".
    public string QuestionChrome
    {
        get
        {
            var (n, of) = Host.QuestionInRound;
            var players = Host.PlayerCount;
            return $"Question {n} of {of} · {players} player{(players == 1 ? "" : "s")}";
        }
    }

    // Winner celebration (3.41) — top of the ordered standings.
    public bool HasWinner => Host.Standings.Count > 0;
    public string WinnerLine => Host.Standings.Count > 0 ? $"{Host.Standings[0].Name} wins the night" : "";

    public Task StartHosting() => Host.Start();
    public Task Reveal() => Host.Reveal();
    public Task Next() => Host.Next();
    public Task Lock() => Host.Lock();
    public Task Skip() => Host.SkipNext();
    public Task Back() => Host.GoBack();
    public Task StartTimer(int seconds) => Host.StartTimer(seconds);
    public Task AddTime(int seconds) => Host.AddTime(seconds);
    public Task ClearTimer() => Host.ClearTimer();
    public Task Adjust(string uid, int delta) => Host.AdjustScore(uid, delta);
    public Task Close() => Host.Close();
}
