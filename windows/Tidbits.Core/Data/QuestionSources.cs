using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// Loads + holds every bundled question source (the corpus + the 8 enrichment
/// sets + the difficulty overlay) from a directory of the shared-asset JSONs.
/// One place the app wires the data layer; QuestionProvider consumes it.
public sealed class QuestionSources
{
    public required CorpusDatabase Corpus { get; init; }
    public required DifficultyOverlay Difficulty { get; init; }
    public required IReadOnlyDictionary<GameMode, JsonQuestionSource> Enrichment { get; init; }

    public JsonQuestionSource Enrich(GameMode m) =>
        Enrichment.TryGetValue(m, out var s) ? s : new JsonQuestionSource(Array.Empty<Question>());

    /// Coverage disclosure (the rule iOS + web already carry, ported here). A mode x
    /// category the bundle cannot fill still PLAYS — it is assembled from other
    /// categories — and saying nothing about that reads as a lie. The picker uses this to
    /// say so before the player commits, dimming rather than disabling: the round is
    /// still worth playing, it just won't be the category they asked for.
    public int Coverage(GameMode mode, string categoryId) =>
        categoryId == "mixed" ? int.MaxValue
        : Enrichment.TryGetValue(mode, out var set) ? set.CountIn(categoryId)
        : Corpus.CountIn(categoryId);

    public bool CanFill(GameMode mode, string categoryId) =>
        Coverage(mode, categoryId) >= mode.QuestionCount();

    /// The bundled sets by their CONTRACT name (docs/QUIZ-CONTRACT.md). A saved
    /// quiz's set-ref names its set precisely because a bare ID is ambiguous — these
    /// share the corpus "src:" namespace.
    private static readonly IReadOnlyDictionary<string, GameMode> ContractSets =
        new Dictionary<string, GameMode>
        {
            ["picture"] = GameMode.PictureId,
            ["thisorthat"] = GameMode.ThisOrThat,
            ["closest"] = GameMode.ClosestCall,
            ["order"] = GameMode.Ordering,
            ["match"] = GameMode.Matching,
            ["typeanswer"] = GameMode.TypeAnswer,
            ["oddoneout"] = GameMode.OddOneOut,
            ["enumerate"] = GameMode.Enumerate,
        };

    /// <summary>Every contract set name, for callers that must try them all.</summary>
    public static IEnumerable<string> ContractSetNames => ContractSets.Keys;

    /// <summary>Look up one bundled-set question by contract set name + id.</summary>
    public Question? Question(string set, string id) =>
        ContractSets.TryGetValue(set, out var mode) ? Enrich(mode).Question(id) : null;

    public static QuestionSources LoadFromDirectory(string dir)
    {
        var enrichment = new Dictionary<GameMode, JsonQuestionSource>
        {
            [GameMode.PictureId] = LoadJson(dir, "picture.json"),
            [GameMode.ThisOrThat] = LoadJson(dir, "thisorthat.json"),
            [GameMode.ClosestCall] = LoadJson(dir, "closest.json"),
            [GameMode.Ordering] = LoadJson(dir, "order.json"),
            [GameMode.Matching] = LoadJson(dir, "match.json"),
            [GameMode.TypeAnswer] = LoadJson(dir, "typeanswer.json"),
            [GameMode.OddOneOut] = LoadJson(dir, "oddoneout.json"),
            [GameMode.Enumerate] = LoadJson(dir, "enumerate.json"),
        };

        CorpusDatabase corpus;
        using (var cs = File.OpenRead(Path.Combine(dir, "corpus.json"))) corpus = CorpusDatabase.Load(cs);

        DifficultyOverlay diff;
        var dp = Path.Combine(dir, "difficulty.json");
        if (File.Exists(dp)) { using var ds = File.OpenRead(dp); diff = DifficultyOverlay.Load(ds); }
        else diff = new DifficultyOverlay();

        return new QuestionSources { Corpus = corpus, Difficulty = diff, Enrichment = enrichment };
    }

    private static JsonQuestionSource LoadJson(string dir, string name)
    {
        var p = Path.Combine(dir, name);
        if (!File.Exists(p)) return new JsonQuestionSource(Array.Empty<Question>());
        using var s = File.OpenRead(p);
        return JsonQuestionSource.Load(s);
    }
}
