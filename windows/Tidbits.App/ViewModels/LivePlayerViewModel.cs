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
}
