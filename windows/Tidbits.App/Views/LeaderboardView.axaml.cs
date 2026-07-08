using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Networking;

namespace Tidbits.App.Views;

public partial class LeaderboardView : UserControl
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private static readonly IBrush Coral = new SolidColorBrush(Color.Parse("#FF5C35"));

    /// The signed-in player's uid, to highlight their own row (null until auth is
    /// wired on Windows — champion is still marked).
    public string? MyUid { get; set; }

    /// The player's private friend list — leads the board with a "Friends" section.
    public IReadOnlyList<PlayerIdentity.Friend> Friends { get; set; } = new List<PlayerIdentity.Friend>();

    /// Fetch + render on load. Tests set this false to render deterministically
    /// (the async network fetch would otherwise race a manual Render).
    public bool AutoLoad { get; set; } = true;

    public LeaderboardView()
    {
        InitializeComponent();
        Loaded += async (_, _) => { if (AutoLoad) await LoadAsync(); };
    }

    private async System.Threading.Tasks.Task LoadAsync()
    {
        Body.Children.Clear();
        Body.Children.Add(new TextBlock { Text = "Loading standings…", Opacity = 0.6 });

        try { Friends = Services.GameData.Shared.Value.Friends.All; } catch { }
        Render(await LeaderboardApi.LoadAsync(Http));
    }

    /// Populate the board from loaded data (extracted so it's testable without a
    /// network fetch). Marks the champion (#1) and the signed-in player's row.
    public void Render(LeaderboardData data)
    {
        Body.Children.Clear();
        if (data.IsEmpty)
        {
            Body.Children.Add(new TextBlock
            {
                Text = "No standings yet — play a live Tidbits night and you'll appear here.",
                Opacity = 0.7, TextWrapping = TextWrapping.Wrap,
            });
            return;
        }

        // L5 social graph: a "Friends" section — your added people, ranked by their
        // standing on the (already-public) overall board; "—" if not yet ranked.
        if (Friends.Count > 0)
        {
            var scoreByUid = data.Overall.ToDictionary(r => r.Uid, r => r.Score);
            var rows = Friends
                .Select(f => new LeaderboardRow { Uid = f.Uid, Name = f.Name, Score = scoreByUid.GetValueOrDefault(f.Uid, -1) })
                .OrderByDescending(r => r.Score)
                .ToList();
            Body.Children.Add(Section("Friends", rows, showChampion: false));
        }

        Body.Children.Add(Section($"{data.Season} · Overall", data.Overall));
        foreach (var v in data.Venues)
            Body.Children.Add(Section(v.Name, v.Rows));
    }

    private Control Section(string title, IReadOnlyList<LeaderboardRow> rows, bool showChampion = true)
    {
        var panel = new StackPanel { Spacing = 6 };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 18, FontWeight = FontWeight.Bold, Margin = new Avalonia.Thickness(0, 6, 0, 2) });
        if (rows.Count == 0)
        {
            panel.Children.Add(new TextBlock { Text = "No standings yet.", Opacity = 0.55 });
            return panel;
        }

        for (int i = 0; i < Math.Min(25, rows.Count); i++)
        {
            var r = rows[i];
            bool me = r.Uid is not null && r.Uid == MyUid;
            bool champ = i == 0 && showChampion;
            var row = new Border
            {
                Background = new SolidColorBrush(Color.Parse("#0F808080")), CornerRadius = new Avalonia.CornerRadius(12),
                BorderBrush = me ? Coral : null, BorderThickness = new Avalonia.Thickness(me ? 2 : 0),
                Padding = new Avalonia.Thickness(14, 10),
            };
            var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("28,*,Auto") };
            grid.Children.Add(new TextBlock { Text = $"{i + 1}", FontWeight = FontWeight.Black, Opacity = champ ? 1 : 0.5 });
            var nameStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            nameStack.Children.Add(new TextBlock { Text = r.Name, FontWeight = FontWeight.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            if (me) nameStack.Children.Add(Chip("YOU", Coral));
            if (champ) nameStack.Children.Add(Chip("CHAMPION", Coral));
            Grid.SetColumn(nameStack, 1);
            grid.Children.Add(nameStack);
            var score = new TextBlock { Text = r.Score < 0 ? "—" : r.Score.ToString(), FontWeight = FontWeight.Black, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(score, 2);
            grid.Children.Add(score);
            row.Child = grid;
            panel.Children.Add(row);
        }
        return panel;
    }

    private static Control Chip(string text, IBrush brush) => new TextBlock
    {
        Text = text, FontSize = 10, FontWeight = FontWeight.Black, Foreground = brush, VerticalAlignment = VerticalAlignment.Center,
    };
}
