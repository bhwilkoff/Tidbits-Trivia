using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Input.Platform;   // SetTextAsync is an extension method on IClipboard
using Tidbits.App.ViewModels;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

public partial class JoinPlayerView : UserControl
{
    private static readonly IBrush Correct = new SolidColorBrush(Color.Parse("#1E9E6A"));
    private static readonly IBrush Wrong = new SolidColorBrush(Color.Parse("#D64545"));
    private static readonly IBrush Picked = new SolidColorBrush(Color.Parse("#FF5C35"));

    private LivePlayerViewModel? _vm;
    private readonly Avalonia.Threading.DispatcherTimer _tick;
    private Window? _window;

    public JoinPlayerView()
    {
        InitializeComponent();
        _tick = new Avalonia.Threading.DispatcherTimer(
            TimeSpan.FromSeconds(1), Avalonia.Threading.DispatcherPriority.Normal, (_, _) => RefreshCountdown());
        _tick.Start();
        AttachedToVisualTree += (_, _) =>
        {
            // Wave C cheat signal (3.27): if the player switches away from the app
            // while a question is live and unanswered, flag their next answer.
            _window = TopLevel.GetTopLevel(this) as Window;
            if (_window is not null) _window.Deactivated += OnWindowDeactivated;
        };
        DetachedFromVisualTree += (_, _) =>
        {
            _tick.Stop();
            if (_window is not null) _window.Deactivated -= OnWindowDeactivated;
        };
    }

    private void OnWindowDeactivated(object? sender, EventArgs e)
    {
        if (_vm is { } vm && vm.ShowQuestion && !vm.Client.HasAnswered)
            vm.Client.Blurred = true;
    }

    /// Tick the host's countdown down locally (coral, turns urgent ≤5s).
    private void RefreshCountdown()
    {
        var s = _vm?.SecondsRemaining;
        CountdownText.Text = s is { } n and > 0 ? $"{n}s" : "";
        CountdownText.Foreground = s is { } m && m <= 5 ? Wrong : Picked;
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (_vm is not null) _vm.Client.Changed -= OnClientChanged;
        _vm = DataContext as LivePlayerViewModel;
        if (_vm is not null) { _vm.Client.Changed += OnClientChanged; ArmAnswerHook(); }
        RebuildOptions();
        RebuildCoplayers();
    }

    private void OnClientChanged() => Avalonia.Threading.Dispatcher.UIThread.Post(() => { RebuildOptions(); RebuildCoplayers(); RebuildRecap(); RefreshClip(); RefreshPicture(); });

    // ---- Decision 060 (pictures) ----------------------------------------------
    private string _pictureKey = "";
    private async void RefreshPicture()
    {
        var vm = _vm; var key = vm?.PictureKey ?? "";
        if (key == _pictureKey) return;
        _pictureKey = key;
        PictureImage.Source = null;
        if (vm is null || !vm.HasPicture) return;
        if (vm.PictureFallback is { } fb)
        {
            var bmp = await Services.ImageCache.Shared.LoadAsync(fb);
            if (_pictureKey == key && bmp is not null) PictureImage.Source = bmp;
        }
        if (vm.Picture is { } pic)
        {
            try
            {
                var path = await LiveMediaCache.Shared.LocalPath(pic, vm.Client.Code);
                if (_pictureKey != key) return;
                using var fs = System.IO.File.OpenRead(path);
                PictureImage.Source = new Avalonia.Media.Imaging.Bitmap(fs);
            }
            catch { /* the fallback stays */ }
        }
    }

    // ---- Decision 060: the host's clip on a Windows joiner ---------------------
    private string _clipKey = "";
    private string? _clipPath;
    private bool _clipLoading;
    private Services.VideoFrameSink? _clipSink;

