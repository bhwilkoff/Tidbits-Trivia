#if os(macOS)
import Foundation

// MARK: - The Tidbits package (docs/LIVE-PACKAGE-FORMAT.md)

/// A night with its media in one `.tidbits` file: a zip with a `mimetype`
/// signature, a manifest listing every media file by SHA-256, the unchanged
/// LIVE-EVENT-FILE document, and the files under `media/`.
///
/// Import copies media into `LiveMediaStore` and turns a round's clip ids into
/// the bookmarks the cockpit already plays; export does the reverse. Nothing is
/// stripped by design: carrying the clips is the point (Decision 059).
enum LivePackage {
    static let formatIdentifier = "com.learningischange.tidbits.package"
    static let formatVersion = 1
    static let mimetype = "application/vnd.learningischange.tidbits+zip"
    static let fileExtension = "tidbits"

    struct MediaEntry: Codable, Sendable {
        var id: String
        var path: String
        var sha256: String
        var bytes: Int
        var mime: String
        var kind: String
        var originalName: String?
        var sourceURL: String?
        var credit: String?
        var license: String?
    }

    struct Manifest: Codable, Sendable {
        var format: String = LivePackage.formatIdentifier
        var version: Int = LivePackage.formatVersion
        var kind: String = "event"
        var title: String = ""
        var createdAt: String = ""
        var createdBy: String = ""
        var media: [MediaEntry] = []
    }

    struct Contents {
        var manifest: Manifest
        var document: LiveEventFile.Document
        var media: [String: Data]   // id -> bytes
    }

    enum PackageError: LocalizedError {
        case notAPackage
        case unsupportedVersion(Int)
        case missingMedia(String)
        case hashMismatch(String)
        case notAnEvent

        var errorDescription: String? {
            switch self {
            case .notAPackage: return "That file is not a Tidbits package."
            case .unsupportedVersion(let v): return "That package was saved by a newer version of Tidbits (format \(v)). Update Tidbits to open it."
            case .missingMedia(let n): return "The package is missing a media file it lists: \(n)."
            case .hashMismatch(let n): return "A media file in the package does not match its checksum: \(n)."
            case .notAnEvent: return "The package's event document is not a Tidbits Live event."
            }
        }
    }

    static func suggestedFilename(for event: LiveEvent) -> String {
        let base = event.name.trimmingCharacters(in: .whitespaces)
        let safe = (base.isEmpty ? "Tidbits Event" : base).replacingOccurrences(of: "/", with: "-")
        return safe + "." + fileExtension
    }

    static func isPackage(_ url: URL) -> Bool { url.pathExtension.lowercased() == fileExtension }

    // MARK: Reading

    static func read(_ data: Data) throws -> Contents {
        let files: [String: Data]
        do { files = try ZipContainer.readAll(data) } catch { throw PackageError.notAPackage }
        guard let mt = files["mimetype"],
              String(decoding: mt, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == mimetype,
              let mdata = files["manifest.json"], let edata = files["event.json"] else { throw PackageError.notAPackage }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: mdata),
              manifest.format == formatIdentifier else { throw PackageError.notAPackage }
        guard manifest.version <= formatVersion else { throw PackageError.unsupportedVersion(manifest.version) }
        let doc: LiveEventFile.Document
        do { doc = try LiveEventFile.decodeDocument(edata) } catch { throw PackageError.notAnEvent }
        var media: [String: Data] = [:]
        for e in manifest.media {
            guard let bytes = files[e.path] else { throw PackageError.missingMedia(e.originalName ?? e.path) }
            guard LiveMediaStore.sha256Hex(bytes) == e.sha256 else { throw PackageError.hashMismatch(e.originalName ?? e.path) }
            media[e.id] = bytes
        }
        return Contents(manifest: manifest, document: doc, media: media)
    }

    /// Open a package INTO the app: media into the store, clip ids into bookmarks.
    /// Returns the event and the clips that could not be attached (by name).
    static func importIntoStore(_ data: Data) throws -> (event: LiveEvent, problems: [String]) {
        let c = try read(data)
        var problems: [String] = []
        for e in c.manifest.media {
            guard let bytes = c.media[e.id] else { continue }
            let ext = (e.path as NSString).pathExtension
            do {
                try LiveMediaStore.store(bytes, ext: ext, originalName: e.originalName,
                                         sourceURL: e.sourceURL, credit: e.credit, license: e.license)
            } catch { problems.append(error.localizedDescription) }
        }
        var event = LiveEventFile.event(from: c.document)
        for (ri, pr) in c.document.event.rounds.enumerated() where event.rounds.indices.contains(ri) {
            if let ids = pr.audio {
                let (marks, bad) = bookmarks(for: ids, in: pr.title, kind: "audio")
                if marks.contains(where: { !$0.isEmpty }) { event.rounds[ri].audioBookmarks = marks }
                problems += bad
            }
            if let ids = pr.video {
                let (marks, bad) = bookmarks(for: ids, in: pr.title, kind: "video")
                if marks.contains(where: { !$0.isEmpty }) { event.rounds[ri].videoBookmarks = marks }
                problems += bad
            }
        }
        return (event, problems)
    }

