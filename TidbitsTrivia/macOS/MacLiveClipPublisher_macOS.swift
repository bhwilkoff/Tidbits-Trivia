#if os(macOS)
import AVFoundation
import CryptoKit
import Foundation

// MARK: - Decision 060: the clip reaches the phones too

/// Turns a question's clip (a security-scoped bookmark, or a store file) into
/// what the ROOM can be given: an https link when the media has one, otherwise
/// the bytes of a small web-safe encoding, written once to
/// `live/{code}/media/{id}` and referenced from `pub.media` as `room:<id>`.
///
/// Until this existed a name-that-tune clip played on the host's PA and a
/// video on the projector, and a phone showed the prompt and nothing else. A
/// remote or hybrid joiner had no clip at all; a table at the back of a loud
/// bar had a song they could not hear.
///
/// The encoding is bounded on purpose (`LiveRoom.mediaMaxBytes`): forty phones
/// fetching a clip is forty downloads, and the RTDB free tier is a wall, not a
/// meter — a clip that cannot be brought under the cap is reported as "not on
/// phones" and the room hears it from the PA as before. Nothing here is a
/// paid bucket (Decision 060 / the $0 rule in TIDBITS-LIVE-PREMIUM-BACKLOG §M).
@MainActor
@Observable
final class LiveClipPublisher {
    static let shared = LiveClipPublisher()

    struct Prepared: Equatable, Sendable {
        /// What `pub.media` carries; nil when the clip cannot reach phones.
        var media: LiveRoom.Media?
        /// The node to write before `media` is published (nil for an https link).
        var node: LiveRoom.RoomMedia?
        var id: String?
        /// The one line the cockpit shows the host under the Play button.
        var note: String
    }

    private var cache: [String: Prepared] = [:]
    private var inFlight: [String: Task<Prepared, Never>] = [:]

    /// One key per clip. The bookmark bytes are stable for a given file, so the
    /// same clip in two nights (or the same night hosted twice) is prepared once.
    nonisolated static func key(_ bookmark: Data) -> String {
        String(SHA256.hash(data: bookmark).map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    func prepare(bookmark: Data, kind: String) async -> Prepared {
        let key = Self.key(bookmark)
        if let hit = cache[key] { return hit }
        if let running = inFlight[key] { return await running.value }
        let task = Task.detached(priority: .utility) { await Self.build(bookmark: bookmark, kind: kind) }
        inFlight[key] = task
        let result = await task.value
        cache[key] = result
        inFlight[key] = nil
        return result
    }

    /// Start every clip of the night early, so a transcode is finished before
    /// the host reaches the question instead of after the room is waiting.
    func prewarm(_ event: LiveEvent) {
        for round in event.rounds {
            for bm in round.audioBookmarks ?? [] where !bm.isEmpty {
                Task { _ = await prepare(bookmark: bm, kind: "audio") }
            }
            for bm in round.videoBookmarks ?? [] where !bm.isEmpty {
                Task { _ = await prepare(bookmark: bm, kind: "video") }
            }
        }
    }

    // MARK: Building

    /// Encodings a phone browser, AVPlayer and Media3 all play natively. A `.mov`
    /// or `.wav` is re-encoded; an `.mp3` under the cap is sent as it is.
    nonisolated static let webSafe: [String: [String: String]] = [
        "audio": ["mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac"],
        "video": ["mp4": "video/mp4", "m4v": "video/mp4"],
    ]

    nonisolated static func megabytes(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1f MB", Double(n) / 1_000_000) : "\(max(1, n / 1000)) KB"
    }

    nonisolated static func build(bookmark: Data, kind: String) async -> Prepared {
        guard let url = try? LiveClip.resolve(bookmark) else {
            return Prepared(media: nil, node: nil, id: nil, note: "Not on phones — the clip could not be opened")
        }
        let scoped = !LiveMediaStore.isStoreFile(url)
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // A store file is named by its hash; the name a player should see is the
        // one the file came in with.
        var name = url.deletingPathExtension().lastPathComponent
        if let id = LiveMediaStore.id(forStoreFile: url), let original = LiveMediaStore.info(id)?.originalName {
            name = (original as NSString).deletingPathExtension
        }

        // An imported package remembers where a clip came from; a direct https
        // file link is the cheapest thing a phone can be given (§5.3).
        if let id = LiveMediaStore.id(forStoreFile: url), let info = LiveMediaStore.info(id),
           let source = info.sourceURL, isDirectFileLink(source) {
            let media = LiveRoom.Media(kind: kind, url: source, mime: info.mime, name: name, bytes: info.bytes)
            return Prepared(media: media, node: nil, id: nil, note: "On phones by link")
        }

        let ext = LiveMediaStore.normalizedExt(url.pathExtension)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var encoded: (data: Data, mime: String)?
        if let mime = webSafe[kind]?[ext], size <= LiveRoom.mediaMaxBytes, let d = try? Data(contentsOf: url) {
            encoded = (d, mime)
        } else {
            encoded = await transcode(url, kind: kind)
        }
        guard let encoded, encoded.data.count <= LiveRoom.mediaMaxBytes else {
            let sizeNote = size > 0 ? " (\(megabytes(size)))" : ""
            return Prepared(media: nil, node: nil, id: nil,
                            note: "Not on phones — too long to send\(sizeNote); the room hears it from the PA")
        }
        let id = LiveMediaStore.id(for: encoded.data)
        let node = LiveRoom.RoomMedia(kind: kind, mime: encoded.mime, bytes: encoded.data.count,
                                      b64: encoded.data.base64EncodedString())
        let media = LiveRoom.Media(kind: kind, url: "\(LiveRoom.mediaScheme):\(id)", mime: encoded.mime,
                                   name: name, bytes: encoded.data.count)
        return Prepared(media: media, node: node, id: id, note: "On phones too · \(megabytes(encoded.data.count))")
    }

    /// A link a `<video>` / AVPlayer can open directly — a file, not a page. A
    /// YouTube or Vimeo page link is a page; the joiner would render a broken
    /// player, so it is treated as "no link" and the bytes go instead.
    nonisolated static func isDirectFileLink(_ s: String) -> Bool {
        guard s.hasPrefix("https://") || s.hasPrefix("http://"), let u = URL(string: s) else { return false }
        let ext = LiveMediaStore.normalizedExt(u.pathExtension)
        return webSafe["audio"]?[ext] != nil || webSafe["video"]?[ext] != nil
            || ["ogg", "wav", "webm", "mov"].contains(ext)
    }

    /// Re-encode to the smallest web-safe form AVFoundation offers, trying the
    /// next-smaller preset when the first lands over the cap. Audio becomes AAC
    /// in an .m4a; video becomes H.264 at 640x480, then the low-quality preset.
    nonisolated static func transcode(_ url: URL, kind: String) async -> (data: Data, mime: String)? {
        let asset = AVURLAsset(url: url)
        let presets: [(String, AVFileType, String, String)] = kind == "audio"
            ? [(AVAssetExportPresetAppleM4A, .m4a, "m4a", "audio/mp4")]
            : [(AVAssetExportPreset640x480, .mp4, "mp4", "video/mp4"),
               (AVAssetExportPresetLowQuality, .mp4, "mp4", "video/mp4")]
        for (preset, type, ext, mime) in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("tidbits-clip-\(UUID().uuidString).\(ext)")
            session.shouldOptimizeForNetworkUse = true
            do { try await session.export(to: tmp, as: type) } catch { continue }
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let d = try? Data(contentsOf: tmp) else { continue }
            if d.count <= LiveRoom.mediaMaxBytes { return (d, mime) }
        }
        return nil
    }
}
#endif
