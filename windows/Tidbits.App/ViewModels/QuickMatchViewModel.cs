using System;
using CommunityToolkit.Mvvm.ComponentModel;
using Tidbits.App.Services;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;

namespace Tidbits.App.ViewModels;

/// Online Quick Match (2.21): find an opponent, both answer the SAME set, best
/// score wins. Drives the QuickMatchClient state machine and hosts the local game.
/// The live 2-player round-trip is gated (needs a second client); the stage/status
/// logic is pure and unit-tested.
public sealed class QuickMatchViewModel : ObservableObject, IDisposable
{
    public enum Stage { Searching, Playing, Result }

    private readonly QuickMatchClient _client;
    private readonly GameData _data;
    private bool _published, _gameStarted, _reported;

    public QuickMatchViewModel(QuickMatchClient client, GameData data)
    {
        _client = client;
        _data = data;
        _client.Changed += OnClientChanged;
    }

    public Stage Current { get; private set; } = Stage.Searching;
    public GameViewModel? Game { get; private set; }
    public QuickOutcome Outcome { get; private set; }

    /// The view re-renders on this (stage change / game ready / result).
    public event Action? Changed;

    public bool IsSearching => Current == Stage.Searching;
    public bool IsPlaying => Current == Stage.Playing;
    public bool IsResult => Current == Stage.Result;

    public int MyScore => _client.MyScore;
    public int OpponentScore => _client.OpponentScore;
    public string OpponentName => _client.OpponentName;

    public string StatusLine => Current switch
    {
        Stage.Searching => _client.EnoughPlayers ? "Opponent found — starting…" : "Finding an opponent…",
        Stage.Playing => $"You vs {OpponentName}",
        _ => ResultHeadline(Outcome),
    };

    public static string ResultHeadline(QuickOutcome o) => o switch
    {
        QuickOutcome.Win => "You win!",
        QuickOutcome.Lose => "You lost",
        _ => "Dead tie",
    };

    public string ScoreLine => $"You {MyScore} · {OpponentName} {OpponentScore}";

    public async void Start(string name)
    {
        try { await _client.FindMatch(name); } catch { }
        OnClientChanged();
    }

    private async void OnClientChanged()
    {
        // Leader: once a second player arrives, generate + publish the shared set.
        if (_client.IsLeader && _client.EnoughPlayers && !_published)
        {
            _published = true;
            try
            {
                var qs = await _data.Provider.Questions(GameMode.Classic, TriviaCategory.Named("mixed"));
                await _client.PublishQuestions(qs);
            }
            catch { _published = false; }
        }

        // Both: when the room flips to playing, start the local game on the shared set.
        if (_client.IsPlaying && !_gameStarted && _client.Questions().Count > 0)
        {
            _gameStarted = true;
            StartGame();
        }

        // Result: both done (or the room is finished) and my score is in.
        if (_reported && (_client.IsFinished || _client.OpponentDone) && Current != Stage.Result)
        {
            Outcome = _client.Outcome();
            Current = Stage.Result;
        }

        Changed?.Invoke();
        OnPropertyChanged(string.Empty);
    }

    private void StartGame()
    {
        var engine = _data.NewEngine();
        Game = new GameViewModel(engine, records: null); // matches don't write solo records
        Game.Finished += OnGameFinished;
        Current = Stage.Playing;
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("mixed"), _client.Questions());
    }

    private async void OnGameFinished()
    {
        if (_reported || Game is null) return;
        _reported = true;
        try { await _client.ReportScore(Game.Engine.Summary.Score, done: true); } catch { }
        OnClientChanged();
    }

    public async void Leave()
    {
        try { await _client.Leave(); } catch { }
    }

    public void Dispose()
    {
        _client.Changed -= OnClientChanged;
        if (Game is not null) Game.Finished -= OnGameFinished;
    }
}
