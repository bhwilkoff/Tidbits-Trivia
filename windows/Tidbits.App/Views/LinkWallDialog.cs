using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Input.Platform;
using FluentAvalonia.UI.Controls;
using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.App.Views;

/// The Club Link Wall dialog (docs/CLUB-FEATURES-BUILD.md "Feature 6") — hosts the
/// live board, wiring `LinkWallUi`'s static builders to a live `RecordsStore` row
/// for `day`. One FAContentDialog whose Content swaps board&lt;-&gt;result (mirrors
/// `ExpeditionsDialog`'s hub&lt;-&gt;map swap) rather than stacking dialogs. Never a
/// free Customize pick and never routed through `GameEngine`/`GameMode` — it isn't a
/// corpus MCQ round, so it owns its play loop here (mirrors Apple's `LinkWallView` /
/// Android's `LinkWallScreen`). Members only — the caller (`PlayView`) gates entry
/// with the existing `ClubPaywallView` before ever calling `ShowAsync`, exactly like
/// Marathon/Weak-Spot (Link Wall is curated-by-generator CONTENT, not player data,
/// so there's no free-tier partial board to show — the paywall itself carries the
/// real preview via the Home card's subtitle).
public static class LinkWallDialog
{
    public static async Task ShowAsync(RecordsStore records, IReadOnlyList<Question> matchQuestions, string day)
    {
        var puzzle = LinkWall.Puzzle(day, matchQuestions);
        var dialog = new FAContentDialog { Title = "Link Wall", CloseButtonText = "Close" };

        if (puzzle is null)
        {
            dialog.Content = LinkWallUi.BuildUnavailable();
            await dialog.ShowAsync();
            return;
        }

        var result = records.LinkWallResultOrCreate(day);
        var byLabel = puzzle.Groups.ToDictionary(g => g.Label);
        var tileGroup = new Dictionary<string, LinkWallGroup>();
        foreach (var g in puzzle.Groups) foreach (var m in g.Members) tileGroup[m] = g;

        var solvedGroups = result.SolvedLabels.Where(byLabel.ContainsKey).Select(l => byLabel[l]).ToList();
        var solvedMembers = solvedGroups.SelectMany(g => g.Members).ToHashSet();
        var remainingTiles = puzzle.Tiles.Where(t => !solvedMembers.Contains(t)).ToList();
        var selected = new List<string>();
        string? oneAwayMessage = null;

        void ShowResult()
        {
            dialog.Content = LinkWallUi.BuildResult(puzzle, result, onShare: () => _ = ShareAsync(), onDone: () => dialog.Hide());
        }

        void ShowBoard()
        {
            if (result.Completed) { ShowResult(); return; }
            dialog.Content = LinkWallUi.BuildBoard(
                puzzle, result, remainingTiles, solvedGroups, selected, oneAwayMessage,
                onToggleTile: ToggleTile, onDeselectAll: DeselectAll, onShuffle: Shuffle, onSubmit: Submit);
        }

        void ToggleTile(string tile)
        {
            if (selected.Contains(tile)) selected.Remove(tile);
            else if (selected.Count < 4) selected.Add(tile);
            ShowBoard();
        }

        void DeselectAll()
        {
            selected.Clear();
            ShowBoard();
        }

        void Shuffle()
        {
            var rnd = Random.Shared;
            for (int i = remainingTiles.Count - 1; i > 0; i--)
            {
                int j = rnd.Next(i + 1);
                (remainingTiles[i], remainingTiles[j]) = (remainingTiles[j], remainingTiles[i]);
            }
            ShowBoard();
        }

        void Submit()
        {
            if (selected.Count != 4) return;
            var selectedSet = selected.ToHashSet();
            var difficulties = selected.Select(t => tileGroup.TryGetValue(t, out var g) ? g.Difficulty : 0).ToList();
            result.RecordGuess(difficulties);

            var matched = puzzle.Groups.FirstOrDefault(g => g.Members.ToHashSet().SetEquals(selectedSet));
            if (matched is not null)
            {
                result.RecordSolvedGroup(matched.Label);
                solvedGroups.Add(matched);
                remainingTiles.RemoveAll(selectedSet.Contains);
                selected.Clear();
                oneAwayMessage = null;
                if (solvedGroups.Count == puzzle.Groups.Count) Finish(won: true);
            }
            else
            {
                result.Mistakes++;
                var closest = LinkWallUi.ClosestUnsolvedGroup(puzzle.Groups, solvedGroups.Select(g => g.Label).ToList(), selected);
                oneAwayMessage = closest is not null ? "One away…" : null;
                if (result.Mistakes >= 4) Finish(won: false);
            }
            records.SaveLinkWallResult(result);
            ShowBoard();
        }

        void Finish(bool won)
        {
            if (!won)
            {
                // Loss reveals every remaining group — mirrors Apple's `finish(won:)`.
                var remaining = puzzle.Groups.Where(g => !solvedGroups.Any(s => s.Label == g.Label)).ToList();
                solvedGroups.AddRange(remaining);
                selected.Clear();
            }
            result.Completed = true;
            result.Won = won;
        }

        async Task ShareAsync()
        {
            var text = LinkWallUi.ShareText(day, result);
            var clipboard = TopLevel.GetTopLevel(dialog)?.Clipboard;
            if (clipboard is not null) await clipboard.SetTextAsync(text);
        }

        ShowBoard();
        await dialog.ShowAsync();
    }
}
