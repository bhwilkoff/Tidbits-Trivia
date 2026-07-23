using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The Club Expedition surfaces (docs/CLUB-FEATURES-BUILD.md "Feature 5") — the
/// Home/Play entry-point card, the hub + map rendering (`ExpeditionsUi`, mirrors
/// KnowledgeAtlasUi/MarathonUi's headless-testable static-builder pattern), and the
/// pass/fail/certificate stage-result beat. UNLIKE Marathon/Knowledge Atlas, the hub
/// and map render for everyone — only the map's Play button differs (Play vs Join
/// Club) — so these tests specifically check that non-member state is a real
/// preview, never a blank wall.
[Collection("EnvSensitive")]
public class ExpeditionsSnapshot
{
    private static string Art()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                  ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static List<string?> TextsOf(Control root) =>
        root.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text).ToList();

    private static void ScrollToEnd(Window win)
    {
        var scroller = win.GetVisualDescendants().OfType<ScrollViewer>().FirstOrDefault();
        if (scroller is null) return;
        scroller.ScrollToEnd();
        Dispatcher.UIThread.RunJobs();
    }

    // MARK: - Home/Play entry-point card

    [AvaloniaFact]
    public void Play_home_renders_the_expeditions_card_for_a_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "1");
        var view = new PlayView();
        var win = new Window { Width = 900, Height = 1000, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("EXPEDITIONS", texts);
        Assert.DoesNotContain("CLUB", texts); // member -> no chip
        var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Open").ToList();
        Assert.NotEmpty(buttons);

        ScrollToEnd(win);
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-expeditions-member.png"));
    }

    /// Non-member: the CLUB chip on the CARD, but the action is STILL "Open" — the
    /// hub is a real preview reachable by everyone, never gated at the card level
    /// (docs/CLUB-FEATURES-BUILD.md "Feature 5": "always opens the hub, never the
    /// paywall directly").
    [AvaloniaFact]
    public void Play_home_renders_the_expeditions_card_with_a_club_chip_but_still_opens_for_a_non_member()
    {
        using var _ = new EnvVarScope("TIDBITS_CLUB", "0");
        var view = new PlayView();
        var win = new Window { Width = 900, Height = 1000, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("EXPEDITIONS", texts);
        Assert.Contains("CLUB", texts);
        var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Open").ToList();
        Assert.NotEmpty(buttons); // NOT "Join Club" -- the hub always opens

        ScrollToEnd(win);
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "home-expeditions-non-member.png"));
    }

    // MARK: - Hub (ExpeditionsUi.BuildHub — pure, headless-testable)

    [AvaloniaFact]
    public void Hub_lists_every_campaign_with_an_honest_pitch_when_nothing_is_started()
    {
        var available = Expeditions.All.Select(e => (e, (ExpeditionProgress?)null)).ToList();
        Expedition? selected = null;
        var content = ExpeditionsUi.BuildHub(available, Array.Empty<ExpeditionCertificate>(), e => selected = e);

        var win = new Window { Width = 520, Height = 700, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("The 20th Century", texts);
        Assert.Contains("Around the World", texts);
        Assert.Contains("The Scientific Record", texts);
        Assert.Contains("Not started", texts);
        Assert.DoesNotContain("Completed", texts); // no certificates shelf yet

        var button = win.GetVisualDescendants().OfType<Button>().First();
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.NotNull(selected);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-hub-empty.png"));
    }

    [AvaloniaFact]
    public void Hub_shows_stage_progress_and_the_certificates_shelf()
    {
        var expedition = Expeditions.Named("20th-century")!;
        var progress = new ExpeditionProgress { ExpeditionId = expedition.Id, CurrentStageIndex = 3 };
        var available = Expeditions.All
            .Select(e => (e, e.Id == expedition.Id ? progress : null))
            .ToList();
        var cert = new ExpeditionCertificate
        {
            ExpeditionId = "scientific-record", Domain = "science", Title = "The Scientific Record",
            TotalScore = 63, StagesCompleted = 7,
        };
        var content = ExpeditionsUi.BuildHub(available, new[] { cert }, _ => { });

        var win = new Window { Width = 520, Height = 800, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("Stage 4 of 7", texts);
        Assert.Contains("Completed", texts); // shelf header
        Assert.Contains("63", texts);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-hub-with-progress.png"));
    }

    // MARK: - Map (locked / current / done)

    [AvaloniaFact]
    public void Map_renders_locked_current_and_done_stages_and_wires_play_on_the_current_one()
    {
        var expedition = Expeditions.Named("20th-century")!;
        var progress = new ExpeditionProgress
        {
            ExpeditionId = expedition.Id, CurrentStageIndex = 2,
            StageResults =
            {
                new ExpeditionStageResult { StageIndex = 0, Passed = true, Correct = 7, Total = 10 },
                new ExpeditionStageResult { StageIndex = 1, Passed = true, Correct = 6, Total = 10 },
            },
        };
        bool played = false;
        bool backCalled = false;
        var content = ExpeditionsUi.BuildMap(expedition, progress, isClub: true,
            onPlayCurrent: () => played = true, onBack: () => backCalled = true);

        var win = new Window { Width = 520, Height = 900, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains(texts, t => t is not null && t.Contains("Stage 1: Turn of the Century"));
        Assert.Contains(texts, t => t is not null && t.Contains("Stage 3: The Cold War Era")); // current
        Assert.Contains(texts, t => t is not null && t.Contains("Stage 7:")); // locked, still visible

        var playButtons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Play").ToList();
        Assert.Single(playButtons); // only the CURRENT stage gets a Play button
        playButtons[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(played);

        var back = win.GetVisualDescendants().OfType<Button>().First();
        back.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(backCalled);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-map-mixed-states.png"));
    }

    /// Non-member: the map STILL renders fully (a real preview) — only the current
    /// stage's button reads "Join Club" instead of "Play".
    [AvaloniaFact]
    public void Map_shows_join_club_on_the_current_stage_for_a_non_member_but_still_renders_every_stage()
    {
        var expedition = Expeditions.Named("around-the-world")!;
        var content = ExpeditionsUi.BuildMap(expedition, progress: null, isClub: false, onPlayCurrent: () => { }, onBack: () => { });

        var win = new Window { Width = 520, Height = 900, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains(texts, t => t is not null && t.Contains("Stage 1:"));
        Assert.Contains(texts, t => t is not null && t.Contains("Stage 7:")); // full path still visible
        var buttons = win.GetVisualDescendants().OfType<Button>().Where(b => (b.Content as string) == "Join Club").ToList();
        Assert.Single(buttons);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-map-non-member.png"));
    }

    [AvaloniaFact]
    public void Map_shows_a_last_try_line_on_the_current_stage_after_a_failed_attempt()
    {
        var expedition = Expeditions.Named("20th-century")!;
        var progress = new ExpeditionProgress
        {
            ExpeditionId = expedition.Id, CurrentStageIndex = 0,
            StageResults = { new ExpeditionStageResult { StageIndex = 0, Passed = false, Correct = 2, Total = 10 } },
        };
        var content = ExpeditionsUi.BuildMap(expedition, progress, isClub: true, onPlayCurrent: () => { }, onBack: () => { });

        var win = new Window { Width = 520, Height = 400, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains(texts, t => t is not null && t.Contains("Last try: needed 6 of 10, got 2"));

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-map-failed-attempt.png"));
    }

    // MARK: - Stage result (pass / fail / certificate)

    [AvaloniaFact]
    public void Stage_result_shows_not_quite_and_try_again_on_a_fail()
    {
        var expedition = Expeditions.Named("20th-century")!;
        var result = new ExpeditionPlayResult(expedition, expedition.Stages[0], Passed: false, Correct: 3, Total: 10, Certificate: null);
        bool retried = false;
        var content = ExpeditionsUi.BuildStageResult(result, onContinue: () => { }, onRetry: () => retried = true, onDone: () => { });

        var win = new Window { Width = 520, Height = 400, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("NOT QUITE", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("Needed 6 of 10 — you got 3"));

        var retry = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Try Again");
        retry.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(retried);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-stage-result-fail.png"));
    }

    [AvaloniaFact]
    public void Stage_result_shows_stage_passed_and_continue_when_more_stages_remain()
    {
        var expedition = Expeditions.Named("20th-century")!;
        var result = new ExpeditionPlayResult(expedition, expedition.Stages[0], Passed: true, Correct: 8, Total: 10, Certificate: null);
        bool continued = false;
        var content = ExpeditionsUi.BuildStageResult(result, onContinue: () => continued = true, onRetry: () => { }, onDone: () => { });

        var win = new Window { Width = 520, Height = 400, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        Assert.Contains("STAGE PASSED", TextsOf(win));
        var button = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Continue");
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(continued);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-stage-result-pass.png"));
    }

    [AvaloniaFact]
    public void Stage_result_shows_the_certificate_beat_on_the_final_stage()
    {
        var expedition = Expeditions.Named("scientific-record")!;
        var cert = new ExpeditionCertificate
        {
            ExpeditionId = expedition.Id, Domain = expedition.Domain, Title = expedition.Title,
            TotalScore = 61, StagesCompleted = 7,
        };
        var result = new ExpeditionPlayResult(expedition, expedition.Stages[6], Passed: true, Correct: 9, Total: 10, cert);
        bool done = false;
        var content = ExpeditionsUi.BuildStageResult(result, onContinue: () => { }, onRetry: () => { }, onDone: () => done = true);

        var win = new Window { Width = 520, Height = 400, Content = content };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var texts = TextsOf(win);
        Assert.Contains("EXPEDITION COMPLETE", texts);
        Assert.Contains(texts, t => t is not null && t.Contains("7 stages · score 61"));

        var button = win.GetVisualDescendants().OfType<Button>().First(b => (b.Content as string) == "Done");
        button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.True(done);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-stage-result-certificate.png"));
    }

    // MARK: - End-to-end: playing a stage through GameView writes a normal record
    // AND the campaign-tracking outcome (unlike Marathon, which skips the record).

    private static GameEngine NewEngine()
    {
        var sources = QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures"));
        return new GameEngine(new QuestionProvider(sources), sources.Difficulty);
    }

    private static RecordsStore NewRecords()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tidbits-expedition-vm-{Guid.NewGuid():N}.json");
        return new RecordsStore(path);
    }

    private static Question Q(string id, string categoryId, int difficulty = 2) => new()
    {
        Id = id, Prompt = $"Prompt for {id}", Options = new[] { "A", "B", "C", "D" },
        CorrectIndex = 0, CategoryId = categoryId, Difficulty = difficulty, Explanation = "Because.",
    };

    [AvaloniaFact]
    public void Finishing_a_stage_writes_a_normal_game_record_and_the_dedicated_result_renders()
    {
        var expedition = Expeditions.Named("20th-century")!;
        var stage = expedition.Stages[0];
        var questions = Enumerable.Range(0, stage.QuestionCount).Select(i => Q($"e{i}", "history")).ToList();
        var engine = NewEngine();
        var records = NewRecords();
        engine.StartCustom(GameMode.Classic, TriviaCategory.Named("history"), questions);

        var vm = new GameViewModel(engine, records, expeditionStage: (expedition, stage.Index));
        var win = new Window { Width = 900, Height = 900, Content = new GameView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        int guard = 0;
        while (engine.CurrentPhase != GameEngine.Phase.Finished && guard++ < 40)
        {
            if (engine.CurrentPhase == GameEngine.Phase.Playing && engine.Current is { } cur)
                engine.Submit(cur.CorrectIndex); // pass the stage
            else if (engine.CurrentPhase == GameEngine.Phase.Reveal)
                engine.Advance();
            Dispatcher.UIThread.RunJobs();
        }

        Assert.Equal(GameEngine.Phase.Finished, engine.CurrentPhase);
        Assert.True(vm.IsExpeditionStage);
        Assert.NotNull(vm.ExpeditionResult);
        Assert.True(vm.ExpeditionResult!.Passed);
        Assert.Equal(stage.QuestionCount, vm.ExpeditionResult.Correct);

        // UNLIKE Marathon, a stage writes a normal GameRecord — the regression this
        // test catches is accidentally routing Expedition through Marathon's
        // skip-the-record path.
        Assert.Single(records.Games);
        Assert.Equal(1, Expeditions.Progress(records, expedition.Id)!.CurrentStageIndex);

        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "expeditions-stage-play-through.png"));
    }
}