    /// A new question (or a new clip) resets the offer; the host's cue readies the
    /// file so the click is instant. Nothing plays until the player clicks.
    private void RefreshClip()
    {
        var vm = _vm;
        var key = vm?.MediaKey ?? "";
        if (key != _clipKey)
        {
            _clipKey = key; _clipPath = null; _clipLoading = false;
            ClipStatus.IsVisible = false; ClipVideoFrame.IsVisible = false;
            Services.GameData.Shared.Value.Av.StopClip();
            if (key.Length > 0 && Services.LaunchHooks.LiveTapClip)
            {
                var k = key;
                Avalonia.Threading.DispatcherTimer.RunOnce(() => { if (_clipKey == k) OnPlayClip(this, new RoutedEventArgs()); }, TimeSpan.FromSeconds(2));
            }
        }
        if (vm?.Media is { StartedAt: not null } && _clipPath is null && !_clipLoading) _ = LoadClip(vm.Media, thenPlay: false);
    }

    private async void OnPlayClip(object? sender, RoutedEventArgs e)
    {
        if (_vm?.Media is not { } media) return;
        await LoadClip(media, thenPlay: true);
    }

    private async Task LoadClip(LiveRoom.Media media, bool thenPlay)
    {
        var key = _clipKey;
        if (_clipPath is null)
        {
            if (_clipLoading) return;
            _clipLoading = true;
            ClipStatus.Text = "Loading the clip"; ClipStatus.IsVisible = true;
            try { _clipPath = await LiveMediaCache.Shared.LocalPath(media, _vm!.Client.Code); }
            catch (Exception ex)
            {
                ClipStatus.Text = $"Clip unavailable — the room hears it from the host. ({ex.Message})";
                _clipLoading = false; return;
            }
            _clipLoading = false;
            if (_clipKey != key) return;
            ClipStatus.Text = "Ready — click to play";
        }
        if (!thenPlay) return;
        var av = Services.GameData.Shared.Value.Av;
        if (!av.Available) { ClipStatus.Text = "This build has no media player (LibVLC missing)"; return; }
        if (media.Kind == "video") AttachClipVideo(av);
        av.PlayClip(_clipPath!);
        ClipStatus.Text = "Playing";
    }

    /// Route a video clip's picture into this card, the way the projector does.
    private void AttachClipVideo(Services.AvPlayer av)
    {
        if (_clipSink is null)
        {
            _clipSink = new Services.VideoFrameSink();
            _clipSink.FrameArrived += () => Avalonia.Threading.Dispatcher.UIThread.Post(() => ClipVideoFrame.IsVisible = true);
            ClipVideo.Sink = _clipSink;
            DetachedFromVisualTree += (_, _) =>
            {
                av.SetVideoSink(null); ClipVideo.Sink = null; _clipSink?.Dispose(); _clipSink = null;
            };
        }
        av.SetVideoSink(_clipSink);
    }

