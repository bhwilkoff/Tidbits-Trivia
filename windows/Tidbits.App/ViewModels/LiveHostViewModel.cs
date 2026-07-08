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
    public bool HasFlags => Host.HasFlags;

    // Wave D venue branding (big screen).
    public bool HasLeadCapture => !string.IsNullOrWhiteSpace(Host.LeadCaptureUrl);
    public string? LeadCaptureUrl => Host.LeadCaptureUrl;
    public bool HasSponsor => !string.IsNullOrWhiteSpace(Host.Sponsor);
    public string SponsorLine => $"Brought to you by {Host.Sponsor}";
    public Avalonia.Media.IBrush BrandBrush
    {
        get
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(Host.BrandHex))
                    return new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse(Host.BrandHex!));
            }
            catch { /* fall through to the brand default */ }
            return new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#FF5C35"));
        }
    }
    public bool IsLocked => Host.Locked;
    /// The answer window has hit its deadline and isn't locked yet — cue auto-lock.
    public bool AutoLockDue => Host.SecondsRemaining == 0 && !Host.Locked && !Host.Revealed;
    public string FlagLine => Host.FlaggedCount == 1
        ? "1 team left the app this question"
        : $"{Host.FlaggedCount} teams left the app this question";

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

    /// The unified standings as CSV text (Wave C export).
    public string StandingsCsv() => LiveExport.StandingsCsv(Host.Standings);
    public bool HasStandings => Host.Standings.Count > 0;

    // Name moderation gate (3.26) — projector uses the moderated names.
    public System.Collections.Generic.IReadOnlyList<LiveHostNet.Joined> ModeratedStandings => Host.ModeratedStandings;
    public void ToggleHidden(string uid) => Host.ToggleHidden(uid);
    public bool IsHidden(string uid) => Host.IsHidden(uid);
    public Task MergeTeams(string intoUid, string fromUid) => Host.MergeTeams(intoUid, fromUid);
    public void AddPaperTeam(string name) => Host.AddPaperTeam(name); // in-room paper team (3.29)

    // Free-text review (3.21) — accept a borderline typed answer.
    public System.Collections.Generic.IReadOnlyList<TextReviewRow> TextReview => Host.TextReview;
    public Task AcceptText(string uid) => Host.AcceptText(uid);

    // Tie-break (3.24) — brains-only manual pick among the tied leaders.
    public bool HasTie => Host.HasTie;
    public System.Collections.Generic.IReadOnlyList<LiveHostNet.Joined> TiedLeaders => Host.TiedLeaders;
    public Task BreakTie(string uid) => Host.BreakTie(uid);
}
