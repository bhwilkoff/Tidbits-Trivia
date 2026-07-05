using System.Text.Json;
using Tidbits.Core.Models;

namespace Tidbits.Core.Store;

public sealed class RecordsData
{
    public List<GameRecord> Games { get; set; } = new();
    public List<MissedFact> Missed { get; set; } = new();
    public List<CalibrationTally> Calibration { get; set; } = new();
    public DailyStreak Streak { get; set; } = new();
    public Dictionary<string, int[]> Telemetry { get; set; } = new();
}

/// Persists the outcome of a finished game (record + missed facts + Daily streak +
/// calibration + answer telemetry). JSON-file-backed — port of RecordsStore.swift's
/// write path (GameCenter + identity-sync are separate parity items). Every platform
/// writes records identically.
public sealed class RecordsStore
{
    private readonly string _path;
    private readonly RecordsData _data;

    public RecordsStore(string path)
    {
        _path = path;
        try
        {
            _data = File.Exists(path)
                ? JsonSerializer.Deserialize<RecordsData>(File.ReadAllText(path)) ?? new RecordsData()
                : new RecordsData();
        }
        catch { _data = new RecordsData(); }
    }

    public IReadOnlyList<GameRecord> Games => _data.Games;
    public IReadOnlyList<MissedFact> Missed => _data.Missed;
    public DailyStreak Streak => _data.Streak;
    public IReadOnlyList<CalibrationTally> Calibration =>
        _data.Calibration.OrderByDescending(c => c.TierValue).ToList();

    /// Record a finished game. Returns whether it's a new best for that mode+category.
    public bool Record(GameSummary summary)
    {
        var isNewBest = summary.Score > BestScore(summary.Mode, summary.Category.Id);

        _data.Games.Add(new GameRecord
        {
            ModeRaw = summary.Mode.Id(),
            CategoryId = summary.Category.Id,
            Score = summary.Score,
            Correct = summary.Correct,
            Total = summary.Total,
            MaxStreak = summary.MaxStreak,
            Answers = summary.Answered.Select(a => new AnswerDetail
            {
                Qid = a.Question.Id, Prompt = a.Question.Prompt, CategoryId = a.Question.CategoryId,
                Correct = a.IsCorrect, Answer = a.Question.CorrectAnswer,
            }).ToList(),
        });

        foreach (var miss in summary.Missed) RegisterMiss(miss.Question);
        foreach (var right in summary.Answered.Where(a => a.IsCorrect)) ResolveMiss(right.Question.Id);

        if (summary.Mode == GameMode.Daily)
        {
            var day = summary.DailyDay ?? QuestionProvider.DayKey();
            if (day == QuestionProvider.DayKey()) BumpDailyStreak();
        }
        if (summary.Mode == GameMode.Stake) AddCalibration(summary.StakeOutcomes);
        RecordTelemetry(summary.Answered, summary.Mode);

        Save();
        return isNewBest;
    }

    public int BestScore(GameMode mode, string categoryId) =>
        _data.Games.Where(g => g.ModeRaw == mode.Id() && g.CategoryId == categoryId)
                   .Select(g => g.Score).DefaultIfEmpty(0).Max();

    /// Questions due for spaced re-asking — unresolved, most-missed + oldest first.
    public List<Question> DueReview(int limit = 2) =>
        _data.Missed.Where(m => !m.Resolved)
            .OrderByDescending(m => m.MissCount).ThenBy(m => m.LastSeen)
            .Select(m => m.Question).Where(q => q is not null).Select(q => q!).Take(limit).ToList();

    private void RegisterMiss(Question? q)
    {
        if (q is null) return;
        var e = _data.Missed.FirstOrDefault(m => m.QuestionId == q.Id);
        if (e is not null) { e.MissCount++; e.LastSeen = DateTime.UtcNow; e.Resolved = false; }
        else _data.Missed.Add(MissedFact.From(q));
    }

    private void ResolveMiss(string qid)
    {
        var e = _data.Missed.FirstOrDefault(m => m.QuestionId == qid);
        if (e is { Resolved: false }) { e.Resolved = true; e.LastSeen = DateTime.UtcNow; }
    }

    private void AddCalibration(IReadOnlyDictionary<int, StakeOutcome> outcomes)
    {
        foreach (var (tier, o) in outcomes)
        {
            if (o.Total <= 0) continue;
            var e = _data.Calibration.FirstOrDefault(c => c.TierValue == tier);
            if (e is not null) { e.Hits += o.Hits; e.Total += o.Total; }
            else _data.Calibration.Add(new CalibrationTally { TierValue = tier, Hits = o.Hits, Total = o.Total });
        }
    }

    private void BumpDailyStreak()
    {
        var today = QuestionProvider.DayKey();
        var yesterday = QuestionProvider.DayKey(DateTime.Now.AddDays(-1));
        var s = _data.Streak;
        if (s.LastPlayedDay == today) return;
        s.Current = s.LastPlayedDay == yesterday ? s.Current + 1 : 1;
        s.Best = Math.Max(s.Best, s.Current);
        s.LastPlayedDay = today;
    }

    private void RecordTelemetry(IReadOnlyList<AnsweredQuestion> answered, GameMode mode)
    {
        if (mode is GameMode.ClosestCall or GameMode.Ordering or GameMode.Matching
            or GameMode.TypeAnswer or GameMode.Enumerate) return; // synthetic chosenIndex
        foreach (var a in answered)
        {
            if (a.ChosenIndex is not { } chosen || a.Question.Options.Count < 2
                || chosen < 0 || chosen >= a.Question.Options.Count) continue;
            var counts = _data.Telemetry.TryGetValue(a.Question.Id, out var c) && c.Length == a.Question.Options.Count
                ? c : new int[a.Question.Options.Count];
            counts[chosen]++;
            _data.Telemetry[a.Question.Id] = counts;
        }
        if (_data.Telemetry.Count > 5000) _data.Telemetry.Clear();
    }

    public int[]? AnswerDistribution(string questionId) => _data.Telemetry.GetValueOrDefault(questionId);

    /// Wipe all records (Settings → Reset all records).
    public void ResetAll()
    {
        _data.Games.Clear();
        _data.Missed.Clear();
        _data.Calibration.Clear();
        _data.Telemetry.Clear();
        _data.Streak = new DailyStreak();
        Save();
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_data));
        }
        catch { /* best-effort persistence */ }
    }
}
