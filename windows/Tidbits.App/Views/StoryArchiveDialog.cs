using System;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Story Archive dialog (docs/CLUB-FEATURES-BUILD.md "Feature 2") — the
/// searchable, filterable library of every story the player has unlocked. Reached
/// only through the Club-gated Records entry point (`RecordsView.OnStoryArchiveAction`);
/// the free in-moment story reveal (`Question.Explanation`, shown right after
/// answering) is untouched — additive, never subtractive (R-MON-1).
///
/// One FAContentDialog whose Content swaps between the list and a story's detail
/// (mirrors RecordsView's See-all-games ShowList/RecapView swap) rather than a nested
/// dialog — the macOS mirror hit a real "one sheet per window" bug doing that, so
/// Windows dodges it the same way from day one. The search box and filter/domain
/// chips are built once and never torn down mid-session, so typing never loses focus
/// or caret position — only the results region rebuilds per keystroke/filter change.
/// Rendering itself lives in `StoryArchiveUi` (a static, headless-testable builder);
/// this class only wires live `RecordsStore` state to it.
public static class StoryArchiveDialog
{
    public static async Task ShowAsync(RecordsStore records, Action<Question> onReask)
    {
        var dialog = new FAContentDialog { Title = "Story Archive", CloseButtonText = "Done" };

        // Snapshot for this dialog session (already most-recent-first). ToggleFavorite
        // mutates the SAME SeenStory instances in place, so favorite changes show up
        // immediately without re-fetching from the store.
        var stories = records.Seen;
        var domains = stories.Select(s => s.CategoryId).Distinct()
            .Select(TriviaCategory.Named).OrderBy(c => c.Name).ToList();

        string search = "";
        var filter = StoryFilter.All;
        string? domain = null;

        var chipsHost = new ContentControl();
        var resultsHost = new ContentControl();
        var searchBox = new TextBox { Watermark = "Search your stories", Margin = new Avalonia.Thickness(0, 0, 0, 10) };

        void RebuildResults()
        {
            var filtered = StoryArchive.Search(stories, search, domain, filter);
            resultsHost.Content = StoryArchiveUi.BuildResultsList(stories, filtered, ShowDetail,
                onFavorite: s => { records.ToggleFavorite(s.QuestionId); RebuildResults(); });
        }

        void RebuildChips()
        {
            chipsHost.Content = StoryArchiveUi.BuildChips(domains, filter, domain,
                onFilter: f => { filter = f; RebuildChips(); RebuildResults(); },
                onDomain: d => { domain = d; RebuildChips(); RebuildResults(); });
        }

        void ShowList()
        {
            var panel = new DockPanel { LastChildFill = true };
            DockPanel.SetDock(searchBox, Dock.Top);
            panel.Children.Add(searchBox);
            DockPanel.SetDock(chipsHost, Dock.Top);
            panel.Children.Add(chipsHost);
            panel.Children.Add(new ScrollViewer { Content = resultsHost, MaxHeight = 420 });
            dialog.Content = new Border { MinWidth = 420, MaxWidth = 460, Child = panel };
            RebuildChips();
            RebuildResults();
        }

        void ShowDetail(SeenStory story)
        {
            var q = story.Question;
            dialog.Content = StoryArchiveUi.BuildDetailPanel(story,
                onBack: ShowList,
                onFavorite: () => { records.ToggleFavorite(story.QuestionId); ShowDetail(story); },
                onReask: q is null ? null : () => { dialog.Hide(); onReask(q); });
        }

        searchBox.TextChanged += (_, _) => { search = searchBox.Text ?? ""; RebuildResults(); };

        ShowList();
        await dialog.ShowAsync();
    }
}
