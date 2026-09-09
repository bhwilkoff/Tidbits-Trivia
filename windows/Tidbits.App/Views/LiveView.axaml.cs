using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

public partial class LiveView : UserControl
{
    public LiveView()
    {
        InitializeComponent();

        // The swatch button opens a real ColorPicker and the hex field mirrors it,
        // so a host can pick a colour OR paste one from a brand guide
        // (ADVERSARIAL-DESIGN-LEDGER W6). `syncing` stops the two inputs from
        // driving each other in a loop.
        var syncing = false;
        void PaintSwatch()
        {
            var hex = (BrandHexBox.Text ?? "").Trim();
            // An EMPTY field is not "no colour" — LiveHostViewModel.BrandBrush falls
            // back to #FF5C35, so that is what the big screen will actually paint.
            // A transparent swatch here read as an empty broken box and misdescribed
            // the event.
            if (!Avalonia.Media.Color.TryParse(hex, out var c))
                c = Avalonia.Media.Color.Parse(LiveHostViewModel.DefaultBrandHex);
            BrandSwatch.Background = new Avalonia.Media.SolidColorBrush(c);
            if (!syncing)
            {
                syncing = true;
                BrandColorPicker.Color = c;
                syncing = false;
            }
        }
        BrandHexBox.TextChanged += (_, _) => PaintSwatch();
        BrandColorPicker.PropertyChanged += (_, e) =>
        {
            if (e.Property != Avalonia.Controls.ColorPicker.ColorProperty || syncing) return;
            var c = BrandColorPicker.Color;
            syncing = true;
            BrandHexBox.Text = $"#{c.R:X2}{c.G:X2}{c.B:X2}";
            syncing = false;
            PaintSwatch();
        };
        PaintSwatch();

        CategoryPicker.ItemsSource = TriviaCategory.All;
        CategoryPicker.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<TriviaCategory>(
            (c, _) => new TextBlock { Text = c?.Name ?? "" });
        CategoryPicker.SelectedIndex = 0; // Mixed Bag

        RoundModeBox.ItemsSource = NightPlan.AllKinds;
        RoundModeBox.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<GameMode>(
            (m, _) => new TextBlock { Text = m.Title() });
        RoundModeBox.SelectedIndex = 0;
        RoundCountBox.ItemsSource = new[] { 3, 4, 5, 6, 8 };
        RoundCountBox.SelectedIndex = 1; // 4
        // Index 0 = one-off; 1..7 = Sunday..Saturday (DayOfWeek 0..6 = index-1).
        WeekdayBox.ItemsSource = new[] { "One-off", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
        WeekdayBox.SelectedIndex = 0;
        BuildSavedEvents();

        // TIDBITS_LIVE_HOST=<preset name> — open a real hosted room straight from launch,
        // the Windows twin of Apple's TIDBITS_NIGHT_HOST and Android's tidbits_night_host.
        // Without it Windows was the one platform that could not be DRIVEN as a host: every
        // route into StartHosting is a Click, so a harness could only get here by blind
        // coordinate tapping. That is why "every platform can host, every platform can join"
        // had never actually been tested in the Windows-hosts direction — not because it
        // failed, but because nothing could ask the question.
        // TIDBITS_LIVE_JOIN=<code> — join a room someone ELSE is hosting. The most
        // consequential of the missing hooks: every other platform could be told to
        // join, so "every platform joins every other platform's game" had been proven
        // in every direction except one — nothing could ask Windows to join at all.
        var joinCode = Services.LaunchHooks.LiveJoin;
        if (joinCode is not null)
        {
            Loaded += (_, _) => JoinAsPlayer(joinCode, Services.LaunchHooks.LiveName);
            return;
        }

        // TIDBITS_LIVE_HOST_FILE: import a night and HOST it from launch — the way
        // the device harness puts a clip-bearing package on the wire.
        Services.LaunchHooks.Diag($"LiveView ctor: hostFile={Services.LaunchHooks.LiveHostFile ?? "(none)"} exists={(Services.LaunchHooks.LiveHostFile is { } hf && System.IO.File.Exists(hf))}");
        if (Services.LaunchHooks.LiveHostFile is { } hostFile && System.IO.File.Exists(hostFile))
        {
            Loaded += (_, _) =>
            {
                try
                {
                    Services.LaunchHooks.Diag("host-file: importing");
                    var bytes = System.IO.File.ReadAllBytes(hostFile);
                    // publiclyVisible: the importer reads GetBuffer(), which a
                    // byte[]-backed stream refuses by default.
                    using var ms = new System.IO.MemoryStream(bytes, 0, bytes.Length, false, true);
                    ImportFromStream(ms);
                    Services.LaunchHooks.Diag($"host-file: imported, rounds={_rounds.Count}, status={StatusText.Text}");
                    Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                    {
                        Services.LaunchHooks.Diag($"host-file: hosting, rounds={_rounds.Count}");
                        OnHostEvent(this, new RoutedEventArgs());
                    }, Avalonia.Threading.DispatcherPriority.Background);
                }
                catch (Exception ex)
                {
                    Services.LaunchHooks.Diag($"host-file: FAILED {ex}");
                    ShowStatus($"Could not host {System.IO.Path.GetFileName(hostFile)}: {ex.Message}");
                }
            };
            return;
        }

        if (Services.LaunchHooks.LiveImportFile is { } importFile && System.IO.File.Exists(importFile))
        {
            Loaded += async (_, _) =>
            {
                try
                {
                    var bytes = System.IO.File.ReadAllBytes(importFile);
                    using var ms = new System.IO.MemoryStream(bytes, 0, bytes.Length, false, true);
                    ImportFromStream(ms);
                    for (int i = 0; i < _rounds.Count; i++) _expandedRounds.Add(i);
                    RebuildBuilderRounds();
                    // The rounds are below the fold of a fresh window; the harness
                    // photographs the desktop, so bring them up and use the display.
                    if (TopLevel.GetTopLevel(this) is Window win) win.WindowState = WindowState.Maximized;
                    await Task.Delay(800);
                    BuilderRounds.BringIntoView();
                    if (Services.LaunchHooks.LiveRefresh)
                    {
                        await Task.Delay(20000);
                        await RefreshRepeats();
                        RebuildBuilderRounds();
                    }
                }
                catch (Exception ex) { ShowStatus($"Could not import {System.IO.Path.GetFileName(importFile)}: {ex.Message}"); }
            };
            return;
        }

        // A double-clicked .tidbits (the MSIX file-type association): import it and
        // select the night, exactly as the Import button would (§8.2).
        if (Program.LaunchPackage is { } pkg)
        {
            Loaded += (_, _) =>
            {
                try
                {
                    var bytes = System.IO.File.ReadAllBytes(pkg);
                    using var ms = new System.IO.MemoryStream(bytes, 0, bytes.Length, false, true);
                    ImportFromStream(ms);
                }
                catch (Exception ex) { ShowStatus($"Could not open {System.IO.Path.GetFileName(pkg)}: {ex.Message}"); }
            };
            return;
        }

        // TIDBITS_NIGHT_HOST=1 — host the default night. Apple and Android both had
        // this; Windows could reach the host seat only through a Click handler.
        var wantHost = Services.LaunchHooks.NightHost
            ? NightPlan.Presets[0].Name
            : Services.LaunchHooks.LiveHost;
        if (!string.IsNullOrWhiteSpace(wantHost))
        {
            var (name, _, plan) = NightPlan.Presets.FirstOrDefault(
                x => string.Equals(x.Item1, wantHost, StringComparison.OrdinalIgnoreCase));
            // Any unrecognised value hosts the first preset rather than silently doing
            // nothing — a harness that asked for a host and got the setup screen would
            // grade the setup screen.
            if (plan is null) (name, _, plan) = NightPlan.Presets[0];
            Loaded += (_, _) => StartHosting(plan, name);
        }
    }

    // The rounds being composed for a custom event (+ an index-aligned host note).
    private readonly System.Collections.Generic.List<NightRound> _rounds = new();
    private readonly System.Collections.Generic.List<string> _notes = new();
    private readonly System.Collections.Generic.List<int> _timers = new();   // per-round countdown, 0 = untimed
    /// G1: which rounds are BUZZ rounds. Index-aligned with _rounds like _notes
    /// and _timers — every add, move and delete below has to keep it that way, or
    /// a host's buzz flag silently lands on a different round.
    private readonly System.Collections.Generic.List<bool> _buzz = new();
    /// G4: the first-letter theme of each round ("" = none). Index-aligned with
    /// _rounds, like _buzz/_notes/_timers.
    private readonly System.Collections.Generic.List<string> _letters = new();
    /// G5: the pick-a-category grid of each round ("" / null = ordinary).
    /// Index-aligned with _rounds, like _letters/_buzz/_notes/_timers.
    private readonly System.Collections.Generic.List<LiveBoard?> _boards = new();
    // The AUTHORED questions of each round, index-aligned with _rounds. Empty means
    // "pull from the corpus at host time", which is what every round did before —
    // and is exactly why a host had nothing to edit (WINDOWS-DESIGN §6.6).
    private readonly System.Collections.Generic.List<System.Collections.Generic.List<Question>> _questions = new();
    private readonly System.Collections.Generic.List<System.Collections.Generic.List<string>> _clips = new();
    private readonly System.Collections.Generic.HashSet<int> _expandedRounds = new();
    private static readonly int[] TimerChoices = { 0, 30, 45, 60, 90, 120 };
    private static int TimerIndex(int seconds) => System.Math.Max(0, System.Array.IndexOf(TimerChoices, seconds));
    private static int TimerSeconds(int index) => index >= 0 && index < TimerChoices.Length ? TimerChoices[index] : 0;

