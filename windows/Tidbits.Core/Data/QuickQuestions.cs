using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Tidbits.Core.Models;

namespace Tidbits.Core.Data;

/// SpeedQuizzing "Quick Questions" folders (QUIZ-FORMATS-RESEARCH §1). A
/// quizpack is a FOLDER of files whose NAMES are the questions and whose
/// CONTENTS are the media: `QQ_Who sang this^^_Dolly Parton.mp3` is a
/// name-that-tune question with the clip attached. The Windows twin of the Mac
/// `LiveQuickQuestions`; both suites assert the same filenames.
///
/// The public documentation gives the separator (underscore), the `^^` → `?`
/// substitution, the leading order number (`05 QQ_…`) and the supported
/// extensions; the full help file ships inside the SpeedQuizzing app and is not
/// public. So this reads what is DOCUMENTED and refuses to guess the rest.
public static class QuickQuestions
{
    public static readonly HashSet<string> MediaExtensions =
        new(StringComparer.OrdinalIgnoreCase) { "jpg", "jpeg", "png", "gif", "mp3", "wav", "m4a", "mp4", "mov" };

    private static readonly Regex OrderPrefix = new(@"^\s*(\d{1,3})[\s._-]+", RegexOptions.Compiled);
    private static readonly Regex KindCode = new(@"^QQ[A-Z]{0,3}$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public sealed record Parsed(string Prompt, IReadOnlyList<string> Answers, bool IsPoll, int? Order);

    /// Read one filename. Returns null when it carries no question at all.
    public static Parsed? Parse(string filename)
    {
        var stem = System.IO.Path.GetFileNameWithoutExtension(filename);
        int? order = null;
        var m = OrderPrefix.Match(stem);
        if (m.Success) { order = int.Parse(m.Groups[1].Value); stem = stem[m.Length..]; }
        var fields = stem.Split('_').Select(f => f.Replace("^^", "?").Trim()).ToList();
        var isPoll = false;
        if (fields.Count > 0 && KindCode.IsMatch(fields[0]))
        {
            isPoll = fields[0].StartsWith("QQV", StringComparison.OrdinalIgnoreCase);
            fields.RemoveAt(0);
        }
        fields.RemoveAll(string.IsNullOrEmpty);
        if (fields.Count == 0) return null;
        return new Parsed(fields[0], fields.Skip(1).ToList(), isPoll, order);
    }

    /// Turn a folder's files into questions. `store` puts a media file in the
    /// media store and returns its id (null when it could not be read).
    ///
    /// Every question is a TYPE-IN with each filename answer accepted: the
    /// documented format does not say whether the fields after the first are
    /// alternative spellings or distractors, and accepting a distractor would
    /// mark a wrong player right. Notes say what was skipped.
    public static (List<Question> Questions, List<string> Notes) FromFolder(
        IEnumerable<string> paths, Func<string, string?> store)
    {
        var rows = new List<(int Order, Question Q)>();
        var notes = new List<string>();
        var n = 0;
        foreach (var path in Sorted(paths))
        {
            var name = System.IO.Path.GetFileName(path);
            if (name.StartsWith('.')) continue;
            var ext = System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            if (ext != "txt" && !MediaExtensions.Contains(ext))
            {
                notes.Add($"{name}: not a Quick Question file (.txt, picture, audio or video)");
                continue;
            }
            var p = Parse(name);
            if (p is null) { notes.Add($"{name}: no question in the filename"); continue; }
            if (p.IsPoll) { notes.Add($"{name}: a voting question has no right answer — skipped"); continue; }
            if (p.Answers.Count == 0) { notes.Add($"{name}: no answer after the question — skipped"); continue; }

            string? mediaId = null;
            if (ext != "txt")
            {
                mediaId = store(path);
                if (mediaId is null) notes.Add($"{name}: could not read the media");
            }
            n++;
            var isPicture = ext is "jpg" or "jpeg" or "png" or "gif";
            rows.Add((p.Order ?? n, new Question
            {
                Id = "sq-" + Guid.NewGuid().ToString("N")[..8],
                Prompt = p.Prompt, Options = new[] { p.Answers[0] }, CorrectIndex = 0,
                CategoryId = "mixed", Difficulty = 3, TemplateId = "speedquizzing",
                Accepted = p.Answers.ToList(),
                ImageUrl = mediaId is not null && isPicture ? Networking.LiveMediaStore.Reference(mediaId) : null,
            }));
        }
        return (rows.OrderBy(r => r.Order).Select(r => r.Q).ToList(), notes);
    }

    /// The clip paths, index-parallel with `FromFolder`'s questions, for the
    /// audio/video files among them (LIVE-PACKAGE-FORMAT §3.2).
    public static List<string> ClipPaths(IEnumerable<string> paths, Func<string, string?> store)
    {
        var outList = new List<string>();
        foreach (var path in Sorted(paths))
        {
            var name = System.IO.Path.GetFileName(path);
            if (name.StartsWith('.')) continue;
            var ext = System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            if (ext != "txt" && !MediaExtensions.Contains(ext)) continue;
            var p = Parse(name);
            if (p is null || p.IsPoll || p.Answers.Count == 0) continue;
            var isClip = ext is "mp3" or "wav" or "m4a" or "mp4" or "mov";
            var id = isClip ? store(path) : null;
            outList.Add(id is null ? "" : Networking.LiveMediaStore.FilePath(id) ?? "");
        }
        return outList;
    }

    private static IEnumerable<string> Sorted(IEnumerable<string> paths) =>
        paths.OrderBy(System.IO.Path.GetFileName, StringComparer.OrdinalIgnoreCase);
}
