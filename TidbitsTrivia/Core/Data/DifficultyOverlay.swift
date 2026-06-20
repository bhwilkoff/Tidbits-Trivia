import Foundation

/// F3 — the derived difficulty overlay (Wikipedia pageviews → 1..5 per subject),
/// loaded from the bundled `difficulty.json`. Additive: the corpus is untouched;
/// the Ladder mode sorts by this and weights its scoring by it. A subject not in
/// the map (or a live-generated question) defaults to 3 (middle).
nonisolated final class DifficultyOverlay: @unchecked Sendable {
    static let shared = DifficultyOverlay()

    private let map: [String: Int]

    init() {
        guard let url = Bundle.main.url(forResource: "difficulty", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dict = root["difficulty"] as? [String: Int] else {
            map = [:]
            return
        }
        map = dict
    }

    /// Difficulty 1 (best-known) … 5 (obscure). `title` is the display title; the
    /// overlay is keyed by the underscored Wikipedia title.
    func difficulty(forTitle title: String) -> Int {
        map[title.replacingOccurrences(of: " ", with: "_")] ?? 3
    }

    func difficulty(for question: Question) -> Int { difficulty(forTitle: question.sourceTitle) }
}
