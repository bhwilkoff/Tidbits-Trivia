using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Tidbits.Core.Store;

/// The host's per-element switches for the live slide (macOS-DESIGN A8.7 — the
/// same ids as the Mac, so a host's mental model carries across). Everything
/// except the question and its answer can be turned off from the cockpit.
///
/// Persisted, because a host sets this up once per venue and expects it back
/// next week. `TIDBITS_LIVE_HIDE=title,roundLine,...` applies a set for ONE
/// launch without persisting it, so a harness can photograph a stripped slide
/// without changing the host's real preference underneath them.
public sealed class ProjectorElements
{
    public static readonly ProjectorElements Shared = new();

    public sealed record Element(string Id, string Title);

    /// Every switchable element, in the order the cockpit menu lists them —
    /// top of the slide to bottom.
    public static readonly IReadOnlyList<Element> All = new[]
    {
        new Element("title", "Event name"),
        new Element("roundLine", "Round line"),
        new Element("countdown", "Countdown"),
        new Element("chrome", "Question chrome (number, players, difficulty)"),
        new Element("picture", "Question picture"),
        new Element("tally", "Live vote bars"),
        new Element("status", "\"Answer on your phones\""),
        new Element("answersIn", "Answers in (12 of 18)"),
        new Element("jokers", "Jokers played (first question of a round)"),
        new Element("story", "Story on reveal"),
        new Element("teams", "Team standings strip"),
        new Element("joinPanel", "Scan-to-join card"),
        new Element("sponsor", "Sponsor footer"),
    };

    public static string FilePath { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TidbitsTrivia", "projector-hidden.json");

    private readonly HashSet<string> _hidden;
    private readonly bool _persists;
    public event Action? Changed;

    public ProjectorElements()
    {
        var env = Environment.GetEnvironmentVariable("TIDBITS_LIVE_HIDE");
        if (!string.IsNullOrWhiteSpace(env))
        {
            _hidden = env.Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToHashSet();
            _persists = false;
        }
        else
        {
            _hidden = Load();
            _persists = true;
        }
    }

    private static HashSet<string> Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<string[]>(File.ReadAllText(FilePath))?.ToHashSet() ?? new();
        }
        catch { /* a bad file is an empty set */ }
        return new();
    }

    private void Save()
    {
        if (!_persists) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(_hidden.OrderBy(s => s, StringComparer.Ordinal).ToArray()));
        }
        catch { /* the switch still applies for this night */ }
    }

    public bool Shows(string id) => !_hidden.Contains(id);
    public void Set(string id, bool shown)
    {
        if (shown) _hidden.Remove(id); else _hidden.Add(id);
        Save(); Changed?.Invoke();
    }
    public void ShowEverything() { _hidden.Clear(); Save(); Changed?.Invoke(); }
    public int HiddenCount => _hidden.Count;
}
