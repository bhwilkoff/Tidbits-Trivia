#if os(macOS)
import Foundation

// MARK: - The event document (macOS-DESIGN §A2.5)

/// A saved Tidbits Live event as ONE self-describing JSON file.
///
/// It is deliberately versioned and self-describing so the Windows build can read
/// and write the same shape (WINDOWS-DESIGN §6.7) — a host moves a night between
/// their Mac and their Windows box, or hands it to a co-host, and it opens.
///
/// Security-scoped bookmarks are NOT portable, so the AV clip references are
/// dropped on export and the file records how many were dropped; the round still
/// arrives with all of its questions and the host re-attaches the clips. Writing
/// a bookmark that resolves to nothing on another machine would be worse: the
/// round would look complete and play silent.
enum LiveEventFile {
    static let formatVersion = 1
    static let formatIdentifier = "com.learningischange.tidbits.live-event"

    struct Document: Codable {
        var format: String = LiveEventFile.formatIdentifier
        var version: Int = LiveEventFile.formatVersion
        var exportedAt: Date = .now
        var app: String = "Tidbits Trivia (macOS)"
        /// Clips dropped on export, so an importing host is told rather than
        /// discovering it mid-night.
        var droppedClipCount: Int = 0
        var event: LiveEvent
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

    /// Strip what cannot cross machines, and count it.
    static func portable(_ event: LiveEvent) -> (event: LiveEvent, dropped: Int) {
        var ev = event
        var dropped = 0
        for i in ev.rounds.indices {
            dropped += (ev.rounds[i].audioBookmarks?.filter { !$0.isEmpty }.count ?? 0)
            dropped += (ev.rounds[i].videoBookmarks?.filter { !$0.isEmpty }.count ?? 0)
            ev.rounds[i].audioBookmarks = nil
            ev.rounds[i].videoBookmarks = nil
        }
        return (ev, dropped)
    }

    static func encode(_ event: LiveEvent) throws -> Data {
        let (ev, dropped) = portable(event)
        let doc = Document(droppedClipCount: dropped, event: ev)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(doc)
    }

    static func decode(_ data: Data) throws -> LiveEvent {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let doc = try? dec.decode(Document.self, from: data),
              doc.format == formatIdentifier else { throw FileError.notATidbitsEvent }
        guard doc.version <= formatVersion else { throw FileError.unsupportedVersion(doc.version) }
        var ev = doc.event
        // A fresh id: importing a co-host's copy must ADD a night, never silently
        // overwrite the one you already have under the same id.
        ev.id = UUID()
        return ev
    }

    static func write(_ event: LiveEvent, to url: URL) throws {
        try encode(event).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> LiveEvent {
        try decode(try Data(contentsOf: url))
    }
}
#endif
