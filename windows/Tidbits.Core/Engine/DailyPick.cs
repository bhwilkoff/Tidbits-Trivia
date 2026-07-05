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

    public static IReadOnlyList<string> Pick(IReadOnlyList<string> ids, string day, string categoryId, int count) =>
        ids.Select(id => (id, rank: Rank(day, categoryId, id)))
           .OrderBy(t => t.rank)
           .ThenBy(t => t.id, Utf8Ordinal.Instance)
           .Take(count)
           .Select(t => t.id)
           .ToList();
}