    /// §6.2 — the menu bar's entry point into the builder. Same handlers as the
    /// buttons, so the two can never drift apart.
    public void RunCommand(string id)
    {
        var e = new RoutedEventArgs();
        switch (id)
        {
            case "addRound":       OnAddRound(this, e); break;
            case "saveEvent":      OnSaveEvent(this, e); break;
            case "importEvent":    OnImportEvent(this, e); break;
            case "exportEvent":    OnExportEvent(this, e); break;
            case "exportPackage":  OnExportPackage(this, e); break;
            case "printPack":      OnPrintQuestionPack(this, e); break;
            case "printSheets":    OnPrintAnswerSheet(this, e); break;
        }
    }

    private void OnAddRound(object? sender, RoutedEventArgs e)
    {
        if (RoundModeBox.SelectedItem is not GameMode mode || RoundCountBox.SelectedItem is not int count) return;
        _rounds.Add(new NightRound { Kind = mode, Count = count });
        _notes.Add(RoundNoteBox.Text?.Trim() ?? "");
        _timers.Add(0);
        _buzz.Add(false);
        _letters.Add("");
        _boards.Add(null);
        _questions.Add(new System.Collections.Generic.List<Question>());
        _clips.Add(new System.Collections.Generic.List<string>());
        RoundNoteBox.Text = "";
        RebuildBuilderRounds();
    }

    /// Move a round up (−1) or down (+1) in the running order (note travels with it).
    private void MoveRound(int index, int delta)
    {
        int target = index + delta;
        if (index < 0 || index >= _rounds.Count || target < 0 || target >= _rounds.Count) return;
        (_rounds[index], _rounds[target]) = (_rounds[target], _rounds[index]);
        (_notes[index], _notes[target]) = (_notes[target], _notes[index]);
        (_timers[index], _timers[target]) = (_timers[target], _timers[index]);
        if (index < _buzz.Count && target < _buzz.Count)
            (_buzz[index], _buzz[target]) = (_buzz[target], _buzz[index]);
        if (index < _letters.Count && target < _letters.Count)
            (_letters[index], _letters[target]) = (_letters[target], _letters[index]);
        if (index < _boards.Count && target < _boards.Count)
            (_boards[index], _boards[target]) = (_boards[target], _boards[index]);
        if (index < _questions.Count && target < _questions.Count)
            (_questions[index], _questions[target]) = (_questions[target], _questions[index]);
        if (index < _clips.Count && target < _clips.Count)
            (_clips[index], _clips[target]) = (_clips[target], _clips[index]);
        RebuildBuilderRounds();
    }

