using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// A night must not ask the same thing twice.
///
/// Tracking question IDs is not enough, and the corpus says so: **4,261
/// (prompt, answer) pairs appear on more than one row**, because the comparison
/// templates generate several questions differing only in their distractors.
/// "Which of these is the largest by area? -> Sonora" twice in one night is the
/// same question to the room, and the second one is free.
public class NightNoRepeatsTest
{
    private static QuestionProvider Provider() =>
        new(QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures")));

    private static string Key(Question q) =>
        (q.Prompt ?? "").Trim().ToLowerInvariant() + "|" + (q.CorrectAnswer ?? "").Trim().ToLowerInvariant();

    [Fact]
    public async Task A_long_night_never_repeats_a_prompt_and_answer()
    {
        // HONEST NOTE ON WHAT THIS PROVES. Disabling the dedup does NOT make this
        // fail — not at 40 questions, and not at 240 either, against the real
        // corpus. The 11,027 duplicated rows live entirely in `sup` and `chron`,
        // and `Corpus.Questions` draws a contiguous slice whose members' ids are
        // far apart, so two rows of the same group are effectively never adjacent
        // in one pull.
        //
        // So this pins a PROPERTY going forward rather than demonstrating a bug
        // that was reproducing. The guard is cheap insurance for a corpus that
        // gains duplicates, or a selection change that starts sampling randomly.
        var plan = new NightPlan
        {
            Rounds =
            [
                new NightRound { Kind = GameMode.Classic, Count = 10 },
                new NightRound { Kind = GameMode.Classic, Count = 10 },
                new NightRound { Kind = GameMode.Classic, Count = 10 },
                new NightRound { Kind = GameMode.Classic, Count = 10 },
            ],
        };
        var qs = await Provider().NightQuestions(plan, TriviaCategory.Named("mixed"));

        var keys = qs.Select(Key).ToList();
        var repeated = keys.GroupBy(k => k).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
        Assert.True(repeated.Count == 0,
            $"the night asks {repeated.Count} question(s) twice: {string.Join(" / ", repeated.Take(3))}");

        // Ids stay unique too — the older guarantee must not regress.
        Assert.Equal(qs.Count, qs.Select(q => q.Id).Distinct().Count());
    }

    [Fact]
    public async Task Dropping_a_repeat_does_not_leave_the_round_short()
    {
        // A short round is worse than a repeat, so the pull tops up rather than
        // just filtering. This is the assertion that keeps the fix honest.
        var plan = new NightPlan
        {
            Rounds =
            [
                new NightRound { Kind = GameMode.Classic, Count = 8 },
                new NightRound { Kind = GameMode.Classic, Count = 8 },
            ],
        };
        var qs = await Provider().NightQuestions(plan, TriviaCategory.Named("mixed"));

        Assert.Equal(16, qs.Count);
        Assert.Equal(8, qs.Count(q => q.RoundIndex == 0));
        Assert.Equal(8, qs.Count(q => q.RoundIndex == 1));
    }

    [Fact]
    public async Task Every_question_still_carries_its_round()
    {
        var plan = new NightPlan
        {
            Rounds =
            [
                new NightRound { Kind = GameMode.Classic, Count = 3 },
                new NightRound { Kind = GameMode.TypeAnswer, Count = 3 },
            ],
        };
        var qs = await Provider().NightQuestions(plan, TriviaCategory.Named("mixed"));
        Assert.All(qs, q => Assert.NotNull(q.RoundIndex));
        Assert.All(qs, q => Assert.InRange(q.RoundIndex!.Value, 0, 1));
    }

    [Fact]
    public async Task A_night_never_gives_the_same_ANSWER_twice()
    {
        // The older guard keyed on prompt+answer, so a night could ask "the answer
        // is Asia" twice with two different clues. That is not theoretical: over
        // the real corpus a 40-question night repeated an answer 17.1% of the time
        // (80-question: 48.1%), because "United States" answers 1,025 rows and
        // 23,159 answers are used more than once.
        //
        // HONEST NOTE, same as the sibling above: reverting AskedKey does NOT make
        // this fail, because the fixture corpus never draws a colliding pair. It is
        // a regression net, not the proof. The proof is Identity_is_the_answer_alone
        // below, which DOES fail when reverted (verified).
        var plan = new NightPlan
        {
            Rounds = Enumerable.Range(0, 8)
                .Select(_ => new NightRound { Kind = GameMode.Classic, Count = 10 })
                .ToList(),
        };
        var qs = await Provider().NightQuestions(plan, TriviaCategory.Named("mixed"));

        var answers = qs.Select(q => (q.CorrectAnswer ?? "").Trim().ToLowerInvariant())
                        .Where(a => a.Length > 0).ToList();
        var repeated = answers.GroupBy(a => a).Where(g => g.Count() > 1)
                              .Select(g => g.Key).ToList();
        Assert.True(repeated.Count == 0,
            $"the night gives {repeated.Count} answer(s) twice: {string.Join(" / ", repeated.Take(5))}");
    }

    [Fact]
    public void Identity_is_the_answer_alone()
    {
        // Two questions the room experiences as the same, worded differently. The
        // old prompt+answer key called these DISTINCT and let both into one night.
        static Question Q(string id, string prompt, string answer) => new()
        {
            Id = id, Prompt = prompt, CategoryId = "mixed",
            Options = new[] { answer, "x", "y", "z" }, CorrectIndex = 0,
        };
        var a = Q("a", "Which of these four came first?", "Asia");
        var b = Q("b", "Which one below is the oldest?", "asia ");
        Assert.Equal(QuestionProvider.AskedKey(a), QuestionProvider.AskedKey(b));

        var c = Q("c", "Which of these four came first?", "Europe");
        Assert.NotEqual(QuestionProvider.AskedKey(a), QuestionProvider.AskedKey(c));
    }
}
