#if os(macOS)
import Foundation
import AppKit
import CryptoKit

// MARK: - The media store (LIVE-PACKAGE-FORMAT §5.1)

/// Where a night's pictures and clips live once a package is imported —
/// content-addressed files under the sandbox's Application Support, plus one
/// index that remembers each file's kind, original name and https twin.
///
/// The event a host keeps references media as `tidbits-media:<id>`; this
/// resolves it. Storing by hash means importing the same package twice, or two
/// nights sharing a picture, costs one file — and a reference with no file
/// behind it is a visible "Picture unavailable", never a silent blank.
nonisolated enum LiveMediaStore {
    static let scheme = "tidbits-media"

    struct Info: Codable, Sendable {
        var ext: String
        var mime: String
        var kind: String
        var bytes: Int
        var originalName: String?
        var sourceURL: String?
        var credit: String?
        var license: String?
    }

    static let allowed: [String: (mime: String, kind: String)] = [
        "png": ("image/png", "image"), "jpg": ("image/jpeg", "image"), "jpeg": ("image/jpeg", "image"),
        "gif": ("image/gif", "image"), "webp": ("image/webp", "image"), "svg": ("image/svg+xml", "image"),
        "mp3": ("audio/mpeg", "audio"), "m4a": ("audio/mp4", "audio"), "wav": ("audio/wav", "audio"),
        "aac": ("audio/aac", "audio"), "ogg": ("audio/ogg", "audio"), "flac": ("audio/flac", "audio"),
        "mp4": ("video/mp4", "video"), "mov": ("video/quicktime", "video"), "m4v": ("video/x-m4v", "video"),
        "webm": ("video/webm", "video"),
    ]

    /// Tests and the harness point the store somewhere disposable; the app never sets it.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = directoryOverride ?? base.appendingPathComponent("LiveMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var indexURL: URL { directory.appendingPathComponent("index.json") }

    static func loadIndex() -> [String: Info] {
        guard let d = try? Data(contentsOf: indexURL),
              let idx = try? JSONDecoder().decode([String: Info].self, from: d) else { return [:] }
        return idx
    }
    private static func saveIndex(_ idx: [String: Info]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let d = try? enc.encode(idx) { try? d.write(to: indexURL, options: .atomic) }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func id(for data: Data) -> String { String(sha256Hex(data).prefix(32)) }

    static func normalizedExt(_ ext: String) -> String {
        let e = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return e == "jpeg" ? "jpg" : e
    }

    /// Put bytes in the store; returns the id. Idempotent for identical bytes.
    @discardableResult
    static func store(_ data: Data, ext rawExt: String, originalName: String? = nil,
                      sourceURL: String? = nil, credit: String? = nil, license: String? = nil) throws -> String {
        let ext = normalizedExt(rawExt)
        guard let kind = allowed[ext] else {
            throw NSError(domain: "LiveMediaStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(originalName ?? ext) is not a picture, audio or video type Tidbits can carry."])
        }
        let id = id(for: data)
        let url = directory.appendingPathComponent("\(id).\(ext)")
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        var idx = loadIndex()
        var info = idx[id] ?? Info(ext: ext, mime: kind.mime, kind: kind.kind, bytes: data.count)
        if let originalName { info.originalName = originalName }
        if let sourceURL { info.sourceURL = sourceURL }
        if let credit { info.credit = credit }
        if let license { info.license = license }
        idx[id] = info
        saveIndex(idx)
        return id
    }

    static func reference(_ id: String) -> URL { URL(string: "\(scheme):\(id)")! }

    static func id(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let raw = url.absoluteString.dropFirst(scheme.count + 1)
        let id = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty ? nil : id
    }

    static func info(_ id: String) -> Info? { loadIndex()[id] }

    /// The file behind an id, if the store has it.
    static func fileURL(_ id: String) -> URL? {
        if let info = loadIndex()[id] {
            let u = directory.appendingPathComponent("\(id).\(info.ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        // The index can lag the files (a crash between the two writes); the file
        // is the truth, so look for it by id.
        if let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
           let hit = names.first(where: { $0.hasPrefix(id + ".") }) {
            return directory.appendingPathComponent(hit)
        }
        return nil
    }

    /// `tidbits-media:<id>` → the local file; any other URL → itself.
    static func resolve(_ url: URL) -> URL? {
        guard let id = id(from: url) else { return url }
        return fileURL(id)
    }

    /// What a JOINER may be given for this reference (§5.3): the https twin when
    /// there is one, otherwise the picture itself as a small data URL. A phone can
    /// never open the host's package, and the shipped joiners already load
    /// whatever `imageURL` says — a data URL needs no client update.
    static func publishableURL(_ url: URL?) -> String? {
        guard let url else { return nil }
        guard let id = id(from: url) else { return url.absoluteString }
        if let s = loadIndex()[id]?.sourceURL, s.hasPrefix("http") { return s }
        return dataURL(forID: id)
    }

    /// Decision 060 (pictures): what a joiner is given for a picture — the https
    /// twin, or the picture split into the once-written room NODE (the full
    /// ≤ 800 px version) plus a SMALL data URL (≤ 320 px, ~20 KB) that rides in
    /// `imageURL` so a joiner that predates the node still shows a picture, and a
    /// joiner that reads the node has something to show while it fetches.
    /// Measured 2026-09-09: the full data URL made `pub` 108 KB and was re-sent
    /// to every phone on every state change.
    struct PublishablePicture: Equatable {
        var fallback: String?
        var node: LiveRoom.RoomMedia?
        var id: String?
        var wire: LiveRoom.Media?
    }
    static let nodeThresholdBytes = 30_000
    static let fallbackMaxPixels = 320
    static let fallbackMaxBytes = 20_000
    nonisolated(unsafe) private static var pictureCache: [String: PublishablePicture] = [:]

    static func publishablePicture(_ url: URL?) -> PublishablePicture {
        guard let url else { return PublishablePicture() }
        guard let id = id(from: url) else { return PublishablePicture(fallback: url.absoluteString) }
        if let s = loadIndex()[id]?.sourceURL, s.hasPrefix("http") { return PublishablePicture(fallback: s) }
        if let hit = pictureCache[id] { return hit }
        guard let full = jpeg(forID: id, maxSide: publishMaxPixels, maxBytes: publishMaxBytes) else { return PublishablePicture() }
        var out: PublishablePicture
        if full.count <= nodeThresholdBytes {
            out = PublishablePicture(fallback: "data:image/jpeg;base64," + full.base64EncodedString())
        } else {
            let small = jpeg(forID: id, maxSide: fallbackMaxPixels, maxBytes: fallbackMaxBytes) ?? full
            let nodeID = Self.id(for: full)
            let name = loadIndex()[id]?.originalName.map { ($0 as NSString).deletingPathExtension }
            out = PublishablePicture(
                fallback: "data:image/jpeg;base64," + small.base64EncodedString(),
                node: LiveRoom.RoomMedia(kind: "image", mime: "image/jpeg", bytes: full.count, b64: full.base64EncodedString()),
                id: nodeID,
                wire: LiveRoom.Media(kind: "image", url: "\(LiveRoom.mediaScheme):\(nodeID)", mime: "image/jpeg", name: name, bytes: full.count))
        }
        pictureCache[id] = out
        return out
    }

    /// The picture as `data:image/jpeg;base64,…`, downscaled so the whole room
    /// can fetch it on venue Wi-Fi: the longest side ≤ 800px, JPEG 0.6, and it
    /// shrinks further until it is under ~120 KB. Cached per id: the same bytes
    /// are published on every state change of the question.
    static let publishMaxPixels = 800
    static let publishMaxBytes = 120_000
    nonisolated(unsafe) private static var dataURLCache: [String: String] = [:]

    static func dataURL(forID id: String) -> String? {
        if let hit = dataURLCache[id] { return hit }
        guard let jpeg = jpeg(forID: id, maxSide: publishMaxPixels, maxBytes: publishMaxBytes) else { return nil }
        let s = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        dataURLCache[id] = s
        return s
    }

    /// A JPEG of the stored picture no larger than `maxSide` and, by shrinking,
    /// no heavier than `maxBytes` (floor: 160 px).
    static func jpeg(forID id: String, maxSide: Int, maxBytes: Int) -> Data? {
        guard let file = fileURL(id), let image = NSImage(contentsOf: file) else { return nil }
        var side = maxSide
        var quality = 0.6
        for _ in 0..<6 {
            guard let jpeg = jpegData(image, maxSide: side, quality: quality) else { return nil }
            if jpeg.count <= maxBytes || side <= 160 { return jpeg }
            side = side * 3 / 4
            quality = max(0.4, quality - 0.1)
        }
        return nil
    }

    private static func jpegData(_ image: NSImage, maxSide: Int, quality: Double) -> Data? {
        guard var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        let scale = min(1, Double(maxSide) / Double(max(w, h)))
        if scale < 1 {
            let nw = max(1, Int(Double(w) * scale)), nh = max(1, Int(Double(h) * scale))
            guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: nw, height: nh))   // JPEG has no alpha: white behind a PNG
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
            guard let scaled = ctx.makeImage() else { return nil }
            cg = scaled
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// The id of a file that lives in the store (its name is `<id>.<ext>`).
    static func id(forStoreFile url: URL) -> String? {
        guard isStoreFile(url) else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.count == 32 ? stem : nil
    }

    static func isStoreFile(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path)
    }
}
#endif
