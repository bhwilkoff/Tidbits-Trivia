import Foundation

/// The canonical cross-platform Daily selection (Decision 037,
/// docs/DATA-CONTRACT.md §Daily): every question id gets a rank
/// `FNV-1a64(UTF-8 "daily:<day>:<categoryId>:<id>")`; the day's set is the
/// `count` smallest ranks, presented in ascending rank order.
///
/// Order-independent BY DESIGN: no RNG, no shuffle, no dependence on how a
/// platform stores or sorts its corpus — the previous per-platform seeded
/// shuffles could never agree (different shuffle algorithms, different pools,
/// different seed strings; the owner caught the sets diverging, 2026-07-01).
/// Identical sets require only (a) the identical id set, which
/// tools/night-wire/check_id_parity.py already guards, and (b) this exact
/// rank function, which tools/daily-parity/run.sh proves against the Kotlin
/// and JS mirrors. Change any part of the rank string in ALL THREE mirrors
/// at once, then re-run both checks.
enum DailyPick {

    static func rank(day: String, categoryID: String, id: String) -> UInt64 {
        "daily:\(day):\(categoryID):\(id)".stableSeed
    }

    /// The Daily question-set VERSION. Two players on different versions answer
    /// DIFFERENT QUESTIONS, so ranking them on one board is meaningless — and the
    /// 7-char marks string is aligned to this pick's ORDER, so a silent change
    /// also mis-indexes every per-question percentage the board publishes. The
    /// version therefore rides the wire; see Decision 050.
    nonisolated static let setV1 = 1
    nonisolated static let setV2 = 2

    /// v2 applies from this day and never retroactively: yesterday's board must
    /// keep resolving to the set it was actually played with.
    nonisolated static let v2From = "2026-09-01"

    nonisolated static func setVersion(for day: String) -> Int { day >= v2From ? setV2 : setV1 }

    /// Spread the day's set across categories instead of drawing uniformly.
    /// Byte-identical to `pickDailyBalanced` in js/engine.js and
    /// `pick_daily_balanced` in tools/aggregate_dailyboard.py.
    static func pickBalanced(ids: [(id: String, category: String)], day: String,
                             categoryID: String, count: Int) -> [String] {
        let ranked = ids
            .map { (id: $0.id, category: $0.category,
                    rank: rank(day: day, categoryID: categoryID, id: $0.id)) }
            .sorted {
                $0.rank != $1.rank ? $0.rank < $1.rank
                                   : $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
            }
        var byCat: [String: [String]] = [:]
        for r in ranked { byCat[r.category, default: []].append(r.id) }

        // The category ORDER is hashed from the day too, so no category is
        // permanently first while the result stays deterministic.
        let order = byCat.keys.sorted { a, b in
            let ha = "dailycat:\(day):\(a)".stableSeed, hb = "dailycat:\(day):\(b)".stableSeed
            return ha != hb ? ha < hb : a.utf8.lexicographicallyPrecedes(b.utf8)
        }

        var out: [String] = []
        var round = 0
        while out.count < count {
            var progressed = false
            for c in order {
                guard let bucket = byCat[c], round < bucket.count else { continue }
                out.append(bucket[round])
                progressed = true
                if out.count == count { break }
            }
            if !progressed { break }        // fewer ids than `count`
            round += 1
        }
        return out
    }

    /// Ties (a 64-bit collision, effectively unreachable) break on the id's
    /// UTF-8 byte order so the result stays total and platform-agnostic.
    static func pick(ids: [String], day: String, categoryID: String, count: Int) -> [String] {
        ids.map { (id: $0, rank: rank(day: day, categoryID: categoryID, id: $0)) }
            .sorted {
                $0.rank != $1.rank ? $0.rank < $1.rank
                                   : $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
            }
            .prefix(count)
            .map(\.id)
    }
}
