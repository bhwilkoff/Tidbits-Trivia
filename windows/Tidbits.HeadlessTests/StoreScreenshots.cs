using System;
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
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Microsoft Store screenshot set (docs/STORE-SCREENSHOTS.md).
///
/// There is no local Windows box (Decision 045), so these render through the same
/// `Avalonia.Headless` + Skia path the visual gate uses. Run on `windows-latest` via
/// `windows-repl.yml` and download the artifact — Skia rasterization and font fallback are
/// NOT identical between the macOS dev head and Windows, so a Mac-rendered PNG would ship a
/// listing that doesn't match what a Windows user sees. The Mac run is for iteration only.
///
/// **Every shot renders the real `MainWindow` shell**, not a bare `UserControl`. A first
/// attempt hosted the views directly and every frame came back with the content collapsed
/// into a narrow left-hand column against a huge empty field: these views are designed to
/// live inside the `FANavigationView`, and without it they lay out at their minimum width.
/// A store screenshot has to show the app a buyer will actually see, chrome included.
///
/// Written to `TIDBITS_ARTIFACTS/store/NN-name.png`, upload-ready as-is.
///
/// **R-SHOT-1: every frame shows a FREE feature** — no Club surface, no paywall.
[Collection("EnvSensitive")]
public class StoreScreenshots
{
    // Microsoft Store accepts 1366×768 and up. 1366×768 — not 1920×1080 — is the right
    // choice here: the app lays its content out in a ~760px column beside a ~200px nav, so
    // at 1920 wide roughly half the frame is empty background. At 1366 the same UI fills
    // the frame and the type reads at thumbnail size.
    private const int W = 1366;
    private const int H = 768;

    private static string StoreDir()
    {
        var root = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                   ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        var dir = Path.Combine(root, "store");
        Directory.CreateDirectory(dir);
        return dir;
    }

    /// The real shell, shown and settled. The Play tab is selected by MainWindow's own
    /// Loaded handler, so a plain Shell() is already the Home shot.
    private static MainWindow Shell()
    {
        var win = new MainWindow { DataContext = new MainWindowViewModel(), Width = W, Height = H };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        return win;
    }

    private static void Save(Window win, string name)
    {
        Dispatcher.UIThread.RunJobs();
        var frame = win.CaptureRenderedFrame()
                    ?? throw new InvalidOperationException($"'{name}' captured no frame");
        frame.Save(Path.Combine(StoreDir(), $"{name}.png"));
    }

    private static T? ByName<T>(Visual root, string name) where T : Control =>
        root.GetVisualDescendants().OfType<T>().FirstOrDefault(c => c.Name == name);

    /// Put a live game inside the shell exactly where the app puts it: PlayView swaps its
    /// own `GameHost` and hides `Landing`. Reached through the visual tree so no app code
    /// needs a screenshot-only seam.
    private static void HostGame(MainWindow win, GameViewModel vm)
    {
        var host = ByName<ContentControl>(win, "GameHost")
                   ?? throw new InvalidOperationException("PlayView.GameHost not found in the shell");
        var landing = ByName<ScrollViewer>(win, "Landing");
        if (landing is not null) landing.IsVisible = false;
        host.Content = new GameView { DataContext = vm };
        Dispatcher.UIThread.RunJobs();
    }


    /// Terms that must never appear in a store screenshot. A random corpus draw put a
    /// Holocaust question — "the official Nazi code name for the murder of all Jews within
    /// reach" — into the reveal slot, the single most-viewed frame in the listing. The corpus
    /// legitimately contains hard history; a marketing asset is not the place for it, and a
    /// random draw will surface it again eventually.
    private static readonly string[] Unsafe =
    {
        "nazi", "holocaust", "genocide", "massacre", "atrocit", "murder", "killed", "killing",
        "war crime", "execut", "slaver", "slave", "rape", "assassin", "terror", "suicide",
        "famine", "lynch", "torture", "concentration camp", "ethnic cleansing", "bomb",
        "casualt", "died", "death", "deaths", "fatal", "shot dead", "abuse",
    };

