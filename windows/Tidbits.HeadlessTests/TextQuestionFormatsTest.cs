using System.Linq;
using Tidbits.Core.Data;
using Xunit;

namespace Tidbits.HeadlessTests;

/// QUIZ-FORMATS-RESEARCH §4 — GIFT and Aiken. The Mac suite asserts the same
/// fixtures (TidbitsTriviaTests/LiveTextFormatsTests.swift).
public class TextQuestionFormatsTest
{
    private const string Gift = "// Moodle export\n"
        + "::coins:: Which kingdom minted the first coins? {=Lydia ~Phrygia ~Caria ~Lycia ####Electrum c.600BC}\n\n"
        + "Croesus was the last king of Lydia. {T}\n\n"
        + "::capital:: The capital of Peru is {=Lima =Ciudad de los Reyes}.\n\n"
        + "How many moons does Mars have? {#2:0}\n\n"
        + "Match the capital {=France -> Paris =Peru -> Lima =Japan -> Tokyo}\n\n"
        + "[html]Which is a spreadsheet\\: app? {~Word =Excel#Yes! ~Outlook}\n";

    private const string Aiken = "Which kingdom minted the first coins?\nA. Phrygia\nB. Lydia\nC. Caria\nD. Lycia\nANSWER: B\n\n"
        + "What is the capital of Peru?\nA) Quito\nB) Lima\nANSWER: B\n";

    [Fact]
    public void Gift_multiple_choice_true_false_short_answer_numerical_matching_and_escapes()
    {
        var qs = TextQuestionFormats.ParseGift(Gift);
        Assert.Equal(6, qs.Count);
        Assert.Equal("Which kingdom minted the first coins?", qs[0].Prompt);
        Assert.Equal("Lydia", qs[0].CorrectAnswer);
        Assert.Equal(new[] { "Lydia", "Phrygia", "Caria", "Lycia" }, qs[0].Options.ToArray());
        Assert.Equal("Electrum c.600BC", qs[0].Explanation);
        Assert.Equal(new[] { "True", "False" }, qs[1].Options.ToArray());
        Assert.Equal(0, qs[1].CorrectIndex);
        Assert.Equal("The capital of Peru is ___ .", qs[2].Prompt);
        Assert.Equal(new[] { "Lima", "Ciudad de los Reyes" }, qs[2].Accepted!.ToArray());
        Assert.Equal(2, qs[3].Closest!.Answer);
        Assert.Equal(new[] { "France", "Peru", "Japan" }, qs[4].Matching!.Keys.ToArray());
        Assert.Equal(new[] { "Paris", "Lima", "Tokyo" }, qs[4].Matching!.Values.ToArray());
        Assert.Equal("Which is a spreadsheet: app?", qs[5].Prompt);
        Assert.Equal("Excel", qs[5].CorrectAnswer);
    }

    [Fact]
    public void Aiken_lettered_options_and_an_answer_line()
    {
        var qs = TextQuestionFormats.ParseAiken(Aiken);
        Assert.Equal(2, qs.Count);
        Assert.Equal("Lydia", qs[0].CorrectAnswer);
        Assert.Equal(4, qs[0].Options.Count);
        Assert.Equal("Lima", qs[1].CorrectAnswer);
    }

    [Fact]
    public void Detection_reads_the_shape_of_the_text()
    {
        Assert.Equal(TextQuestionFormats.Kind.Gift, TextQuestionFormats.Detect(Gift));
        Assert.Equal(TextQuestionFormats.Kind.Aiken, TextQuestionFormats.Detect(Aiken));
        Assert.Equal(TextQuestionFormats.Kind.Csv, TextQuestionFormats.Detect("prompt,correct,wrong1\nA?,a,b\n"));
    }

    [Fact]
    public void Gift_export_reimports_every_type_it_writes()
    {
        var qs = TextQuestionFormats.ParseGift(Gift);
        var back = TextQuestionFormats.ParseGift(TextQuestionFormats.ExportGift(qs));
        Assert.Equal(qs.Count, back.Count);
        Assert.Equal(qs.Select(q => q.Prompt).ToArray(), back.Select(q => q.Prompt).ToArray());
        Assert.Equal("Lydia", back[0].CorrectAnswer);
        Assert.Equal("Electrum c.600BC", back[0].Explanation);
        Assert.Equal(qs[2].Accepted!.ToArray(), back[2].Accepted!.ToArray());
        Assert.Equal(2, back[3].Closest!.Answer);
        Assert.Equal(qs[4].Matching!.Keys.ToArray(), back[4].Matching!.Keys.ToArray());
    }
}
