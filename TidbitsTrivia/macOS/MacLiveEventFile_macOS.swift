#if os(macOS)
import Foundation

// MARK: - The portable event document (macOS-DESIGN §A2.5, docs/LIVE-EVENT-FILE.md)

/// A saved Tidbits Live event as ONE self-describing JSON file.
///
/// This is deliberately NOT `LiveEvent`'s own `Codable` output. Windows keeps a
/// round as `NightRound {kind, count}` plus index-aligned side arrays — because
/// `NightRound` is the wire type published to every joiner and Apple pins its
/// `CodingKeys` to `{kind, count}` with golden coverage on it — while macOS
/// keeps `{title, format, categoryID, questions}`. Exporting either internal
/// shape would produce a file the other side cannot read, and would bake one
/// platform's storage decisions into a user's document. Both write the contract
/// in `docs/LIVE-EVENT-FILE.md` instead, so a host moves a night between their
/// Mac and their Windows box and it opens.
enum LiveEventFile {
    static let formatVersion = 1
    static let formatIdentifier = "com.learningischange.tidbits.live-event"

    // MARK: The contract types (§1, §2)

    struct Document: Codable {
        var format: String = LiveEventFile.formatIdentifier
        var version: Int = LiveEventFile.formatVersion
        var exportedAt: Date = .now
        var app: String = "Tidbits Trivia (macOS)"
        /// Clips that could NOT travel (§3), so an importing host is told at import
        /// time rather than finding out mid-night.
        var droppedClipCount: Int = 0
        var event: PortableEvent
    }

    struct PortableEvent: Codable {
        var id: String
        var name: String
        var venue: String
        var createdAt: Date
        var sponsor: String
        var leadCaptureURL: String
        var brandHex: String
        var weekday: Int?
        var joker: Bool?            // A2.14: tables play a joker (absent = no)
        var rounds: [PortableRound]
    }

    struct PortableRound: Codable {
        var id: String
        var title: String
        var format: String          // GameMode raw value (§2.2)
        var categoryID: String
        var timerSeconds: Int?
        var points: Int?            // A2.11: points per correct for the round (absent = the night's setting)
        var hostNote: String?
        var isWager: Bool?
        var isSpeed: Bool?
        var isBuzz: Bool?
        var questions: [Question]   // the shared Question shape, verbatim (§2.1)
        /// LIVE-PACKAGE-FORMAT §3.2: one media id per question (null = none). Only a
        /// PACKAGE writes these; the bare document leaves them absent, because a
        /// bookmark cannot travel and an id without its file is a broken promise.
        var audio: [String?]?
        var video: [String?]?
        /// §2.6: per-question overrides (index-parallel; null = the round default).
        var questionTimers: [Int?]?
        var questionPoints: [Int?]?
        var questionNotes: [String?]?
        var questionPolls: [Bool?]?
    }