    private void RebuildBuilderRounds()
    {
        BuilderRounds.Children.Clear();
        for (int i = 0; i < _rounds.Count; i++)
        {
            int idx = i;
            var r = _rounds[i];
            var note = idx < _notes.Count ? _notes[idx] : "";
            // 0 chevron · 1 label · 2 timer · 3 buzz · 4 letter · 5 up · 6 down · 7 delete.
            // Buzz used to share column 2 with the timer, so Avalonia stacked the two
            // in one cell and the toggle drew ON TOP of the countdown dropdown. Every
            // per-round control gets its own column.
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto,Auto,Auto,Auto,Auto"), Margin = new Avalonia.Thickness(0, 0, 0, 2) };
            bool open = _expandedRounds.Contains(idx);
            var chevron = new Button
            {
                Content = Icon(open ? FluentAvalonia.UI.Controls.FASymbol.ChevronDown : FluentAvalonia.UI.Controls.FASymbol.ChevronRight),
                Padding = new Avalonia.Thickness(6, 2), Margin = new Avalonia.Thickness(0, 0, 6, 0),
            };
            AutomationProperties.SetName(chevron, open ? $"Hide round {idx + 1} questions" : $"Show round {idx + 1} questions");
            chevron.Click += (_, _) =>
            {
                if (!_expandedRounds.Remove(idx)) _expandedRounds.Add(idx);
                RebuildBuilderRounds();
            };
            Grid.SetColumn(chevron, 0);
            row.Children.Add(chevron);
            int authored = idx < _questions.Count ? _questions[idx].Count : 0;
            var countText = authored > 0
                ? (authored == 1 ? "1 question (yours)" : $"{authored} questions (yours)")
                : (r.Count == 1 ? "1 question" : $"{r.Count} questions");
            var titleLine = $"{idx + 1}. {r.Kind.Title()} · {countText}";
            var labelBlock = new StackPanel { Spacing = 1, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center };
            labelBlock.Children.Add(new TextBlock
            {
                Text = titleLine, FontWeight = Avalonia.Media.FontWeight.SemiBold,
                TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis,
            });
            if (note.Length > 0)
            {
                labelBlock.Children.Add(new TextBlock
                {
                    Text = note, FontSize = 12, Opacity = 0.7, TextWrapping = Avalonia.Media.TextWrapping.Wrap,
                });
            }
            Grid.SetColumn(labelBlock, 1);
            row.Children.Add(labelBlock);
            // Wave A per-round countdown (macOS parity). "No timer" is first and the
            // default: a pub quiz that silently starts a clock on every round would change
            // how the room plays without the host asking for it.
            var timer = new ComboBox
            {
                ItemsSource = new[] { "No timer", "30s", "45s", "60s", "90s", "120s" },
                SelectedIndex = TimerIndex(idx < _timers.Count ? _timers[idx] : 0),
                MinWidth = 96, FontSize = 12,
            };
            Avalonia.Automation.AutomationProperties.SetName(timer, $"Countdown for round {idx + 1}");
            timer.SelectionChanged += (_, _) =>
            {
                while (_timers.Count <= idx) _timers.Add(0);
                _timers[idx] = TimerSeconds(timer.SelectedIndex);
            };
            Grid.SetColumn(timer, 2);
            row.Children.Add(timer);

            var up = new Button { Content = Icon(FluentAvalonia.UI.Controls.FASymbol.ChevronUp), Padding = new Avalonia.Thickness(7, 2), IsEnabled = idx > 0 };
            AutomationProperties.SetName(up, $"Move round {idx + 1} up");
            up.Click += (_, _) => MoveRound(idx, -1);
            // G1: mark this round a BUZZ round — the room races to buzz and the first
            // team answers out loud. Per-round, like the Mac builder's Buzz toggle.
            var buzz = new ToggleButton
            {
                Content = "Buzz", FontSize = 11, Padding = new Avalonia.Thickness(8, 2),
                Margin = new Avalonia.Thickness(4, 0, 4, 0),
                IsChecked = idx < _buzz.Count && _buzz[idx],
            };
            AutomationProperties.SetName(buzz, $"Round {idx + 1} is a buzz round");
            buzz.Click += (_, _) =>
            {
                while (_buzz.Count <= idx) _buzz.Add(false);
                _buzz[idx] = buzz.IsChecked == true;
            };
            Grid.SetColumn(buzz, 3);
            row.Children.Add(buzz);
            // G4: the first-letter theme of this round — every answer in it begins
            // with the chosen letter. "—" (no theme) is first and the default.
            var letters = new System.Collections.Generic.List<string> { "\u2014" };
            for (char c = 'A'; c <= 'Z'; c++) letters.Add(c.ToString());
            var cur = idx < _letters.Count ? _letters[idx] : "";
            var letter = new ComboBox
            {
                ItemsSource = letters,
                SelectedIndex = string.IsNullOrEmpty(cur) ? 0 : cur[0] - 'A' + 1,
                MinWidth = 64, FontSize = 12, Margin = new Avalonia.Thickness(0, 0, 4, 0),
            };
            AutomationProperties.SetName(letter, $"First-letter theme for round {idx + 1}");
            letter.SelectionChanged += (_, _) =>
            {
                while (_letters.Count <= idx) _letters.Add("");
                _letters[idx] = letter.SelectedIndex <= 0 ? "" : letters[letter.SelectedIndex];
                RebuildBuilderRounds();
            };
            Grid.SetColumn(letter, 4);
            row.Children.Add(letter);
            Grid.SetColumn(up, 5);
            row.Children.Add(up);
            var down = new Button { Content = Icon(FluentAvalonia.UI.Controls.FASymbol.ChevronDown), Padding = new Avalonia.Thickness(7, 2), IsEnabled = idx < _rounds.Count - 1, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(down, $"Move round {idx + 1} down");
            down.Click += (_, _) => MoveRound(idx, +1);
            Grid.SetColumn(down, 6);
            row.Children.Add(down);
            var del = new Button { Content = Icon(FluentAvalonia.UI.Controls.FASymbol.Delete), Padding = new Avalonia.Thickness(8, 2), Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(del, $"Remove round {idx + 1}");
            del.Click += (_, _) =>
            {
                _rounds.RemoveAt(idx);
                if (idx < _notes.Count) _notes.RemoveAt(idx);
                if (idx < _timers.Count) _timers.RemoveAt(idx);
                if (idx < _buzz.Count) _buzz.RemoveAt(idx);
                if (idx < _letters.Count) _letters.RemoveAt(idx);
                if (idx < _boards.Count) _boards.RemoveAt(idx);
                if (idx < _questions.Count) _questions.RemoveAt(idx);
                if (idx < _clips.Count) _clips.RemoveAt(idx);
                _expandedRounds.Clear();   // the indices below this round all shifted
                RebuildBuilderRounds();
            };
            Grid.SetColumn(del, 7);
            row.Children.Add(del);
            BuilderRounds.Children.Add(row);
            if (open) BuilderRounds.Children.Add(BuildQuestionList(idx));
        }
        RebuildBalance();
    }

    // Test seams. The builder is driven entirely by Click handlers, so a headless
    // test could otherwise only reach the question list by synthesising pointer
    // events at guessed coordinates — which asserts the layout, not the feature
    // (`hooks-are-coverage`). These call the SAME methods the buttons do.
    public void LoadEventForTesting(LiveEvent ev) => LoadEvent(ev);

    /// G1: the buzz flags as the builder currently holds them. Exposed because the
    /// failure that matters is ALIGNMENT — a flag landing on the wrong round after
    /// a move or a delete — and that is invisible from the rendered row.
    public System.Collections.Generic.IReadOnlyList<bool> BuzzFlagsForTesting => _buzz;
    public System.Collections.Generic.IReadOnlyList<string> RoundLettersForTesting => _letters;
    public System.Collections.Generic.IReadOnlyList<LiveBoard?> RoundBoardsForTesting => _boards;
    public void MoveRoundForTesting(int index, int delta) => MoveRound(index, delta);

    public void ExpandRoundForTesting(int roundIndex)
    {
        _expandedRounds.Add(roundIndex);
        RebuildBuilderRounds();
    }

    /// Scroll the setup pane so a snapshot shows the ROUNDS rather than the top of
    /// the page. A PNG that does not contain the thing under test is not evidence.
    public void ScrollToRoundsForTesting()
    {
        Setup.UpdateLayout();
        BuilderRounds.BringIntoView();
    }

    /// A round's questions, each opening the editor — WINDOWS-DESIGN §6.6.
    /// A round with no authored questions says so and offers both ways to fill it,
    /// rather than rendering as a blank strip (`universal-feature-states`).
    private Control BuildQuestionList(int roundIndex)
    {
        while (_questions.Count <= roundIndex) _questions.Add(new System.Collections.Generic.List<Question>());
        var qs = _questions[roundIndex];
        var kind = _rounds[roundIndex].Kind;
        var panel = new StackPanel { Spacing = 4, Margin = new Avalonia.Thickness(26, 2, 0, 10) };

        if (qs.Count == 0)
        {
            panel.Children.Add(new TextBlock
            {
                Text = "No questions written yet — this round draws from the Tidbits question bank when you host. "
                     + "Add or pull one to shape it yourself.",
                FontSize = 12, Opacity = 0.7, TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            });
        }

        for (int i = 0; i < qs.Count; i++)
        {
            int qi = i;
            var q = qs[qi];
            // Seven columns: number, prompt, difficulty, Edit, Save to library, Duplicate, ✕.
            // The Save button was added at column 6 of a SIX-column grid, which Avalonia
            // clamps to the last column — it would have sat on top of the remove button.
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto,Auto,Auto,Auto,Auto") };
            grid.Children.Add(new TextBlock
            {
                Text = $"{qi + 1}.", FontSize = 12, Opacity = 0.6, MinWidth = 22,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            var text = new StackPanel { Spacing = 0, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center };
            text.Children.Add(new TextBlock
            {
                Text = string.IsNullOrWhiteSpace(q.Prompt) ? "Untitled question" : q.Prompt,
                // WRAP, don't trim. `MaxLines = 2` with an ellipsis and no wrapping
                // still laid out on ONE line, so a real prompt read "...minted some of
                // the world's old…" and the host could not check their own question
                // against the room. Same fix the Mac took as ledger M1.
                TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            });
            text.Children.Add(new TextBlock
            {
                Text = AnswerSummary(q, kind), FontSize = 12, Opacity = 0.62,
                TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis,
            });
            if (Played.Entry(q.Id) is { } heard)   // 3.56: the room has heard this one
            {
                var badge = new TextBlock
                {
                    Text = "⟲ " + Tidbits.Core.Store.PlayedLog.AskedLine(heard, DateTimeOffset.Now), FontSize = 12,
                    Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#FF5C35")),
                    TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis,
                };
                AutomationProperties.SetName(badge, $"Asked before: question {qi + 1} of round {roundIndex + 1}");
                text.Children.Add(badge);
            }
            Grid.SetColumn(text, 1);
            grid.Children.Add(text);

            var diff = new TextBlock
            {
                Text = $"D{q.Difficulty}", FontSize = 12, Opacity = 0.6,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                Margin = new Avalonia.Thickness(8, 0),
            };
            Grid.SetColumn(diff, 2);
            grid.Children.Add(diff);

            var edit = new Button { Content = "Edit", Padding = new Avalonia.Thickness(12, 4), FontSize = 12 };
            AutomationProperties.SetName(edit, $"Edit question {qi + 1} of round {roundIndex + 1}");
            edit.Click += async (_, _) =>
            {
                string? newClip = null; bool clipChanged = false;
                var updated = await LiveQuestionEditorDialog.ShowAsync(q, kind, $"Round {roundIndex + 1}, question {qi + 1}",
                    ClipAt(roundIndex, qi), path => { newClip = path; clipChanged = true; });
                if (updated is not null)
                {
                    _questions[roundIndex][qi] = updated;
                    if (clipChanged) SetClip(roundIndex, qi, newClip);
                    SyncRoundCount(roundIndex); RebuildBuilderRounds();
                }
            };
            Grid.SetColumn(edit, 3);
            grid.Children.Add(edit);

            var save = new Button { Content = "Save to library", Padding = new Avalonia.Thickness(10, 4), FontSize = 12, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(save, $"Save question {qi + 1} of round {roundIndex + 1} to library");
            save.Click += (_, _) =>
            {
                var isNew = GameData.Shared.Value.Library.Add(q, EventNameBox.Text ?? "");
                ShowStatus(isNew ? $"Saved to your library ({GameData.Shared.Value.Library.All.Count})." : "Already in your library — updated.");
            };
            Grid.SetColumn(save, 4);
            grid.Children.Add(save);

            var dup = new Button { Content = "Duplicate", Padding = new Avalonia.Thickness(10, 4), FontSize = 12, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(dup, $"Duplicate question {qi + 1} of round {roundIndex + 1}");
            dup.Click += (_, _) =>
            {
                // A fresh id: two rows the UI cannot tell apart is a bug waiting to
                // happen the moment anything keys on the question id.
                _questions[roundIndex].Insert(qi + 1, q with { Id = Guid.NewGuid().ToString("N") });
                SyncRoundCount(roundIndex); RebuildBuilderRounds();
            };
            Grid.SetColumn(dup, 5);
            grid.Children.Add(dup);

            // 3.56: a bank question of the same kind the room has NOT heard, in this seat.
            var fresh = new Button { Content = "Fresh", Padding = new Avalonia.Thickness(10, 4), FontSize = 12, Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            ToolTip.SetTip(fresh, "Swap for a question from the bank that the room has not heard");
            AutomationProperties.SetName(fresh, $"Swap question {qi + 1} of round {roundIndex + 1} for a fresh one");
            fresh.Click += async (_, _) => { await SwapForFresh(roundIndex, qi); RebuildBuilderRounds(); };
            Grid.SetColumn(fresh, 6);
            grid.Children.Add(fresh);

            var remove = new Button { Content = Icon(FluentAvalonia.UI.Controls.FASymbol.Dismiss), Padding = new Avalonia.Thickness(9, 4), Margin = new Avalonia.Thickness(4, 0, 0, 0) };
            AutomationProperties.SetName(remove, $"Remove question {qi + 1} of round {roundIndex + 1}");
            remove.Click += (_, _) => { _questions[roundIndex].RemoveAt(qi); SyncRoundCount(roundIndex); RebuildBuilderRounds(); };
            Grid.SetColumn(remove, 7);
            grid.Children.Add(remove);

            // Drop a picture, an audio file or a video onto the question row (the Mac
            // twin, LIVE-PACKAGE-FORMAT §8.1). The file's KIND decides what it becomes;
            // anything else is refused by name rather than silently ignored.
            var dropRound = roundIndex; var dropIndex = qi;
            DragDrop.SetAllowDrop(grid, true);
            grid.AddHandler(DragDrop.DragOverEvent, (object? _, DragEventArgs de) =>
            {
                de.DragEffects = de.DataTransfer.TryGetFiles() is not null ? DragDropEffects.Copy : DragDropEffects.None;
                de.Handled = true;
            });
            grid.AddHandler(DragDrop.DropEvent, async (object? _, DragEventArgs de) =>
            {
                de.Handled = true;
                var files = de.DataTransfer.TryGetFiles();
                if (files is null) return;
                foreach (var f in files)
                {
                    var path = f.Path?.LocalPath;
                    if (string.IsNullOrEmpty(path) || !System.IO.File.Exists(path)) continue;
                    await AttachDropped(path, dropRound, dropIndex);
                    break;   // one file per question
                }
            });

            panel.Children.Add(grid);
        }

        var actions = new WrapPanel { Orientation = Orientation.Horizontal, Margin = new Avalonia.Thickness(0, 6, 0, 0) };
        var add = new Button { Content = "+ Add question", Padding = new Avalonia.Thickness(12, 5), FontSize = 12, Margin = new Avalonia.Thickness(0, 0, 8, 4) };
        add.Click += async (_, _) =>
        {
            var cat = (CategoryPicker.SelectedItem as TriviaCategory)?.Id ?? "mixed";
            string? newClip = null; bool clipChanged = false;
            var made = await LiveQuestionEditorDialog.ShowAsync(
                LiveQuestionEditorDialog.Blank(kind, cat), kind, $"New question in round {roundIndex + 1}",
                null, path => { newClip = path; clipChanged = true; });
            if (made is not null)
            {
                _questions[roundIndex].Add(made);
                if (clipChanged) SetClip(roundIndex, _questions[roundIndex].Count - 1, newClip);
                SyncRoundCount(roundIndex); RebuildBuilderRounds();
            }
        };
        actions.Children.Add(add);

        // The other four ways into this round were four more text pills of the same
        // weight as "+ Add question", so the row read as five equal doors when only
        // one is the ordinary action — the W11 defect at round scale. They collapse
        // into ONE "Add from…" menu, exactly as the page-level file plumbing did.
        var more = new MenuFlyout();

        var pull = new MenuItem { Header = "The Tidbits question bank" };
        pull.Click += async (_, _) =>
        {
            var cat = CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
            var plan = new NightPlan { Rounds = new[] { new NightRound { Kind = kind, Count = 1 } } };
            var pulled = await GameData.Shared.Value.Provider.NightQuestions(plan, cat);
            if (pulled.Count > 0) { _questions[roundIndex].Add(pulled[0] with { RoundIndex = null }); SyncRoundCount(roundIndex); RebuildBuilderRounds(); }
        };
        more.Items.Add(pull);

        // §6: the host's own bank. Search it and add to THIS round; save the round to it.
        var fromLibrary = new MenuItem { Header = "Your saved library…" };
        AutomationProperties.SetName(fromLibrary, $"Add from library to round {roundIndex + 1}");
        fromLibrary.Click += async (_, _) => await ShowLibraryPicker(roundIndex);
        more.Items.Add(fromLibrary);

        if (qs.Count > 0)
        {
            more.Items.Add(new Separator());
            var saveRound = new MenuItem { Header = "Save this round to your library" };
            saveRound.Click += (_, _) =>
            {
                var n = GameData.Shared.Value.Library.Add(qs, EventNameBox.Text ?? "");
                ShowStatus($"Saved round to your library: {n} new, {qs.Count - n} already there.");
            };
            more.Items.Add(saveRound);

            var heardCount = qs.Count(q => Played.Ids.Contains(q.Id));
            if (heardCount > 0)   // 3.56: the repeats, named, with the one-click fix
            {
                var swapHeard = new MenuItem { Header = heardCount == 1 ? "Swap the 1 question the room has heard" : $"Swap the {heardCount} questions the room has heard" };
                AutomationProperties.SetName(swapHeard, $"Swap heard questions in round {roundIndex + 1}");
                swapHeard.Click += async (_, _) => { await RefreshRepeats(new[] { roundIndex }); RebuildBuilderRounds(); };
                more.Items.Add(swapHeard);
            }
            var clear = new MenuItem { Header = "Discard these and draw from the bank" };
            AutomationProperties.SetName(clear, $"Clear authored questions in round {roundIndex + 1}");
            clear.Click += (_, _) => { _questions[roundIndex].Clear(); RebuildBuilderRounds(); };
            more.Items.Add(clear);
        }

        var moreBtn = new DropDownButton
        {
            Content = "Add from…",
            Flyout = more,
            Padding = new Avalonia.Thickness(12, 5),
            FontSize = 12,
            Margin = new Avalonia.Thickness(0, 0, 8, 4),
        };
        AutomationProperties.SetName(moreBtn, $"Add questions to round {roundIndex + 1} from elsewhere");
        actions.Children.Add(moreBtn);        panel.Children.Add(actions);
        return panel;
    }

    /// The round's LENGTH is its count once it is authored (LIVE-EVENT-FILE §2.5).
    /// Letting the two disagree builds a night that asks for more questions than the
    /// host wrote.
    private void SyncRoundCount(int roundIndex)
    {
        if (roundIndex < 0 || roundIndex >= _rounds.Count) return;
        int authored = roundIndex < _questions.Count ? _questions[roundIndex].Count : 0;
        if (authored > 0) _rounds[roundIndex] = _rounds[roundIndex] with { Count = authored };
    }

    /// One line the host can scan to know whether a question is right, without opening it.
    private static string AnswerSummary(Question q, GameMode kind) => kind switch
    {
        GameMode.ClosestCall => q.Closest is null ? "No numeric answer set" : $"Answer: {q.Closest.FormattedAnswer}",
        GameMode.Ordering => q.Ordering is { Count: > 0 } o ? $"Order: {string.Join(" \u2192 ", o.Take(4))}…" : "No items",
        GameMode.Matching => $"{q.Matching?.Keys.Count ?? 0} pairs",
        GameMode.Enumerate => $"{q.Enumerate?.Groups.Count ?? 0} accepted answers",
        GameMode.TypeAnswer => $"Accepts: {string.Join(", ", (q.Accepted ?? new[] { q.CorrectAnswer }).Take(3))}",
        _ => $"Answer: {q.CorrectAnswer}",
    };

    /// The balance meter — a bar per question type (width ∝ its share) + a variety
    /// verdict, so the host can see the night's mix as they compose it.
    private void RebuildBalance()
    {
        BalancePanel.Children.Clear();
        BalancePanel.IsVisible = _rounds.Count > 0;
        if (_rounds.Count == 0) return;

        var shares = Tidbits.Core.Networking.LiveEventBalance.ByType(_rounds);
        int max = shares.Count > 0 ? System.Math.Max(1, shares.Max(s => s.Questions)) : 1;
        foreach (var s in shares)
        {
            var stack = new Panel { Height = 22, Margin = new Avalonia.Thickness(0, 1) };
            stack.Children.Add(new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#33FF5C35")),
                CornerRadius = new Avalonia.CornerRadius(5), HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Left,
                Width = 120 + 260.0 * s.Questions / max,
            });
            stack.Children.Add(new TextBlock
            {
                Text = $"{s.Kind.Title()} · {s.Questions}", FontSize = 12, Margin = new Avalonia.Thickness(8, 0),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            });
            BalancePanel.Children.Add(stack);
        }
        BalancePanel.Children.Add(new TextBlock
        {
            Text = Tidbits.Core.Networking.LiveEventBalance.Verdict(_rounds),
            FontSize = 12, FontWeight = Avalonia.Media.FontWeight.SemiBold, Foreground = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#FF5C35")),
            Margin = new Avalonia.Thickness(0, 4, 0, 0),
        });
    }

    private static Tidbits.Core.Store.PlayedLog Played => Tidbits.Core.Store.PlayedLog.Shared.Value;

    /// 3.56: swap one authored question for a bank question of the same kind that
    /// neither the room has heard nor the night already holds. The seat stays put.
    /// Returns whether anything changed.
    private async Task<bool> SwapForFresh(int roundIndex, int qi)
    {
        if (roundIndex >= _questions.Count || qi >= _questions[roundIndex].Count || roundIndex >= _rounds.Count) return false;
        var kind = _rounds[roundIndex].Kind;
        var cat = CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
        var taken = new HashSet<string>(Played.Ids);
        foreach (var r in _questions) foreach (var q in r) taken.Add(q.Id);
        var provider = GameData.Shared.Value.Provider;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            var plan = new NightPlan { Rounds = new[] { new NightRound { Kind = kind, Count = 3 } } };
            var pulled = await provider.NightQuestions(plan, cat);
            var pick = pulled.FirstOrDefault(q => !taken.Contains(q.Id));
            if (pick is not null)
            {
                _questions[roundIndex][qi] = pick with { RoundIndex = null };
                return true;
            }
        }
        ShowStatus($"The bank has nothing fresh for this round — every {kind.NightRoundTitle().ToLowerInvariant()} question has been asked.");
        return false;
    }

    /// 3.56: every authored question the room has heard, in the given rounds (all
    /// by default), swapped for a fresh one. Reports what changed.
    private async Task RefreshRepeats(IEnumerable<int>? rounds = null)
    {
        int swapped = 0, stuck = 0;
        foreach (var ri in rounds ?? Enumerable.Range(0, _questions.Count))
        {
            if (ri >= _questions.Count) continue;
            for (int qi = 0; qi < _questions[ri].Count; qi++)
            {
                if (!Played.Ids.Contains(_questions[ri][qi].Id)) continue;
                if (await SwapForFresh(ri, qi)) swapped++; else stuck++;
            }
        }
        if (swapped + stuck == 0) return;
        ShowStatus(swapped == 0
            ? $"No fresh questions for {stuck} repeat{(stuck == 1 ? "" : "s")} — the bank is spent for those rounds."
            : (swapped == 1 ? "1 question swapped for a fresh one" : $"{swapped} questions swapped for fresh ones") + (stuck > 0 ? $" · {stuck} had nothing fresh left" : "") + ".");
    }

    /// 3.57: a copy the host runs as its own night; `fresh` swaps every authored
    /// question the room has heard (a recurring night's regulars are the same
    /// people every week). Sourced rounds are fresh at host time by 3.56.
    private async Task DuplicateEvent(LiveEvent e, bool fresh)
    {
        var copy = e.Duplicated(e.CloneName(DateTime.Now));
        GameData.Shared.Value.LiveEvents.Save(copy);
        LoadEvent(copy);
        if (fresh) await RefreshRepeats();
        GameData.Shared.Value.LiveEvents.Save(CurrentEvent() with { Id = copy.Id });
        RebuildBuilderRounds(); BuildSavedEvents();
        ShowStatus($"Saved “{copy.Name}”.");
    }

    private LiveEvent CurrentEvent() => new()
    {
        Name = string.IsNullOrWhiteSpace(EventNameBox.Text) ? "Custom Night" : EventNameBox.Text!.Trim(),
        Rounds = new System.Collections.Generic.List<NightRound>(_rounds),
        Sponsor = string.IsNullOrWhiteSpace(SponsorBox.Text) ? null : SponsorBox.Text!.Trim(),
        BrandHex = string.IsNullOrWhiteSpace(BrandHexBox.Text) ? null : BrandHexBox.Text!.Trim(),
        LeadCaptureUrl = string.IsNullOrWhiteSpace(LeadUrlBox.Text) ? null : LeadUrlBox.Text!.Trim(),
        Weekday = WeekdayBox.SelectedIndex >= 1 ? WeekdayBox.SelectedIndex - 1 : (int?)null,
        WagerFinalRound = WagerFinalCheck.IsChecked == true,
        RoundNotes = new System.Collections.Generic.List<string>(_notes),
        RoundTimers = new System.Collections.Generic.List<int>(_timers),
        BuzzRounds = new System.Collections.Generic.List<bool>(_buzz),
        RoundLetters = new System.Collections.Generic.List<string>(_letters),
        RoundBoards = new System.Collections.Generic.List<LiveBoard?>(_boards),
        RoundQuestions = _questions
            .Select(q => (System.Collections.Generic.IReadOnlyList<Question>)new System.Collections.Generic.List<Question>(q))
            .ToList(),
        RoundClips = _clips
            .Select(c => (System.Collections.Generic.IReadOnlyList<string>)new System.Collections.Generic.List<string>(c))
            .ToList(),
    };

    /// Load an event into the builder fields (import, or picking a saved event).
    private void LoadEvent(LiveEvent ev)
    {
        EventNameBox.Text = ev.Name;
        SponsorBox.Text = ev.Sponsor ?? "";
        BrandHexBox.Text = ev.BrandHex ?? "";
        LeadUrlBox.Text = ev.LeadCaptureUrl ?? "";
        WeekdayBox.SelectedIndex = ev.Weekday is int w and >= 0 and <= 6 ? w + 1 : 0;
        WagerFinalCheck.IsChecked = ev.WagerFinalRound;
        _rounds.Clear(); _notes.Clear(); _timers.Clear(); _questions.Clear(); _clips.Clear(); _expandedRounds.Clear(); _buzz.Clear(); _letters.Clear(); _boards.Clear();
        for (int i = 0; i < ev.Rounds.Count; i++)
        {
            _rounds.Add(ev.Rounds[i]);
            _notes.Add(i < ev.RoundNotes.Count ? ev.RoundNotes[i] : "");
            _timers.Add(i < ev.RoundTimers.Count ? ev.RoundTimers[i] : 0);
            _buzz.Add(i < ev.BuzzRounds.Count && ev.BuzzRounds[i]);
            _letters.Add(i < ev.RoundLetters.Count ? ev.RoundLetters[i] : "");
            _boards.Add(ev.BoardFor(i));
            _questions.Add(ev.QuestionsFor(i).ToList());
            _clips.Add(Enumerable.Range(0, ev.QuestionsFor(i).Count).Select(q => ev.ClipFor(i, q) ?? "").ToList());
        }
        RebuildBuilderRounds();
    }

    private void OnHostEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        var ev = CurrentEvent();
        StartHosting(ev.ToPlan(), ev.Name, ev);
    }

    /// Play the composed event solo (no records) to vet the questions (3.13).
    private async void OnPreviewEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        var data = GameData.Shared.Value;
        var cat = CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed");
        var ev = CurrentEvent();
        var plan = ev.ToPlan();
        // Preview is a rehearsal of the REAL night, so it plays the host's authored
        // questions — previewing the corpus instead would vet questions the room
        // will never see.
        var questions = await LiveNightHost.PreviewQuestions(plan, ev, data.Provider, cat);
        if (questions.Count == 0) { StatusText.Text = "No questions available for that event."; StatusText.IsVisible = true; return; }
        var engine = data.NewEngine();
        var vm = new GameViewModel(engine, records: null); // preview → no records
        vm.Closed += () => { CockpitHost.Content = null; Setup.IsVisible = true; };
        Setup.IsVisible = false;
        StatusText.IsVisible = false;
        CockpitHost.Content = new GameView { DataContext = vm };
        engine.StartNight(plan, cat, questions);
    }

    /// The teams' blank answer sheet — printable BEFORE the night from the plan alone
    /// (round titles + counts), which is the Wi-Fi-dies contingency hosts actually want.
    private async void OnPrintAnswerSheet(object? sender, RoutedEventArgs e)
    {
        var ev = CurrentEvent();
        if (ev.Rounds.Count == 0) return;
        var html = Tidbits.Core.Networking.LiveExport.AnswerSheetHtml(ev.Name, ev.Rounds);
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "tidbits-answer-sheet.html");
        try
        {
            await System.IO.File.WriteAllTextAsync(path, html);
            var top = TopLevel.GetTopLevel(this);
            if (top?.Launcher is { } launcher) await launcher.LaunchUriAsync(new Uri(new Uri("file://"), path));
        }
        catch { /* best-effort */ }
    }

    private void OnSaveEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { StatusText.Text = "Add at least one round first."; StatusText.IsVisible = true; return; }
        GameData.Shared.Value.LiveEvents.Save(CurrentEvent());
        BuildSavedEvents();
    }

    /// Build an audio or video round from picked clips — the Windows mirror of
    /// macOS §A2.4's AV rounds, which Windows had no equivalent of at all.
    ///
    /// Each clip becomes a "name it" question whose answer defaults to the file
    /// name, and the clip path is stored index-aligned with the question. Unlike
    /// macOS there is no security-scoped bookmark to keep: on Windows the path IS
    /// the reference.
    /// G5: add a pick-a-category board round.
    ///
    /// The pool is queried PER CELL, not per category. Asking for a category pool
    /// and slicing it is how a grid comes back with holes — a thin tier like
    /// business at 500 is ~1.5% of its own category, so a random sample misses it.
    private void OnAddBoardRound(object? sender, RoutedEventArgs e)
    {
        var corpus = GameData.Shared.Value.Sources.Corpus;
        var columns = LiveBoardBuilder
            .FillableCategories(corpus.Questions("mixed", new System.Collections.Generic.HashSet<string>(), 4000))
            .Where(c => c != "mixed").Take(5).ToList();
        if (columns.Count == 0)
            columns = TriviaCategory.All.Where(c => c.Id != "mixed").Take(5).Select(c => c.Id).ToList();

        var pool = new System.Collections.Generic.List<Question>();
        foreach (var c in columns)
            foreach (var t in LiveBoard.DefaultTiers)
                pool.AddRange(corpus.Questions(c, t, new System.Collections.Generic.HashSet<string>(), 1));

        var board = LiveBoardBuilder.Build(pool, columns);
        if (board.Cells.Count == 0) { ShowStatus("The corpus cannot fill a board right now."); return; }

        // The round HOLDS the questions its grid references, in cell order, so the
        // board and the question list can never disagree about what is in it.
        var questions = board.Cells.Select(cell => pool.First(q => q.Id == cell.QuestionId)).ToList();
        _rounds.Add(new NightRound { Kind = GameMode.Classic, Count = questions.Count });
        _notes.Add("Pick a Category");
        _timers.Add(0);
        _buzz.Add(false);
        _letters.Add("");
        _boards.Add(board);
        _questions.Add(questions);
        _clips.Add(new System.Collections.Generic.List<string>());
        _expandedRounds.Clear();
        RebuildBuilderRounds();
        ShowStatus($"Board round added — {board.Cells.Count} cells, {board.PointsRemaining:N0} points.");
    }

    /// The library picker: search box, category filter, one row per hit with Add.
    private async System.Threading.Tasks.Task ShowLibraryPicker(int roundIndex)
    {
        var lib = GameData.Shared.Value.Library;
        var search = new TextBox { Watermark = "Search your library", MinWidth = 320 };
        AutomationProperties.SetName(search, "Search library");
        var cats = new[] { (Id: "", Name: "Any category") }.Concat(TriviaCategory.All.Select(c => (Id: c.Id, Name: c.Name))).ToList();
        var catBox = new ComboBox { MinWidth = 160, ItemsSource = cats.Select(c => c.Name).ToList(), SelectedIndex = 0 };
        var list = new StackPanel { Spacing = 6 };
        var count = new TextBlock { Classes = { "caption" }, Opacity = 0.72 };
        var added = new System.Collections.Generic.HashSet<string>();
        void Refresh()
        {
            list.Children.Clear();
            var cat = catBox.SelectedIndex > 0 ? cats[catBox.SelectedIndex].Id : null;
            var hits = lib.Search(search.Text ?? "", cat);
            count.Text = lib.All.Count == 0
                ? "Your library is empty — save a question from any round, or import a bank package."
                : $"{hits.Count} of {lib.All.Count} saved";
            foreach (var it in hits)
            {
                var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto") };
                var text = new StackPanel();
                text.Children.Add(new TextBlock { Text = it.Question.Prompt, TextWrapping = Avalonia.Media.TextWrapping.Wrap, MaxWidth = 420 });
                text.Children.Add(new TextBlock
                {
                    Text = $"{it.Question.CorrectAnswer} · {TriviaCategory.Named(it.Question.CategoryId).Name} · D{it.Question.Difficulty} · from {it.Source}"
                           + (it.Question.ImageUrl is null ? "" : " · picture"),
                    Classes = { "caption" }, Opacity = 0.72,
                });
                row.Children.Add(text);
                var addBtn = new Button { Content = added.Contains(it.Id) ? "Added" : "Add", IsEnabled = !added.Contains(it.Id), Padding = new Avalonia.Thickness(10, 3), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
                var id = it.Id; var question = it.Question;
                addBtn.Click += (_, _) =>
                {
                    _questions[roundIndex].Add(question with { Id = Guid.NewGuid().ToString("N"), RoundIndex = null });
                    SyncRoundCount(roundIndex);
                    added.Add(id); Refresh();
                };
                Grid.SetColumn(addBtn, 1); row.Children.Add(addBtn);
                var rm = new Button { Content = "\u2715", Padding = new Avalonia.Thickness(8, 3), Margin = new Avalonia.Thickness(4, 0, 0, 0) };
                AutomationProperties.SetName(rm, "Remove from library");
                rm.Click += (_, _) => { lib.Remove(id); Refresh(); };
                Grid.SetColumn(rm, 2); row.Children.Add(rm);
                list.Children.Add(row);
            }
        }
        search.TextChanged += (_, _) => Refresh();
        catBox.SelectionChanged += (_, _) => Refresh();
        Refresh();
        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        top.Children.Add(search); top.Children.Add(catBox);
        var body = new StackPanel { Spacing = 8, MinWidth = 560 };
        body.Children.Add(top); body.Children.Add(count);
        body.Children.Add(new ScrollViewer { Content = list, MaxHeight = 380 });
        var dialog = new FluentAvalonia.UI.Controls.FAContentDialog
        {
            Title = $"Add from your library to round {roundIndex + 1}",
            CloseButtonText = "Done",
            Content = body,
        };
        await dialog.ShowAsync();
        RebuildBuilderRounds();
    }

    /// The whole library as a `bank` package (LIVE-PACKAGE-FORMAT §6).
    private async void OnExportLibrary(object? sender, RoutedEventArgs e)
    {
        var lib = GameData.Shared.Value.Library;
        if (lib.All.Count == 0) { ShowStatus("Your library is empty — save a question from any round first."); return; }
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        try
        {
            var file = await sp.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
            {
                Title = "Export library", SuggestedFileName = "Question library." + LivePackage.FileExtension,
                DefaultExtension = LivePackage.FileExtension,
            });
            if (file is null) return;
            var bank = LiveLibrary.BankEvent(lib.All, "Question library");
            var version = typeof(LiveView).Assembly.GetName().Version?.ToString(3) ?? "";
            await using (var stream = await file.OpenWriteAsync())
                LivePackage.Write(stream, bank, $"Tidbits Trivia (Windows) {version}", "", packageKind: "bank");
            ShowStatus($"Exported your library: {lib.All.Count} questions in {bank.Rounds.Count} categories.");
        }
        catch (Exception ex) { ShowStatus($"Could not export the library: {ex.Message}"); }
    }

    /// A real Fluent icon, not a text glyph (ADVERSARIAL-DESIGN-LEDGER W3). A bare
    /// Unicode shape as Button.Content falls back to whatever the TEXT font carries;
    /// Inter has no ✕ or ▲, so the builder rendered `▯ ▼ ▯` on every round header.
    private static FluentAvalonia.UI.Controls.FASymbolIcon Icon(FluentAvalonia.UI.Controls.FASymbol symbol) =>
        new() { Symbol = symbol, FontSize = 14 };

    /// A dropped file becomes this question's picture or clip, by its KIND — the
    /// media store decides, so an unsupported type is named rather than ignored.
    private async System.Threading.Tasks.Task AttachDropped(string path, int roundIndex, int qi)
    {
        var ext = LiveMediaStore.NormalizedExt(System.IO.Path.GetExtension(path));
        if (!LiveMediaStore.Allowed.TryGetValue(ext, out var kind))
        {
            ShowStatus($"Could not use {System.IO.Path.GetFileName(path)} — drop a picture, an audio file or a video.");
            return;
        }
        try
        {
            var bytes = await System.IO.File.ReadAllBytesAsync(path);
            var id = LiveMediaStore.Store(bytes, ext, System.IO.Path.GetFileName(path));
            if (kind.Kind == "image")
            {
                _questions[roundIndex][qi] = _questions[roundIndex][qi] with { ImageUrl = LiveMediaStore.Reference(id) };
                ShowStatus($"Picture attached to question {qi + 1} of round {roundIndex + 1}.");
            }
            else
            {
                SetClip(roundIndex, qi, LiveMediaStore.FilePath(id));
                ShowStatus($"Clip attached to question {qi + 1} of round {roundIndex + 1}.");
            }
            RebuildBuilderRounds();
        }
        catch (Exception ex) { ShowStatus($"Could not use {System.IO.Path.GetFileName(path)}: {ex.Message}"); }
    }

    /// A round's clips are index-parallel to its questions (LIVE-PACKAGE-FORMAT §3.2);
    /// these keep the list sized so any question can carry one, not only the
    /// questions an audio/video ROUND was built from.
    private string? ClipAt(int roundIndex, int qi)
    {
        if (roundIndex >= _clips.Count) return null;
        var list = _clips[roundIndex];
        return qi < list.Count && !string.IsNullOrEmpty(list[qi]) ? list[qi] : null;
    }

    private void SetClip(int roundIndex, int qi, string? path)
    {
        while (_clips.Count <= roundIndex) _clips.Add(new System.Collections.Generic.List<string>());
        var list = _clips[roundIndex];
        var n = roundIndex < _questions.Count ? _questions[roundIndex].Count : qi + 1;
        while (list.Count < Math.Max(n, qi + 1)) list.Add("");
        list[qi] = path ?? "";
    }

    private async void OnAddAudioRound(object? sender, RoutedEventArgs e) => await AddClipRound(video: false);
    private async void OnAddVideoRound(object? sender, RoutedEventArgs e) => await AddClipRound(video: true);

    private async System.Threading.Tasks.Task AddClipRound(bool video)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        var kind = video ? "video" : "audio";
        var files = await sp.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
        {
            Title = video ? "Choose video clips" : "Choose audio clips",
            AllowMultiple = true,
            FileTypeFilter = new[]
            {
                new Avalonia.Platform.Storage.FilePickerFileType(video ? "Video" : "Audio")
                {
                    Patterns = video
                        ? new[] { "*.mp4", "*.mov", "*.m4v", "*.mkv", "*.avi", "*.webm" }
                        : new[] { "*.mp3", "*.m4a", "*.wav", "*.aac", "*.flac", "*.ogg" },
                },
            },
        });
        if (files.Count == 0) return;

