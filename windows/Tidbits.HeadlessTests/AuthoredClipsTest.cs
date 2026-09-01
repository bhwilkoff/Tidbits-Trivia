using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Tidbits.Core.Data;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Tidbits.Core.Store;
using Xunit;

namespace Tidbits.HeadlessTests;

/// Audio/video ROUNDS on Windows — WINDOWS-DESIGN §6.6's media half.
///
/// Windows could play an ad-hoc clip the host picked mid-night, but a round could
/// not CARRY clips: there was nowhere in the model to put them. These pin the two
/// things that make the feature real rather than decorative — the clip reaches the
/// cockpit for the right question, and a clip that has gone missing is reported
/// instead of silently becoming a dead play button (the exact macOS failure).
public class AuthoredClipsTest : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), $"tidbits-clips-{Guid.NewGuid():N}");

    public AuthoredClipsTest() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { } }

    private string MakeClip(string name)
    {
        var p = Path.Combine(_dir, name);
        File.WriteAllBytes(p, new byte[] { 0x52, 0x49, 0x46, 0x46 });
        return p;
    }

    private static Question Q(string id) => new()
    {
        Id = id, Prompt = $"{id} — name it", Options = ["answer"], CorrectIndex = 0,
        CategoryId = "music", Difficulty = 3, TemplateId = "audio", Accepted = ["answer"],
    };

    private static QuestionProvider Provider() =>
        new(QuestionSources.LoadFromDirectory(Path.Combine(AppContext.BaseDirectory, "Fixtures")));

    private static LiveNightHost HostFor(LiveEvent ev) => new(ev.ToPlan(), TriviaCategory.Named("mixed"), Provider(), ev.Name)
    {
        AuthoredQuestions = Enumerable.Range(0, ev.Rounds.Count).Select(ev.QuestionsFor).ToList(),
        AuthoredClips = Enumerable.Range(0, ev.Rounds.Count)
            .Select(i => (IReadOnlyList<string>)Enumerable.Range(0, ev.QuestionsFor(i).Count)
                .Select(q => ev.ClipFor(i, q) ?? "").ToList()).ToList(),
    };

    private LiveEvent TwoClipEvent(out string first, out string second)
    {
        first = MakeClip("one.wav");
        second = MakeClip("two.wav");
        return new LiveEvent
        {
            Name = "Name That Tune",
            Rounds = [new NightRound { Kind = GameMode.TypeAnswer, Count = 2 }],
            RoundQuestions = [new List<Question> { Q("clip:1"), Q("clip:2") }],
            RoundClips = [new List<string> { first, second }],
        };
    }

    [Fact]
    public void A_clip_round_stores_a_clip_per_question()
    {
        var ev = TwoClipEvent(out var first, out var second);
        Assert.Equal(first, ev.ClipFor(0, 0));
        Assert.Equal(second, ev.ClipFor(0, 1));
        Assert.Null(ev.ClipFor(0, 2));
        Assert.Null(ev.ClipFor(1, 0));
        Assert.True(ev.RoundHasClips(0));
        Assert.False(ev.RoundHasClips(1));
    }

    [Fact]
    public async Task The_cockpit_gets_the_clip_for_the_question_on_screen()
    {
        // The whole point: an authored clip must arrive at the cockpit attached to
        // the RIGHT question, not the right index of the whole night.
        var ev = TwoClipEvent(out var first, out var second);
        var host = HostFor(ev);
        await host.LoadQuestionsOffline();

        Assert.Equal(2, host.Questions.Count);
        Assert.Equal(first, host.CurrentClipPath);
        Assert.False(host.CurrentClipMissing);
    }

    [Fact]
    public async Task A_clip_that_has_gone_missing_is_reported_not_silently_dropped()
    {
        var ev = TwoClipEvent(out var first, out _);
        var host = HostFor(ev);
        await host.LoadQuestionsOffline();
        Assert.NotNull(host.CurrentClipPath);

        File.Delete(first);
        // A host whose clip moved must see "unavailable", not a play button that
        // does nothing with a room watching.
        Assert.Null(host.CurrentClipPath);
        Assert.True(host.CurrentClipMissing);
    }

    [Fact]
    public async Task A_round_with_no_clips_reports_nothing_missing()
    {
        var ev = new LiveEvent
        {
            Name = "Plain",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 1 }],
            RoundQuestions = [new List<Question> { Q("plain:1") }],
        };
        var host = HostFor(ev);
        await host.LoadQuestionsOffline();
        Assert.Null(host.CurrentClipPath);
        // "No clip round" and "your clip moved" are different states, and the
        // cockpit shows different things for them.
        Assert.False(host.CurrentClipMissing);
    }

    [Fact]
    public void Deleting_a_question_keeps_the_clip_list_the_same_length()
    {
        // Otherwise clip N slides onto question N+1 the first time a host edits a
        // clip round — every remaining question would then play the wrong track.
        var ev = TwoClipEvent(out var first, out _);
        var trimmed = ev.WithQuestions(0, ev.QuestionsFor(0).Take(1).ToList());
        Assert.Equal(1, trimmed.Rounds[0].Count);
        Assert.Single(trimmed.RoundClips[0]);
        Assert.Equal(first, trimmed.ClipFor(0, 0));
    }

    [Fact]
    public void Adding_a_question_to_a_clip_round_leaves_its_clip_slot_empty()
    {
        var ev = TwoClipEvent(out var first, out var second);
        var grown = ev.WithQuestions(0, ev.QuestionsFor(0).Append(Q("clip:3")).ToList());
        Assert.Equal(3, grown.RoundClips[0].Count);
        Assert.Equal(first, grown.ClipFor(0, 0));
        Assert.Equal(second, grown.ClipFor(0, 1));
        Assert.Null(grown.ClipFor(0, 2));   // the new question has no clip yet
    }

    [Fact]
    public async Task The_cockpit_view_model_offers_play_only_when_the_clip_is_there()
    {
        // The VM is what the cockpit binds IsVisible to, so these three flags ARE
        // the difference between a working control, a warning, and nothing at all.
        var ev = TwoClipEvent(out var first, out _);
        var host = HostFor(ev);
        await host.LoadQuestionsOffline();
        var vm = new Tidbits.App.ViewModels.LiveHostViewModel(host);

        Assert.True(vm.HasClip);
        Assert.False(vm.ClipMissing);
        Assert.Equal("one.wav", vm.ClipName);

        File.Delete(first);
        var vm2 = new Tidbits.App.ViewModels.LiveHostViewModel(host);
        Assert.False(vm2.HasClip);      // no play button
        Assert.True(vm2.ClipMissing);   // ...but an explicit warning instead
    }

    [Fact]
    public async Task A_plain_round_shows_neither_a_play_button_nor_a_warning()
    {
        var ev = new LiveEvent
        {
            Name = "Plain",
            Rounds = [new NightRound { Kind = GameMode.Classic, Count = 1 }],
            RoundQuestions = [new List<Question> { Q("plain:1") }],
        };
        var host = HostFor(ev);
        await host.LoadQuestionsOffline();
        var vm = new Tidbits.App.ViewModels.LiveHostViewModel(host);
        Assert.False(vm.HasClip);
        Assert.False(vm.ClipMissing);
        Assert.Equal("", vm.ClipName);
    }
}
