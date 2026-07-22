import Foundation
import SwiftData

/// The Club Story Archive's read side (docs/CLUB-FEATURES-BUILD.md "Feature
/// 2") — a plain, transparent view over `SeenStory`. No ranking model: search
/// is substring match, filters are simple predicates, exactly like
/// Weak-Spot's reason strings stayed honest about their own make-up.
@MainActor
enum StoryArchive {

    /// A genuine one-line sample from the player's own archive for the
    /// non-member preview (MONETIZATION §4a: "a real preview, never a nag") —
    /// the most recently met story. nil once the player has no history yet.
    static func previewLine(in context: ModelContext) -> String? {
        var desc = FetchDescriptor<SeenStory>(sortBy: [SortDescriptor(\.lastSeen, order: .reverse)])
        desc.fetchLimit = 1
        guard let story = (try? context.fetch(desc))?.first else { return nil }
        return "\u{201C}\(story.story)\u{201D} — Club keeps every story you unlock, searchable forever."
    }

    /// Total distinct stories collected — the member-facing subtitle.
    static func count(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SeenStory>())) ?? 0
    }

    static func toggleFavorite(qid: String, in context: ModelContext) {
        let desc = FetchDescriptor<SeenStory>(predicate: #Predicate { $0.questionID == qid })
        guard let story = try? context.fetch(desc).first else { return }
        story.favorite.toggle()
        try? context.save()
    }

    /// Transparent client-side search + filter over an already-fetched,
    /// most-recent-first list — no opaque model, just what's on the card.
    static func search(_ stories: [SeenStory], text: String, domain: String?, filter: StoryFilter) -> [SeenStory] {
        var results = stories
        if let domain { results = results.filter { $0.categoryID == domain } }
        switch filter {
        case .all:        break
        case .favorites:  results = results.filter(\.favorite)
        case .missed:     results = results.filter { !$0.everCorrect }
        case .mastered:   results = results.filter(\.everCorrect)
        }
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return results }
        return results.filter {
            $0.prompt.localizedCaseInsensitiveContains(q)
                || $0.correctAnswer.localizedCaseInsensitiveContains(q)
                || $0.story.localizedCaseInsensitiveContains(q)
        }
    }
}

/// The archive's plain filter set (favorited / missed / mastered), alongside
/// domain + free-text search.
enum StoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, favorites, missed, mastered
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "All"
        case .favorites: return "Favorites"
        case .missed:    return "Missed"
        case .mastered:  return "Got it"
        }
    }
}
