using System;
using System.Threading.Tasks;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Knowledge Atlas dialog (docs/CLUB-FEATURES-BUILD.md "Feature 4") —
/// domain accuracy over the trailing 12 months + a Decay radar, every row a
/// tap-to-play door. Reached only through the Club-gated Records entry point
/// (`RecordsView.OnKnowledgeAtlasAction`); the free Topic Levels / Pie this reads
/// the SAME rows as are untouched — additive, never subtractive (R-MON-1).
/// Rendering lives in `KnowledgeAtlasUi` (a static, headless-testable builder);
/// this class only wires live `RecordsStore` state to it and hides the dialog
/// before handing off to the domain round (mirrors `StoryArchiveDialog`'s
/// `onReask` hand-off so the round never stacks on top of this dialog).
public static class KnowledgeAtlasDialog
{
    public static async Task ShowAsync(RecordsStore records, Action<TriviaCategory> onPlay)
    {
        var dialog = new FAContentDialog { Title = "Knowledge Atlas", CloseButtonText = "Done" };
        var domains = KnowledgeAtlas.Domains(records.Games);
        var decaying = KnowledgeAtlas.DecayRadar(records.Games);
        dialog.Content = KnowledgeAtlasUi.BuildAtlas(domains, decaying,
            onPlay: cat => { dialog.Hide(); onPlay(cat); });
        await dialog.ShowAsync();
    }
}
