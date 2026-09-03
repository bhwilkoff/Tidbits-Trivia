using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Tidbits.App.Services;
using Tidbits.App.ViewModels;
using Tidbits.App.Views;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

namespace Tidbits.HeadlessTests;

/// G5 — the pick-a-category grid on the Windows projector.
///
/// The macOS board shipped with FIVE HOLES in it and a unit test could not have
/// seen that: every Core assertion passed, because the Core was right and the
/// POOL handed to the builder was too small. It took rendering the slide. So the
/// Windows grid gets rendered and COUNTED, not just built.
public class LiveBoardRenderTest
{
    private static string Art()
    {
        var d = Environment.GetEnvironmentVariable("TIDBITS_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    private static readonly string[] Columns = { "history", "science", "music", "screen", "geography" };

    private static async Task<LiveHostViewModel> BoardHost()
    {
        var data = GameData.FromDirectory(Path.Combine(AppContext.BaseDirectory, "Data"));
        var host = new LiveNightHost(NightPlan.Quick, TriviaCategory.Named("mixed"), data.Provider, "Friday Pub Quiz");
        await host.LoadQuestionsOffline();

        // Ask the corpus for each CELL. Building the board from the NIGHT's
        // questions returns an empty grid — a Quick night over "mixed" does not
        // hold a question at every (category, tier), which is the same
        // wrong-pool mistake that put five holes in the macOS board.
        var pool = new List<Question>();
        foreach (var c in Columns)
            foreach (var t in LiveBoard.DefaultTiers)
                pool.AddRange(data.Sources.Corpus.Questions(c, t, new HashSet<string>(), 1));

        var board = LiveBoardBuilder.Build(pool, Columns);
        // The round must HOLD the questions its grid references, or picking a cell
        // finds no question to open.
        host.Questions.Clear();
        host.Questions.AddRange(board.Cells.Select(cell => pool.First(q => q.Id == cell.QuestionId)));
        host.RoundBoards = new List<LiveBoard?> { board };
        host.ShowBoard = true;
        return new LiveHostViewModel(host);
    }

    [AvaloniaFact]
    public async Task The_board_slide_renders_every_cell_the_grid_declares()
    {
        var vm = await BoardHost();
        var win = new Window { Width = 1280, Height = 720, Content = new ProjectorView { DataContext = vm } };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        // The board takes the big screen; the question screen must be GONE. Both
        // visible at once is the Mac cockpit bug — a room reading a question
        // nobody picked.
        Assert.True(vm.ShowBoardScreen);
        Assert.False(vm.ShowQuestionScreen);

        // COUNT the tiles. "It rendered" is what a snapshot asserts, and a grid
        // with holes in it renders perfectly well.
        Assert.Equal(Columns.Length * LiveBoard.DefaultTiers.Length, vm.BoardTiles.Count);
        Assert.All(vm.BoardTiles, t => Assert.NotEqual("", t.Label));
        Assert.Equal(Columns.Length, vm.BoardColumns);

        win.CaptureRenderedFrame()!.Save(Path.Combine(Art(), "projector-board.png"));
    }

    [AvaloniaFact]
    public async Task Picking_a_cell_takes_it_once_and_opens_its_question()
    {
        var vm = await BoardHost();
        var host = vm.Host;
        var first = host.CurrentBoard!.Cells[0];

        Assert.True(host.PickBoardCell(first.CategoryId, first.Tier));
        Assert.Equal(first.QuestionId, host.Current!.Id);
        Assert.False(host.ShowBoard);          // the grid gives way to the question
        Assert.True(host.CurrentBoard!.Cell(first.CategoryId, first.Tier)!.Taken);

        // A second click on the same tile must not advance the night again.
        host.ReturnToBoard();
        Assert.False(host.PickBoardCell(first.CategoryId, first.Tier));
    }

    [AvaloniaFact]
    public async Task A_taken_cell_is_no_longer_playable_but_keeps_its_place()
    {
        var vm = await BoardHost();
        var cell = vm.Host.CurrentBoard!.Cells[0];
        vm.Host.PickBoardCell(cell.CategoryId, cell.Tier);
        vm.Host.ReturnToBoard();

        var tiles = vm.BoardTiles;
        // Still 25 tiles: a played cell goes quiet IN PLACE. A grid that reflows on
        // every pick makes the room re-find its column.
        Assert.Equal(Columns.Length * LiveBoard.DefaultTiers.Length, tiles.Count);
        var played = tiles.First(t => t.CategoryId == cell.CategoryId && t.Tier == cell.Tier);
        Assert.False(played.Playable);
    }
}
