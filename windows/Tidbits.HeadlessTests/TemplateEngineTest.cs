using System.Linq;
using Tidbits.Core.Engine;
using Tidbits.Core.Networking;
using Xunit;

public class TemplateEngineTest
{
    private static WikipediaClient.Summary Sci(string title, string first, string desc)
    {
        // Pad the extract past the 600-char fame floor with plausible prose.
        var pad = string.Concat(Enumerable.Repeat(" Their work influenced generations of researchers and remains widely studied today.", 8));
        return new WikipediaClient.Summary
        {
            Type = "standard",
            Title = title,
            Description = desc,
            Extract = first + pad,
        };
    }

    private static WikipediaClient.Summary[] Pool() => new[]
    {
        Sci("Ada Lovelace", "Ada Lovelace was an English mathematician who wrote the first published algorithm for the Analytical Engine.", "English mathematician"),
        Sci("Alan Turing", "Alan Turing was an English mathematician who formalised computation with the Turing machine at Cambridge.", "English mathematician"),
        Sci("Emmy Noether", "Emmy Noether was a German mathematician who proved a foundational theorem linking symmetry and conservation.", "German mathematician"),
        Sci("Carl Gauss", "Carl Gauss was a German mathematician who contributed to number theory and the normal distribution.", "German mathematician"),
        Sci("Henri Poincare", "Henri Poincare was a French mathematician who founded topology and studied the three-body problem.", "French mathematician"),
    };

    [Fact]
    public void Generates_well_formed_questions()
    {
        var qs = TemplateEngine.MakeQuestions(Pool(), "science", 3, seed: 42);
        Assert.NotEmpty(qs);
        foreach (var q in qs)
        {
            Assert.Equal(4, q.Options.Count);                       // exactly 4 options
            Assert.InRange(q.CorrectIndex, 0, 3);                   // valid answer index
            Assert.Equal(4, q.Options.Distinct().Count());          // no duplicate options
            Assert.NotEqual("", q.Prompt);
            Assert.Contains("science", q.CategoryId);
            // The answer text must NOT appear in the prompt (no leak).
            Assert.False(TemplateEngine.Leaks(q.Options[q.CorrectIndex], q.Prompt));
        }
    }

    [Fact]
    public void Deterministic_for_a_fixed_seed()
    {
        var a = TemplateEngine.MakeQuestions(Pool(), "science", 3, seed: 7);
        var b = TemplateEngine.MakeQuestions(Pool(), "science", 3, seed: 7);
        Assert.Equal(a.Select(q => q.Prompt), b.Select(q => q.Prompt));
    }

    [Fact]
    public void Quality_gate_rejects_stubs_and_disambiguation()
    {
        Assert.False(TemplateEngine.IsUsable(new WikipediaClient.Summary { Title = "X", Description = "short", Extract = "tiny" }));
        Assert.False(TemplateEngine.IsUsable(new WikipediaClient.Summary { Title = "Mercury", Type = "disambiguation", Description = "several meanings here", Extract = new string('x', 700) }));
        Assert.False(TemplateEngine.IsUsable(new WikipediaClient.Summary { Title = "List of rivers", Description = "a list of rivers in the world", Extract = new string('x', 700) }));
    }
}
