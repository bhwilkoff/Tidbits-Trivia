using System;
using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Engine;
using Tidbits.Core.Models;

namespace Tidbits.Core.Networking;

/// Play vs CPU — the online-multiplayer v0 (Decision 038). Faithful C# twin of
/// js/bots.js / BotOpponent.swift / Bots.kt (keep the four in lockstep).
///
/// HONESTY RULE (learning-orientation, non-negotiable): a bot is always visibly
/// labeled CPU. Never present a bot as a human.
public sealed record Bot(string Id, string Name, double BaseSkill,
    IReadOnlyDictionary<string, double> CategorySkill, double SpeedMean, double SpeedSigma);

/// What a bot did with one question, within the answer window.
public readonly record struct BotResult(string BotId, int? ChoiceIndex, double? Seconds);

public static class Bots
{
    public static readonly IReadOnlyDictionary<string, Bot> All = new Dictionary<string, Bot>
    {
        ["rookie"] = new("rookie", "Rookie Rae", 0.55,
            new Dictionary<string, double> { ["sports"] = 0.15, ["film"] = 0.10, ["science"] = -0.12 }, 6.5, 0.45),
        ["regular"] = new("regular", "Trivia Tina", 0.70,
            new Dictionary<string, double> { ["history"] = 0.10, ["arts"] = 0.08, ["sports"] = -0.10 }, 5.5, 0.40),
        ["ace"] = new("ace", "Ace Botsworth", 0.85,
            new Dictionary<string, double> { ["science"] = 0.10, ["geography"] = 0.08, ["music"] = -0.08 }, 4.0, 0.35),
    };

    /// Adapts to the player's recent accuracy so solo-vs-CPU stays a fair fight.
    public static Bot House(double playerAccuracy) =>
        new("house", "The House", Math.Min(0.90, Math.Max(0.35, playerAccuracy)),
            new Dictionary<string, double>(), 5.0, 0.40);

    public static Bot ById(string id, double playerAccuracy) =>
        All.TryGetValue(id, out var b) ? b : House(playerAccuracy);

    private static double DifficultyAdj(int d) => d <= 2 ? 0.15 : d >= 4 ? -0.20 : 0;

    private static double Gaussian(Random rng) // Box–Muller
    {
        var u1 = Math.Max(rng.NextDouble(), double.Epsilon);
        var u2 = rng.NextDouble();
        return Math.Sqrt(-2 * Math.Log(u1)) * Math.Cos(2 * Math.PI * u2);
    }

    /// Resolve what this bot does with this question, inside `window` seconds.
    public static BotResult Resolve(Bot bot, string categoryId, int difficulty, int correctIndex,
        int optionCount, double windowSecs, Random rng)
    {
        var catAdj = bot.CategorySkill.TryGetValue(categoryId, out var c) ? c : 0;
        var p = Math.Min(0.98, Math.Max(0.02, bot.BaseSkill + catAdj + DifficultyAdj(difficulty)));
        if (rng.NextDouble() < 0.05) return new(bot.Id, null, null); // freeze
        var correct = rng.NextDouble() < p;
        var t = Math.Exp(Math.Log(bot.SpeedMean) + Gaussian(rng) * bot.SpeedSigma);
        if (correct) t *= 0.85; // knowing feels fast
        t = Math.Min(Math.Max(t, 0.8), Math.Max(1.0, windowSecs - 0.5));
        var choice = correctIndex;
        if (!correct)
        {
            var wrong = new List<int>();
            for (int i = 0; i < Math.Max(optionCount, 2); i++) if (i != correctIndex) wrong.Add(i);
            choice = wrong[rng.Next(wrong.Count)];
        }
        return new(bot.Id, choice, t);
    }
}

/// The running vs-CPU match beside the player's engine-scored game.
public sealed class VsMatch
{
    public sealed class Seat
    {
        public required Bot Bot { get; init; }
        public int Score { get; set; }
        public int Streak { get; set; }
        public bool? LastCorrect { get; set; }
    }

    private readonly Random _rng;
    private readonly List<Seat> _seats;
    private List<BotResult> _pending = new();
    private int _committed = -1;

    public VsMatch(IEnumerable<Bot> bots, Random? rng = null)
    {
        _rng = rng ?? new Random();
        _seats = bots.Select(b => new Seat { Bot = b }).ToList();
    }

    public IReadOnlyList<Seat> Seats => _seats;

    public void BeginQuestion(Question q, double windowSecs)
    {
        _pending = _seats.Select(s =>
            Bots.Resolve(s.Bot, q.CategoryId, q.Difficulty, q.CorrectIndex, q.Options.Count, windowSecs, _rng)).ToList();
    }

    public void Commit(Question q, int index, double budget)
    {
        if (index == _committed) return; // reveal fires once per question
        _committed = index;
        foreach (var s in _seats)
        {
            var a = _pending.FirstOrDefault(x => x.BotId == s.Bot.Id);
            var correct = a.ChoiceIndex == q.CorrectIndex;
            s.LastCorrect = a.ChoiceIndex is null ? false : correct;
            if (correct)
            {
                s.Streak += 1;
                s.Score += Scoring.Points(true, a.Seconds ?? budget, budget, s.Streak);
            }
            else s.Streak = 0;
        }
    }

    public IReadOnlyList<Seat> Standings => _seats.OrderByDescending(s => s.Score).ToList();
}
