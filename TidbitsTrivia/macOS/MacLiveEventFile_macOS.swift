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
        var rounds: [PortableRound]
    }

    struct PortableRound: Codable {
        var id: String
        var title: String
        var format: String          // GameMode raw value (§2.2)
        var categoryID: String
        var timerSeconds: Int?
        var hostNote: String?
        var isWager: Bool?
        var isSpeed: Bool?
        var isBuzz: Bool?
        var questions: [Question]   // the shared Question shape, verbatim (§2.1)
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
        let doc = Document(
            droppedClipCount: droppedClipCount(in: event),
            event: PortableEvent(
                id: event.id.uuidString,
                name: event.name,
                venue: event.venue,
                createdAt: event.createdAt,
                sponsor: event.sponsor,
                leadCaptureURL: event.leadCaptureURL,
                brandHex: event.brandHex,
                weekday: event.weekday,
                rounds: event.rounds.map { r in
                    PortableRound(id: r.id.uuidString, title: r.title,
                                  format: r.format.rawValue, categoryID: r.categoryID,
                                  timerSeconds: r.timerSeconds, hostNote: r.hostNote,
                                  isWager: r.isWager, isSpeed: r.isSpeed, isBuzz: r.isBuzz,
                                  questions: r.questions)
                }))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(doc)
    }

    // MARK: Import

    static func decode(_ data: Data) throws -> LiveEvent {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let doc = try? dec.decode(Document.self, from: data),
              doc.format == formatIdentifier else { throw FileError.notATidbitsEvent }
        guard doc.version <= formatVersion else { throw FileError.unsupportedVersion(doc.version) }

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
        event.rounds = e.rounds.map { r in
            LiveRound(id: UUID(uuidString: r.id) ?? UUID(),
                      title: r.title,
                      format: GameMode(rawValue: r.format) ?? .classic,
                      categoryID: r.categoryID,
                      questions: r.questions,
                      timerSeconds: r.timerSeconds,
                      hostNote: r.hostNote,
                      isWager: r.isWager,
                      isSpeed: r.isSpeed,
                      isBuzz: r.isBuzz)
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
