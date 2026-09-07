#if os(macOS)
import AppKit
import Foundation
import Testing

/// LIVE-PACKAGE-FORMAT §7.1 — the golden package both stacks must open.
///
/// A night with pictures and an audio round could not leave the Mac at all
/// before the package existed. These pin the container (a zip the Windows
/// `ZipArchive` and the Python reference writer also produce), the manifest,
/// the media by hash, and that pack → unpack → pack keeps the fields §2–§4
/// name. The Windows side runs the same assertions against the same bytes
/// (`windows/Tidbits.HeadlessTests/LivePackageGoldenTest.cs`).
@Suite("Live package — the night with its media in one file", .serialized)
struct LivePackageGoldenTests {
    static let pngID = "e06f876bfc434e1656878a0db85b9a13"
    static let wavID = "8f70a2eed10865d07de5779de0d8475e"

    private static func goldenData() throws -> Data {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("tools/live-event/golden.tidbits")
            if FileManager.default.fileExists(atPath: candidate.path) { return try Data(contentsOf: candidate) }
            dir.deleteLastPathComponent()
        }
        throw NSError(domain: "golden", code: 1, userInfo: [NSLocalizedDescriptionKey: "golden.tidbits not found above \(#filePath)"])
    }

    private static func scratchStore() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tidbits-media-test-\(UUID().uuidString)")
        LiveMediaStore.directoryOverride = dir
        return dir
    }

    @Test("the zip reader sees the five entries, mimetype first and stored")
    func zipEntries() throws {
        let entries = try ZipContainer.entries(in: try Self.goldenData())
        #expect(entries.map(\.name) == ["mimetype", "manifest.json", "event.json",
                                        "media/\(Self.wavID).wav", "media/\(Self.pngID).png"])
        #expect(entries[0].method == 0)
        #expect(entries[1].method == 8)   // deflated by the reference writer; the reader inflates
        let mt = try ZipContainer.extract(entries[0], from: try Self.goldenData())
        #expect(String(decoding: mt, as: UTF8.self) == LivePackage.mimetype)
    }

    @Test("reads the golden: manifest, media by hash, the document inside")
    func readsGolden() throws {
        let c = try LivePackage.read(try Self.goldenData())
        #expect(c.manifest.kind == "event")
        #expect(c.manifest.title == "Friday Pub Quiz")
        #expect(c.manifest.media.map(\.id) == [Self.wavID, Self.pngID])
        let png = c.manifest.media[1]
        #expect(png.kind == "image" && png.mime == "image/png" && png.bytes == 69)
        #expect(png.sourceURL == "https://example.test/golden-picture.png")
        #expect(png.credit == "Golden Studio" && png.license == "CC0")
        #expect(c.media[Self.pngID]?.count == 69)
        #expect(c.media[Self.wavID]?.count == 1644)
        let r0 = c.document.event.rounds[0]
        #expect(r0.questions[0].imageURL?.absoluteString == "tidbits-media:\(Self.pngID)")
        #expect(r0.questions[1].imageURL?.absoluteString == "https://example.test/by-url.jpg")
        #expect(r0.audio == [Self.wavID, nil])
        #expect(r0.video == nil)
    }

    @Test("a foreign zip and a tampered package are refused by name")
    func refusals() throws {
        let foreign = ZipContainer.write([("hello.txt", Data("hi".utf8))])
        #expect(throws: LivePackage.PackageError.self) { try LivePackage.read(foreign) }
        // Same entries, one media byte flipped: the hash check must fire.
        var files = try ZipContainer.readAll(try Self.goldenData())
        var png = files["media/\(Self.pngID).png"]!
        png[png.count - 1] ^= 0xFF
        files["media/\(Self.pngID).png"] = png
        let order = ["mimetype", "manifest.json", "event.json", "media/\(Self.wavID).wav", "media/\(Self.pngID).png"]
        let tampered = ZipContainer.write(order.map { ($0, files[$0]!) })
        #expect(throws: LivePackage.PackageError.self) { try LivePackage.read(tampered) }
    }

    @Test("import puts the media in the store, resolves the picture, and attaches the clip")
    func importIntoStore() throws {
        let dir = Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: dir); LiveMediaStore.directoryOverride = nil }
        let (event, problems) = try LivePackage.importIntoStore(try Self.goldenData())
        #expect(problems.isEmpty, "\(problems)")
        #expect(event.rounds.count == 2)
        let q0 = event.rounds[0].questions[0]
        let ref = try #require(q0.imageURL)
        let file = try #require(LiveMediaStore.resolve(ref))
        #expect(file.lastPathComponent == "\(Self.pngID).png")
        #expect(try Data(contentsOf: file).count == 69)
        // The joiner gets the https twin, never the store reference (§5.3).
        #expect(LiveMediaStore.publishableURL(q0.imageURL) == "https://example.test/golden-picture.png")
        #expect(LiveMediaStore.publishableURL(event.rounds[0].questions[1].imageURL) == "https://example.test/by-url.jpg")
        let marks = try #require(event.rounds[0].audioBookmarks)
        #expect(marks.count == 2 && !marks[0].isEmpty && marks[1].isEmpty)
        #expect(LiveClip.isPlayable(marks[0]))
    }

    @Test("a store-only picture reaches a phone as a small JPEG data URL (§5.3)")
    func storeOnlyPictureIsPublishedAsDataURL() throws {
        let dir = Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: dir); LiveMediaStore.directoryOverride = nil }
        // A 1200x900 red picture with NO https twin.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 900, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<900 { for x in 0..<1200 { rep.setColor(NSColor(red: 1, green: 0.2, blue: 0.1, alpha: 1), atX: x, y: y) } }
        let png = rep.representation(using: .png, properties: [:])!
        let id = try LiveMediaStore.store(png, ext: "png", originalName: "big.png")
        let published = try #require(LiveMediaStore.publishableURL(LiveMediaStore.reference(id)))
        #expect(published.hasPrefix("data:image/jpeg;base64,"))
        #expect(published.count < 170_000)   // ~120 KB of JPEG, base64-expanded
        let jpeg = try #require(Data(base64Encoded: String(published.dropFirst("data:image/jpeg;base64,".count))))
        let back = try #require(NSImage(data: jpeg))
        #expect(back.size.width <= 800 && back.size.height <= 800)
        // The same id publishes the same bytes (cached), and an https twin still wins.
        #expect(LiveMediaStore.publishableURL(LiveMediaStore.reference(id)) == published)
    }

    @Test("pack → unpack → pack keeps the manifest media and the document")
    func roundTrip() throws {
        let dir = Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: dir); LiveMediaStore.directoryOverride = nil }
        let (event, _) = try LivePackage.importIntoStore(try Self.goldenData())
        let (bytes, dropped) = try LivePackage.export(event, createdBy: "test")
        #expect(dropped.isEmpty, "\(dropped)")
        let again = try LivePackage.read(bytes)
        #expect(again.manifest.media.map(\.id) == [Self.wavID, Self.pngID])
        #expect(again.manifest.media.map(\.sha256) == (try LivePackage.read(try Self.goldenData())).manifest.media.map(\.sha256))
        let r0 = again.document.event.rounds[0]
        #expect(r0.questions.map(\.prompt) == event.rounds[0].questions.map(\.prompt))
        #expect(r0.questions[0].imageURL?.absoluteString == "tidbits-media:\(Self.pngID)")
        #expect(r0.questions[1].imageURL?.absoluteString == "https://example.test/by-url.jpg")
        #expect(r0.audio == [Self.wavID, nil])
        #expect(again.document.droppedClipCount == 0)
        // Our writer STORES everything; our reader must read our own output too.
        #expect(try ZipContainer.entries(in: bytes).allSatisfy { $0.method == 0 })
    }
}
#endif
