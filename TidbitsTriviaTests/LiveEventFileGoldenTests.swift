#if os(macOS)
import Foundation
import Testing

/// LIVE-EVENT-FILE §5.1 — the golden document both stacks must round-trip.
///
/// A host's night has to move between their Mac and their Windows box. Nothing
/// enforced that before this: each platform could quietly change its export and
/// the break would only show up when a real host's file failed to open, in a
/// bar, on a Friday. The Windows side runs the same assertions against the same
/// bytes (`windows/Tidbits.HeadlessTests/LiveEventFileGoldenTest.cs`).
@Suite("Live event file — the portable night")
struct LiveEventFileGoldenTests {

    /// The golden lives in the repo, not in either platform's bundle, so both
    /// stacks assert against ONE file. Walk up from this source file rather than
    /// guessing a working directory.
    private static func goldenData() throws -> Data {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("tools/live-event/golden.tidbitsevent.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            dir = dir.deletingLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test("decodes the golden document")
    func decodesGolden() throws {
        let ev = try LiveEventFile.decode(try Self.goldenData())

        #expect(ev.name == "Friday Pub Quiz")
        #expect(ev.venue == "The Anchor")
        #expect(ev.sponsor == "The Anchor Brewery")
        #expect(ev.brandHex == "#FF5C35")
        #expect(ev.leadCaptureURL == "https://example.test/list")
        #expect(ev.weekday == 6)
        #expect(ev.rounds.count == 2)

        #expect(ev.rounds[0].format == .classic)
        #expect(ev.rounds[0].title == "Round 1 — Warm Up")
        #expect(ev.rounds[0].categoryID == "history")
        #expect(ev.rounds[0].timerSeconds == 60)
        #expect(ev.rounds[0].hostNote == "Read the first one slowly.")
        #expect(ev.rounds[0].questions.count == 2)

        #expect(ev.rounds[1].format == .typeAnswer)
        #expect(ev.rounds[1].isWager == true)
        #expect(ev.rounds[1].isSpeed == true)
        #expect(ev.rounds[1].timerSeconds == nil)
        #expect(ev.rounds[1].questions.count == 1)

        let q = ev.rounds[0].questions[0]
        #expect(q.id == "golden:q1")
        #expect(q.correctAnswer == "Lydia")
        #expect(q.difficulty == 3)
        #expect(q.options.count == 4)

        #expect(ev.rounds[1].questions[0].accepted == ["Bohemian Rhapsody"])
        #expect(ev.totalQuestions == 3)
    }

    @Test("round-trips the contract fields")
    func roundTrips() throws {
        let once = try LiveEventFile.decode(try Self.goldenData())
        let twice = try LiveEventFile.decode(try LiveEventFile.encode(once))

        #expect(once.name == twice.name)
        #expect(once.venue == twice.venue)
        #expect(once.sponsor == twice.sponsor)
        #expect(once.brandHex == twice.brandHex)
        #expect(once.weekday == twice.weekday)
        #expect(once.rounds.count == twice.rounds.count)
        for (a, b) in zip(once.rounds, twice.rounds) {
            #expect(a.format == b.format)
            #expect(a.title == b.title)
            #expect(a.categoryID == b.categoryID)
            #expect(a.timerSeconds == b.timerSeconds)
            #expect(a.hostNote == b.hostNote)
            #expect(a.isWager == b.isWager)
            #expect(a.isSpeed == b.isSpeed)
            #expect(a.questions.map(\.id) == b.questions.map(\.id))
            #expect(a.questions.map(\.correctAnswer) == b.questions.map(\.correctAnswer))
        }
    }

    @Test("import assigns a new id so it never overwrites an existing night")
    func importIsAdditive() throws {
        // §2.3. Two imports of the SAME co-host file must land as two nights, not
        // one silently replacing the other in the upsert-by-id store.
        let a = try LiveEventFile.decode(try Self.goldenData())
        let b = try LiveEventFile.decode(try Self.goldenData())
        #expect(a.id != b.id)
    }

    @Test("refuses a file that is not a Tidbits event")
    func refusesForeignFile() throws {
        let data = Data(#"{"format":"com.example.other","version":1,"event":{}}"#.utf8)
        #expect(throws: (any Error).self) { try LiveEventFile.decode(data) }
    }

    @Test("refuses a newer format version, naming it")
    func refusesNewerVersion() throws {
        let text = String(decoding: try Self.goldenData(), as: UTF8.self)
            .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        do {
            _ = try LiveEventFile.decode(Data(text.utf8))
            Issue.record("a version-99 document must be refused")
        } catch let error as LiveEventFile.FileError {
            #expect(error.errorDescription?.contains("99") == true)
        }
    }

    @Test("ignores unknown keys so additive fields need no version bump")
    func ignoresUnknownKeys() throws {
        // §2.4. Without this the forward-compat policy in §1.2 is unusable: every
        // new optional field would break every older reader.
        let text = String(decoding: try Self.goldenData(), as: UTF8.self)
            .replacingOccurrences(of: "\"version\" : 1", with: "\"somethingNew\" : 42,\n  \"version\" : 1")
        let ev = try LiveEventFile.decode(Data(text.utf8))
        #expect(ev.rounds.count == 2)
    }

    @Test("clips are counted, never written")
    func clipsAreDroppedAndCounted() throws {
        // §3.1. A security-scoped bookmark is meaningless on another machine;
        // writing one would make a round look complete and play silent.
        var ev = try LiveEventFile.decode(try Self.goldenData())
        ev.rounds[1].audioBookmarks = [Data("not-a-real-bookmark".utf8)]
        #expect(LiveEventFile.droppedClipCount(in: ev) == 1)

        let text = String(decoding: try LiveEventFile.encode(ev), as: UTF8.self)
        #expect(text.contains("\"droppedClipCount\" : 1"))
        #expect(!text.contains("audioBookmarks"))

        // The questions still all came across — only the clip reference is gone.
        let back = try LiveEventFile.decode(try LiveEventFile.encode(ev))
        #expect(back.rounds[1].questions.count == 1)
        #expect(back.rounds[1].audioBookmarks == nil)
    }
}
#endif
