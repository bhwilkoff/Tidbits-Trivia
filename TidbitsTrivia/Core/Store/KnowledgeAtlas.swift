import Foundation
import SwiftData

/// Feature 4 — Knowledge Atlas (docs/CLUB-FEATURES-BUILD.md). A transparent,
/// interpreted layer over the SAME per-game rows the free Topic Levels / Pie
/// already read (`GameRecord.categoryID/correct/total`, `ProgressMath.domainIDs`)
/// — additive, never a lock on what's already free (R-MON-1). No opaque
/// "mastery score": every number here is a plain count.
///
/// `AnswerDetail` (the per-question record) carries no timestamp of its own,
/// so month-bucketing uses each GAME's date for all of that game's answers —
/// the same granularity the corpus already persists. Trailing 12 months only;
/// older history keeps feeding the free lifetime Pie/Levels but drops out of
/// the Atlas's month math.
@MainActor
enum KnowledgeAtlas {

    /// Below this many answers in a window, a read is withheld rather than
    /// shown noisy — "don't flag a domain with <~8 answers" (design spec).
    static let sampleFloor = 8
    /// A domain counts as "strong" in the decay radar's older window at this
    /// accuracy or higher.
    static let strongThreshold = 0.70
    /// A drop of at least this many accuracy points (0..1 scale) counts as
    /// decaying, both for the per-domain trajectory flag and the radar.
    static let decayDelta = 0.12

    /// One domain's trailing-12-month standing. `recentAccuracy`/`priorAccuracy`
    /// are this-quarter (months 0–2) vs the quarter before (months 3–5); either
    /// is nil below `sampleFloor` — an honest "not enough history yet" rather
    /// than a noisy arrow.
    struct DomainAtlasEntry: Identifiable, Sendable, Hashable {
        let categoryID: String
        let correct: Int
        let total: Int
        let recentAccuracy: Double?
        let priorAccuracy: Double?

        var id: String { categoryID }
        var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
        var sampleSize: Int { total }
        /// Recent-quarter minus prior-quarter accuracy, in points (0..1 scale).
        /// nil when either quarter is too thin to read.
        var trajectoryDelta: Double? {
            guard let r = recentAccuracy, let p = priorAccuracy else { return nil }
            return r - p
        }
        var isDecaying: Bool { (trajectoryDelta ?? 0) <= -KnowledgeAtlas.decayDelta }
    }

    /// A domain that was strong 6+ months ago and has since declined — the
    /// Decay radar's "shore it up" list.
    struct DecayEntry: Identifiable, Sendable, Hashable {
        let categoryID: String
        let pastAccuracy: Double
        let recentAccuracy: Double
        var id: String { categoryID }
        var delta: Double { recentAccuracy - pastAccuracy }
    }

    /// Per-domain trailing-12-month standing, domains you've never played
    /// omitted (same convention as `DomainProgress` for the free Pie/Levels).
    static func domains(in context: ModelContext) -> [DomainAtlasEntry] {
        let rows = trailingYearRows(in: context)
        return ProgressMath.domainIDs.compactMap { domain -> DomainAtlasEntry? in
            let mine = rows.filter { $0.categoryID == domain }
            guard !mine.isEmpty else { return nil }
            let correct = mine.reduce(0) { $0 + $1.correct }
            let total = mine.reduce(0) { $0 + $1.total }
            return DomainAtlasEntry(
                categoryID: domain, correct: correct, total: total,
                recentAccuracy: quarterAccuracy(mine, monthsAgo: 0...2),
                priorAccuracy: quarterAccuracy(mine, monthsAgo: 3...5))
        }
        .sorted { $0.total > $1.total }
    }

    /// Domains strong (≥`strongThreshold`) 6–11 months ago that have since
    /// dropped by ≥`decayDelta` in the last 6 months — both windows honest
    /// about sample size.
    static func decayRadar(in context: ModelContext) -> [DecayEntry] {
        let rows = trailingYearRows(in: context)
        return ProgressMath.domainIDs.compactMap { domain -> DecayEntry? in
            let mine = rows.filter { $0.categoryID == domain }
            guard let past = quarterAccuracy(mine, monthsAgo: 6...11),
                  let recent = quarterAccuracy(mine, monthsAgo: 0...5),
                  past >= strongThreshold, recent <= past - decayDelta else { return nil }
            return DecayEntry(categoryID: domain, pastAccuracy: past, recentAccuracy: recent)
        }
        .sorted { $0.delta < $1.delta }
    }

    /// A genuine strongest + weakest domain for the non-member teaser
    /// (MONETIZATION §4a: "a real preview, never a nag"). nil until the
    /// player has enough history for at least one honest read.
    static func previewLine(in context: ModelContext) -> String? {
        let ds = domains(in: context).filter { $0.total >= 3 }.sorted { $0.accuracy < $1.accuracy }
        guard let weakest = ds.first else { return nil }
        guard let strongest = ds.last, strongest.categoryID != weakest.categoryID else {
            let name = TriviaCategory.named(weakest.categoryID).name
            return "\(Int((weakest.accuracy * 100).rounded()))% in \(name) so far — Club maps every domain across 12 months and shows what's rising or drifting."
        }
        let strongName = TriviaCategory.named(strongest.categoryID).name
        let weakName = TriviaCategory.named(weakest.categoryID).name
        return "\(Int((strongest.accuracy * 100).rounded()))% in \(strongName), \(Int((weakest.accuracy * 100).rounded()))% in \(weakName) — Club maps everything you know and where it's drifting."
    }

    // MARK: - Month bucketing

    private struct Row { let categoryID: String; let correct: Int; let total: Int; let monthsAgo: Int }

    private static func trailingYearRows(in context: ModelContext) -> [Row] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: .now) ?? .distantPast
        let desc = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.date >= cutoff })
        let records = (try? context.fetch(desc)) ?? []
        return records.map { Row(categoryID: $0.categoryID, correct: $0.correct, total: $0.total, monthsAgo: monthsAgo($0.date)) }
    }

    private static func quarterAccuracy(_ rows: [Row], monthsAgo range: ClosedRange<Int>) -> Double? {
        let mine = rows.filter { range.contains($0.monthsAgo) }
        let total = mine.reduce(0) { $0 + $1.total }
        guard total >= sampleFloor else { return nil }
        let correct = mine.reduce(0) { $0 + $1.correct }
        return Double(correct) / Double(total)
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func monthsAgo(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let months = calendar.dateComponents([.month], from: startOfMonth(date, calendar: calendar), to: startOfMonth(now, calendar: calendar)).month ?? 0
        return max(0, months)
    }
}
