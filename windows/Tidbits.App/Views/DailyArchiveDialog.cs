using System;
using System.Threading.Tasks;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// "Previous Tidbits" — the last two weeks of Dailies, behind a link on the Play home
/// instead of stacked on it. Mirrors iOS's Daily archive sheet; the dialog closes before
/// starting a past day so the game is not hidden behind it.
public static class DailyArchiveDialog
{
    public static async Task ShowAsync(DailyLog log, Action<string> onPlay)
    {
        var dialog = new FAContentDialog { Title = "Previous Tidbits", CloseButtonText = "Done" };
        dialog.Content = DailyUi.BuildArchiveList(log, day =>
        {
            dialog.Hide();
            onPlay(day);
        });
        await dialog.ShowAsync();
    }
}
