namespace Tidbits.Core.Engine;

/// The canonical cross-platform Daily selection (Decision 037, DATA-CONTRACT
/// §Daily). Every id gets rank = FNV-1a64("daily:<day>:<categoryID>:<id>"); the
/// day's set is the `count` smallest ranks in ascending rank order; ties (a
/// 64-bit collision, effectively unreachable) break on the id's UTF-8 byte order.
/// Order-independent BY DESIGN — no RNG, no shuffle. Byte-exact with the Kotlin/JS
/// mirrors (proven by tools/daily-parity/run.sh). Change the rank string in ALL
/// mirrors at once.
public static class DailyPick
{
    public static ulong Rank(string day, string categoryId, string id) =>
        StableSeed.Of($"daily:{day}:{categoryId}:{id}");

    /// The Daily question-set VERSION. Two players on different versions answer
    /// DIFFERENT QUESTIONS, so one board cannot rank them together — and the
    /// 7-char marks string is aligned to this pick's ORDER, so a silent change
    /// also mis-indexes every per-question percentage published. Decision 050.
    public const int SetV1 = 1;
    public const int SetV2 = 2;

    /// v2 applies from this day and never retroactively: an archived day keeps
    /// resolving to the set it was actually played with.
    public const string V2From = "2026-09-01";

    public static int SetVersion(string day) =>
        string.CompareOrdinal(day, V2From) >= 0 ? SetV2 : SetV1;

    /// Spread the day's set across categories instead of drawing uniformly, so a
    /// corpus that is 29% Film and TV does not make 15% of Dailies four-of-seven
    /// one category. Same FNV ranking — which question a category contributes is
    /// unchanged — then the best unused id from each category in turn, with the
    /// category ORDER itself hashed from the day. Byte-exact with
    /// DailyPick.pickBalanced (Swift), pickDailyBalanced (JS),
    /// pickDailyBalancedIds (Kotlin) and pick_daily_balanced (the cron).
    public static IReadOnlyList<string> PickBalanced(
        IReadOnlyList<string> ids, IReadOnlyList<string> cats,
        string day, string categoryId, int count)
    {
        var ranked = Enumerable.Range(0, ids.Count)
            .Select(i => (id: ids[i], cat: cats[i], rank: Rank(day, categoryId, ids[i])))
            .OrderBy(t => t.rank)
            .ThenBy(t => t.id, Utf8Ordinal.Instance)
            .ToList();

        var byCat = new Dictionary<string, List<string>>();
        foreach (var t in ranked)
        {
            if (!byCat.TryGetValue(t.cat, out var bucket))
            {
                bucket = new List<string>();
                byCat[t.cat] = bucket;
            }
            bucket.Add(t.id);
        }

        var order = byCat.Keys
            .OrderBy(c => StableSeed.Of($"dailycat:{day}:{c}"))
            .ThenBy(c => c, Utf8Ordinal.Instance)
            .ToList();

        var outIds = new List<string>();
        for (var round = 0; outIds.Count < count; round++)
        {
            var progressed = false;
            foreach (var c in order)
            {
                var bucket = byCat[c];
                if (round >= bucket.Count) continue;
                outIds.Add(bucket[round]);
                progressed = true;
                if (outIds.Count == count) break;
            }
            if (!progressed) break;          // fewer ids than `count`
        }
        return outIds;
    }

    public static IReadOnlyList<string> Pick(IReadOnlyList<string> ids, string day, string categoryId, int count) =>
        ids.Select(id => (id, rank: Rank(day, categoryId, id)))
           .OrderBy(t => t.rank)
           .ThenBy(t => t.id, Utf8Ordinal.Instance)
           .Take(count)
           .Select(t => t.id)
           .ToList();
}