    /// The wrap's learning payoff: tough ones nailed (with a copyable "How did you
    /// know that?"), and what to remember with the answer, story and source.
    private void RebuildRecap()
    {
        RecapPanel.Children.Clear();
        if (_vm is not { } vm || !vm.IsEnded) return;
        var tough = vm.RecapTough; var remember = vm.RecapToRemember;
        if (tough.Count == 0 && remember.Count == 0) return;
        Border Card(Tidbits.Core.Networking.LiveRecapEntry e, bool nailed)
        {
            var body = new StackPanel { Spacing = 3 };
            body.Children.Add(new TextBlock { Text = e.Prompt, FontWeight = FontWeight.Bold, TextWrapping = TextWrapping.Wrap });
            body.Children.Add(new TextBlock { Text = (nailed ? "You got it: " : "Answer: ") + (e.Answer ?? ""), Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
            if (nailed)
            {
                var share = new Button { Content = "How did you know that? · Copy", Padding = new Thickness(0), Background = null, BorderThickness = new Thickness(0), Foreground = new SolidColorBrush(Color.Parse("#0047FF")), FontWeight = FontWeight.Bold };
                share.Click += async (_, _) =>
                {
                    var clip = TopLevel.GetTopLevel(this)?.Clipboard;
                    if (clip is not null) { await clip.SetTextAsync(Tidbits.Core.Networking.LiveRecapBook.HowDidYouKnowText(e)); share.Content = "Copied — paste it to a friend"; }
                };
                body.Children.Add(share);
            }
            else
            {
                if (!string.IsNullOrWhiteSpace(e.Story)) body.Children.Add(new TextBlock { Text = e.Story, Opacity = 0.85, TextWrapping = TextWrapping.Wrap });
                if (!string.IsNullOrWhiteSpace(e.SourceTitle))
                {
                    if (e.SourceUrl is { } url)
                        body.Children.Add(new HyperlinkButton { Content = "Learn more on Wikipedia · " + e.SourceTitle, NavigateUri = new System.Uri(url), Padding = new Thickness(0), FontWeight = FontWeight.Bold });
                    else
                        body.Children.Add(new TextBlock { Text = "From Wikipedia · " + e.SourceTitle, Opacity = 0.7, FontWeight = FontWeight.Bold });
                }
            }
            return new Border { Child = body, Padding = new Thickness(12, 10), CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Color.Parse("#0F808080")) };
        }
        if (tough.Count > 0)
        {
            RecapPanel.Children.Add(new TextBlock { Text = "Tough ones you nailed", FontWeight = FontWeight.Bold, FontSize = 16, Margin = new Thickness(0, 6, 0, 0) });
            foreach (var e in tough) RecapPanel.Children.Add(Card(e, true));
        }
        if (remember.Count > 0)
        {
            RecapPanel.Children.Add(new TextBlock { Text = "Tidbits to remember", FontWeight = FontWeight.Bold, FontSize = 16, Margin = new Thickness(0, 6, 0, 0) });
            foreach (var e in remember) RecapPanel.Children.Add(Card(e, false));
        }
    }

    /// At the wrap, list the people you played with, each with an Add / Added button.
    private void RebuildCoplayers()
    {
        CoplayersPanel.Children.Clear();
        if (_vm is not { } vm || !vm.HasCoplayers) return;
        foreach (var co in vm.Coplayers)
        {
            var friend = co;
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
            row.Children.Add(new TextBlock { Text = friend.Name, VerticalAlignment = VerticalAlignment.Center });
            bool added = vm.IsFriend(friend.Uid);
            var btn = new Button
            {
                Content = added ? "Added ✓" : "Add", IsEnabled = !added,
                Padding = new Thickness(14, 6), FontSize = 13,
            };
            btn.Click += (_, _) => { vm.AddFriend(friend); btn.Content = "Added ✓"; btn.IsEnabled = false; };
            Grid.SetColumn(btn, 1);
            row.Children.Add(btn);
            CoplayersPanel.Children.Add(row);
        }
    }

    private async void OnJoin(object? sender, RoutedEventArgs e)
    {
        if (_vm is null) return;
        await _vm.Join(CodeBox.Text ?? "", TeamBox.Text ?? "");
        if (Services.LaunchHooks.LiveJoker is int jr && _vm.Client.Joined) await _vm.Client.PlayJoker(jr);   // A2.14 harness
    }

    /// G7: look the room up as soon as the code is complete, so the tables are on
    /// screen BEFORE the player commits to a name.
    private async void OnCodeChanged(object? sender, Avalonia.Controls.TextChangedEventArgs e)
    {
        if (_vm is null) return;
        await _vm.LoadRoomTeams((CodeBox.Text ?? "").Trim());
    }

    /// Tapping a table fills the LEADER's spelling — that is what keeps it one row
    /// rather than two near-identical ones.
    private void OnPickTeam(object? sender, RoutedEventArgs e)
    {
        if ((sender as Control)?.DataContext is RosterTeam t) TeamBox.Text = t.Name;
    }

    /// Fill the form and submit it, for TIDBITS_LIVE_JOIN.
    ///
    /// Deliberately drives the SAME fields and the same OnJoin the button does, rather
    /// than calling the view model directly: a hook that takes a shortcut past the form
    /// proves the network works and says nothing about whether a person could have got
    /// there. A blank name is not silently allowed either — the form rejects it, so the
    /// hook supplies "Windows" the way tvOS supplies "Apple TV".
    public void AutoJoin(string code, string? name)
    {
        CodeBox.Text = code.Trim().ToUpperInvariant();
        TeamBox.Text = string.IsNullOrWhiteSpace(name) ? "Windows" : name.Trim();
        // After the visual tree settles, or the click lands on a control that has not
        // finished attaching and the join quietly never fires.
        Avalonia.Threading.Dispatcher.UIThread.Post(
            () => OnJoin(this, new RoutedEventArgs()),
            Avalonia.Threading.DispatcherPriority.Background);
    }

    /// Options: clickable MCQ buttons while answering; on reveal, colored (correct green /
    /// your-wrong-pick red / others dim). After answering, your pick shows in the brand color.
    // 3.75: the answer UI is rebuilt only when what it depends on changes — the client
    // fires Changed on every stream event (a team joining, a score echo), and a TextBox
    // rebuilt mid-word loses the player's typing.
    private string _answerKey = "";
    private string _qid = "";
    private string _typed = "";
    private double? _number;
    private System.Collections.Generic.List<int> _order = new();
    private System.Collections.Generic.List<int> _pairs = new();
    private readonly System.Collections.Generic.List<string> _named = new();

    /// A2.14: the joker — a ComboBox of the rounds still ahead (FluentAvalonia first);
    /// once the pick's round has begun, a quiet line. Nothing when there is nothing to play.
    private void BuildJoker(LivePlayerClient c, LiveRoom.Pub p)
    {
        var rounds = (p.JokerRounds ?? Array.Empty<LiveRoom.JokerRound>()).ToList();
        var cur = c.JokerRound;
        if (cur is int played && !rounds.Any(r => r.Index == played))
        {
            OptionsPanel.Children.Add(new TextBlock
            {
                Text = $"Your joker: played on Round {played + 1} \u2014 every point there counts double.",
                Opacity = 0.7, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8),
            });
            return;
        }
        if (rounds.Count == 0) return;
        var box = new StackPanel { Spacing = 4, Margin = new Thickness(0, 0, 0, 10) };
        box.Children.Add(new TextBlock { Text = cur is int r0 ? $"YOUR JOKER \u00b7 ROUND {r0 + 1}" : "YOUR JOKER", FontWeight = FontWeight.Black, FontSize = 11, Foreground = Avalonia.Media.Brush.Parse("#FF5C35") });
        var pick = new ComboBox
        {
            ItemsSource = new[] { "Pick a round to double\u2026" }.Concat(rounds.Select(r => r.Title)).ToList(),
            SelectedIndex = cur is int r1 ? rounds.FindIndex(r => r.Index == r1) + 1 : 0,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        pick.SelectionChanged += async (_, _) =>
        {
            var i = pick.SelectedIndex - 1;
            if (i >= 0 && i < rounds.Count && rounds[i].Index != c.JokerRound) await c.PlayJoker(rounds[i].Index);
        };
        box.Children.Add(pick);
        box.Children.Add(new TextBlock { Text = "Every point your table scores in that round counts double. Pick before it starts.", FontSize = 12, Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
        OptionsPanel.Children.Add(box);
    }

    private void RebuildOptions()
    {
        var c = _vm?.Client;
        if (c?.Pub is not { } p) { OptionsPanel.Children.Clear(); _answerKey = ""; return; }
        bool question = p.Phase == LiveRoom.Phase.Question;
        bool reveal = p.Phase == LiveRoom.Phase.Reveal;
        bool answered = c.HasAnswered;
        if (p.Qid != _qid) { _qid = p.Qid; _typed = ""; _number = null; _order = new(); _pairs = new(); _named.Clear(); }
        var key = $"{p.Qid}|{p.Phase}|{answered}|{p.Locked == true}|{p.Wager == true}|{c.Score}|{p.JokerRounds?.Count ?? 0}|{c.JokerRound}";
        if (key == _answerKey) return;
        _answerKey = key;
        OptionsPanel.Children.Clear();
        BuildJoker(c, p);   // A2.14: above every answer shape
        if (p.Options is not { } opts)
        {
            // Every other format: typed, closest-number, ordering, matching, name-as-many.
            // Until 2026-09-10 the Windows joiner drew nothing here — a Name-It question
            // showed a prompt and no way to answer it.
            bool locked = !question || answered || p.Locked == true;
            if (p.Buzz == true || p.Board is not null) return;
            if (p.Numeric is { } n) BuildNumeric(n, locked);
            else if (p.OrderItems is { Count: > 0 } items) BuildOrdering(items, locked);
            else if (p.MatchKeys is { Count: > 0 } keys && p.MatchValues is { } values) BuildMatching(keys, values, locked);
            else if (p.EnumTarget is { } target) BuildEnumerate(target, locked);
            else if (question || reveal) BuildText(locked);
            return;
        }

        // Final wager round: a stake stepper (0…your score) above the options.
        if (question && !answered && _vm is { IsWager: true } vm)
        {
            int max = System.Math.Max(0, vm.MaxWager);
            var label = new TextBlock { Text = $"Wager: {vm.Wager} of {max}", FontWeight = FontWeight.Bold, Margin = new Thickness(0, 0, 0, 4) };
            var stake = new Slider { Minimum = 0, Maximum = max, Value = vm.Wager, IsSnapToTickEnabled = true, TickFrequency = 1 };
            stake.PropertyChanged += (_, ev) =>
            {
                if (ev.Property == Slider.ValueProperty) { vm.Wager = (int)stake.Value; label.Text = $"Wager: {vm.Wager} of {max}"; }
            };
            OptionsPanel.Children.Add(label);
            OptionsPanel.Children.Add(stake);
        }

        for (int i = 0; i < opts.Count; i++)
        {
            int idx = i;
            var btn = new Button
            {
                Content = opts[i],
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(16, 14),
                FontSize = 16,
                Margin = new Thickness(0, 4),
            };

            if (question && !answered)
            {
                btn.Click += (_, _) => _ = _vm!.SubmitChoice(idx);
            }
            else
            {
                btn.IsHitTestVisible = false;
                bool poll = c.Pub.Poll == true;   // A2.10: no right or wrong on a poll
                if (reveal && !poll && i == c.Pub.AnswerIndex) { btn.Background = Correct; btn.Foreground = Brushes.White; }
                else if (i == c.Chosen) { btn.Background = reveal && !poll ? Wrong : Picked; btn.Foreground = Brushes.White; }
                else btn.Opacity = 0.45;
            }
            OptionsPanel.Children.Add(btn);
        }
    }

    // MARK: - 3.75 non-choice answer formats (macOS `LiveTextAnswer` … `LiveEnumerateAnswer` parity)

    private Button SubmitButton(string text, System.Action onClick)
    {
        var b = new Button { Content = text, Classes = { "accent" }, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center, Padding = new Thickness(16, 12), FontSize = 16, Margin = new Thickness(0, 8, 0, 0) };
        Avalonia.Automation.AutomationProperties.SetName(b, text);
        b.Click += (_, _) => onClick();
        return b;
    }

    private void BuildText(bool locked)
    {
        var box = new TextBox { Text = _typed, Watermark = "Type your answer", FontSize = 16, Padding = new Thickness(12), IsEnabled = !locked, Name = "AnswerText" };
        Avalonia.Automation.AutomationProperties.SetName(box, "Your answer");
        box.TextChanged += (_, _) => _typed = box.Text ?? "";
        void Submit() { var t = (box.Text ?? "").Trim(); if (t.Length == 0 || _vm is null) return; _ = _vm.Client.SubmitText(t); }
        box.KeyDown += (_, ev) => { if (ev.Key == Avalonia.Input.Key.Enter && !locked) { Submit(); ev.Handled = true; } };
        OptionsPanel.Children.Add(box);
        if (!locked) OptionsPanel.Children.Add(SubmitButton("Submit", Submit));
        else if (_typed.Length > 0) OptionsPanel.Children.Add(new TextBlock { Text = $"You said: {_typed}", Opacity = 0.7, Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap });
    }

    private void BuildNumeric(LiveRoom.Numeric n, bool locked)
    {
        double step = n.Step > 0 ? n.Step : 1;
        double value = _number ?? System.Math.Round((n.Min + n.Max) / 2 / step) * step;
        string Fmt(double v) => (v == System.Math.Round(v) ? ((long)v).ToString() : v.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)) + (n.Unit.Length > 0 ? " " + n.Unit : "");
        var label = new TextBlock { Text = Fmt(value), FontSize = 30, FontWeight = FontWeight.Black, HorizontalAlignment = HorizontalAlignment.Center, Name = "AnswerNumber" };
        var slider = new Slider { Minimum = n.Min, Maximum = n.Max, Value = value, IsSnapToTickEnabled = true, TickFrequency = step, IsEnabled = !locked };
        Avalonia.Automation.AutomationProperties.SetName(slider, "Your number");
        slider.PropertyChanged += (_, ev) => { if (ev.Property == Slider.ValueProperty) { _number = slider.Value; label.Text = Fmt(slider.Value); } };
        OptionsPanel.Children.Add(label); OptionsPanel.Children.Add(slider);
        if (!locked) OptionsPanel.Children.Add(SubmitButton("Submit", () => { _number = slider.Value; _ = _vm?.Client.SubmitNumber(slider.Value); }));
    }

    private void BuildOrdering(System.Collections.Generic.IReadOnlyList<string> items, bool locked)
    {
        if (_order.Count != items.Count) _order = System.Linq.Enumerable.Range(0, items.Count).ToList();
        var list = new StackPanel { Spacing = 4, Name = "AnswerOrder" };
        void Draw()
        {
            list.Children.Clear();
            for (int pos = 0; pos < _order.Count; pos++)
            {
                int at = pos;
                var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto") };
                var num = new TextBlock { Text = $"{pos + 1}.", FontWeight = FontWeight.Bold, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
                var name = new TextBlock { Text = items[_order[pos]], TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(name, 1);
                row.Children.Add(num); row.Children.Add(name);
                if (!locked)
                {
                    var up = new Button { Content = "▲", Padding = new Thickness(8, 4), IsEnabled = pos > 0, Margin = new Thickness(4, 0, 0, 0) };
                    var down = new Button { Content = "▼", Padding = new Thickness(8, 4), IsEnabled = pos < _order.Count - 1, Margin = new Thickness(4, 0, 0, 0) };
                    Avalonia.Automation.AutomationProperties.SetName(up, $"Move {items[_order[pos]]} up");
                    Avalonia.Automation.AutomationProperties.SetName(down, $"Move {items[_order[pos]]} down");
                    up.Click += (_, _) => { (_order[at - 1], _order[at]) = (_order[at], _order[at - 1]); Draw(); };
                    down.Click += (_, _) => { (_order[at + 1], _order[at]) = (_order[at], _order[at + 1]); Draw(); };
                    Grid.SetColumn(up, 2); Grid.SetColumn(down, 3);
                    row.Children.Add(up); row.Children.Add(down);
                }
                list.Children.Add(row);
            }
        }
        Draw();
        OptionsPanel.Children.Add(list);
        if (!locked) OptionsPanel.Children.Add(SubmitButton("Submit order", () => _ = _vm?.Client.SubmitOrder(_order.ToList())));
    }

    private void BuildMatching(System.Collections.Generic.IReadOnlyList<string> keys, System.Collections.Generic.IReadOnlyList<string> values, bool locked)
    {
        if (_pairs.Count != keys.Count) _pairs = System.Linq.Enumerable.Repeat(-1, keys.Count).ToList();
        var list = new StackPanel { Spacing = 6, Name = "AnswerMatch" };
        Button? submit = null;
        void Refresh() { if (submit is not null) submit.IsEnabled = _pairs.All(x => x >= 0); }
        for (int i = 0; i < keys.Count; i++)
        {
            int ki = i;
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,*") };
            var k = new TextBlock { Text = keys[i], FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
            var pick = new ComboBox { ItemsSource = new[] { "Choose…" }.Concat(values).ToList(), SelectedIndex = _pairs[i] + 1, IsEnabled = !locked, HorizontalAlignment = HorizontalAlignment.Stretch };
            Avalonia.Automation.AutomationProperties.SetName(pick, $"Match for {keys[i]}");
            pick.SelectionChanged += (_, _) => { _pairs[ki] = pick.SelectedIndex - 1; Refresh(); };
            Grid.SetColumn(pick, 1);
            row.Children.Add(k); row.Children.Add(pick);
            list.Children.Add(row);
        }
        OptionsPanel.Children.Add(list);
        if (!locked) { submit = SubmitButton("Submit matches", () => _ = _vm?.Client.SubmitPairs(_pairs.ToList())); Refresh(); OptionsPanel.Children.Add(submit); }
    }

    private void BuildEnumerate(int target, bool locked)
    {
        var head = new TextBlock { Opacity = 0.75, TextWrapping = TextWrapping.Wrap, Name = "AnswerEnumHead" };
        var chips = new TextBlock { TextWrapping = TextWrapping.Wrap, FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 4, 0, 0) };
        void Draw()
        {
            head.Text = $"Name as many as you can ({_named.Count}{(target > 0 ? "/" + target : "")})";
            chips.Text = string.Join(" · ", _named);
            chips.IsVisible = _named.Count > 0;
        }
        Draw();
        OptionsPanel.Children.Add(head); OptionsPanel.Children.Add(chips);
        if (locked) return;
        var box = new TextBox { Watermark = "Add one…", FontSize = 16, Padding = new Thickness(12), Name = "AnswerEnumBox" };
        Avalonia.Automation.AutomationProperties.SetName(box, "Add an answer");
        void Add() { var t = (box.Text ?? "").Trim(); if (t.Length == 0) return; _named.Add(t); box.Text = ""; Draw(); }
        box.KeyDown += (_, ev) => { if (ev.Key == Avalonia.Input.Key.Enter) { Add(); ev.Handled = true; } };
        var add = new Button { Content = "Add", Padding = new Thickness(14, 8), Margin = new Thickness(6, 0, 0, 0) };
        Avalonia.Automation.AutomationProperties.SetName(add, "Add");
        add.Click += (_, _) => Add();
        var addRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), Margin = new Thickness(0, 8, 0, 0) };
        Grid.SetColumn(add, 1); addRow.Children.Add(box); addRow.Children.Add(add);
        OptionsPanel.Children.Add(addRow);
        OptionsPanel.Children.Add(SubmitButton("Done", () => { Add(); _ = _vm?.Client.SubmitList(_named.ToList()); }));
    }

    /// TIDBITS_LIVE_ANSWER=<text> (+_AT, default 75 s): type the answer into the SAME box a
    /// player uses and press its Submit — a harness cannot type on the box, so the
    /// hook drives the widget rather than the client (3.75).
    private bool _answerHookArmed;
    private void ArmAnswerHook()
    {
        if (_answerHookArmed || Services.LaunchHooks.LiveAnswer is not { Length: > 0 } text) return;
        _answerHookArmed = true;
        _ = Task.Run(async () =>
        {
            await Task.Delay(TimeSpan.FromSeconds(Services.LaunchHooks.LiveAnswerAt));
            await Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() =>
            {
                var box = System.Linq.Enumerable.OfType<TextBox>(OptionsPanel.Children).FirstOrDefault(b => b.Name == "AnswerText");
                var submit = System.Linq.Enumerable.OfType<Button>(OptionsPanel.Children).FirstOrDefault(b => (b.Content as string) == "Submit");
                Services.LaunchHooks.Diag($"answer hook: box={(box is null ? "none" : "found")} submit={(submit is null ? "none" : "found")}");
                if (box is null || submit is null) return;
                box.Text = text;
                submit.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            });
        });
    }

    /// Return to whichever surface opened this. Play owns joining now; Tidbits Live
    /// can still host it, so ask the visual tree rather than assuming a parent.
    private void OnLeave(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (Avalonia.VisualTree.VisualExtensions.FindAncestorOfType<PlayView>(this) is { } play)
            play.BackToPlay();
        else
            Avalonia.VisualTree.VisualExtensions.FindAncestorOfType<LiveView>(this)?.BackToSetup();
    }

    /// G1: buzz in. The payload is empty on purpose — the ANSWER is spoken out
    /// loud to the room; all the wire needs to carry is who got there first, and
    /// the server stamps that.
    private async void OnBuzz(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (_vm?.Client is { } c) await c.SubmitBuzz();
    }
}
