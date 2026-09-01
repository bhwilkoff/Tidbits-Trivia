#if os(macOS)
import AVFoundation
import Foundation

// MARK: - Audio / video clip references for a live round

/// Making and resolving the security-scoped bookmarks an audio or video round
/// stores for each question's clip.
///
/// This exists because the previous code was `(try? url.bookmarkData(options:
/// .withSecurityScope)) ?? Data()` at both call sites. In a sandboxed app WITHOUT
/// `com.apple.security.files.bookmarks.app-scope` that `try?` always fails, so
/// every clip the host picked was stored as an empty `Data`. The round looked
/// complete, the "Play this clip" button appeared on the cockpit, and nothing
/// ever played — which is the whole of the owner's "audio and video rounds that
/// don't do anything" (2026-09-01).
///
/// The entitlement is now declared, and the swallow is gone: making a bookmark
/// VERIFIES it by resolving it straight back, and a failure is reported to the
/// host rather than written to disk as silence.
enum LiveClip {
    enum ClipError: LocalizedError {
        case couldNotBookmark(name: String, underlying: String)
        case bookmarkDidNotResolve(name: String)
        case accessDenied(name: String)
        case missing

        var errorDescription: String? {
            switch self {
            case .couldNotBookmark(let name, let underlying):
                return "Tidbits could not keep a reference to “\(name)”. \(underlying)"
            case .bookmarkDidNotResolve(let name):
                return "The saved reference to “\(name)” no longer points at a file. Re-attach the clip."
            case .accessDenied(let name):
                return "macOS would not grant access to “\(name)”. Re-attach the clip."
            case .missing:
                return "That question has no clip attached."
            }
        }
    }

    /// Make a bookmark AND prove it works before returning it. A bookmark that is
    /// written but never resolved is the failure mode this whole type exists to
    /// prevent: it is indistinguishable from a good one until the night is live.
    static func bookmark(for url: URL) throws -> Data {
        let name = url.lastPathComponent
        let data: Data
        do {
            data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw ClipError.couldNotBookmark(name: name, underlying: error.localizedDescription)
        }
        // Resolve it right now. If it cannot come back, it is not a clip.
        var stale = false
        guard let round = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                   relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw ClipError.bookmarkDidNotResolve(name: name)
        }
        guard round.startAccessingSecurityScopedResource() else {
            throw ClipError.accessDenied(name: name)
        }
        round.stopAccessingSecurityScopedResource()
        return data
    }

    /// Resolve a stored bookmark for playback. The caller owns the access scope
    /// and must call `stopAccessingSecurityScopedResource()` when done.
    static func resolve(_ data: Data) throws -> URL {
        guard !data.isEmpty else { throw ClipError.missing }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw ClipError.bookmarkDidNotResolve(name: "this clip")
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw ClipError.accessDenied(name: url.lastPathComponent)
        }
        return url
    }

    /// Is this stored bookmark still usable? Used by the cockpit to show a real
    /// "clip unavailable" state instead of a Play button that does nothing.
    static func isPlayable(_ data: Data?) -> Bool {
        guard let data, !data.isEmpty else { return false }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return false }
        let ok = url.startAccessingSecurityScopedResource()
        if ok { url.stopAccessingSecurityScopedResource() }
        return ok
    }

    // MARK: The self-test

    /// Report, on the glass, whether clip references and clip DECODING actually
    /// work in this build.
    ///
    /// The first version of this wrote its probe file into the app's own temporary
    /// directory — which the sandbox already grants — so it reported OK both with
    /// and without `files.bookmarks.app-scope` and proved nothing. A check that
    /// cannot fail for the reason you care about is not a check
    /// (`gate-blind-in-ci`). It now takes a path from
    /// `TIDBITS_LIVE_AVSELFTEST_PATH`, so the harness points it at a real file
    /// OUTSIDE the container, and it additionally opens the file the way the round
    /// actually will.
    static func selfTestSummary() -> String {
        var lines: [String] = []
        let external = ProcessInfo.processInfo.environment["TIDBITS_LIVE_AVSELFTEST_PATH"]

        // 1. Bookmarking a file inside the container — the weak case, kept only so
        //    the two are visibly distinguished in the output.
        let inside = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidbits-clip-selftest-\(UUID().uuidString).wav")
        do {
            try Data([0x52, 0x49, 0x46, 0x46]).write(to: inside)
            defer { try? FileManager.default.removeItem(at: inside) }
            _ = try bookmark(for: inside)
            lines.append("BOOKMARK inside container: OK")
        } catch {
            lines.append("BOOKMARK inside container: FAIL — \(error.localizedDescription)")
        }

        // 2. Bookmarking a file OUTSIDE the container. This is the case a host's
        //    picked clip actually is, and the one the entitlement governs.
        if let path = external {
            let url = URL(fileURLWithPath: path)
            do {
                let data = try bookmark(for: url)
                let back = try resolve(data)
                defer { back.stopAccessingSecurityScopedResource() }
                lines.append("BOOKMARK outside container: OK (\(data.count) bytes)")
            } catch {
                lines.append("BOOKMARK outside container: FAIL — \(error.localizedDescription)")
            }
            // 3. And DECODE it the way the audio round will. A bookmark that
            //    resolves to a file AVAudioFile cannot read is still a silent round.
            lines.append("DECODE \(url.lastPathComponent): \(decodeProbe(url))")
        } else {
            lines.append("BOOKMARK outside container: SKIPPED (set TIDBITS_LIVE_AVSELFTEST_PATH)")
        }
        return lines.joined(separator: "\n")
    }

    /// Can the audio round's player actually read this file? The picker offers
    /// .mp3 among others; whether `AVAudioFile` accepts one is a fact to measure,
    /// not to assume.
    static func decodeProbe(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try AVAudioFile(forReading: url)
            return "OK (\(Int(file.length)) frames, \(Int(file.processingFormat.sampleRate)) Hz)"
        } catch {
            return "FAIL — \(error.localizedDescription)"
        }
    }
}
#endif
