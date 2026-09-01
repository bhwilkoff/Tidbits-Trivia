using System.Linq;
using Tidbits.Core.Data;
using Xunit;

public class CsvQuestionsTest
{
    [Fact]
    public void Parses_rows_skips_header_and_handles_quotes()
    {
        var csv = string.Join("\n",
            "prompt,a,b,c,d,correct,explanation",
            "What is 2+2?,3,4,5,6,2,Basic arithmetic",
            "\"Which city, historically, was capital?\",\"Rome, Italy\",Paris,Berlin,\"He said \"\"no\"\"\",1,Because.");
        var qs = CsvQuestions.Parse(csv);

        Assert.Equal(2, qs.Count);
        Assert.Equal("What is 2+2?", qs[0].Prompt);
        Assert.Equal(1, qs[0].CorrectIndex);          // "correct"=2 → index 1
        Assert.Equal("4", qs[0].Options[1]);

        // Quoted fields with embedded commas + escaped quotes survive intact.
        Assert.Equal("Which city, historically, was capital?", qs[1].Prompt);
        Assert.Equal("Rome, Italy", qs[1].Options[0]);
        Assert.Equal("He said \"no\"", qs[1].Options[3]);
        Assert.Equal(0, qs[1].CorrectIndex);
    }

    [Fact]
    public void Drops_malformed_rows()
    {
        var csv = string.Join("\n",
            "Too few columns,a,b",                       // <6 fields
            "Bad index,a,b,c,d,9,x",                      // correct out of 1–4
            ",a,b,c,d,1,empty prompt",                    // empty prompt
            "Good?,a,b,c,d,3,ok");                         // valid
        var qs = CsvQuestions.Parse(csv);
        Assert.Single(qs);
        Assert.Equal("Good?", qs[0].Prompt);
        Assert.Equal(2, qs[0].CorrectIndex);
    }

    // ---- docs/LIVE-EVENT-FILE.md §6: the two shipped column orders ----------
    //
    // The Swift suite asserts the same cases against the same rows
    // (TidbitsTriviaTests/LiveCSVImportTests.swift). A host's CSV has to mean the
    // same thing on both machines.

    private const string MacOrder =
        "Which kingdom minted the first coins?,Lydia,Phrygia,Caria,Lycia,history,3,Electrum c.600BC";
    private const string WindowsOrder =
        "Which kingdom minted the first coins?,Phrygia,Lydia,Caria,Lycia,2,Electrum c.600BC";

    [Fact]
    public void A_macOS_order_csv_now_imports_at_all()
    {
        // THE BUG: field 5 ("history") would not parse as 1-4, so every row of a
        // macOS-exported bank was dropped and the import produced nothing.
        var qs = CsvQuestions.Parse(MacOrder);
        Assert.Single(qs);
        Assert.Equal("Lydia", qs[0].CorrectAnswer);
        Assert.Equal("history", qs[0].CategoryId);
        Assert.Equal(3, qs[0].Difficulty);
    }

    [Fact]
    public void The_windows_order_still_works()
    {
        var qs = CsvQuestions.Parse(WindowsOrder);
        Assert.Single(qs);
        Assert.Equal("Lydia", qs[0].CorrectAnswer);
    }

    [Fact]
    public void A_named_header_wins_in_any_column_order()
    {
        var csv = string.Join("\n",
            "question,explanation,difficulty,correct,optionA,optionB,optionC,optionD,category",
            "Which kingdom minted the first coins?,Electrum,4,Lydia,Phrygia,Lydia,Caria,Lycia,history");
        var qs = CsvQuestions.Parse(csv);
        Assert.Single(qs);
        Assert.Equal("Lydia", qs[0].CorrectAnswer);
        Assert.Equal(4, qs[0].Difficulty);
        Assert.Equal("history", qs[0].CategoryId);
    }

    [Fact]
    public void A_header_whose_correct_column_is_an_index_resolves_to_the_text()
    {
        // §6.2 — `correct` may be the answer text OR a 1-based index.
        var csv = string.Join("\n",
            "prompt,optionA,optionB,optionC,optionD,correct,explanation",
            "Which kingdom minted the first coins?,Phrygia,Lydia,Caria,Lycia,2,Electrum");
        var qs = CsvQuestions.Parse(csv);
        Assert.Single(qs);
        Assert.Equal("Lydia", qs[0].CorrectAnswer);
    }

    [Fact]
    public void A_row_whose_answer_is_not_among_its_options_is_dropped()
    {
        // §6.4 — an answer no option matches is a question nobody can get right.
        var csv = string.Join("\n",
            "prompt,correct,wrong1,wrong2,wrong3",
            "Which kingdom minted the first coins?,Atlantis,Phrygia,Caria,Lycia");
        foreach (var q in CsvQuestions.Parse(csv))
            Assert.Contains(q.CorrectAnswer, q.Options);
    }

    [Fact]
    public void Every_imported_question_keeps_four_distinct_options()
    {
        foreach (var q in CsvQuestions.Parse(MacOrder + "\n" + WindowsOrder))
        {
            Assert.Equal(4, q.Options.Count);
            Assert.Equal(4, q.Options.Distinct().Count());
            Assert.Contains(q.CorrectAnswer, q.Options);
        }
    }
}