    private static bool IsSafe(Question q)
    {
        var haystack = (q.Prompt + " " + string.Join(" ", q.Options) + " " + (q.Explanation ?? "")).ToLowerInvariant();
        return !Unsafe.Any(haystack.Contains);
    }

    /// A deterministic, screened, VARIED set of real corpus questions for the gameplay
    /// shots. Screening alone wasn't enough: ordering the safe pool by id produced ten
    /// near-identical "which of these was born first?" questions, which advertises a
    /// one-note app. So this also requires a story (the differentiator), prefers the
    /// narrative-length prompts, and takes at most one question per category and per
    /// prompt-shape.
    private static List<Question> SafeQuestions(QuestionSources src, int count)
    {
        var candidates = src.Corpus.Questions("mixed", new HashSet<string>(), 8000)
            .Where(IsSafe)
            // The reveal slot sells "you LEARN here", so the question needs a real story —
            // not a restatement. A first pass surfaced "In what year was <film> released?"
            // whose whole explanation was "<film>: 2023", which differentiates nothing.
            .Where(q => (q.Explanation ?? "").Length >= 80)
            // " is a " / " was a " picks the Wikipedia-lead-style explanations (the ones that
            // actually teach you something) over the restatements ("The elevation of X is
            // about 313 m."), which read as filler in the differentiator slot.
            .Where(q => (q.Explanation ?? "").Contains(" is a ") || (q.Explanation ?? "").Contains(" was a "))
            .Where(q => !q.Prompt.StartsWith("In what year", StringComparison.OrdinalIgnoreCase))
            // The older test fixture still has 2,313 explanations with a body blank the
            // corpus repair could not resolve — never let one into a listing.
            .Where(q => !(q.Explanation ?? "").Contains("____"))
            .Where(q => q.Prompt.Length >= 70)                       // the narrative prompts read best
            .OrderBy(q => q.Id, StringComparer.Ordinal)              // stable across runs
            .ToList();

        var chosen = new List<Question>();
        var usedCategories = new HashSet<string>();
        var usedShapes = new HashSet<string>();
        // Two passes: first one-per-category for maximum spread, then fill by shape only.
        foreach (var pass in new[] { true, false })
        {
            foreach (var q in candidates)
            {
                if (chosen.Count == count) break;
                if (chosen.Contains(q)) continue;
                var shape = new string(q.Prompt.Take(24).ToArray()).ToLowerInvariant();
                if (!usedShapes.Add(shape)) continue;
                if (pass && !usedCategories.Add(q.CategoryId)) { usedShapes.Remove(shape); continue; }
                chosen.Add(q);
            }
        }
        Assert.True(chosen.Count == count, $"only {chosen.Count} varied screened questions available, need {count}");
        return chosen;
    }

