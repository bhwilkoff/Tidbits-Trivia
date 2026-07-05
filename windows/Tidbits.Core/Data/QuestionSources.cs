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
