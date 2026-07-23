using System;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Media;
using FluentAvalonia.UI.Controls;
using Tidbits.App.Services;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Expedition hub + map dialog (docs/CLUB-FEATURES-BUILD.md "Feature 5") —
/// campaign list + certificates shelf, and a per-campaign stage path. UNLIKE
/// Marathon/Knowledge Atlas/Story Archive, the hub AND map are a REAL preview
/// reachable by everyone (never gated at this layer, matching Apple/Android) — only
/// tapping Play on the CURRENT stage is Club-gated, and that check reads
/// `GameData.Shared` live (not a snapshot) so a purchase made from the inline
/// paywall is reflected immediately without reopening the dialog.
///
/// One FAContentDialog whose Content swaps hub/map/paywall (mirrors StoryArchive/
/// MarathonHistory/KnowledgeAtlas's list<->detail swap) rather than stacking a
/// second dialog on top — the macOS mirror hit a real "one sheet per window" bug
/// doing that, so Windows dodges it the same way from day one. Rendering lives in
/// `ExpeditionsUi` (a static, headless-testable builder); this class only wires
/// live `RecordsStore` state to it and hands off to the round launcher.
public static class ExpeditionsDialog
{
    /// `onPlay(expedition, stageIndex)` fires once the dialog hides — the caller
    /// (PlayView) launches the actual round. `openExpeditionId` opens straight to
    /// that campaign's map (used after a stage session returns, so the player lands
    /// back where they were instead of the hub).
    public static async Task ShowAsync(RecordsStore records, Action<Expedition, int> onPlay, string? openExpeditionId = null)
    {
        var dialog = new FAContentDialog { Title = "Expeditions", CloseButtonText = "Done" };

        void ShowHub()
        {
            var available = Expeditions.Available(records);
            var certificates = Expeditions.Certificates(records);
            dialog.Content = ExpeditionsUi.BuildHub(available, certificates, ShowMap);
        }

        void ShowMap(Expedition expedition)
        {
            var progress = Expeditions.Progress(records, expedition.Id);
            var isClub = GameData.Shared.Value.Entitlement.IsClub;
            dialog.Content = ExpeditionsUi.BuildMap(expedition, progress, isClub,
                onPlayCurrent: () => OnPlayCurrent(expedition),
                onBack: ShowHub);
        }

        void OnPlayCurrent(Expedition expedition)
        {
            if (!GameData.Shared.Value.Entitlement.IsClub)
            {
                ShowPaywall(() => ShowMap(expedition));
                return;
            }
            var progress = Expeditions.Progress(records, expedition.Id);
            var stageIndex = progress?.CurrentStageIndex ?? 0;
            dialog.Hide();
            onPlay(expedition, stageIndex);
        }

        void ShowPaywall(Action onBack)
        {
            var back = new Button
            {
                Content = "‹ Back", Background = Brushes.Transparent, BorderThickness = new Avalonia.Thickness(0),
                Padding = new Avalonia.Thickness(0),
            };
            back.Click += (_, _) => onBack();
            var panel = new StackPanel
            {
                Spacing = 12, MinWidth = 380, MaxWidth = 460,
                Children = { back, new ClubPaywallView() },
            };
            dialog.Content = new ScrollViewer { Content = panel, MaxHeight = 640 };
        }

        if (openExpeditionId is not null && Expeditions.Named(openExpeditionId) is { } exp) ShowMap(exp);
        else ShowHub();

        await dialog.ShowAsync();
    }
}
