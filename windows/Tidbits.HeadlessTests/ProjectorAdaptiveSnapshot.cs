using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Tidbits.App.Services;
using Xunit;

/// macOS-DESIGN A8.9 on Windows: the projector ADAPTS to which elements are on,
/// and nothing is ever laid over anything. Renders the question and the reveal
/// with a long prompt, a long story, six teams and votes at 1280x720 and
/// 1920x1080, with every A8.7 element ON and then OFF, and asserts the thing
/// the owner reported on the Mac ("literally everything overlaps"): no two
/// visible text blocks intersect, and nothing is truncated.
namespace Tidbits.HeadlessTests;

public class ProjectorAdaptiveSnapshot
{
    private const string LongPrompt =
        "This Iron Age kingdom in western Anatolia, ruled from Sardis, is credited with minting " +
        "some of the world's oldest coins from electrum in the seventh century BCE — which kingdom?";
    private const string LongStory =
        "Lydia's coins were struck from electrum, a natural alloy of gold and silver panned from the Pactolus " +
        "river; the stamped lion of the Mermnad dynasty guaranteed weight, which is what let coins replace " +
        "weighed metal. Croesus, the last Lydian king, later separated gold and silver into a bimetallic standard.";

    private static string ArtifactDir()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static (LiveNightHost Host, Action Seed) SeededHost()
    {
        var q = new Question
        {
            Id = "adaptive-1", Prompt = LongPrompt,
            Options = new[] { "Kingdom of Portugal", "Pahlavi Iran", "Lydia", "Soviet Union" },
            CorrectIndex = 2, CategoryId = "history", Difficulty = 3, Explanation = LongStory,
            SourceTitle = "", TemplateId = "mcq",
        };
        var plan = new NightPlan { Rounds = new[] { new NightRound { Kind = GameMode.Classic, Count = 1 } } };
        var host = new LiveNightHost(plan, TriviaCategory.Named("history"), null!, "Thursday Night Trivia at The Anchor")
        {
            AuthoredQuestions = new[] { (IReadOnlyList<Question>)new[] { q } },
            Sponsor = "Left Hand Brewing",
        };
        var names = new[] { "The Quizzards of Oz", "Les Quizerables", "Trivia Newton John", "Norfolk Enchants", "Smarty Pints", "Beer Pressure" };
        var teams = new Dictionary<string, LiveRoom.Team>(); var scores = new Dictionary<string, int>(); var answers = new Dictionary<string, LiveRoom.Answer>();
        var pts = new[] { 14, 12, 12, 9, 7, 3 }; var picks = new[] { 2, 2, 0, 2, 1, 3 };
        for (int i = 0; i < names.Length; i++)
        {
            teams[$"uid{i}"] = new LiveRoom.Team { Name = names[i], JoinedAt = 1_757_000_000_000 + i };
            scores[$"uid{i}"] = pts[i];
            answers[$"uid{i}"] = new LiveRoom.Answer { Choice = picks[i], Ts = 1_757_000_000_000 };
        }
        // Seeded AFTER the reveal: with the net "open", Reveal would publish to a
        // real database from a unit test.
        return (host, () => host.Net.PreviewSeed("QATEST", teams, scores, answers));
    }

    private static IEnumerable<(string Text, Rect Box)> VisibleTextBoxes(Window win) =>
        win.GetVisualDescendants().OfType<TextBlock>()
           .Where(t => t.IsEffectivelyVisible && !string.IsNullOrWhiteSpace(t.Text) && t.Bounds.Width > 0)
           .Select(t =>
           {
               var tb = t.GetTransformedBounds();
               return (t.Text!, tb is { } b ? b.Bounds.TransformToAABB(b.Transform) : t.Bounds);
           });

    private static void AssertNoOverlap(Window win, string label)
    {
        var boxes = VisibleTextBoxes(win).ToList();
        for (int i = 0; i < boxes.Count; i++)
            for (int j = i + 1; j < boxes.Count; j++)
            {
                var a = boxes[i].Box.Deflate(1); var b = boxes[j].Box.Deflate(1);
                var x = a.Intersect(b);
                // A sliver of overlap between neighbours in a row is layout rounding; a
                // real collision covers a meaningful area of the smaller block.
                var minArea = Math.Min(a.Width * a.Height, b.Width * b.Height);
                Assert.False(x.Width > 0 && x.Height > 0 && x.Width * x.Height > 0.1 * minArea,
                             $"{label}: \"{boxes[i].Text}\" overlaps \"{boxes[j].Text}\"");
            }
        foreach (var t in boxes.Select(b => b.Text))
            Assert.False(t.TrimEnd().EndsWith("…") || t.TrimEnd().EndsWith("..."), $"{label}: truncated: {t}");
        // A line limit drops the LAST line of a question with no ellipsis at all —
        // the room reads "…in the seventh century BCE — which" and nothing else.
        // Clipping is measured, not inferred: the laid-out text must fit its box.
        foreach (var t in win.GetVisualDescendants().OfType<TextBlock>()
                              .Where(t => t.IsEffectivelyVisible && !string.IsNullOrWhiteSpace(t.Text)))
            Assert.True(t.Bounds.Height + 1.5 >= t.TextLayout.Height,
                        $"{label}: clipped ({t.TextLayout.Height:F0} of text in {t.Bounds.Height:F0}): {t.Text}");
    }

    public static IEnumerable<object[]> Cases()
    {
        foreach (var (w, h) in new[] { (1280, 720), (1920, 1080) })
            foreach (var reveal in new[] { false, true })
                foreach (var allOn in new[] { true, false })
                    yield return new object[] { w, h, reveal, allOn };
    }

    [AvaloniaTheory]
    [MemberData(nameof(Cases))]
    public async Task Every_projector_state_fits_with_nothing_overlapping(int w, int h, bool reveal, bool allOn)
    {
        ProjectorElements.FilePath = Path.Combine(Path.GetTempPath(), $"projector-elements-test-{Guid.NewGuid():N}.json");
        var elements = ProjectorElements.Shared;
        if (allOn) elements.ShowEverything();
        else foreach (var e in ProjectorElements.All) elements.Set(e.Id, false);

        var (host, seed) = SeededHost();
        await host.LoadQuestionsOffline();
        Assert.NotNull(host.Current);
        if (reveal) await host.Reveal();
        seed();
        var vm = new LiveHostViewModel(host);
        var win = new Window { Width = w, Height = h, Content = new ProjectorView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        await Task.Yield();
        Dispatcher.UIThread.RunJobs();

        var label = $"projector-adaptive-{w}x{h}-{(reveal ? "reveal" : "question")}-{(allOn ? "all-on" : "all-off")}";
        win.CaptureRenderedFrame()!.Save(Path.Combine(ArtifactDir(), label + ".png"));

        var text = VisibleTextBoxes(win).Select(b => b.Text).ToList();
        Assert.Contains(text, t => t.Contains("Iron Age"));
        if (allOn)
        {
            Assert.Contains(text, t => t.Contains("QATEST"));
            Assert.Contains(text, t => t.Contains("Quizzards"));
            Assert.Contains(text, t => t.Contains("Left Hand"));
            if (reveal) Assert.Contains(text, t => t.Contains("electrum"));
        }
        else
        {
            Assert.DoesNotContain(text, t => t.Contains("QATEST"));
            Assert.DoesNotContain(text, t => t.Contains("Left Hand"));
        }
        AssertNoOverlap(win, label);
        elements.ShowEverything();
    }
}
