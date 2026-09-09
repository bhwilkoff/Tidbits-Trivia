import Foundation

/// Decision 060: the joiner's copy of a clip the host offered in `pub.media`.
///
/// A `room:<id>` reference is fetched from `live/{code}/media/{id}` ONCE and
/// kept as a file under Caches (the one directory every Apple platform,
/// tvOS included, may write to), keyed by id so a re-published question or a
/// reconnect never downloads it again. An https link is handed back as it is.
/// Nothing is fetched until a player or the host's cue asks — an offer costs
/// the room nothing until it is taken up.
@MainActor
final class LiveMediaCache {
    static let shared = LiveMediaCache()

    enum MediaError: LocalizedError {
        case missing, badData, badLink
        var errorDescription: String? {
            switch self {
            case .missing: return "The host's clip isn't in the room yet."
            case .badData: return "That clip couldn't be read."
            case .badLink: return "That clip's link isn't valid."
            }
        }
    }

    private var files: [String: URL] = [:]
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// The extension a player needs to recognise the container — AVPlayer sniffs
    /// a file by its name before its bytes.
    nonisolated static func fileExtension(mime: String, kind: String) -> String {
        switch mime.lowercased() {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/aac": return "aac"
        case "audio/wav", "audio/x-wav": return "wav"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/webm": return "webm"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return kind == "video" ? "mp4" : (kind == "image" ? "jpg" : "m4a")
        }
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("LiveRoomMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A URL a player can open for this offer — local for a room node, remote
    /// for a link.
    func localURL(for media: LiveRoom.Media, code: String) async throws -> URL {
        guard let id = LiveRoom.mediaID(from: media.url) else {
            guard let u = URL(string: media.url), u.scheme?.hasPrefix("http") == true else { throw MediaError.badLink }
            return u
        }
        if let hit = files[id], FileManager.default.fileExists(atPath: hit.path) { return hit }
        if let running = inFlight[id] { return try await running.value }
        let task = Task<URL, Error> {
            let path = LiveRoom.mediaPath(code, id: id)
            guard let node = try await FirebaseRTDB.shared.get(path, as: LiveRoom.RoomMedia.self) else {
                throw MediaError.missing
            }
            guard let data = Data(base64Encoded: node.b64), !data.isEmpty else { throw MediaError.badData }
            let ext = Self.fileExtension(mime: node.mime, kind: node.kind)
            let url = Self.directory.appendingPathComponent("\(id).\(ext)")
            try data.write(to: url, options: .atomic)
            return url
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let url = try await task.value
        files[id] = url
        return url
    }
}