    enum FileError: LocalizedError {
        case notATidbitsEvent
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notATidbitsEvent:
                return "That file is not a Tidbits Live event."
            case .unsupportedVersion(let v):
                return "That event was saved by a newer version of Tidbits (format \(v)). Update Tidbits to open it."
            }
        }
    }

    static func suggestedFilename(for event: LiveEvent) -> String {
        let base = event.name.trimmingCharacters(in: .whitespaces)
        let safe = base.isEmpty ? "Tidbits Event" : base
        return safe.replacingOccurrences(of: "/", with: "-") + ".tidbitsevent.json"
    }

    // MARK: Export

    /// Strip what cannot cross machines (§3.1), and count it. Writing a
    /// security-scoped bookmark that resolves to nothing on another machine would
    /// make a round look complete and play SILENT — strictly worse than an empty
    /// clip slot the host can see and re-fill.
    static func droppedClipCount(in event: LiveEvent) -> Int {
        event.rounds.reduce(0) { total, round in
            total
                + (round.audioBookmarks?.filter { !$0.isEmpty }.count ?? 0)
                + (round.videoBookmarks?.filter { !$0.isEmpty }.count ?? 0)
        }
    }

    static func encode(_ event: LiveEvent) throws -> Data {
        try encode(document(for: event, droppedClipCount: droppedClipCount(in: event)))
    }

    static func encode(_ doc: Document) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(doc)
    }

    /// The document for an event. Split from `encode` so the package writer can
    /// add its media ids to the same document before it is serialized.
    static func document(for event: LiveEvent, droppedClipCount: Int) -> Document {
        Document(
            droppedClipCount: droppedClipCount,
            event: PortableEvent(
                id: event.id.uuidString,
                name: event.name,
                venue: event.venue,
                createdAt: event.createdAt,
                sponsor: event.sponsor,
                leadCaptureURL: event.leadCaptureURL,
                brandHex: event.brandHex,
                weekday: event.weekday,
                joker: event.joker == true ? true : nil,
                rounds: event.rounds.map { r in
                    PortableRound(id: r.id.uuidString, title: r.title,
                                  format: r.format.rawValue, categoryID: r.categoryID,
                                  timerSeconds: r.timerSeconds, points: (r.points ?? 0) > 0 ? r.points : nil, hostNote: r.hostNote,
                                  isWager: r.isWager, isSpeed: r.isSpeed, isBuzz: r.isBuzz,
                                  questions: r.questions,
                                  questionTimers: r.questionTimers.map { $0.map { $0 > 0 ? $0 : nil } },
                                  questionPoints: r.questionPoints.map { $0.map { $0 > 0 ? $0 : nil } },
                                  questionNotes: r.questionNotes.map { $0.map { $0.isEmpty ? nil : $0 } },
                                  questionPolls: r.questionPolls.map { $0.map { $0 ? true : nil } })
                }))
    }

    // MARK: Import

    static func decode(_ data: Data) throws -> LiveEvent {
        event(from: try decodeDocument(data))
    }

    static func decodeDocument(_ data: Data) throws -> Document {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let doc = try? dec.decode(Document.self, from: data),
              doc.format == formatIdentifier else { throw FileError.notATidbitsEvent }
        guard doc.version <= formatVersion else { throw FileError.unsupportedVersion(doc.version) }
        return doc
    }

    /// The event for a document. Media ids on the rounds are NOT resolved here —
    /// that is the package importer's job, because only it has the files.
    static func event(from doc: Document) -> LiveEvent {
        let e = doc.event
        var event = LiveEvent(name: e.name, venue: e.venue)
        // §2.3: a NEW id, so importing a co-host's copy ADDS a night instead of
        // silently overwriting one you already have under the same id.
        event.id = UUID()
        event.createdAt = e.createdAt
        event.sponsor = e.sponsor
        event.leadCaptureURL = e.leadCaptureURL
        event.brandHex = e.brandHex
        event.weekday = e.weekday
        event.joker = e.joker == true ? true : nil
        event.rounds = e.rounds.map { r in
            var round = LiveRound(id: UUID(uuidString: r.id) ?? UUID(),
                                  title: r.title,
                                  format: GameMode(rawValue: r.format) ?? .classic,
                                  categoryID: r.categoryID,
                                  questions: r.questions,
                                  timerSeconds: r.timerSeconds,
                                  points: (r.points ?? 0) > 0 ? r.points : nil,
                                  hostNote: r.hostNote,
                                  isWager: r.isWager,
                                  isSpeed: r.isSpeed,
                                  isBuzz: r.isBuzz)
            round.questionTimers = r.questionTimers.flatMap { t in t.contains { ($0 ?? 0) > 0 } ? t.map { $0 ?? 0 } : nil }
            round.questionPoints = r.questionPoints.flatMap { t in t.contains { ($0 ?? 0) > 0 } ? t.map { $0 ?? 0 } : nil }
            round.questionNotes = r.questionNotes.flatMap { t in t.contains { !($0 ?? "").isEmpty } ? t.map { $0 ?? "" } : nil }
            round.questionPolls = r.questionPolls.flatMap { t in t.contains { $0 == true } ? t.map { $0 ?? false } : nil }
            return round
        }
        return event
    }

    static func write(_ event: LiveEvent, to url: URL) throws {
        try encode(event).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> LiveEvent {
        try decode(try Data(contentsOf: url))
    }
}
#endif
