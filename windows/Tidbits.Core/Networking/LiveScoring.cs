using Tidbits.Core.Models;
using Tidbits.Core.Store;

namespace Tidbits.Core.Networking;

/// Authoritative per-shape scoring of a joiner's LiveRoom.Answer against the host's
/// LOCAL Question (port of LiveNightHost.score/isMCQ/answerLine). Nothing that could
/// leak an answer is ever published; the host scores from its own copy on reveal.
public static class LiveScoring
{
    /// Points for one submission, by question type (partial credit for ordering/
    /// matching/enumerate; proximity for numeric; alias-match for typed; MCQ otherwise).
    public static int Score(Question q, LiveRoom.Answer a, IReadOnlyList<string> shuffledOrder,
                            IReadOnlyList<string> shuffledValues, int mcqPoints)
    {
        if (q.Closest is { } c) return a.Number is { } n ? c.Points(n) : 0;

        if (q.Ordering is { } correctOrder && a.Order is { } order)
        {
            var seq = order.Where(i => i >= 0 && i < shuffledOrder.Count).Select(i => shuffledOrder[i]).ToList();
            int pts = 0;
            for (int i = 0; i < Math.Min(seq.Count, correctOrder.Count); i++)
                if (seq[i] == correctOrder[i]) pts++;   // +1 per correct position
            return pts;
        }

        if (q.Matching is { } m && a.Pairs is { } pairs)
        {
            int pts = 0;
            for (int i = 0; i < m.Keys.Count; i++)
                if (i < pairs.Count && pairs[i] >= 0 && pairs[i] < shuffledValues.Count
                    && shuffledValues[pairs[i]] == m.Values[i]) pts++;   // +1 per correct pairing
            return pts;
        }

        if (q.Accepted is { } accepted && a.Text is { } text)
            return GameEngine.MatchesAccepted(text, accepted) ? mcqPoints : 0;

        if (q.Enumerate is { } e && a.List is { } list)
        {
            var filled = new HashSet<int>();
            foreach (var name in list)
                for (int gi = 0; gi < e.Groups.Count; gi++)
                    if (!filled.Contains(gi) && GameEngine.MatchesAccepted(name, e.Groups[gi])) { filled.Add(gi); break; }
            return filled.Count;   // +1 per unique set member
        }

        return a.Choice == q.CorrectIndex ? mcqPoints : 0;   // MCQ / picture / T-or-T / odd
    }

    /// Option-based types (classic/describe/cloze/oddOneOut/thisOrThat/pictureId).
    public static bool IsMcq(Question q) =>
        q.Closest is null && q.Ordering is null && q.Matching is null && q.Accepted is null && q.Enumerate is null;

    /// The host-facing correct answer to read out on reveal (all types).
    public static string AnswerLine(Question q)
    {
        if (q.Closest is { } c) return c.FormattedAnswer;
        if (q.Accepted is { Count: > 0 } acc) return acc[0];
        if (q.Ordering is { } ord) return string.Join(" → ", ord);
        if (q.Matching is { } m) return string.Join(", ", m.Keys.Zip(m.Values, (k, v) => $"{k} = {v}"));
        if (q.Enumerate is { } e) return string.Join(", ", e.DisplayNames);
        return q.CorrectAnswer;
    }
}
