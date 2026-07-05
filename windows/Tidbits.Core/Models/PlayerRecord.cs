using System.Text.Json.Serialization;

namespace Tidbits.Core.Models;

/// One question's outcome inside a completed game — the drill-in unit.
public sealed class AnswerDetail
{
    public string Qid { get; set; } = "";
    public string Prompt { get; set; } = "";
    public string CategoryId { get; set; } = "";
    public bool Correct { get; set; }
    public string Answer { get; set; } = "";
}

/// One completed game — the personal-record spine ("compete against your past self").
public sealed class GameRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ModeRaw { get; set; } = "classic";
    public string CategoryId { get; set; } = "mixed";
    public int Score { get; set; }
    public int Correct { get; set; }
    public int Total { get; set; }
    public int MaxStreak { get; set; }
    public DateTime Date { get; set; } = DateTime.UtcNow;
    public List<AnswerDetail> Answers { get; set; } = new();

    [JsonIgnore] public GameMode Mode => GameModeExtensions.FromId(ModeRaw) ?? GameMode.Classic;
    [JsonIgnore] public double Accuracy => Total == 0 ? 0 : (double)Correct / Total;
}

/// A question the player got wrong — kept for spaced re-asking (the testing effect).
public sealed class MissedFact
{
    public string QuestionId { get; set; } = "";
    public string Prompt { get; set; } = "";
    public string CorrectAnswer { get; set; } = "";
    public string Explanation { get; set; } = "";
    public string CategoryId { get; set; } = "";
    public int MissCount { get; set; } = 1;
    public DateTime LastSeen { get; set; } = DateTime.UtcNow;
    public bool Resolved { get; set; }
    public string OptionsJoined { get; set; } = "";
    public int CorrectIndex { get; set; }
    public string SourceTitle { get; set; } = "";
    public string SourceUrl { get; set; } = "";
    public string TemplateId { get; set; } = "";
    public int Difficulty { get; set; } = 3;

    public static MissedFact From(Question q) => new()
    {
        QuestionId = q.Id, Prompt = q.Prompt, CorrectAnswer = q.CorrectAnswer, Explanation = q.Explanation,
        CategoryId = q.CategoryId, OptionsJoined = string.Join('', q.Options), CorrectIndex = q.CorrectIndex,
        SourceTitle = q.SourceTitle, SourceUrl = q.SourceUrl ?? "", TemplateId = q.TemplateId, Difficulty = q.Difficulty,
    };

    [JsonIgnore]
    public Question? Question
    {
        get
        {
            var options = OptionsJoined.Split('');
            if (options.Length != 4) return null;
            return new Question
            {
                Id = QuestionId, Prompt = Prompt, Options = options, CorrectIndex = CorrectIndex,
                CategoryId = CategoryId, Difficulty = Difficulty, Explanation = Explanation,
                SourceTitle = SourceTitle, SourceUrl = string.IsNullOrEmpty(SourceUrl) ? null : SourceUrl, TemplateId = TemplateId,
            };
        }
    }
}

/// Lifetime calibration from Stake rounds — one row per confidence tier.
public sealed class CalibrationTally
{
    public int TierValue { get; set; }
    public int Hits { get; set; }
    public int Total { get; set; }
}

/// The Daily streak, independent of any single game record.
public sealed class DailyStreak
{
    public int Current { get; set; }
    public int Best { get; set; }
    public string LastPlayedDay { get; set; } = "";
}
