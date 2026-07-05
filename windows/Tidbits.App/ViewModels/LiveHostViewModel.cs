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

    public Task StartHosting() => Host.Start();
    public Task Reveal() => Host.Reveal();
    public Task Next() => Host.Next();
    public Task Lock() => Host.Lock();
    public Task Close() => Host.Close();
}