        var questions = new System.Collections.Generic.List<Question>();
        var clips = new System.Collections.Generic.List<string>();
        var skipped = new System.Collections.Generic.List<string>();
        int n = 0;
        foreach (var f in files)
        {
            // A clip Tidbits cannot resolve to a real local path must NOT become a
            // question: that is exactly how the macOS build ended up with rounds
            // that looked complete and played silence.
            var path = f.Path.LocalPath;
            if (string.IsNullOrEmpty(path) || !System.IO.File.Exists(path))
            {
                skipped.Add(f.Name);
                continue;
            }
            n++;
            var answer = System.IO.Path.GetFileNameWithoutExtension(path);
            questions.Add(new Question
            {
                Id = Guid.NewGuid().ToString("N"),
                Prompt = video ? $"Clip {n} — name it" : $"Track {n} — name it",
                Options = [answer],
                CorrectIndex = 0,
                CategoryId = video ? "screen" : "music",
                Difficulty = 3,
                TemplateId = kind,
                Accepted = [answer],
            });
            clips.Add(path);
        }
        if (skipped.Count > 0)
            ShowStatus($"Skipped {skipped.Count} file(s) Tidbits could not read: {string.Join(", ", skipped.Take(3))}");
        if (questions.Count == 0) return;

        _rounds.Add(new NightRound { Kind = GameMode.TypeAnswer, Count = questions.Count });
        _notes.Add(video ? "Play each clip on the projector, then take answers."
                         : "Play each track through the PA, then take answers.");
        _timers.Add(0);
        _buzz.Add(false);
        _letters.Add("");
        _questions.Add(questions);
        _clips.Add(clips);
        _expandedRounds.Add(_rounds.Count - 1);
        RebuildBuilderRounds();
        if (skipped.Count == 0)
            ShowStatus($"Added a {kind} round with {questions.Count} clip(s).");
    }

    /// Write the event's authored questions out as CSV a spreadsheet can edit
    /// (LIVE-EVENT-FILE §6.1) — the door to Excel and back, which the event file
    /// does not provide.
    /// A host's own question file as a new round — CSV (any tool's header, LIVE-EVENT-FILE
    /// §6.1), GIFT or Aiken; the text says which. The Mac's Import questions… twin.
    private async void OnImportQuestions(object? sender, RoutedEventArgs e)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        try
        {
            var files = await sp.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
            {
                Title = "Import questions (CSV, GIFT, Aiken)", AllowMultiple = false,
                FileTypeFilter = new[] { new Avalonia.Platform.Storage.FilePickerFileType("Questions") { Patterns = new[] { "*.csv", "*.txt", "*.gift" } } },
            });
            if (files.Count == 0) return;
            string text;
            await using (var stream = await files[0].OpenReadAsync())
            using (var reader = new System.IO.StreamReader(stream))
                text = await reader.ReadToEndAsync();
            var questions = Tidbits.Core.Data.TextQuestionFormats.Detect(text) switch
            {
                Tidbits.Core.Data.TextQuestionFormats.Kind.Aiken => Tidbits.Core.Data.TextQuestionFormats.ParseAiken(text),
                Tidbits.Core.Data.TextQuestionFormats.Kind.Gift => Tidbits.Core.Data.TextQuestionFormats.ParseGift(text),
                _ => Tidbits.Core.Data.CsvQuestions.Parse(text),
            };
            if (questions.Count == 0) { ShowStatus($"No questions in \u201C{files[0].Name}\u201D (CSV, GIFT or Aiken)."); return; }
            // One format per round: pick the one the questions share, else classic.
            var kind = questions.All(q => q.Accepted is not null) ? GameMode.TypeAnswer
                     : questions.All(q => q.Closest is not null) ? GameMode.ClosestCall
                     : questions.All(q => q.Matching is not null) ? GameMode.Matching
                     : GameMode.Classic;
            // NightRound is the wire type pinned to {kind, count} (LIVE-EVENT-FILE §4.1):
            // its Title is computed from the mode, so an imported round is named by its
            // FORMAT, not the file. The file name rides in the round's host note instead.
            _rounds.Add(new NightRound { Kind = kind, Count = questions.Count });
            _questions.Add(questions.Select(q => q with { RoundIndex = null }).ToList());
            _notes.Add($"Imported from {files[0].Name}"); _timers.Add(0); _clips.Add(new System.Collections.Generic.List<string>());
            _buzz.Add(false); _letters.Add(""); _boards.Add(null);
            RebuildBuilderRounds();
            ShowStatus($"Imported {questions.Count} question(s) as a new round.");
        }
        catch (Exception ex) { ShowStatus($"Could not import that file: {ex.Message}"); }
    }

    /// Kahoot's own import template, so a host can hand a Tidbits night to someone
    /// who runs Kahoot (QUIZ-FORMATS-RESEARCH §4). Their importer takes only xlsx.
    private async void OnExportKahootSheet(object? sender, RoutedEventArgs e)
    {
        var ev = CurrentEvent();
        var questions = Enumerable.Range(0, ev.Rounds.Count).SelectMany(ev.QuestionsFor).ToList();
        // One timer for the whole sheet: Kahoot allows a per-question time, but a
        // Tidbits round has ONE, so the first round's timer is the honest source.
        var (rows, notes) = Tidbits.Core.Data.KahootSheet.Rows(questions, ev.RoundTimers.FirstOrDefault());
        if (rows.Count == 0)
        {
            ShowStatus("Nothing to export for Kahoot — their sheet only carries multiple-choice questions with two to four answers."
                       + (notes.Count == 0 ? "" : $" {string.Join("; ", notes.Take(3))}"));
            return;
        }
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        try
        {
            var file = await sp.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
            {
                Title = "Export for Kahoot", SuggestedFileName = $"{Sanitise(ev.Name)} - for Kahoot.xlsx", DefaultExtension = "xlsx",
            });
            if (file is null) return;
            var bytes = Tidbits.Core.Data.KahootSheet.Xlsx(rows);
            await using (var stream = await file.OpenWriteAsync()) await stream.WriteAsync(bytes);
            ShowStatus($"Exported {rows.Count} of {questions.Count} question(s) for Kahoot."
                       + (notes.Count == 0 ? "" : $" {notes.Count} note(s): {string.Join("; ", notes.Take(3))}"));
        }
        catch (Exception ex) { ShowStatus($"Could not export for Kahoot: {ex.Message}"); }
    }

    /// A SpeedQuizzing quizpack is a FOLDER whose filenames are the questions and
    /// whose files are the media (QUIZ-FORMATS-RESEARCH §1). Each picture, MP3 or
    /// clip lands in the media store, so the round exports as a `.tidbits` package
    /// with the media inside — the whole point of the format.
    private async void OnImportQuickQuestions(object? sender, RoutedEventArgs e)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a folder picker."); return; }
        try
        {
            var folders = await sp.OpenFolderPickerAsync(new Avalonia.Platform.Storage.FolderPickerOpenOptions
            {
                Title = "Import a SpeedQuizzing folder", AllowMultiple = false,
            });
            if (folders.Count == 0) return;
            var dir = folders[0].Path?.LocalPath;
            if (string.IsNullOrEmpty(dir) || !System.IO.Directory.Exists(dir)) { ShowStatus("Could not read that folder."); return; }
            var files = System.IO.Directory.GetFiles(dir);
            string? Store(string path)
            {
                try
                {
                    return LiveMediaStore.Store(System.IO.File.ReadAllBytes(path),
                                                System.IO.Path.GetExtension(path), System.IO.Path.GetFileName(path));
                }
                catch { return null; }
            }
            var (qs, notes) = Tidbits.Core.Data.QuickQuestions.FromFolder(files, Store);
            if (qs.Count == 0)
            {
                ShowStatus($"No Quick Questions in that folder — a Quick Question is a file whose NAME is the "
                         + "question and answer, separated by underscores, e.g. \u201CQQ_Who sang this^^_Dolly Parton.mp3\u201D.");
                return;
            }
            var clips = Tidbits.Core.Data.QuickQuestions.ClipPaths(files, Store);
            _rounds.Add(new NightRound { Kind = GameMode.TypeAnswer, Count = qs.Count });
            _questions.Add(qs);
            _notes.Add($"Imported from {System.IO.Path.GetFileName(dir)}");
            _timers.Add(0);
            _clips.Add(clips.Take(qs.Count).Concat(Enumerable.Repeat("", Math.Max(0, qs.Count - clips.Count))).ToList());
            _buzz.Add(false); _letters.Add(""); _boards.Add(null);
            RebuildBuilderRounds();
            var pictured = qs.Count(q => q.ImageUrl is not null);
            var clipped = clips.Take(qs.Count).Count(c => !string.IsNullOrEmpty(c));
            ShowStatus($"Imported {qs.Count} Quick Questions ({pictured} with pictures, {clipped} with clips)."
                       + (notes.Count == 0 ? "" : $" {notes.Count} note(s): {string.Join("; ", notes.Take(3))}"));
        }
        catch (Exception ex) { ShowStatus($"Could not import that folder: {ex.Message}"); }
    }

    /// GIFT: the human-writable archive form (QUIZ-FORMATS-RESEARCH §4).
    private async void OnExportQuestionsGift(object? sender, RoutedEventArgs e)
    {
        var ev = CurrentEvent();
        var questions = Enumerable.Range(0, ev.Rounds.Count).SelectMany(ev.QuestionsFor).ToList();
        if (questions.Count == 0) { ShowStatus("There are no authored questions to export yet."); return; }
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        try
        {
            var file = await sp.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
            {
                Title = "Export questions as GIFT", SuggestedFileName = $"{Sanitise(ev.Name)} - questions.gift.txt", DefaultExtension = "txt",
            });
            if (file is null) return;
            await using var stream = await file.OpenWriteAsync();
            await using var writer = new System.IO.StreamWriter(stream);
            await writer.WriteAsync(Tidbits.Core.Data.TextQuestionFormats.ExportGift(questions));
            ShowStatus($"Exported {questions.Count} question(s) as GIFT.");
        }
        catch (Exception ex) { ShowStatus($"Could not export the questions: {ex.Message}"); }
    }

    private async void OnExportQuestionsCsv(object? sender, RoutedEventArgs e)
    {
        var ev = CurrentEvent();
        var questions = Enumerable.Range(0, ev.Rounds.Count).SelectMany(ev.QuestionsFor).ToList();
        if (questions.Count == 0)
        {
            ShowStatus("There are no authored questions to export yet. Open a round and add or "
                     + "pull some first — corpus-sourced rounds are drawn when you host.");
            return;
        }
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        try
        {
            var file = await sp.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
            {
                Title = "Export questions as CSV",
                SuggestedFileName = $"{Sanitise(ev.Name)} - questions.csv",
                DefaultExtension = "csv",
            });
            if (file is null) return;
            await using var stream = await file.OpenWriteAsync();
            await using var writer = new System.IO.StreamWriter(stream);
            await writer.WriteAsync(Tidbits.Core.Data.CsvQuestions.Export(questions));
            ShowStatus($"Exported {questions.Count} question(s) as CSV.");
        }
        catch (Exception ex)
        {
            ShowStatus($"Could not export the questions: {ex.Message}");
        }
    }

    /// The host's question pack, printable BEFORE the night — the Wi-Fi-dies
    /// fallback is worth nothing if it can only be produced from a running cockpit.
    ///
    /// Only an event whose rounds carry their own questions can print an honest
    /// pack; a corpus-sourced round draws at host time, so a pack printed now would
    /// list questions the room never sees. That case says so instead of printing a
    /// lie.
    private async void OnPrintQuestionPack(object? sender, RoutedEventArgs e)
    {
        var ev = CurrentEvent();
        if (ev.Rounds.Count == 0) { ShowStatus("Add at least one round first."); return; }

        var unauthored = Enumerable.Range(0, ev.Rounds.Count).Where(i => ev.QuestionsFor(i).Count == 0).ToList();
        if (unauthored.Count == ev.Rounds.Count)
        {
            ShowStatus("This event's rounds are drawn from the corpus when you host, so there is "
                     + "no pack to print yet. Open a round and add or pull questions first, or "
                     + "print the pack from the cockpit once the night is running.");
            return;
        }

        var questions = new System.Collections.Generic.List<Question>();
        for (int i = 0; i < ev.Rounds.Count; i++)
            foreach (var q in ev.QuestionsFor(i))
                questions.Add(q with { RoundIndex = i });

        var html = Tidbits.Core.Networking.LiveExport.QuestionPackHtml(ev.Name, questions);
        var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                                          $"{Sanitise(ev.Name)} - question pack.html");
        try
        {
            await System.IO.File.WriteAllTextAsync(path, html);
            var top = TopLevel.GetTopLevel(this);
            if (top?.Launcher is { } launcher) await launcher.LaunchUriAsync(new Uri(new Uri("file://"), path));
            ShowStatus(unauthored.Count == 0
                ? $"Question pack ready — {questions.Count} questions."
                : $"Question pack ready — {questions.Count} questions. "
                  + $"{unauthored.Count} corpus-sourced round(s) are not in it; they are drawn when you host.");
        }
        catch (Exception ex)
        {
            // A silent catch here is a print button that does nothing.
            ShowStatus($"Could not prepare the question pack: {ex.Message}");
        }
    }

    private static string Sanitise(string name)
    {
        foreach (var ch in System.IO.Path.GetInvalidFileNameChars()) name = name.Replace(ch, '-');
        return string.IsNullOrWhiteSpace(name) ? "Tidbits event" : name;
    }

    /// Export the composed event as the portable document (docs/LIVE-EVENT-FILE.md).
    /// A host's night is their work product: it has to survive a reinstall, move to
    /// their Mac, and be shareable with a co-host.
    private async void OnExportEvent(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { ShowStatus("Add at least one round first."); return; }
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        var ev = CurrentEvent();
        try
        {
            var file = await sp.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
            {
                Title = "Export event",
                SuggestedFileName = LiveEventFile.SuggestedFileName(ev),
                DefaultExtension = "json",
            });
            if (file is null) return;
            await using var stream = await file.OpenWriteAsync();
            await using var writer = new System.IO.StreamWriter(stream);
            await writer.WriteAsync(LiveEventFile.Encode(ev));
            ShowStatus($"Exported \u201C{ev.Name}\u201D \u2014 {ev.TotalQuestions} questions across {ev.Rounds.Count} rounds.");
        }
        catch (Exception ex)
        {
            // A silent catch here is how an export "works" and writes nothing.
            ShowStatus($"Could not export the event: {ex.Message}");
        }
    }

    /// One importer for both shapes. Sniffs the bytes, never the extension: a
    /// package renamed .zip still opens, and a JSON document named .tidbits is
    /// still read as JSON.
    private void ImportFromStream(System.IO.MemoryStream ms)
    {
        LiveEvent ev;
        System.Collections.Generic.IReadOnlyList<string> problems = System.Array.Empty<string>();
        if (ms.Length >= 2 && ms.GetBuffer()[0] == (byte)'P' && ms.GetBuffer()[1] == (byte)'K')
        {
            // A BANK goes into the library, not the list of nights (§6.1).
            var peek = Tidbits.Core.Networking.LivePackage.Read(ms);
            ms.Position = 0;
            if (peek.Manifest.Kind == "bank")
            {
                var (bank, bankProblems) = Tidbits.Core.Networking.LivePackage.ImportIntoStore(ms);
                var all = Enumerable.Range(0, bank.Rounds.Count).SelectMany(i => bank.QuestionsFor(i)).Select(q => q with { RoundIndex = null }).ToList();
                var n = GameData.Shared.Value.Library.Add(all, string.IsNullOrEmpty(bank.Name) ? "bank" : bank.Name);
                ShowStatus($"Imported bank into your library: {n} new, {all.Count - n} already there."
                           + (bankProblems.Count == 0 ? "" : $" {bankProblems.Count} problem(s)."));
                return;
            }
            (ev, problems) = Tidbits.Core.Networking.LivePackage.ImportIntoStore(ms);
        }
        else
        {
            using var reader = new System.IO.StreamReader(ms);
            ev = LiveEventFile.Decode(reader.ReadToEnd());
        }
        LoadEvent(ev);
        GameData.Shared.Value.LiveEvents.Save(ev);
        BuildSavedEvents();
        ShowStatus(problems.Count == 0
            ? $"Imported \u201C{ev.Name}\u201D \u2014 {ev.TotalQuestions} questions across {ev.Rounds.Count} rounds."
            : $"Imported \u201C{ev.Name}\u201D with {problems.Count} problem(s): {string.Join("; ", problems.Take(3))}");
    }

    /// Write the night as ONE file with its media inside (docs/LIVE-PACKAGE-FORMAT.md,
    /// Decision 059). The JSON export above is kept for hosts who want text.
    private async void OnExportPackage(object? sender, RoutedEventArgs e)
    {
        if (_rounds.Count == 0) { ShowStatus("Add at least one round first."); return; }
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        var ev = CurrentEvent();
        try
        {
            var file = await sp.SaveFilePickerAsync(new Avalonia.Platform.Storage.FilePickerSaveOptions
            {
                Title = "Export package",
                SuggestedFileName = Tidbits.Core.Networking.LivePackage.SuggestedFileName(ev),
                DefaultExtension = Tidbits.Core.Networking.LivePackage.FileExtension,
            });
            if (file is null) return;
            var version = typeof(LiveView).Assembly.GetName().Version?.ToString(3) ?? "";
            System.Collections.Generic.IReadOnlyList<string> dropped;
            await using (var stream = await file.OpenWriteAsync())
            {
                dropped = Tidbits.Core.Networking.LivePackage.Write(stream, ev, $"Tidbits Trivia (Windows) {version}");
            }
            ShowStatus(dropped.Count == 0
                ? $"Exported package \u201C{ev.Name}\u201D \u2014 {ev.TotalQuestions} questions, media inside."
                : $"Exported package without {dropped.Count} clip(s) that could not be read: {string.Join(", ", dropped.Take(3))}");
        }
        catch (Exception ex)
        {
            ShowStatus($"Could not export the package: {ex.Message}");
        }
    }

    /// Import an event back — a `.tidbits` package (media and all) or the bare JSON
    /// document — from this machine, a co-host, or the Mac app.
    private async void OnImportEvent(object? sender, RoutedEventArgs e)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is not { } sp) { ShowStatus("This window cannot open a file picker."); return; }
        try
        {
            var files = await sp.OpenFilePickerAsync(new Avalonia.Platform.Storage.FilePickerOpenOptions
            {
                Title = "Import event or package", AllowMultiple = false,
                FileTypeFilter = new[]
                {
                    new Avalonia.Platform.Storage.FilePickerFileType("Tidbits event or package") { Patterns = new[] { "*.tidbits", "*.json" } },
                },
            });
            if (files.Count == 0) return;
            await using var stream = await files[0].OpenReadAsync();
            using var ms = new System.IO.MemoryStream();
            await stream.CopyToAsync(ms);
            ms.Position = 0;
            ImportFromStream(ms);
        }
        catch (LiveEventFile.FileFormatException ex)
        {
            ShowStatus(ex.Message);
        }
        catch (Tidbits.Core.Networking.LivePackage.PackageException ex)
        {
            ShowStatus(ex.Message);
        }
        catch (Exception ex)
        {
            ShowStatus($"Could not import that file: {ex.Message}");
        }
    }

    private void ShowStatus(string text)
    {
        StatusText.Text = text;
        StatusText.IsVisible = true;
    }

    private void BuildSavedEvents()
    {
        SavedEvents.Children.Clear();
        var events = GameData.Shared.Value.LiveEvents.All;
        SavedEventsHeader.IsVisible = events.Count > 0;
        foreach (var ev in events)
        {
            var e = ev;
            var row = new Border
            {
                Background = new Avalonia.Media.SolidColorBrush(Avalonia.Media.Color.Parse("#0F808080")),
                CornerRadius = new Avalonia.CornerRadius(10), Padding = new Avalonia.Thickness(14, 10),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto,Auto,Auto") };
            grid.Children.Add(new StackPanel
            {
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center, Spacing = 1,
                Children =
                {
                    new TextBlock { Text = e.Name, FontWeight = Avalonia.Media.FontWeight.SemiBold },
                    new TextBlock
                    {
                        Text = e.IsRecurring ? $"{e.ScheduleLine(DateTime.Now)} · {e.Summary}" : e.Summary,
                        FontSize = 12, Opacity = 0.65,
                    },
                },
            });
            var host = new Button { Content = "Host", Padding = new Avalonia.Thickness(14, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0) };
            host.Classes.Add("accent");
            host.Click += (_, _) => StartHosting(e.ToPlan(), e.Name, e);
            Grid.SetColumn(host, 1);
            grid.Children.Add(host);
            // 3.57: the night as a template — next week's copy, fresh where the room has heard it.
            var clone = new Button
            {
                Content = e.IsRecurring ? $"Clone for next {(DayOfWeek)e.Weekday!.Value}" : "Duplicate",
                Padding = new Avalonia.Thickness(10, 7), Margin = new Avalonia.Thickness(8, 0, 0, 0),
            };
            ToolTip.SetTip(clone, e.IsRecurring
                ? "A copy for next week — every question the room has heard is swapped for a fresh one"
                : "A copy you can run as its own night");
            AutomationProperties.SetName(clone, $"Duplicate saved event {e.Name}");
            clone.Click += async (_, _) => await DuplicateEvent(e, fresh: e.IsRecurring);
            Grid.SetColumn(clone, 2);
            grid.Children.Add(clone);
            var del = new Button
            {
                // A Unicode ✕ as Content falls back to the TEXT font, and Inter has no
                // glyph for it — it drew ▯. Same fix as the round header (W3/W21).
                Content = new FluentAvalonia.UI.Controls.FASymbolIcon
                    { Symbol = FluentAvalonia.UI.Controls.FASymbol.Dismiss, FontSize = 14 },
                Padding = new Avalonia.Thickness(10, 7),
                Margin = new Avalonia.Thickness(8, 0, 0, 0),
            };
            AutomationProperties.SetName(del, $"Delete saved event {e.Name}");
            del.Click += (_, _) => { GameData.Shared.Value.LiveEvents.Remove(e.Id); BuildSavedEvents(); };
            Grid.SetColumn(del, 3);
            grid.Children.Add(del);
            row.Child = grid;
            SavedEvents.Children.Add(row);
        }
    }

    private async void StartHosting(NightPlan plan, string title, LiveEvent? branding = null)
    {
        var data = GameData.Shared.Value;
        var host = NightHostFactory.Create(
            plan,
            CategoryPicker.SelectedItem as TriviaCategory ?? TriviaCategory.Named("mixed"),
            data.Provider,
            title,
            SpeedBonusCheck.IsChecked == true,
            HostPlaysCheck.IsChecked == true,
            HostNameBox.Text,
            branding);
        var vm = new LiveHostViewModel(host);
        Setup.IsVisible = false;
        CockpitHost.Content = new LiveCockpitView { DataContext = vm };
        StatusText.IsVisible = false;
        try
        {
            await vm.StartHosting();
            if (!host.IsOpen)
            {
                // Couldn't open a room — return to setup with the reason.
                CockpitHost.Content = null;
                Setup.IsVisible = true;
                StatusText.Text = host.ErrorText ?? "Couldn't start hosting.";
                StatusText.IsVisible = true;
            }
        }
        catch (Exception ex)
        {
            CockpitHost.Content = null;
            Setup.IsVisible = true;
            StatusText.Text = $"Couldn't start hosting: {ex.Message}";
            StatusText.IsVisible = true;
        }
    }

    private void OnJoinGame(object? sender, RoutedEventArgs e) => JoinAsPlayer(null, null);

    /// Open the player-join surface, optionally pre-filled and auto-submitted.
    ///
    /// `code == null` is the ordinary button path: show the form and let the player
    /// type. With a code, the harness path fills both fields and joins — the same
    /// code path a person drives, not a parallel one, so what it proves is what a
    /// person would get.
    private void JoinAsPlayer(string? code, string? name)
    {
        Setup.IsVisible = false;
        var view = new JoinPlayerView { DataContext = new LivePlayerViewModel() };
        CockpitHost.Content = view;
        if (code is not null) view.AutoJoin(code, name);
    }

    /// Called by the cockpit's Close to return to setup.
    public void BackToSetup()
    {
        CockpitHost.Content = null;
        Setup.IsVisible = true;
    }
}
