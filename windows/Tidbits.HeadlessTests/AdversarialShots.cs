using System;
using System.Collections.Generic;
using System.IO;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// The adversarial design pass (Archive Watch's method, ported): re-shoot EVERY
/// consumer surface and read the pixels hostilely. The lint and the layout tests
/// own "did a banned shape come back"; this owns "does it look designed".
///
/// Two widths on purpose. A view photographed alone at a generous size hides the
/// faults a host actually meets — `windows-owner-parity-2026-07-30`: render the
/// WHOLE shell at a NARROW width. 1180x760 is the app's own default window;
/// 900x680 is a laptop with the sidebar open.
[Collection("EnvSensitive")]
public class AdversarialShots
{
    private static string Dir()
    {
        var dir = Environment.GetEnvironmentVariable("TIDBITS_ADVERSARIAL")
                  ?? Path.Combine(AppContext.BaseDirectory, "adversarial");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static void Shoot(Control view, string name, int w, int h)
    {
        var win = new Window { Width = w, Height = h, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        // A second pump: content that builds on Loaded is not on the glass yet.
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Dir(), $"{name}-{w}x{h}.png"));
    }

    private static LiveEvent AuthoredNight()
    {
        var qs = new List<Question>
        {
            new() { Id = "q1", Prompt = "Which Iron Age kingdom in western Anatolia minted some of the world's oldest coins?",
                    Options = new[] { "Lydia", "Phrygia", "Caria", "Lycia" }, CorrectIndex = 0, CategoryId = "history",
                    Difficulty = 3, Explanation = "Electrum coins, struck in Lydia around 600 BC." },
            new() { Id = "q2", Prompt = "Capital of Peru?", Options = new[] { "Lima", "Quito", "La Paz", "Bogota" },
                    CorrectIndex = 0, CategoryId = "geography", Difficulty = 2 },
            new() { Id = "q3", Prompt = "Who sang this?", Options = new[] { "Dolly Parton" }, CorrectIndex = 0,
                    CategoryId = "music", Difficulty = 3, Accepted = new[] { "Dolly Parton" } },
        };
        return new LiveEvent
        {
            Name = "Friday Pub Quiz",
            Rounds = new[]
            {
                new NightRound { Kind = GameMode.Classic, Count = qs.Count },
                new NightRound { Kind = GameMode.TypeAnswer, Count = 0 },
            },
            RoundQuestions = new[] { (IReadOnlyList<Question>)qs, Array.Empty<Question>() },
            RoundNotes = new[] { "Read the first one slowly.", "" },
            RoundTimers = new[] { 60, 0 },
        };
    }

    public static IEnumerable<object[]> Sizes => new[]
    {
        new object[] { 1180, 760 },   // the app's own default window
        new object[] { 900, 680 },    // a laptop with the sidebar open
    };

    [AvaloniaTheory]
    [MemberData(nameof(Sizes))]
    public void Play(int w, int h) => Shoot(new PlayView(), "play", w, h);

    [AvaloniaTheory]
    [MemberData(nameof(Sizes))]
    public void Create(int w, int h) => Shoot(new CreateView(), "create", w, h);

    [AvaloniaTheory]
    [MemberData(nameof(Sizes))]
    public void Live_landing(int w, int h) => Shoot(new LiveView(), "live-landing", w, h);

    [AvaloniaTheory]
    [MemberData(nameof(Sizes))]
    public void Live_builder_with_an_authored_round(int w, int h)
    {
        var view = new LiveView();
        var win = new Window { Width = w, Height = h, Content = view };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        view.LoadEventForTesting(AuthoredNight());
        Dispatcher.UIThread.RunJobs();
        view.ExpandRoundForTesting(0);
        Dispatcher.UIThread.RunJobs();
        view.ScrollToRoundsForTesting();
        Dispatcher.UIThread.RunJobs();
        win.CaptureRenderedFrame()!.Save(Path.Combine(Dir(), $"live-builder-{w}x{h}.png"));
    }

    [AvaloniaTheory]
    [MemberData(nameof(Sizes))]
    public void Join(int w, int h) => Shoot(new JoinPlayerView(), "join", w, h);
}
