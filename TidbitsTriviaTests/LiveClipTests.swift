#if os(macOS)
import AVFoundation
import Foundation
import Testing

/// The audio/video round's clip references.
///
/// The owner's report was "audio and video rounds that don't do anything", and
/// the code that produced it was `(try? url.bookmarkData(options:
/// .withSecurityScope)) ?? Data()` at both call sites — a swallow that turned any
/// failure into an EMPTY bookmark. The round then looked complete, the cockpit
/// showed "Play this clip", and nothing played, with no error anywhere.
///
/// These tests pin the two properties that make that impossible to repeat: a
/// bookmark is proven by resolving it before it is returned, and an empty or
/// broken one is reported as unplayable rather than silently accepted.
@Suite("Live clips")
struct LiveClipTests {

    /// A real, decodable WAV — 0.2s of 440 Hz. Written rather than fixtured so the
    /// decode probe is testing an actual audio file, not a stub with a .wav name.
    private static func makeWav() throws -> URL {
        let sr = 44_100, frames = sr / 5
        var pcm = Data()
        for i in 0..<frames {
            let v = Int16(12_000 * sin(2 * Double.pi * 440 * Double(i) / Double(sr)))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var out = Data("RIFF".utf8)
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        out += le32(36 + pcm.count) + Data("WAVEfmt ".utf8) + le32(16) + le16(1) + le16(1)
        out += le32(sr) + le32(sr * 2) + le16(2) + le16(16) + Data("data".utf8) + le32(pcm.count)
        out += pcm
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidbits-cliptest-\(UUID().uuidString).wav")
        try out.write(to: url)
        return url
    }

    @Test("a bookmark round-trips to the same file")
    func bookmarkRoundTrips() throws {
        let url = try Self.makeWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try LiveClip.bookmark(for: url)
        #expect(!data.isEmpty)

        let back = try LiveClip.resolve(data)
        defer { back.stopAccessingSecurityScopedResource() }
        #expect(back.lastPathComponent == url.lastPathComponent)
    }

    @Test("the round's player can actually decode what the picker accepts")
    func decodes() throws {
        // A bookmark that resolves to a file `AVAudioFile` cannot read is still a
        // silent round, so the decode is checked separately from the reference.
        let url = try Self.makeWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = LiveClip.decodeProbe(url)
        #expect(probe.hasPrefix("OK"), "decode probe said: \(probe)")

        let file = try AVAudioFile(forReading: url)
        #expect(file.length > 0)
    }

    @Test("an empty bookmark is unplayable, not silently accepted")
    func emptyIsUnplayable() {
        // This is the exact value the old `?? Data()` wrote for every clip.
        #expect(LiveClip.isPlayable(Data()) == false)
        #expect(LiveClip.isPlayable(nil) == false)
        #expect(throws: (any Error).self) { _ = try LiveClip.resolve(Data()) }
    }

    @Test("a bookmark to a file that has since vanished reports itself unplayable")
    func vanishedFileIsUnplayable() throws {
        let url = try Self.makeWav()
        let data = try LiveClip.bookmark(for: url)
        #expect(LiveClip.isPlayable(data))

        try FileManager.default.removeItem(at: url)
        // The cockpit asks exactly this before it offers a Play button, so a host
        // whose clip moved sees "Clip unavailable" instead of a dead control.
        #expect(LiveClip.isPlayable(data) == false)
    }

    @Test("garbage is refused rather than resolved")
    func garbageIsRefused() {
        #expect(LiveClip.isPlayable(Data("not a bookmark".utf8)) == false)
        #expect(throws: (any Error).self) { _ = try LiveClip.resolve(Data("not a bookmark".utf8)) }
    }

    @Test("every clip error says what the host should do about it")
    func errorsAreActionable() {
        // A live host reads these mid-round; "operation could not be completed" is
        // not a message anyone can act on with a room waiting.
        let errors: [LiveClip.ClipError] = [
            .couldNotBookmark(name: "clip.wav", underlying: "no permission"),
            .bookmarkDidNotResolve(name: "clip.wav"),
            .accessDenied(name: "clip.wav"),
            .missing,
        ]
        for e in errors {
            let text = e.errorDescription ?? ""
            #expect(!text.isEmpty)
            #expect(text.first?.isUppercase == true || text.hasPrefix("macOS"),
                    "not a sentence: \(text)")
        }
    }
}
#endif