    private static func bookmarks(for ids: [String?], in round: String, kind: String) -> ([Data], [String]) {
        var marks: [Data] = [], problems: [String] = []
        for (i, raw) in ids.enumerated() {
            // §3.2 says a bare id; a `tidbits-media:` prefix is tolerated.
            let id = raw.map { $0.hasPrefix(LiveMediaStore.scheme + ":") ? String($0.dropFirst(LiveMediaStore.scheme.count + 1)) : $0 }
            guard let id, let url = LiveMediaStore.fileURL(id) else { marks.append(Data()); continue }
            do { marks.append(try LiveClip.bookmark(for: url)) }
            catch {
                marks.append(Data())
                problems.append("\(round) \(kind) #\(i + 1): \(error.localizedDescription)")
            }
        }
        return (marks, problems)
    }

    // MARK: Writing

    /// Build a package from an event: pictures already in the store travel by id,
    /// clips are read through their bookmarks, https pictures stay URLs (§3.3).
    /// Returns the bytes and the names of clips that could NOT be read.
    static func export(_ event: LiveEvent, createdBy: String, kind: String = "event") throws -> (data: Data, dropped: [String]) {
        var doc = LiveEventFile.document(for: event, droppedClipCount: 0)
        var media: [String: (bytes: Data, entry: MediaEntry)] = [:]
        var dropped: [String] = []
        let index = LiveMediaStore.loadIndex()

        func add(_ bytes: Data, ext: String, originalName: String?, sourceURL: String?, credit: String?, license: String?) -> String? {
            let e = LiveMediaStore.normalizedExt(ext)
            guard let kind = LiveMediaStore.allowed[e] else { return nil }
            let sha = LiveMediaStore.sha256Hex(bytes)
            let id = String(sha.prefix(32))
            if media[id] == nil {
                media[id] = (bytes, MediaEntry(id: id, path: "media/\(id).\(e)", sha256: sha, bytes: bytes.count,
                                               mime: kind.mime, kind: kind.kind, originalName: originalName,
                                               sourceURL: sourceURL, credit: credit, license: license))
            }
            return id
        }
        func addStoreFile(_ id: String) -> String? {
            guard let url = LiveMediaStore.fileURL(id), let bytes = try? Data(contentsOf: url) else { return nil }
            let info = index[id]
            return add(bytes, ext: url.pathExtension, originalName: info?.originalName, sourceURL: info?.sourceURL,
                       credit: info?.credit, license: info?.license)
        }
        func addClips(_ marks: [Data]?, round: String, kind: String) -> [String?]? {
            guard let marks, marks.contains(where: { !$0.isEmpty }) else { return nil }
            return marks.enumerated().map { i, mark -> String? in
                guard !mark.isEmpty else { return nil }
                guard let url = try? LiveClip.resolve(mark) else {
                    dropped.append("\(round) \(kind) #\(i + 1)"); return nil
                }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let bytes = try? Data(contentsOf: url),
                      let id = add(bytes, ext: url.pathExtension, originalName: url.lastPathComponent,
                                   sourceURL: nil, credit: nil, license: nil) else {
                    dropped.append("\(round) \(kind) #\(i + 1) (\(url.lastPathComponent))"); return nil
                }
                return id
            }
        }

        for (ri, round) in event.rounds.enumerated() {
            for (qi, q) in round.questions.enumerated() {
                if let u = q.imageURL, let id = LiveMediaStore.id(from: u) {
                    if addStoreFile(id) == nil {
                        dropped.append("\(round.title) picture #\(qi + 1)")
                        var stripped = q; stripped.imageURL = nil
                        doc.event.rounds[ri].questions[qi] = stripped
                    }
                }
            }
            doc.event.rounds[ri].audio = addClips(round.audioBookmarks, round: round.title, kind: "audio")
            doc.event.rounds[ri].video = addClips(round.videoBookmarks, round: round.title, kind: "video")
        }
        doc.droppedClipCount = dropped.count

        let f = ISO8601DateFormatter()
        let manifest = Manifest(kind: kind, title: event.name, createdAt: f.string(from: .now),
                                createdBy: createdBy, media: media.keys.sorted().map { media[$0]!.entry })
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        var entries: [(name: String, data: Data)] = [
            ("mimetype", Data(mimetype.utf8)),
            ("manifest.json", try enc.encode(manifest)),
            ("event.json", try LiveEventFile.encode(doc)),
        ]
        for id in media.keys.sorted() { entries.append((media[id]!.entry.path, media[id]!.bytes)) }
        return (ZipContainer.write(entries), dropped)
    }

    static func write(_ event: LiveEvent, to url: URL, createdBy: String, kind: String = "event") throws -> [String] {
        let (data, dropped) = try export(event, createdBy: createdBy, kind: kind)
        try data.write(to: url, options: .atomic)
        return dropped
    }
}
#endif
