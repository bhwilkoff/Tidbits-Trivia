using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// 3.62 — the answer sheet: every team's submission and credit per question, as CSV.
public class AnswerSheetTest
{
    private static Question Q(IReadOnlyList<string>? accepted = null) => new()
    {
        Id = "q1", Prompt = "Who, \"Neo\"?", Options = new[] { "Keanu Reeves", "B", "C", "D" }, CorrectIndex = 0,
        CategoryId = "film", Difficulty = 4, Explanation = "", SourceTitle = "", TemplateId = "hand", Accepted = accepted,
    };

    [Fact]
    public void Submissions_render_for_typed_chosen_and_listed_answers()
    {
        Assert.Equal("keanu", LiveAnswerRecord.Submitted(Q(new[] { "Keanu Reeves" }), new LiveRoom.Answer { Text = "keanu", Ts = 1 }));
        Assert.Equal("Keanu Reeves", LiveAnswerRecord.Submitted(Q(), new LiveRoom.Answer { Choice = 0, Ts = 1 }));
        Assert.Equal("a · b", LiveAnswerRecord.Submitted(Q(), new LiveRoom.Answer { List = new[] { "a", "b" }, Ts = 1 }));
        Assert.Equal("", LiveAnswerRecord.Submitted(Q(), new LiveRoom.Answer { Ts = 1 }));
    }

    [Fact]
    public void The_csv_is_long_format_quoted_and_alphabetical()
    {
        var rec = new LiveAnswerRecord("r0q0", 1, 1, "Who, \"Neo\"?", "Keanu Reeves", new[]
        {
            new LiveAnswerRecord.Line("b", "Zed", "keanu reaves", 0),
            new LiveAnswerRecord.Line("a", "Alpha, Beta", "Keanu Reeves", 3),
        });
        var csv = LiveExport.AnswersCsv(new[] { rec });
        Assert.StartsWith("round,question,prompt,answer,team,submitted,points\n", csv);
        Assert.Contains("1,1,\"Who, \"\"Neo\"\"?\",Keanu Reeves,\"Alpha, Beta\",Keanu Reeves,3\n", csv);
        Assert.Contains("1,1,\"Who, \"\"Neo\"\"?\",Keanu Reeves,Zed,keanu reaves,0\n", csv);
        Assert.True(csv.IndexOf("Alpha") < csv.IndexOf("Zed"));
    }
}
