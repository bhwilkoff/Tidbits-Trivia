using System;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// Shared chrome for the Daily Tidbit: ONE row builder used by both the Play home
/// (today only) and the Previous Tidbits archive (the past two weeks).
///
/// Why the split: the Play home used to render all 14 days inline, which read as
/// "fourteen Dailies" and buried Quick Play. Every other platform shows today's
/// Tidbit as a single card with the archive behind a link (R-HOME-1: the home is a
/// single obvious action, not a list of everything the app can do).
public static class DailyUi
{
    /// One day's row. `heroToday` styling is reserved for an unplayed today, so the
    /// card the player should act on is the only bright thing on the panel.
    public static Border BuildRow(DateTime date, string todayKey, DailyLog log, Action<string> onPlay)
    {
        var day = QuestionProvider.DayKey(date);
        bool isToday = day == todayKey;
        var result = log.Result(day);
        var label = isToday ? "Today" : date.ToString("ddd, MMM d");
        bool heroToday = isToday && result is null;

        var row = new Border
        {
            Background = heroToday ? new SolidColorBrush(Color.Parse("#FF5C35")) : null,
            CornerRadius = new Avalonia.CornerRadius(10),
            BorderBrush = heroToday ? null : new SolidColorBrush(Color.Parse("#22808080")),
            BorderThickness = new Avalonia.Thickness(heroToday ? 0 : 1),
            Padding = new Avalonia.Thickness(16, 12),
            Margin = new Avalonia.Thickness(0, 0, 0, 6),
        };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var labelBlock = new TextBlock
        {
            Text = label,
            FontWeight = FontWeight.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (heroToday) labelBlock.Foreground = Brushes.White;   // else inherit the themed default
        grid.Children.Add(labelBlock);

        if (result is not null)
        {
            var done = new TextBlock
            {
                Text = $"{result.Correct}/{result.Total} · {result.Score} pts",
                VerticalAlignment = VerticalAlignment.Center,
                Opacity = 0.75,
                FontSize = 13,
            };
            Grid.SetColumn(done, 1);
            grid.Children.Add(done);
        }
        else
        {
            // An accent button on an ACCENT surface disappears — brand coral on brand coral.
            // On the hero row use the inverse treatment (white chip, coral label); elsewhere
            // the row is neutral, so the normal accent CTA is right.
            var play = new Button
            {
                Content = isToday ? "Play today's Tidbit" : "Play",
                Padding = new Avalonia.Thickness(16, 8),
            };
            if (heroToday)
            {
                play.Background = Brushes.White;
                play.Foreground = new SolidColorBrush(Color.Parse("#FF5C35"));
                play.BorderBrush = Brushes.White;
                play.FontWeight = FontWeight.SemiBold;
            }
            else
            {
                play.Classes.Add("accent");
            }
            play.Click += (_, _) => onPlay(day);
            Grid.SetColumn(play, 1);
            grid.Children.Add(play);
        }
        row.Child = grid;
        return row;
    }

    /// The archive body: yesterday backwards. Past days stay playable (the day key seeds
    /// the pick deterministically) and never bump the streak — RecordsStore enforces that.
    public static Control BuildArchiveList(DailyLog log, Action<string> onPlay)
    {
        var today = QuestionProvider.DayKey();
        var panel = new StackPanel { Spacing = 0, MinWidth = 360 };
        for (int i = 1; i < 14; i++)
            panel.Children.Add(BuildRow(DateTime.Now.Date.AddDays(-i), today, log, onPlay));
        return new ScrollViewer { Content = panel, MaxHeight = 420 };
    }
}
