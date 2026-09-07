using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Xunit;

namespace Tidbits.HeadlessTests;

/// QUIZ-FORMATS-RESEARCH §4 — a Tidbits night as Kahoot's own import template.
/// The Mac suite asserts the same cells (TidbitsTriviaTests/LiveKahootSheetTests.swift).
public class KahootSheetTest
{
    private static Question Mcq(string prompt, string[] options, int correct) =>
        new() { Id = System.Guid.NewGuid().ToString("N"), Prompt = prompt, Options = options, CorrectIndex = correct,
                CategoryId = "history", Difficulty = 3, TemplateId = "t" };

    [Fact]
    public void Only_multiple_choice_travels_and_every_other_type_is_named()
    {
        var typeIn = Mcq("Name it", new[] { "Lydia" }, 0) with { Accepted = new[] { "Lydia" } };
        var numeric = Mcq("How many?", new[] { "7" }, 0) with
        {
            Closest = new ClosestSpec { Answer = 7, Min = 0, Max = 20, Step = 1, Tolerance = 2, Unit = "" },
        };
        var (rows, notes) = KahootSheet.Rows(
            new[] { Mcq("Which kingdom minted the first coins?", new[] { "Lydia", "Phrygia", "Caria", "Lycia" }, 0), typeIn, numeric }, 30);
        Assert.Single(rows);
        Assert.Equal(new[] { 1 }, rows[0].Correct.ToArray());
        Assert.Equal(30, rows[0].Seconds);
        Assert.Contains(notes, n => n.Contains("type-the-answer"));
        Assert.Contains(notes, n => n.Contains("numeric"));
    }

    [Fact]
    public void Their_caps_are_applied_and_reported()
    {
        var longText = new string('x', 200);
        var (rows, notes) = KahootSheet.Rows(new[] { Mcq(longText, new[] { new string('y', 90), "b", "c", "d" }, 0) }, null);
        Assert.Equal(KahootSheet.QuestionCap, rows[0].Prompt.Length);
        Assert.Equal(KahootSheet.AnswerCap, rows[0].Answers[0].Length);
        Assert.Contains(notes, n => n.Contains("shortened"));
        Assert.Equal(20, rows[0].Seconds);
    }

    [Fact]
    public void A_fifth_answer_is_dropped_and_a_correct_answer_outside_the_four_is_refused()
    {
        var keepable = Mcq("A?", new[] { "one", "two", "three", "four", "five" }, 1);
        var broken = Mcq("B?", new[] { "one", "two", "three", "four", "five" }, 4);
        var (rows, notes) = KahootSheet.Rows(new[] { keepable, broken }, null);
        Assert.Single(rows);
        Assert.Equal(4, rows[0].Answers.Count);
        Assert.Equal(new[] { 2 }, rows[0].Correct.ToArray());
        Assert.Contains(notes, n => n.Contains("not among the first four"));
    }

    [Fact]
    public void Time_snaps_to_a_value_their_importer_accepts()
    {
        Assert.Equal(30, KahootSheet.NearestTime(45));
        Assert.Equal(60, KahootSheet.NearestTime(75));
        Assert.Equal(20, KahootSheet.NearestTime(null));
        Assert.Contains(KahootSheet.NearestTime(200), KahootSheet.AllowedTimes);
    }

    [Fact]
    public void The_workbook_is_a_real_xlsx_with_their_header_in_row_8()
    {
        var (rows, _) = KahootSheet.Rows(
            new[] { Mcq("Which kingdom minted the first coins?", new[] { "Lydia", "Phrygia", "Caria", "Lycia" }, 2) }, 60);
        using var ms = new MemoryStream(KahootSheet.Xlsx(rows));
        using var zip = new ZipArchive(ms, ZipArchiveMode.Read);
        Assert.Equal(
            new[] { "[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/workbook.xml", "xl/worksheets/sheet1.xml" },
            zip.Entries.Select(e => e.FullName).OrderBy(n => n, System.StringComparer.Ordinal).ToArray());
        using var reader = new StreamReader(zip.GetEntry("xl/worksheets/sheet1.xml")!.Open(), Encoding.UTF8);
        var sheet = reader.ReadToEnd();
        Assert.Contains("<row r=\"8\">", sheet);
        Assert.Contains("Question - max 95 characters", sheet);
        Assert.Contains("r=\"H8\"", sheet);
        Assert.Contains("<row r=\"9\">", sheet);
        Assert.Contains("<c r=\"C9\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Lydia", sheet);
        Assert.Contains("<c r=\"G9\"><v>60</v>", sheet);
        Assert.Contains("<c r=\"H9\" t=\"inlineStr\"><is><t xml:space=\"preserve\">3", sheet);
    }

    [Fact]
    public void Xml_hostile_text_cannot_produce_an_unopenable_workbook()
    {
        var (rows, _) = KahootSheet.Rows(new[] { Mcq("Fish & chips <or> \"pie\"?", new[] { "a & b", "b", "c", "d" }, 0) }, null);
        using var ms = new MemoryStream(KahootSheet.Xlsx(rows));
        using var zip = new ZipArchive(ms, ZipArchiveMode.Read);
        using var reader = new StreamReader(zip.GetEntry("xl/worksheets/sheet1.xml")!.Open(), Encoding.UTF8);
        var sheet = reader.ReadToEnd();
        Assert.Contains("Fish &amp; chips &lt;or&gt; &quot;pie&quot;?", sheet);
        Assert.DoesNotContain("<or>", sheet);
    }
}
