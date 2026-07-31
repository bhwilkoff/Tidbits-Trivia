import Foundation
import SwiftData

/// Local persistence for saved quizzes (docs/QUIZ-CONTRACT.md §4).
///
/// **Local is the source of truth for your own quizzes.** They must work offline and
/// before sign-in, so nothing here needs an account; sync and sharing layer on top.
///
/// The stored payload is the CONTRACT JSON, not a set of SwiftData columns. That is
/// deliberate: the quiz wire format is already frozen and mirrored on four stacks, so
/// storing anything else here would create a fifth representation to keep in step.
/// The columns that exist are only the ones a list needs to sort and filter without
/// decoding every row.
@Model
final class SavedQuizRecord {
    /// The contract `id` — 10 chars, unique per quiz.
    @Attribute(.unique) var quizID: String = ""
    var title: String = ""
    var topic: String = ""
    var createdAt: Date = Date.distantPast
    /// When the player last played it — nil until they do. Drives "recently played".
    var lastPlayedAt: Date?
    var playCount: Int = 0
    var questionCount: Int = 0
    /// True once published to the shared bucket. A quiz you never share never leaves
    /// your account (QUIZ-CONTRACT §4).
    var isShared: Bool = false
    /// The canonical `quiz.v1` JSON. One representation, four stacks.
    var wireJSON: String = ""

    init(quiz: SavedQuiz) {
        quizID = quiz.id
        apply(quiz)
    }

    func apply(_ quiz: SavedQuiz) {
        title = quiz.title
        topic = quiz.topic
        createdAt = quiz.createdAt
        questionCount = quiz.questionCount
        wireJSON = quiz.jsonData().map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    var quiz: SavedQuiz? {
        SavedQuiz(jsonData: Data(wireJSON.utf8))
    }
}

/// Save / list / delete. Static like `RecordsStore` so views call it with their
/// `@Environment(\.modelContext)` and no store object has to be threaded around.
enum QuizStore {

    /// Insert, or update in place if this quiz ID is already saved. Returns false
    /// only when the quiz can't be encoded at all.
    ///
    /// Saving the same quiz twice is a normal thing to do (replay → save again), so
    /// it must be idempotent rather than creating duplicates.
    @discardableResult
    static func save(_ quiz: SavedQuiz, in context: ModelContext) -> Bool {
        guard quiz.jsonData() != nil else { return false }
        if let existing = record(id: quiz.id, in: context) {
            existing.apply(quiz)
        } else {
            context.insert(SavedQuizRecord(quiz: quiz))
        }
        try? context.save()
        return true
    }

    static func record(id: String, in context: ModelContext) -> SavedQuizRecord? {
        var descriptor = FetchDescriptor<SavedQuizRecord>(
            predicate: #Predicate { $0.quizID == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func quiz(id: String, in context: ModelContext) -> SavedQuiz? {
        record(id: id, in: context)?.quiz
    }

    /// Newest first — a created quiz should be at the top the moment you save it.
    static func all(in context: ModelContext) -> [SavedQuizRecord] {
        let descriptor = FetchDescriptor<SavedQuizRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func recent(in context: ModelContext, limit: Int = 3) -> [SavedQuizRecord] {
        Array(all(in: context).prefix(limit))
    }

    static func count(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SavedQuizRecord>())) ?? 0
    }

    static func delete(id: String, in context: ModelContext) {
        guard let r = record(id: id, in: context) else { return }
        context.delete(r)
        try? context.save()
    }

    /// Record a play. Kept separate from `save` so replaying doesn't rewrite the
    /// quiz payload — the contract's merge guard is "created or deleted, never
    /// edited in place", and play counts are local metadata, not part of the quiz.
    static func markPlayed(id: String, at date: Date = Date(), in context: ModelContext) {
        guard let r = record(id: id, in: context) else { return }
        r.lastPlayedAt = date
        r.playCount += 1
        try? context.save()
    }

    static func markShared(id: String, in context: ModelContext) {
        guard let r = record(id: id, in: context) else { return }
        r.isShared = true
        try? context.save()
    }

