using System.Linq;
using System.Threading.Tasks;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Marathon History dialog (docs/CLUB-FEATURES-BUILD.md "Feature 3") —
/// every completed run, most recent first; tapping one opens its full scorecard.
/// One FAContentDialog whose Content swaps list&lt;-&gt;detail (mirrors
/// `StoryArchiveDialog` / RecordsView's See-all-games swap) rather than a nested
/// dialog. Reached from Records' own entry point AND from the in-game scorecard's
/// "See Marathon history" link (`GameView.RebuildMarathonResult`).
public static class MarathonHistoryDialog
{
    public static async Task ShowAsync(RecordsStore records)
    {
        var dialog = new FAContentDialog { Title = "Marathon History", CloseButtonText = "Done" };
        var scores = records.MarathonHistory;

        void ShowList() => dialog.Content = MarathonUi.BuildHistoryList(scores, ShowDetail);

        void ShowDetail(MarathonScore score)
        {
            var previous = scores.SkipWhile(s => s != score).Skip(1).FirstOrDefault();
            dialog.Content = MarathonUi.BuildHistoryDetail(score, previous, onBack: ShowList);
        }

        ShowList();
        await dialog.ShowAsync();
    }
}
