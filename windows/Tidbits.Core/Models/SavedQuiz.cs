using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace Tidbits.Core.Models;

/// <summary>
/// One entry in a quiz's ordered question list: a CORPUS ref (a bare string on the
/// wire), a BUNDLED-SET ref (carrying which set it came from), or an INLINE question.
///
/// SetRef exists because a bare ID is genuinely ambiguous: the bundled sets share the
/// corpus "src:" namespace, and 166 of 200 sampled Picture ID rows have an ID that
/// ALSO exists in the corpus as a different question shape. Resolving corpus-first
/// therefore served a text question in place of a saved picture question.
/// </summary>
public readonly record struct QuizEntry(string? Ref, string? Set, InlineQuestion? Inline)
{
    public static QuizEntry OfRef(string id) => new(id, null, null);
    public static QuizEntry OfSetRef(string set, string id) => new(id, set, null);
    public static QuizEntry OfInline(InlineQuestion q) => new(null, null, q);
    public bool IsRef => Ref is not null && Set is null;
    public bool IsSetRef => Set is not null;
}

/// <summary>
/// A live-generated MCQ carried inside a quiz, in the corpus.json row shape:
/// [id, prompt, [o0,o1,o2,o3], correctIndex, category, difficulty, explanation,
/// sourceTitle, sourceURL]. Reusing the corpus row is the whole point — every stack
/// already decodes it, so the six implementations cannot drift.
/// </summary>
public sealed record InlineQuestion(
    string Id, string Prompt, IReadOnlyList<string> Options, int CorrectIndex,
    string CategoryId, int Difficulty, string Explanation, string SourceTitle, string SourceUrl)
{
    public static InlineQuestion? FromRow(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Array || row.GetArrayLength() < 9) return null;
        var a = row.EnumerateArray().ToArray();
        if (a[0].ValueKind != JsonValueKind.String || a[1].ValueKind != JsonValueKind.String) return null;
        if (a[2].ValueKind != JsonValueKind.Array || a[2].GetArrayLength() != 4) return null;
        if (a[3].ValueKind != JsonValueKind.Number || a[5].ValueKind != JsonValueKind.Number) return null;
        if (a[4].ValueKind != JsonValueKind.String || a[6].ValueKind != JsonValueKind.String
            || a[7].ValueKind != JsonValueKind.String) return null;
        return new InlineQuestion(
            a[0].GetString()!, a[1].GetString()!,
            a[2].EnumerateArray().Select(o => o.GetString() ?? "").ToList(),
            a[3].GetInt32(), a[4].GetString()!, a[5].GetInt32(),
            a[6].GetString()!, a[7].GetString()!,
            a[8].ValueKind == JsonValueKind.String ? a[8].GetString()! : "");
    }

    public Question ToQuestion() => new()
    {
        Id = Id, Prompt = Prompt, Options = Options.ToList(), CorrectIndex = CorrectIndex,
        CategoryId = CategoryId, Difficulty = Difficulty, Explanation = Explanation,
        SourceTitle = SourceTitle, SourceUrl = SourceUrl,
        TemplateId = Id.Split(':').FirstOrDefault() ?? "live",
    };
}

/// <summary>
/// What a reader got back after resolving refs against the local corpus. Refs go
/// missing legitimately (older build, retired row), so this reports the shortfall
/// instead of hiding it.
/// </summary>
public sealed record QuizResolution(IReadOnlyList<Question> Questions, int Missing)
{
    public bool IsPlayable => Questions.Count >= SavedQuiz.MinimumPlayable;
    public bool IsComplete => Missing == 0;
}

/// <summary>
/// A quiz the player created and kept — the first user-authored object in Tidbits,
/// so it is a wire contract before it is a screen (docs/QUIZ-CONTRACT.md).
///
/// A quiz stores question REFERENCES, not question text: every platform already ships
/// the corpus, so a 20-question quiz is under 1KB and costs nothing to sync, host, or
/// put in a URL. Only live-generated questions (always plain MCQ) travel inline.
///
/// Mirrors Swift SavedQuiz.swift, Kotlin SavedQuiz.kt and JS quiz.js; pinned by
/// tools/quiz-wire/golden/quiz-v1.json.
/// </summary>
public sealed class SavedQuiz
{
    /// Crockford-style, with 0/o, 1/l/i and u removed so an ID read aloud in a pub or
    /// typed off a projector is unambiguous, and a random ID can't spell something
    /// unfortunate. 30 chars: 30^10 ~= 5.9e14.
    public const string IdAlphabet = "23456789abcdefghjkmnpqrstvwxyz";
    public const int IdLength = 10;

