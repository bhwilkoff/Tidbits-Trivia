using System;
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
        if (_vm is not null) _vm.Client.Changed += OnClientChanged;
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
    private void RebuildOptions()
    {
        OptionsPanel.Children.Clear();
        var c = _vm?.Client;
        if (c?.Pub?.Options is not { } opts) return;

        bool question = c.Pub.Phase == LiveRoom.Phase.Question;
        bool reveal = c.Pub.Phase == LiveRoom.Phase.Reveal;
        bool answered = c.HasAnswered;

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
                if (reveal && i == c.Pub.AnswerIndex) { btn.Background = Correct; btn.Foreground = Brushes.White; }
                else if (i == c.Chosen) { btn.Background = reveal ? Wrong : Picked; btn.Foreground = Brushes.White; }
                else btn.Opacity = 0.45;
            }
            OptionsPanel.Children.Add(btn);
        }
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
