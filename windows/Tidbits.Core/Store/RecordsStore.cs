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
    /// The Club Story Archive's data source (docs/CLUB-FEATURES-BUILD.md "Feature 2") —
    /// every distinct question ever answered, right or wrong.
    public List<SeenStory> Seen { get; set; } = new();
    /// The Club Marathon's in-progress run (docs/CLUB-FEATURES-BUILD.md "Feature 3") —
    /// at most one at a time; null when no run is active.
    public MarathonRun? MarathonRun { get; set; }
    /// Permanent completed-Marathon history.
    public List<MarathonScore> MarathonHistory { get; set; } = new();
    /// The Club Expedition's in-progress campaigns (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 5") — keyed by expeditionId; SEVERAL concurrent, unlike Marathon's
    /// single slot.
    public Dictionary<string, ExpeditionProgress> ExpeditionProgress { get; set; } = new();
    /// Permanent completed-Expedition certificates.
    public List<ExpeditionCertificate> ExpeditionCertificates { get; set; } = new();
    /// The Club Link Wall's daily rows (docs/CLUB-FEATURES-BUILD.md "Feature 6") —
    /// keyed by day (`yyyy-MM-dd`), like `ExpeditionProgress`; several days (past
    /// completed + today in-progress) can sit here at once, unlike Marathon's single
    /// slot. One row per day; reopening resumes THIS row, never a fresh board.
    public Dictionary<string, LinkWallResult> LinkWall { get; set; } = new();
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

    /// Append synthetic games IN MEMORY, for TIDBITS_SEED_RECORDS.
    ///
    /// Deliberately never calls Save(): a hook that populates a screen for a capture
    /// must not write fiction into a real person's history, and this is the same store
    /// the live app reads. Refuses outright if there is already real history, so a
    /// mis-set variable on the owner's machine cannot mix invented games into their
    /// records even in memory.
    public void SeedForCapture(IEnumerable<GameRecord> games)
    {
        if (_data.Games.Count > 0) return;
        _data.Games.AddRange(games);
    }
    public IReadOnlyList<MissedFact> Missed => _data.Missed;
    public DailyStreak Streak => _data.Streak;
    public IReadOnlyList<CalibrationTally> Calibration =>
        _data.Calibration.OrderByDescending(c => c.TierValue).ToList();
    /// The Club Story Archive's data source — every distinct answered question, most
    /// recently met first.
    public IReadOnlyList<SeenStory> Seen => _data.Seen.OrderByDescending(s => s.LastSeen).ToList();
    /// The Club Marathon's in-progress run, if any (at most one).
    public MarathonRun? MarathonRun => _data.MarathonRun;
    /// Permanent completed-Marathon history, most recent first.
    public IReadOnlyList<MarathonScore> MarathonHistory =>
        _data.MarathonHistory.OrderByDescending(s => s.Date).ToList();
    /// The Club Expedition's in-progress campaigns, keyed by expeditionId — several
    /// concurrent (docs/CLUB-FEATURES-BUILD.md "Feature 5").
    public IReadOnlyDictionary<string, ExpeditionProgress> ExpeditionProgress => _data.ExpeditionProgress;
    /// Permanent completed-Expedition certificates, most recent first.
    public IReadOnlyList<ExpeditionCertificate> ExpeditionCertificates =>
        _data.ExpeditionCertificates.OrderByDescending(c => c.CompletedAt).ToList();
    /// The Club Link Wall's daily rows, keyed by day (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 6").
    public IReadOnlyDictionary<string, LinkWallResult> LinkWall => _data.LinkWall;

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

        // Club Story Archive (Feature 2): every answered question — right or wrong —
        // upserts into the seen-forever library. R-MON-1: purely additive; the free
        // in-moment story reveal this reads from is untouched.
        foreach (var a in summary.Answered) RecordSeenStory(a);

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

    private void RecordSeenStory(AnsweredQuestion answered)
    {
        var q = answered.Question;
        var e = _data.Seen.FirstOrDefault(s => s.QuestionId == q.Id);
        if (e is not null)
        {
            e.LastSeen = DateTime.UtcNow;
            if (answered.IsCorrect) e.EverCorrect = true;
        }
        else
        {
            _data.Seen.Add(SeenStory.From(q, answered.IsCorrect));
        }
    }

    /// Toggle the archive's participation lever (docs/CLUB-FEATURES-BUILD.md "Feature
    /// 2") for one story, keyed by qid. No-op if the qid isn't in the archive.
    public void ToggleFavorite(string qid)
    {
        var e = _data.Seen.FirstOrDefault(s => s.QuestionId == qid);
        if (e is null) return;
        e.Favorite = !e.Favorite;
        Save();
    }

    /// Persist the in-progress Marathon run (or clear it with null) — called
    /// after every answer and on Start/Start-over so a crash/quit never loses
    /// progress (docs/CLUB-FEATURES-BUILD.md "Feature 3").
    public void SaveMarathonRun(MarathonRun? run)
    {
        _data.MarathonRun = run;
        Save();
    }

    /// Write the permanent Marathon score and clear the in-progress run.
    /// Marathon writes NO GameRecord / miss / seen-story here — a partial
    /// session slice would misreport lifetime stats — so this is its own
    /// dedicated, additive history.
    public void FinishMarathon(MarathonScore score)
    {
        _data.MarathonHistory.Add(score);
        _data.MarathonRun = null;
        Save();
    }

    /// Persist one campaign's in-progress state (docs/CLUB-FEATURES-BUILD.md
    /// "Feature 5") — called after every stage attempt so a player can leave and
    /// come back over days or weeks. Unlike `SaveMarathonRun`'s single slot, this
    /// upserts into a dictionary — several campaigns can be in progress at once.
    public void SaveExpeditionProgress(ExpeditionProgress progress)
    {
        _data.ExpeditionProgress[progress.ExpeditionId] = progress;
        Save();
    }

    /// Retire a campaign's in-progress row — called once its last stage passes
    /// (the permanent certificate is written in the same call, see
    /// `AppendExpeditionCertificate`).
    public void DeleteExpeditionProgress(string expeditionId)
    {
        _data.ExpeditionProgress.Remove(expeditionId);
        Save();
    }

    /// Write a permanent Expedition certificate — a completed campaign, kept forever.
    public void AppendExpeditionCertificate(ExpeditionCertificate certificate)
    {
        _data.ExpeditionCertificates.Add(certificate);
        Save();
    }

    /// Fetch today's (or any day's) Link Wall row, or insert a fresh one — never a
    /// second row for the same day. Mirrors Apple's `LinkWallLog.resultOrCreate`.
    public LinkWallResult LinkWallResultOrCreate(string day)
    {
        if (_data.LinkWall.TryGetValue(day, out var existing)) return existing;
        var fresh = new LinkWallResult { Day = day };
        _data.LinkWall[day] = fresh;
        Save();
        return fresh;
    }

    /// Persist one day's Link Wall progress — called after every guess so a
    /// crash/quit never loses progress (docs/CLUB-FEATURES-BUILD.md "Feature 6").
    public void SaveLinkWallResult(LinkWallResult result)
    {
        _data.LinkWall[result.Day] = result;
        Save();
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
        _data.Seen.Clear();
        _data.MarathonRun = null;
        _data.MarathonHistory.Clear();
        _data.ExpeditionProgress.Clear();
        _data.ExpeditionCertificates.Clear();
        _data.LinkWall.Clear();
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