    /// Below this a quiz isn't worth playing; above it we play and say so.
    public const int MinimumPlayable = 3;

    public required string Id { get; init; }
    public required string Title { get; set; }
    public required string Topic { get; init; }
    /// Settable because publishing stamps the authenticated uid: the RTDB rules only
    /// let `by === auth.uid` overwrite a quiz, so a locally-created quiz saved as
    /// "local" must carry the real uid once it is shared.
    public required string CreatorId { get; set; }
    public required string CreatorName { get; init; }
    public required long CreatedAtMs { get; init; }
    public required string Mode { get; set; }
    public required List<QuizEntry> Entries { get; set; }

    public int QuestionCount => Entries.Count;

    /// Random, never derived from content: two people who both make a "Jazz" quiz must
    /// get different IDs, and an ID must not leak what is inside it.
    public static string MakeId(Random? rng = null)
    {
        rng ??= Random.Shared;
        var sb = new StringBuilder(IdLength);
        for (int i = 0; i < IdLength; i++) sb.Append(IdAlphabet[rng.Next(IdAlphabet.Length)]);
        return sb.ToString();
    }

    /// Titles ride in share cards and list rows, so they are trimmed and capped rather
    /// than rejected — a long paste should still save.
    public static string CleanTitle(string? raw)
    {
        var t = (raw ?? "").Trim();
        if (t.Length == 0) return "Untitled quiz";
        return t.Length <= 60 ? t : t[..60];
    }

    /// Live Wikipedia generation is the only source that isn't addressable by ID from
    /// a bundled file, so it is the only thing a quiz has to carry inline.
    public static bool IsLiveGenerated(Question q)
        => q.Id.StartsWith("live:") || q.TemplateId == "live";

    /// Which bundled set a question came from, or null for a plain corpus row.
    /// Derived from the question's SHAPE rather than threaded through from the call
    /// site, so it stays correct no matter which surface built the set.
    public static string? BundledSetName(Question q)
    {
        if (q.ImageUrl is not null) return "picture";
        if (q.Closest is not null) return "closest";
        if (q.Ordering is not null) return "order";
        if (q.Matching is not null) return "match";
        if (q.Accepted is not null) return "typeanswer";
        if (q.Enumerate is not null) return "enumerate";
        if (q.Id.StartsWith("tot:")) return "thisorthat";
        if (q.Id.StartsWith("odd:")) return "oddoneout";
        return null;
    }

    public static SavedQuiz From(IEnumerable<Question> questions, string topic, string creatorId,
                                 string creatorName, string? title = null, string mode = "mix",
                                 string? id = null, long? createdAtMs = null) => new()
    {
        Id = id ?? MakeId(),
        Title = CleanTitle(title ?? topic),
        Topic = topic,
        CreatorId = creatorId,
        CreatorName = creatorName,
        CreatedAtMs = createdAtMs ?? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
        Mode = mode,
        Entries = questions.Select(q =>
        {
            if (IsLiveGenerated(q))
                return QuizEntry.OfInline(new InlineQuestion(q.Id, q.Prompt, q.Options, q.CorrectIndex,
                    q.CategoryId, q.Difficulty, q.Explanation, q.SourceTitle, q.SourceUrl ?? ""));
            var set = BundledSetName(q);
            return set is not null ? QuizEntry.OfSetRef(set, q.Id) : QuizEntry.OfRef(q.Id);
        }).ToList(),
    };

    /// Resolve in order, keeping inline questions verbatim. <paramref name="lookup"/>
    /// returns null for an ID this build can't resolve. Never substitutes a different
    /// question — a shared quiz that quietly changes content is worse than one that
    /// admits it is incomplete.
    public QuizResolution Resolve(Func<string, Question?> lookup,
                                  Func<string, string, Question?>? setLookup = null)
    {
        var outQ = new List<Question>();
        int missing = 0;
        foreach (var e in Entries)
        {
            if (e.IsSetRef)
            {
                // Deliberately does NOT fall back to the corpus: the corpus holds a
                // DIFFERENT question under this ID, and serving it would be the silent
                // substitution the contract forbids. Better to be one short.
                var q = setLookup?.Invoke(e.Set!, e.Ref!);
                if (q is not null) outQ.Add(q); else missing++;
            }
            else if (e.IsRef)
            {
                var q = lookup(e.Ref!);
                if (q is not null) outQ.Add(q); else missing++;
            }
            else outQ.Add(e.Inline!.ToQuestion());
        }
        return new QuizResolution(outQ, missing);
    }

