using System;
using System.ComponentModel;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

public partial class GameView : UserControl
{
    private static readonly IBrush Correct = new SolidColorBrush(Color.Parse("#1E9E6A"));
    private static readonly IBrush Wrong = new SolidColorBrush(Color.Parse("#D64545"));

    private GameViewModel? _vm;

    public GameView()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (_vm is not null) _vm.Engine.PropertyChanged -= OnEngineChanged;
        _vm = DataContext as GameViewModel;
        if (_vm is not null) _vm.Engine.PropertyChanged += OnEngineChanged;
        RebuildOptions();
    }

    /// Rebuild the answer surface only on a full change (phase/question) or an
    /// explicit reorder — NOT on the 100ms Remaining tick, which would otherwise
    /// destroy the text field / slider the player is interacting with.
    private void OnEngineChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (string.IsNullOrEmpty(e.PropertyName) || e.PropertyName == nameof(GameEngine.CurrentOrder))
            RebuildOptions();
        if (string.IsNullOrEmpty(e.PropertyName))
        {
            RebuildMarathonResult();
            RebuildExpeditionResult();
        }
    }

    /// Club Marathon's Finished-phase scorecard renders via the same builder the
    /// Records "Marathon History" drill-in uses (`MarathonUi.BuildScorecard`) — one
    /// implementation, headless-testable, instead of a parallel XAML template
    /// (docs/CLUB-FEATURES-BUILD.md "Feature 3"). GameViewModel's own
    /// PropertyChanged subscription (constructed first) always runs before this
    /// one, so `_vm.MarathonResult` is already set the instant the run finishes.
    private void RebuildMarathonResult()
    {
        if (MarathonResultHost is null) return;
        var engine = _vm?.Engine;
        if (engine?.Mode != GameMode.Marathon || engine.CurrentPhase != GameEngine.Phase.Finished
            || _vm?.MarathonResult is not { } result || _vm.Records is not { } records)
        {
            MarathonResultHost.Content = null;
            return;
        }
        var previous = records.MarathonHistory.SkipWhile(s => s != result).Skip(1).FirstOrDefault();
        MarathonResultHost.Content = MarathonUi.BuildScorecard(result, previous, records.MarathonHistory.Count,
            onPlayAgain: () => _vm!.PlayAgain(), onDone: () => _vm!.Quit(),
            onSeeHistory: () => _ = MarathonHistoryDialog.ShowAsync(records));
    }

    /// Club Expedition's Finished-phase pass/fail/certificate beat — renders via
    /// `ExpeditionsUi.BuildStageResult` (docs/CLUB-FEATURES-BUILD.md "Feature 5").
    /// Continue (pass) / Try Again (fail) / Done (certificate) all just close the
    /// session — the launcher's `Closed` handler re-opens the campaign's map so the
    /// player sees the result reflected immediately (mirrors Marathon's
    /// `RebuildMarathonResult` pattern: GameViewModel's own PropertyChanged
    /// subscription runs first, so `_vm.ExpeditionResult` is already set here).
    private void RebuildExpeditionResult()
    {
        if (ExpeditionResultHost is null) return;
        var engine = _vm?.Engine;
        if (engine?.CurrentPhase != GameEngine.Phase.Finished || _vm?.ExpeditionResult is not { } result)
        {
            ExpeditionResultHost.Content = null;
            return;
        }
        ExpeditionResultHost.Content = ExpeditionsUi.BuildStageResult(result,
            onContinue: () => _vm!.Quit(),
            onRetry: () => _vm!.PlayAgain(),
            onDone: () => _vm!.Quit());
    }

    /// The answer surface is rebuilt on each engine change and dispatched by the
    /// question's shape: MCQ options (recolored on reveal), a numeric slider
    /// (Closest Call), or a text field (Name It / Type-the-answer).
    private void RebuildOptions()
    {
        OptionsPanel.Children.Clear();
        var engine = _vm?.Engine;
        if (engine?.Current is not { } q) return;
        if (engine.CurrentPhase is not (GameEngine.Phase.Playing or GameEngine.Phase.Reveal)) return;

        bool reveal = engine.CurrentPhase == GameEngine.Phase.Reveal;
        if (q.Closest is { } closest) { BuildNumeric(engine, closest, reveal); return; }
        if (q.Accepted is not null) { BuildText(engine, reveal); return; }
        if (q.Ordering is { } ordering) { BuildOrdering(engine, ordering, reveal); return; }
        if (q.Matching is { } matching) { BuildMatch(engine, matching, reveal); return; }
        if (q.Enumerate is { } enumSpec) { BuildEnum(engine, enumSpec, reveal); return; }
        if (q.ImageUrl is { } imageUrl) { BuildPicture(engine, q, imageUrl, reveal); return; }
        if (engine.Mode == GameMode.Stake) { BuildStake(engine, q, reveal); return; }
        BuildMcq(engine, q, reveal);
    }

    /// MCQ options — green correct / red chosen-wrong / dim others on reveal.
    /// When !interactive (Stake before a chip is committed) options are dimmed
    /// and unclickable.
    private void BuildMcq(GameEngine engine, Tidbits.Core.Models.Question q, bool reveal, bool interactive = true)
    {
        for (int i = 0; i < q.Options.Count; i++)
        {
            int idx = i;
            var btn = new Button
            {
                Content = q.Options[i],
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(16, 13),
                FontSize = 15,
                Margin = new Thickness(0, 4),
            };
            if (reveal)
            {
                // Non-interactive via hit-test only — NOT IsEnabled=false, whose disabled-state
                // styling would override the green/red backgrounds we set here.
                btn.IsHitTestVisible = false;
                if (i == q.CorrectIndex) { btn.Background = Correct; btn.Foreground = Brushes.White; }
                else if (i == engine.ChosenIndex) { btn.Background = Wrong; btn.Foreground = Brushes.White; }
                else btn.Opacity = 0.45;
            }
            else if (interactive)
            {
                btn.Click += (_, _) => _vm?.Submit(idx);
            }
            else
            {
                btn.IsHitTestVisible = false;
                btn.Opacity = 0.4;
            }
            OptionsPanel.Children.Add(btn);
        }
    }

    /// Stake — a confidence-chip budget row above the MCQ options. Options stay
    /// dimmed until a chip is committed (the engine blocks Submit otherwise).
    private void BuildStake(GameEngine engine, Tidbits.Core.Models.Question q, bool reveal)
    {
        if (!reveal)
        {
            var chips = new WrapPanel { Margin = new Thickness(0, 0, 0, 6) };
            foreach (var tier in engine.StakeTiers)
            {
                var t = tier;
                bool selected = engine.CurrentStake == t.Value;
                var chip = new Button
                {
                    Content = $"{t.Label} +{t.Value} · ×{t.Remaining}",
                    Margin = new Thickness(0, 0, 8, 8), Padding = new Thickness(14, 9),
                    IsEnabled = t.Remaining > 0 || selected,
                };
                if (selected) chip.Classes.Add("accent");
                chip.Click += (_, _) => engine.SetStake(t.Value);
                chips.Children.Add(chip);
            }
            OptionsPanel.Children.Add(chips);
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = engine.CurrentStake == 0 ? "Commit a chip, then answer." : $"Staked {engine.StakeLabel} (+{engine.CurrentStake})",
                FontSize = 13, Opacity = 0.7, Margin = new Thickness(0, 0, 0, 8),
            });
        }
        BuildMcq(engine, q, reveal, interactive: reveal || engine.CurrentStake != 0);
    }

    /// In Order — each item with up/down move buttons, then Submit. On reveal the
    /// panel shows the correct sequence (the shared card has no single answer).
    private void BuildOrdering(GameEngine engine, System.Collections.Generic.IReadOnlyList<string> correct, bool reveal)
    {
        if (reveal)
        {
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = "Correct order", FontWeight = FontWeight.Bold, FontSize = 14, Margin = new Thickness(0, 0, 0, 6),
            });
            for (int i = 0; i < correct.Count; i++)
                OptionsPanel.Children.Add(new TextBlock
                {
                    Text = $"{i + 1}.  {correct[i]}", FontSize = 15, Foreground = Correct, Margin = new Thickness(0, 3),
                });
            return;
        }

        var order = engine.CurrentOrder;
        for (int i = 0; i < order.Count; i++)
        {
            int idx = i;
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto"), Margin = new Thickness(0, 4) };
            var label = new Border
            {
                Background = new SolidColorBrush(Color.Parse("#20808080")), CornerRadius = new CornerRadius(8),
                Padding = new Thickness(14, 11), Child = new TextBlock { Text = order[i], FontSize = 15 },
            };
            var up = new Button { Content = "▲", Margin = new Thickness(6, 0, 0, 0), Padding = new Thickness(12, 8), IsEnabled = idx > 0 };
            var down = new Button { Content = "▼", Margin = new Thickness(6, 0, 0, 0), Padding = new Thickness(12, 8), IsEnabled = idx < order.Count - 1 };
            up.Click += (_, _) => engine.MoveOrderItem(idx, up: true);
            down.Click += (_, _) => engine.MoveOrderItem(idx, up: false);
            Grid.SetColumn(up, 1); Grid.SetColumn(down, 2);
            row.Children.Add(label); row.Children.Add(up); row.Children.Add(down);
            OptionsPanel.Children.Add(row);
        }
        var submit = new Button
        {
            Content = "Submit order", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 12), FontWeight = FontWeight.Bold, Margin = new Thickness(0, 10, 0, 0),
        };
        submit.Classes.Add("accent");
        submit.Click += (_, _) => engine.SubmitOrder();
        OptionsPanel.Children.Add(submit);
    }

    /// Match Up — tap a key row (highlights), then tap a value chip to link it.
    /// A linked key shows its value inline. Reveal lists each key → correct value.
    private void BuildMatch(GameEngine engine, Tidbits.Core.Models.MatchSpec m, bool reveal)
    {
        if (reveal)
        {
            for (int k = 0; k < m.Keys.Count; k++)
            {
                bool got = engine.MatchedValue(k) == m.Values[k];
                OptionsPanel.Children.Add(new TextBlock
                {
                    Text = $"{m.Keys[k]}  →  {m.Values[k]}", FontSize = 15, Margin = new Thickness(0, 3),
                    Foreground = got ? Correct : Wrong,
                });
            }
            return;
        }

        for (int k = 0; k < m.Keys.Count; k++)
        {
            int key = k;
            bool selected = engine.MatchSelectedKey == k;
            var matched = engine.MatchedValue(k);
            var row = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(14, 11), Margin = new Thickness(0, 4),
                Content = matched is null ? m.Keys[k] : $"{m.Keys[k]}  →  {matched}",
            };
            if (selected) row.Classes.Add("accent");
            row.Click += (_, _) => engine.SelectMatchKey(key);
            OptionsPanel.Children.Add(row);
        }

        OptionsPanel.Children.Add(new TextBlock
        {
            Text = engine.MatchSelectedKey is null ? "Tap a row, then tap its match below." : "Now tap the matching value.",
            FontSize = 13, Opacity = 0.7, Margin = new Thickness(0, 8, 0, 4),
        });
        var chips = new WrapPanel();
        for (int v = 0; v < engine.MatchValues.Count; v++)
        {
            int val = v;
            var chip = new Button
            {
                Content = engine.MatchValues[v], Margin = new Thickness(0, 0, 8, 8), Padding = new Thickness(13, 9),
                IsEnabled = engine.MatchSelectedKey is not null,
            };
            chip.Click += (_, _) => engine.AssignMatchValue(val);
            chips.Children.Add(chip);
        }
        OptionsPanel.Children.Add(chips);

        var submit = new Button
        {
            Content = "Submit matches", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 12), FontWeight = FontWeight.Bold, Margin = new Thickness(0, 10, 0, 0),
        };
        submit.Classes.Add("accent");
        submit.Click += (_, _) => engine.SubmitMatch();
        OptionsPanel.Children.Add(submit);
    }

    /// Name as Many — type against a 60s clock; each unique hit fills a chip.
    /// Reveal shows the full set, named vs missed. "Done" ends early.
    private void BuildEnum(GameEngine engine, Tidbits.Core.Models.EnumSpec spec, bool reveal)
    {
        if (reveal)
        {
            var named = new System.Collections.Generic.HashSet<string>(engine.EnumNamed);
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = $"You named {engine.EnumNamed.Count} of {spec.Total}", FontWeight = FontWeight.Bold,
                FontSize = 15, Margin = new Thickness(0, 0, 0, 6),
            });
            var all = new WrapPanel();
            foreach (var name in spec.DisplayNames)
            {
                bool hit = named.Contains(name);
                all.Children.Add(new Border
                {
                    Background = new SolidColorBrush(hit ? Color.Parse("#2620A060") : Color.Parse("#18808080")),
                    CornerRadius = new CornerRadius(8), Padding = new Thickness(11, 7), Margin = new Thickness(0, 0, 8, 8),
                    Child = new TextBlock { Text = name, FontSize = 14, Foreground = hit ? Correct : null, Opacity = hit ? 1 : 0.6 },
                });
            }
            OptionsPanel.Children.Add(all);
            return;
        }

        OptionsPanel.Children.Add(new TextBlock
        {
            Text = $"{engine.EnumFilled.Count} of {spec.Total}", FontSize = 22, FontWeight = FontWeight.Bold,
            Margin = new Thickness(0, 0, 0, 6),
        });

        var box = new TextBox { Text = "", Watermark = "Name one…", FontSize = 16, Margin = new Thickness(0, 4) };
        void Go()
        {
            var text = box.Text ?? "";
            if (text.Trim().Length == 0) return;
            engine.SubmitEnumGuess(text); // fires Changed -> rebuild (fresh empty box, refocused)
        }
        box.KeyDown += (_, ev) => { if (ev.Key == Avalonia.Input.Key.Enter) Go(); };
        OptionsPanel.Children.Add(box);

        if (engine.EnumNamed.Count > 0)
        {
            var chips = new WrapPanel { Margin = new Thickness(0, 8, 0, 0) };
            foreach (var name in engine.EnumNamed)
                chips.Children.Add(new Border
                {
                    Background = new SolidColorBrush(Color.Parse("#2620A060")), CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(11, 7), Margin = new Thickness(0, 0, 8, 8),
                    Child = new TextBlock { Text = name, FontSize = 14, Foreground = Correct },
                });
            OptionsPanel.Children.Add(chips);
        }

        var done = new Button
        {
            Content = "Done", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 11), Margin = new Thickness(0, 10, 0, 0),
        };
        done.Click += (_, _) => engine.FinishEnum();
        OptionsPanel.Children.Add(done);
        box.Focus();
    }

    /// Picture ID — a Commons image (async-decoded via the shared ImageCache,
    /// with a loading + unavailable fallback) above the 4 vetted MCQ options.
    private void BuildPicture(GameEngine engine, Tidbits.Core.Models.Question q, string imageUrl, bool reveal)
    {
        var img = new Image { Stretch = Stretch.Uniform };
        var hint = new TextBlock
        {
            Text = "Loading image…", FontSize = 13, Opacity = 0.6,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        var stack = new Panel();
        stack.Children.Add(hint);
        stack.Children.Add(img);
        var frame = new Border
        {
            Height = 220, HorizontalAlignment = HorizontalAlignment.Stretch,
            Background = new SolidColorBrush(Color.Parse("#14808080")), CornerRadius = new CornerRadius(10),
            ClipToBounds = true, Margin = new Thickness(0, 0, 0, 12), Child = stack,
        };
        OptionsPanel.Children.Add(frame);

        if (Services.ImageCache.Shared.Cached(imageUrl) is { } cached)
        {
            img.Source = cached; hint.IsVisible = false;
        }
        else
        {
            string qid = q.Id;
            Services.ImageCache.Shared.LoadAsync(imageUrl).ContinueWith(t =>
            {
                Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                {
                    if (_vm?.Engine.Current?.Id != qid) return; // the question moved on
                    if (t.Result is { } bmp) { img.Source = bmp; hint.IsVisible = false; }
                    else hint.Text = "Image unavailable";
                });
            });
        }

        BuildMcq(engine, q, reveal);
    }

    /// Closest Call — a slider over [min,max] plus a live value read-out and a
    /// Submit button. On reveal, shows the player's guess (the answer + points
    /// land in the shared "learn the fact" card).
    private void BuildNumeric(GameEngine engine, Tidbits.Core.Models.ClosestSpec spec, bool reveal)
    {
        string Fmt(double v)
        {
            var n = v == Math.Round(v) ? ((long)v).ToString() : v.ToString("0.##");
            return string.IsNullOrEmpty(spec.Unit) ? n : $"{n} {spec.Unit}";
        }

        if (reveal)
        {
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = $"Your guess: {Fmt(engine.CurrentGuess)}",
                FontSize = 15, Opacity = 0.8, Margin = new Thickness(0, 4),
            });
            return;
        }

        var readout = new TextBlock
        {
            Text = Fmt(engine.CurrentGuess), FontSize = 30, FontWeight = FontWeight.Bold,
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8),
        };
        var slider = new Slider
        {
            Minimum = spec.Min, Maximum = spec.Max, Value = engine.CurrentGuess,
            TickFrequency = spec.Step > 0 ? spec.Step : 1, IsSnapToTickEnabled = spec.Step > 0,
            Margin = new Thickness(0, 4),
        };
        slider.PropertyChanged += (_, ev) =>
        {
            if (ev.Property == Slider.ValueProperty)
            {
                engine.SetGuess(slider.Value);
                readout.Text = Fmt(engine.CurrentGuess);
            }
        };
        var ends = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*") };
        var lo = new TextBlock { Text = Fmt(spec.Min), FontSize = 12, Opacity = 0.55 };
        var hi = new TextBlock { Text = Fmt(spec.Max), FontSize = 12, Opacity = 0.55,
            HorizontalAlignment = HorizontalAlignment.Right };
        Grid.SetColumn(hi, 1);
        ends.Children.Add(lo); ends.Children.Add(hi);

        var submit = new Button
        {
            Content = "Submit guess", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 12), FontWeight = FontWeight.Bold, Margin = new Thickness(0, 10, 0, 0),
        };
        submit.Classes.Add("accent");
        submit.Click += (_, _) => engine.SubmitGuess();

        OptionsPanel.Children.Add(readout);
        OptionsPanel.Children.Add(slider);
        OptionsPanel.Children.Add(ends);
        OptionsPanel.Children.Add(submit);
    }

    /// Name It / Type-the-answer — a text field + Submit (also submits on Enter).
    private void BuildText(GameEngine engine, bool reveal)
    {
        if (reveal)
        {
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = string.IsNullOrWhiteSpace(engine.TypedText) ? "You didn't answer" : $"You typed: {engine.TypedText}",
                FontSize = 15, Opacity = 0.8, Margin = new Thickness(0, 4),
            });
            return;
        }

        var box = new TextBox
        {
            Text = engine.TypedText, Watermark = "Type your answer…", FontSize = 16,
            Margin = new Thickness(0, 4),
        };
        var submit = new Button
        {
            Content = "Submit", HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(22, 12), FontWeight = FontWeight.Bold, Margin = new Thickness(0, 10, 0, 0),
        };
        submit.Classes.Add("accent");
        void Go() { engine.TypedText = box.Text ?? ""; engine.SubmitText(); }
        box.TextChanged += (_, _) => engine.TypedText = box.Text ?? "";
        box.KeyDown += (_, ev) => { if (ev.Key == Avalonia.Input.Key.Enter) Go(); };
        submit.Click += (_, _) => Go();

        OptionsPanel.Children.Add(box);
        OptionsPanel.Children.Add(submit);
        box.Focus();
    }

    private void OnStartRound(object? sender, RoutedEventArgs e) => _vm?.StartRound();

    private void OnNext(object? sender, RoutedEventArgs e) => _vm?.Advance();

    private void OnDone(object? sender, RoutedEventArgs e) => _vm?.Quit();

    private void OnPlayAgain(object? sender, RoutedEventArgs e) => _vm?.PlayAgain();

    /// Copy the spoiler-free share text to the clipboard (Windows has no system
    /// share sheet for arbitrary text; clipboard is the native idiom).
    private async void OnShare(object? sender, RoutedEventArgs e)
    {
        if (_vm is null) return;
        var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
        if (clipboard is null) return;
        await clipboard.SetTextAsync(_vm.ShareString);
        if (ShareButton is { } b) b.Content = "Copied ✓";
    }

    /// L5 reflection — copy a conversation-starter about a hard question you nailed.
    private async void OnHowDidYouKnow(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: Tidbits.Core.Models.AnsweredQuestion a } btn) return;
        var clipboard = TopLevel.GetTopLevel(this)?.Clipboard;
        if (clipboard is null) return;
        await clipboard.SetTextAsync(ViewModels.GameViewModel.HowDidYouKnowText(a));
        btn.Content = "Copied — start a conversation ✓";
    }
}
