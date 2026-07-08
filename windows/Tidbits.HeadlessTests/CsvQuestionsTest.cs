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
}