    // MARK: Wire codec (docs/QUIZ-CONTRACT.md §2)

    /// Keys are written in SORTED order and slashes/quotes are left unescaped, because
    /// two devices writing the same quiz must produce byte-identical output. Both are
    /// load-bearing for cross-stack identity, not cosmetics: System.Text.Json escapes
    /// an apostrophe to ' by default, so a quiz about "Destiny's Child" would
    /// differ byte-for-byte from every other stack while decoding to the same object.
    private static readonly JsonWriterOptions WriterOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        Indented = false,
    };

    public string ToJson()
    {
        using var stream = new MemoryStream();
        using (var w = new Utf8JsonWriter(stream, WriterOptions))
        {
            w.WriteStartObject();
            w.WriteNumber("at", CreatedAtMs);
            w.WriteString("bn", CreatorName);
            w.WriteString("by", CreatorId);
            w.WriteString("id", Id);
            w.WriteString("m", Mode);
            w.WriteStartArray("qs");
            foreach (var e in Entries)
            {
                if (e.IsSetRef)
                {
                    w.WriteStartObject();          // keys sorted: i before s
                    w.WriteString("i", e.Ref!);
                    w.WriteString("s", e.Set!);
                    w.WriteEndObject();
                    continue;
                }
                if (e.IsRef) { w.WriteStringValue(e.Ref!); continue; }
                var i = e.Inline!;
                w.WriteStartArray();
                w.WriteStringValue(i.Id);
                w.WriteStringValue(i.Prompt);
                w.WriteStartArray();
                foreach (var o in i.Options) w.WriteStringValue(o);
                w.WriteEndArray();
                w.WriteNumberValue(i.CorrectIndex);
                w.WriteStringValue(i.CategoryId);
                w.WriteNumberValue(i.Difficulty);
                w.WriteStringValue(i.Explanation);
                w.WriteStringValue(i.SourceTitle);
                w.WriteStringValue(i.SourceUrl);
                w.WriteEndArray();
            }
            w.WriteEndArray();
            w.WriteString("t", Title);
            w.WriteString("tp", Topic);
            w.WriteNumber("v", 1);
            w.WriteEndObject();
        }
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    /// Lenient by contract: unknown keys are ignored and a malformed entry is skipped
    /// rather than failing the whole quiz, because these objects outlive the app
    /// version that wrote them.
    public static SavedQuiz? FromJson(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            if (!root.TryGetProperty("id", out var idEl) || idEl.ValueKind != JsonValueKind.String) return null;
            var id = idEl.GetString()!;
            if (id.Length == 0) return null;
            if (!root.TryGetProperty("by", out var byEl) || byEl.ValueKind != JsonValueKind.String) return null;
            if (!root.TryGetProperty("qs", out var qsEl) || qsEl.ValueKind != JsonValueKind.Array) return null;

            var entries = new List<QuizEntry>();
            foreach (var raw in qsEl.EnumerateArray())
            {
                if (raw.ValueKind == JsonValueKind.String)
                {
                    var s = raw.GetString()!;
                    if (s.Length > 0) entries.Add(QuizEntry.OfRef(s));
                }
                else if (raw.ValueKind == JsonValueKind.Object)
                {
                    if (raw.TryGetProperty("s", out var setEl) && setEl.ValueKind == JsonValueKind.String
                        && raw.TryGetProperty("i", out var idEl2) && idEl2.ValueKind == JsonValueKind.String)
                    {
                        var set = setEl.GetString()!;
                        var qid = idEl2.GetString()!;
                        if (set.Length > 0 && qid.Length > 0) entries.Add(QuizEntry.OfSetRef(set, qid));
                    }
                }
                else
                {
                    var inline = InlineQuestion.FromRow(raw);
                    if (inline is not null) entries.Add(QuizEntry.OfInline(inline));
                }
            }

            return new SavedQuiz
            {
                Id = id,
                Title = CleanTitle(Str(root, "t")),
                Topic = Str(root, "tp") ?? "",
                CreatorId = byEl.GetString()!,
                CreatorName = Str(root, "bn") ?? "",
                CreatedAtMs = root.TryGetProperty("at", out var at) && at.ValueKind == JsonValueKind.Number
                    ? at.GetInt64() : 0,
                Mode = Str(root, "m") ?? "mix",
                Entries = entries,
            };
        }
        catch (JsonException) { return null; }
    }

    private static string? Str(JsonElement o, string key)
        => o.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
}
