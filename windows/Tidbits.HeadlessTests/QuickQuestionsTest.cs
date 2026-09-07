using System.Collections.Generic;
using System.Linq;
using Tidbits.Core.Data;
using Xunit;

namespace Tidbits.HeadlessTests;

/// QUIZ-FORMATS-RESEARCH §1 — SpeedQuizzing Quick Questions. The Mac suite
/// asserts the same filenames (TidbitsTriviaTests/LiveTextFormatsTests.swift).
public class QuickQuestionsTest
{
    [Fact]
    public void The_documented_filename_shape()
    {
        var a = QuickQuestions.Parse("QQ_Who sang this^^_Dolly Parton.mp3");
        Assert.Equal("Who sang this?", a!.Prompt);
        Assert.Equal(new[] { "Dolly Parton" }, a.Answers.ToArray());
        Assert.False(a.IsPoll);

        var b = QuickQuestions.Parse("05 QQ_What is the capital of Peru^^_Lima_Ciudad de los Reyes.txt");
        Assert.Equal(5, b!.Order);
        Assert.Equal("What is the capital of Peru?", b.Prompt);
        Assert.Equal(new[] { "Lima", "Ciudad de los Reyes" }, b.Answers.ToArray());

        // The verbatim example from SpeedQuizzing's own documentation.
        Assert.True(QuickQuestions.Parse("QQV_Who would have won in a cage fight in their prime^^_Mike Tyson_Bruce Lee.txt")!.IsPoll);
        Assert.Empty(QuickQuestions.Parse("QQ_Just a question^^.txt")!.Answers);
    }

    [Fact]
    public void A_folder_becomes_a_round_with_media_votes_skipped_and_order_honoured()
    {
        var files = new[]
        {
            "/quizpack/03 QQ_Who sang this^^_Dolly Parton.mp3",
            "/quizpack/01 QQ_Which building is this^^_Chrysler Building.jpg",
            "/quizpack/02 QQ_Capital of Peru^^_Lima_Ciudad de los Reyes.txt",
            "/quizpack/QQV_Cats or dogs^^_Cats_Dogs.txt",
            "/quizpack/notes.pdf",
            "/quizpack/.DS_Store",
        };
        var (qs, notes) = QuickQuestions.FromFolder(files, p => "id" + System.IO.Path.GetExtension(p).TrimStart('.'));
        Assert.Equal(3, qs.Count);
        Assert.Equal(new[] { "Which building is this?", "Capital of Peru?", "Who sang this?" }, qs.Select(q => q.Prompt).ToArray());
        Assert.Equal("tidbits-media:idjpg", qs[0].ImageUrl);
        Assert.Null(qs[1].ImageUrl);
        Assert.Equal(new[] { "Lima", "Ciudad de los Reyes" }, qs[1].Accepted!.ToArray());
        Assert.All(qs, q => Assert.NotNull(q.Accepted));
        Assert.Equal(2, notes.Count);
        Assert.Contains(notes, n => n.Contains("voting"));
        Assert.Contains(notes, n => n.Contains("notes.pdf"));
    }

    [Fact]
    public void Clip_slots_line_up_with_the_questions()
    {
        var files = new[]
        {
            "/quizpack/01 QQ_Which building is this^^_Chrysler Building.jpg",
            "/quizpack/02 QQ_Who sang this^^_Dolly Parton.mp3",
        };
        // No store hit for the picture; the MP3 asks for one (and gets a null path here).
        var asked = new List<string>();
        var clips = QuickQuestions.ClipPaths(files, p => { asked.Add(System.IO.Path.GetExtension(p)); return null; });
        Assert.Equal(2, clips.Count);
        Assert.Equal("", clips[0]);
        Assert.Equal(new[] { ".mp3" }, asked.ToArray());
    }
}
