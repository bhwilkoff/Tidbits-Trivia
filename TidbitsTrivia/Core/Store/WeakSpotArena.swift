import Foundation
import SwiftData

/// Builds the Club-only Weak-Spot Arena round entirely from the player's own
/// miss history — the deeper layer above the free spaced-review weave
/// (`RecordsStore.dueReview`, PARITY row 214). Transparent by construction:
/// every question carries a plain-language reason so the round never reads
/// as an opaque model (docs/CLUB-FEATURES-BUILD.md "Feature 1").
@MainActor
enum WeakSpotArena {

    static let roundSize = 10
    /// Below this many true misses, the round is topped up from weak domains.
    static let trueMissFloor = 4
    /// Target size when topping up with domain-fill (not the full 10 — a
    /// round mostly built from "shoring up X" stops being a *weak-spot* arena).
    static let fillTarget = 8

    /// Build one round. Never throws; an empty/thin history just yields a
    /// short (possibly empty) round — the caller shows the "play a few
    /// rounds first" empty state below the floor.
    static func build(in context: ModelContext) -> WeakSpotRound {
        var desc = FetchDescriptor<MissedFact>(
            predicate: #Predicate { !$0.resolved },
            sortBy: [SortDescriptor(\.missCount, order: .reverse),
                     SortDescriptor(\.lastSeen, order: .forward)])
        desc.fetchLimit = roundSize * 3
        let facts = (try? context.fetch(desc)) ?? []

        var questions: [Question] = []
        var reasons: [String: String] = [:]
        var pickedIDs = Set<String>()

        for fact in facts {
            guard questions.count < roundSize, let q = fact.question, !pickedIDs.contains(q.id) else { continue }
            questions.append(q)
            pickedIDs.insert(q.id)
            reasons[q.id] = "Missed \(relative(fact.lastSeen)) · ×\(fact.missCount)"
        }
        let trueMissCount = questions.count

        if trueMissCount < trueMissFloor {
            let records = (try? context.fetch(FetchDescriptor<GameRecord>())) ?? []
            let weakestDomains = DomainProgress.summarize(records.map { ($0.categoryID, $0.correct, $0.total) })
                .filter { $0.total >= 3 }
                .sorted { $0.accuracy < $1.accuracy }
            for domain in weakestDomains {
                guard questions.count < fillTarget else { break }
                let pool = CorpusDatabase.shared.questions(
                    categoryID: domain.categoryID, excluding: pickedIDs, limit: fillTarget - questions.count)
                for q in pool where questions.count < fillTarget {
                    questions.append(q)
                    pickedIDs.insert(q.id)
                    reasons[q.id] = "Shoring up \(TriviaCategory.named(domain.categoryID).name)"
                }
            }
        }

        return WeakSpotRound(questions: questions, reasons: reasons, missCount: trueMissCount)
    }

    /// A single genuine sample for the non-member preview on Home — the
    /// oldest-standing / most-missed fact, so the pitch is never a stock line
    /// (MONETIZATION §4a: "a real preview, never a nag").
    static func previewLine(in context: ModelContext) -> String? {
        var desc = FetchDescriptor<MissedFact>(
            predicate: #Predicate { !$0.resolved },
            sortBy: [SortDescriptor(\.missCount, order: .reverse)])
        desc.fetchLimit = 1
        guard let fact = (try? context.fetch(desc))?.first else { return nil }
        return "Missed: \u{201C}\(fact.prompt)\u{201D} — Club turns misses like this into a round."
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

/// One generated Weak-Spot round: the questions, a why-you're-seeing-this
/// reason per question ID, and how many are true misses (vs. domain-fill) —
/// the count shown before play so the round stays honest about its make-up.
struct WeakSpotRound: Sendable {
    let questions: [Question]
    let reasons: [String: String]
    let missCount: Int
}
