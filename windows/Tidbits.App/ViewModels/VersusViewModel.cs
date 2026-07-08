using System;
using System.ComponentModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;

namespace Tidbits.App.ViewModels;

/// Wraps a player's GameViewModel with a CPU opponent (VsMatch). Drives the bot
/// off the engine's phases — resolve on each new question, commit on reveal —
/// and exposes the live "You vs CPU" standings. Classic (MCQ) only.
///
/// HONESTY RULE: the opponent is always labeled CPU.
public sealed class VersusViewModel : ObservableObject, IDisposable
{
    public GameViewModel Player { get; }
    private readonly VsMatch _match;
    private readonly Bot _bot;
    private int _lastBegun = -1;

    public VersusViewModel(GameViewModel player, Bot bot, Random? rng = null)
    {
        Player = player;
        _bot = bot;
        _match = new VsMatch(new[] { bot }, rng);
        Player.Engine.PropertyChanged += OnEngineChanged;
    }

    public string BotLabel => $"{_bot.Name} · CPU";
    public int PlayerScore => Player.Engine.Score;
    public int BotScore => _match.Seats.FirstOrDefault()?.Score ?? 0;

    public bool IsFinished => Player.Engine.CurrentPhase == GameEngine.Phase.Finished;
    public string ResultLine =>
        !IsFinished ? "" :
        PlayerScore > BotScore ? "You win!" :
        PlayerScore < BotScore ? $"{_bot.Name} wins" : "Dead tie";

    private void OnEngineChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!string.IsNullOrEmpty(e.PropertyName)) return; // ignore the Remaining tick
        var engine = Player.Engine;
        if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Index != _lastBegun && engine.Current is { } q)
        {
            _lastBegun = engine.Index;
            _match.BeginQuestion(q, GameEngine.ShapeBudget(q));
        }
        else if (engine.CurrentPhase == GameEngine.Phase.Reveal && engine.Current is { } rq)
        {
            _match.Commit(rq, engine.Index, GameEngine.ShapeBudget(rq));
        }
        OnPropertyChanged(string.Empty); // refresh the score strip
    }

    public void Dispose() => Player.Engine.PropertyChanged -= OnEngineChanged;
}