    private static QuestionSources Sources() =>
        QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));

    private static GameEngine NewEngine(QuestionSources? s = null)
    {
        var src = s ?? Sources();
        return new GameEngine(new QuestionProvider(src), src.Difficulty);
    }

    private static async Task PlayToEnd(GameEngine engine)
    {
        int guard = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 300)
        {
            if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } q)
                engine.Submit(q.CorrectIndex);   // correct throughout: option 0 is a harness
                                                 // artefact and would advertise a bad score
            else if (engine.CurrentPhase == GameEngine.Phase.Reveal) engine.Advance();
            Dispatcher.UIThread.RunJobs();
        }
        await Task.CompletedTask;
    }

    [AvaloniaFact]
    public void Shot_01_home()
    {
        Save(Shell(), "01-home");
    }

    [AvaloniaFact]
    public async Task Shot_02_question_and_03_reveal()
    {
        var win = Shell();
        var src = Sources();
        var engine = NewEngine(src);
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("mixed"), SafeQuestions(src, 10));
        Dispatcher.UIThread.RunJobs();
        var vm = new GameViewModel(engine);
        HostGame(win, vm);

        Assert.Equal(GameEngine.Phase.Playing, engine.CurrentPhase);
        Assert.True(IsSafe(engine.Current!), "the question shot must be screened");
        Save(win, "02-question");

        // The reveal + its "story behind the answer" is the differentiator (R-SHOT-2), so it
        // shows a CORRECT answer — never a red miss.
        engine.Submit(engine.Current!.CorrectIndex);
        Dispatcher.UIThread.RunJobs();
        Assert.Equal(GameEngine.Phase.Reveal, engine.CurrentPhase);
        Save(win, "03-reveal");
    }

    [AvaloniaFact]
    public async Task Shot_04_results()
    {
        var win = Shell();
        var src = Sources();
        var engine = NewEngine(src);
        // The scorecard lists every question under "Tough ones you nailed", so the WHOLE
        // round has to be screened, not just the first question.
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("mixed"), SafeQuestions(src, 10));
        Dispatcher.UIThread.RunJobs();
        var vm = new GameViewModel(engine);
        HostGame(win, vm);
        await PlayToEnd(engine);
        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Save(win, "04-results");
    }

    [AvaloniaFact]
    public async Task Shot_05_records()
    {
        // Real history, not an empty state: play a spread of modes/categories into a
        // throwaway store, then show the Records tab in the shell.
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-store-shot-{Guid.NewGuid():N}.json");
        try
        {
            var sources = Sources();
            var store = new RecordsStore(path);
            foreach (var (mode, cat) in new (GameMode, string)[]
                     {
                         (GameMode.Classic, "history"), (GameMode.Classic, "science"),
                         (GameMode.TimeAttack, "geography"), (GameMode.Survival, "arts"),
                         (GameMode.Classic, "music"), (GameMode.Sweep, "screen"),
                     })
            {
                var engine = NewEngine(sources);
                await engine.Start(mode, TriviaCategory.Named(cat));
                await PlayToEnd(engine);
                store.Record(engine.Summary);
            }

            var win = Shell();
            win.Route(new DeepLinkTarget(DeepLinkKind.Records));
            Dispatcher.UIThread.RunJobs();
            // The shell binds Records to the app's shared store; point it at the seeded one.
            var host = ByName<ContentControl>(win, "ContentHost");
            if (host is not null) host.Content = new RecordsView { DataContext = new RecordsViewModel(store) };
            Save(win, "05-records");
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [AvaloniaFact]
    public void Shot_06_trivia_night()
    {
        var win = Shell();
        win.Route(new DeepLinkTarget(DeepLinkKind.Live));
        Save(win, "06-trivia-night");
    }

    [AvaloniaFact]
    public void Shot_08_create()
    {
        var win = Shell();
        win.Route(new DeepLinkTarget(DeepLinkKind.Create));
        Save(win, "08-create");
    }

    /// R-SHOT-1, enforced: no store frame may name a Club feature or quote a price. A
    /// screenshot set is exactly the kind of asset that drifts silently.
    [AvaloniaFact]
    public void No_store_shot_surfaces_a_club_feature()
    {
        foreach (var kind in new[] { DeepLinkKind.Play, DeepLinkKind.Records, DeepLinkKind.Create, DeepLinkKind.Live })
        {
            var win = Shell();
            win.Route(new DeepLinkTarget(kind));
            Dispatcher.UIThread.RunJobs();
            var texts = win.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "").ToList();
            foreach (var banned in new[] { "LINK WALL", "WEAK-SPOT ARENA", "MARATHON", "EXPEDITIONS", "STORY ARCHIVE", "KNOWLEDGE ATLAS" })
                Assert.DoesNotContain(banned, texts);
            // The single quiet Club DOOR on Play is allowed — its own copy says the rest is
            // free (docs/STORE-SCREENSHOTS.md §1). A price never is.
            Assert.DoesNotContain(texts, t => t.Contains('$'));
        }
    }
}
