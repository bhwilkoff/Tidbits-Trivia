using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Live builder with a round EXPANDED to its questions — WINDOWS-DESIGN §6.6.
///
/// "Renders on the Mac head" is never "correct on Windows", so this is the
/// iterate-fast half; `windows-repl.yml` renders the same PNGs on windows-latest
/// and that is the gate. What is asserted here is structural and platform-neutral:
/// the per-question controls EXIST and are reachable, which is the thing that was
/// missing entirely.
public class LiveBuilderSnapshot
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    private static Question Q(string id, string prompt, string answer) => new()
    {
        Id = id, Prompt = prompt,
        Options = [answer, "Wrong one", "Wrong two", "Wrong three"], CorrectIndex = 0,
        CategoryId = "history", Difficulty = 3, TemplateId = "hand",
    };

    [AvaloniaFact]
    public void An_expanded_round_shows_every_question_with_its_own_controls()
    {
        var view = new LiveView();
        var win = new Window { Width = 900, Height = 760, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        // Drive the builder the way a host does: load an event with authored
        // questions, then expand its first round.
        var ev = new LiveEvent
        {
            Name = "Friday Pub Quiz",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 2 }],
            RoundQuestions =
            [
                new List<Question>
                {
                    Q("g:1", "This Iron Age kingdom in western Anatolia minted the world's oldest coins — which kingdom?", "Lydia"),
                    Q("g:2", "In which year was the Battle of Hastings fought?", "1066"),
                },
            ],
            RoundNotes = ["Read the first one slowly."],
            RoundTimers = [60],
        };
        view.LoadEventForTesting(ev);
        view.ExpandRoundForTesting(0);
        Dispatcher.UIThread.RunJobs();
        view.ScrollToRoundsForTesting();
        Dispatcher.UIThread.RunJobs();

        var names = view.GetVisualDescendants().OfType<Control>()
                        .Select(AutomationProperties.GetName)
                        .Where(n => !string.IsNullOrEmpty(n)).ToList();

        // Every question is individually editable, duplicable and removable. An
        // expanded round that rendered only a summary line would pass a screenshot
        // and still leave the host unable to fix one question.
        Assert.Contains("Edit question 1 of round 1", names);
        Assert.Contains("Edit question 2 of round 1", names);
        Assert.Contains("Duplicate question 1 of round 1", names);
        Assert.Contains("Remove question 2 of round 1", names);
        Assert.Contains("Hide round 1 questions", names);

        // The prompts themselves are on the glass, not just the controls.
        var texts = view.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "").ToList();
        Assert.Contains(texts, t => t.Contains("Iron Age kingdom"));
        Assert.Contains(texts, t => t.Contains("Answer: Lydia"));
        Assert.Contains(texts, t => t.Contains("2 questions (yours)"));

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "live-builder-questions.png"));
    }

    [AvaloniaFact]
    public void A_collapsed_round_hides_the_questions_again()
    {
        var view = new LiveView();
        var win = new Window { Width = 900, Height = 700, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var ev = new LiveEvent
        {
            Name = "Collapsed",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 1 }],
            RoundQuestions = [new List<Question> { Q("g:1", "Hidden prompt", "Answer") }],
        };
        view.LoadEventForTesting(ev);
        Dispatcher.UIThread.RunJobs();

        var texts = view.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "").ToList();
        Assert.DoesNotContain(texts, t => t.Contains("Hidden prompt"));
        var names = view.GetVisualDescendants().OfType<Control>()
                        .Select(AutomationProperties.GetName).ToList();
        Assert.Contains("Show round 1 questions", names);
    }

    [AvaloniaFact]
    public void An_unauthored_round_says_it_comes_from_the_corpus()
    {
        // universal-feature-states: an expanded empty round must explain itself and
        // offer the way out, not render as a blank strip.
        var view = new LiveView();
        var win = new Window { Width = 900, Height = 700, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var ev = new LiveEvent { Name = "Empty", Rounds = [new NightRound { Kind = GameMode.Classic, Count = 5 }] };
        view.LoadEventForTesting(ev);
        view.ExpandRoundForTesting(0);
        Dispatcher.UIThread.RunJobs();
        view.ScrollToRoundsForTesting();
        Dispatcher.UIThread.RunJobs();

        var texts = view.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "").ToList();
        Assert.Contains(texts, t => t.Contains("pulled from the corpus"));

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "live-builder-unauthored-round.png"));
    }
}