    /// Rename. The only field a player can edit after creation — the questions are
    /// fixed, so a shared quiz can never change under someone who already has it.
    static func rename(id: String, to newTitle: String, in context: ModelContext) {
        guard let r = record(id: id, in: context), var q = r.quiz else { return }
        q.title = SavedQuiz.cleanTitle(newTitle)
        r.apply(q)
        try? context.save()
    }
}

// MARK: - Turning a saved quiz back into a playable round

extension SavedQuiz {

    /// Resolve this quiz's refs against everything the app actually ships: the
    /// corpus first, then the bundled shaped sets (Picture ID, Closest Call, …).
    ///
    /// Ordering is preserved, and a ref that resolves nowhere is COUNTED, not
    /// replaced (QUIZ-CONTRACT §1) — a shared quiz that quietly swaps in a
    /// different question is worse than one that admits it is short.
    /// The bundled sets by their contract name. A set-ref names its set precisely
    /// because a bare ID would be ambiguous — these share the corpus `src:` namespace.
    @MainActor
    private static let bundledSets: [String: JSONQuestionSource] = [
        "picture": .picture, "thisorthat": .thisOrThat, "closest": .closestCall,
        "order": .ordering, "match": .matching, "typeanswer": .typeAnswer,
        "oddoneout": .oddOneOut, "enumerate": .enumerate,
    ]

    @MainActor
    func resolveAgainstBundle() -> Resolution {
        // One batched corpus fetch rather than a query per ref: a 20-question quiz
        // would otherwise be 20 round trips through the sqlite queue.
        let refIDs = entries.compactMap { if case .ref(let r) = $0 { return r } else { return nil } }
        var found: [String: Question] = [:]
        for q in CorpusDatabase.shared.questions(ids: refIDs) { found[q.id] = q }
        return resolve(lookup: { found[$0] },
                       setLookup: { set, id in Self.bundledSets[set]?.question(id: id) })
    }
}

// MARK: - Sharing (docs/QUIZ-CONTRACT.md §5)

/// Publishing and fetching a shared quiz. Mirrors the web's `publishQuiz` /
/// `fetchSharedQuiz`, and writes the SAME `quiz.v1` bytes — a quiz shared from an
/// iPhone has to open on the web and on Windows, which is the whole point.
enum QuizSharing {

    /// The canonical link target on every platform. The web app is the one surface
    /// someone without the app can open, so it is what we hand out.
    static func shareURL(for id: String) -> URL? {
        URL(string: "https://tidbitstrivia.com/#/quiz/\(id)")
    }

    /// What a fetch actually came back with. "Gone" and "couldn't load" are
    /// DIFFERENT: telling someone with a working link that the quiz was deleted
    /// stops them retrying something transient.
    enum FetchResult: Sendable {
        case found(SavedQuiz)
        case notFound
        case failed(String)
    }

    /// Publish so anyone with the link can play it. EXPLICIT — a quiz you never
    /// share never leaves your account. The creator is stamped at publish time so
    /// the rules (`by === auth.uid`) let only its author overwrite it later.
    @discardableResult
    static func publish(_ quiz: SavedQuiz, in context: ModelContext) async throws -> URL? {
        let uid = try await FirebaseRTDB.shared.ensureAuth()
        var stamped = quiz
        stamped.creatorID = uid
        guard let json = stamped.jsonData() else { return nil }
        try await FirebaseRTDB.shared.putJSON("quizzes/\(quiz.id)", json)
        QuizStore.markShared(id: quiz.id, in: context)
        return shareURL(for: quiz.id)
    }

    static func fetch(id: String) async -> FetchResult {
        do {
            guard let json = try await FirebaseRTDB.shared.getJSON("quizzes/\(id)") else {
                return .notFound
            }
            guard let quiz = SavedQuiz(jsonData: json) else {
                return .failed("This quiz is in a format this version can’t read.")
            }
            return .found(quiz)
        } catch {
            return .failed("Couldn’t reach the quiz. Check your connection and try again.")
        }
    }
}
