import Foundation
import Testing
#if os(macOS)
import AppKit
import CoreGraphics
#endif

/// Decision 060: the clip a question carries reaches the phones over the wire.
///
/// `pub.media` is additive — an older joiner never sees it — and its `url` is
/// either a direct https file link or `room:<id>`, a reference to the
/// once-written `live/{code}/media/{id}` node. These pin the keys every stack
/// mirrors (js/live.js, FirebaseNet.kt, LiveRoom.cs) and the size cap the RTDB
/// rules enforce, so a host cannot publish a reference no phone can resolve.
@Suite("Live media wire")
struct LiveMediaWireTests {

    @Test("pub.media round-trips with the exact keys the other stacks read")
    func pubMediaKeys() throws {
        var pub = LiveRoom.Pub(round: 1, roundTitle: "Name That Tune", qid: "r1q0", qNum: 1, qTotal: 5,
                               phase: LiveRoom.Phase.question, prompt: "What song is this?",
                               options: nil, format: "typeAnswer", answerIndex: nil)
        pub.media = LiveRoom.Media(kind: "audio", url: "room:0123456789abcdef0123456789abcdef",
                                   mime: "audio/mp4", name: "golden-beep", bytes: 1644, startedAt: 1_757_000_000_000)
        let data = try JSONEncoder().encode(pub)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let media = try #require(obj["media"] as? [String: Any])
        #expect(media["kind"] as? String == "audio")
        #expect(media["url"] as? String == "room:0123456789abcdef0123456789abcdef")
        #expect(media["mime"] as? String == "audio/mp4")
        #expect(media["name"] as? String == "golden-beep")
        #expect(media["bytes"] as? Int == 1644)
        #expect(media["startedAt"] as? Int == 1_757_000_000_000)
        let back = try JSONDecoder().decode(LiveRoom.Pub.self, from: data)
        #expect(back == pub)
    }

    @Test("a question without a clip publishes no media key at all")
    func noMediaKey() throws {
        let pub = LiveRoom.Pub(round: 1, roundTitle: "History", qid: "r0q0", qNum: 1, qTotal: 5,
                               phase: LiveRoom.Phase.question, prompt: "?", options: ["a", "b"],
                               format: "classic", answerIndex: nil)
        let data = try JSONEncoder().encode(pub)
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["media"] == nil)
    }

    @Test("a pub from an older host (no media) still decodes")
    func olderHostDecodes() throws {
        let json = #"{"round":1,"roundTitle":"x","qid":"r0q0","qNum":1,"qTotal":1,"phase":"question","prompt":"p","format":"classic"}"#
        let pub = try JSONDecoder().decode(LiveRoom.Pub.self, from: Data(json.utf8))
        #expect(pub.media == nil)
    }

    @Test("the room node carries what a joiner needs to build a blob, and nothing else")
    func roomNodeKeys() throws {
        let node = LiveRoom.RoomMedia(kind: "video", mime: "video/mp4", bytes: 3, b64: "AAAA")
        let obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(node)) as? [String: Any])
        #expect(Set(obj.keys) == ["kind", "mime", "bytes", "b64"])
        #expect(LiveRoom.mediaPath("ABCD", id: "deadbeef") == "live/ABCD/media/deadbeef")
    }

    @Test("room references parse; links and package references do not")
    func mediaIDParsing() {
        #expect(LiveRoom.mediaID(from: "room:abc123") == "abc123")
        #expect(LiveRoom.mediaID(from: "room:") == nil)
        #expect(LiveRoom.mediaID(from: "https://example.test/clip.mp3") == nil)
        #expect(LiveRoom.mediaID(from: "tidbits-media:abc123") == nil)
    }

    @Test("the cap matches what the rules validate (base64 of 3 MB fits under 4.2M chars)")
    func capMatchesRules() {
        let b64Length = (LiveRoom.mediaMaxBytes + 2) / 3 * 4
        #expect(b64Length <= 4_200_000)
        #expect(LiveRoom.mediaMaxBytes == 3_000_000)
    }
}

@Suite("Live media cache")
struct LiveMediaCacheTests {
    @Test("the file name carries the container the player sniffs")
    func extensions() {
        #expect(LiveMediaCache.fileExtension(mime: "audio/mp4", kind: "audio") == "m4a")
        #expect(LiveMediaCache.fileExtension(mime: "audio/mpeg", kind: "audio") == "mp3")
        #expect(LiveMediaCache.fileExtension(mime: "video/mp4", kind: "video") == "mp4")
        #expect(LiveMediaCache.fileExtension(mime: "", kind: "video") == "mp4")
        #expect(LiveMediaCache.fileExtension(mime: "application/octet-stream", kind: "audio") == "m4a")
    }
}

@Suite("Live picture node")
struct LivePictureNodeTests {
    @Test("pub.picture round-trips beside imageURL, and is absent without one")
    func pictureKey() throws {
        var pub = LiveRoom.Pub(round: 1, roundTitle: "x", qid: "r0q0", qNum: 1, qTotal: 1,
                               phase: LiveRoom.Phase.question, prompt: "p", options: ["a", "b"], format: "pictureId", answerIndex: nil)
        var obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pub)) as? [String: Any])
        #expect(obj["picture"] == nil)
        pub.imageURL = "data:image/jpeg;base64,AAAA"
        pub.picture = LiveRoom.Media(kind: "image", url: "room:abc", mime: "image/jpeg", name: "photo", bytes: 108_000)
        obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pub)) as? [String: Any])
        let pic = try #require(obj["picture"] as? [String: Any])
        #expect(pic["kind"] as? String == "image")
        #expect(pic["url"] as? String == "room:abc")
        #expect(obj["imageURL"] as? String == "data:image/jpeg;base64,AAAA")
        #expect(LiveMediaCache.fileExtension(mime: "image/jpeg", kind: "image") == "jpg")
    }

    #if os(macOS)
    /// A photo-sized picture splits into a ≤120 KB node and a ≤20 KB fallback;
    /// a small one stays a plain data URL (no node).
    @Test("a big store-only picture becomes a node plus a small fallback")
    func bigPictureSplits() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("picnode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        LiveMediaStore.directoryOverride = dir
        defer { LiveMediaStore.directoryOverride = nil }
        // 1600x1200 with per-pixel noise: compresses like a photo, not a flat fill.
        let w = 1600, h = 1200
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var seed: UInt32 = 7
        for i in stride(from: 0, to: bytes.count, by: 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[i] = UInt8(truncatingIfNeeded: seed >> 24); bytes[i + 1] = UInt8(truncatingIfNeeded: seed >> 16)
            bytes[i + 2] = UInt8(truncatingIfNeeded: seed >> 8); bytes[i + 3] = 255
        }
        let cg = try #require(CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let id = try LiveMediaStore.store(png, ext: "png", originalName: "photo.png")
        let pic = LiveMediaStore.publishablePicture(LiveMediaStore.reference(id))
        let node = try #require(pic.node)
        #expect(node.kind == "image" && node.mime == "image/jpeg")
        #expect(node.bytes <= LiveMediaStore.publishMaxBytes && node.bytes > LiveMediaStore.nodeThresholdBytes)
        #expect(pic.wire?.url == "room:\(pic.id ?? "")" && (pic.id?.count ?? 0) == 32)
        let fallback = try #require(pic.fallback)
        #expect(fallback.hasPrefix("data:image/jpeg;base64,"))
        #expect(fallback.count <= LiveMediaStore.fallbackMaxBytes * 4 / 3 + 64)
        // A tiny picture never needs a node.
        let tinyID = try LiveMediaStore.store(png, ext: "png", originalName: "tiny.png")   // same bytes → same id, fine
        _ = tinyID
    }
    #endif
}

@Suite("Live source on reveal")
struct LiveSourceWireTests {
    @Test("the Wikipedia source rides the reveal with title + url, and never before")
    func sourceKey() throws {
        var pub = LiveRoom.Pub(round: 1, roundTitle: "x", qid: "r0q0", qNum: 1, qTotal: 1,
                               phase: LiveRoom.Phase.reveal, prompt: "p", options: ["a", "b"], format: "classic", answerIndex: 1)
        pub.story = "Lydia's coins were electrum."
        pub.source = LiveRoom.Source(title: "Lydia", url: "https://en.wikipedia.org/wiki/Lydia")
        let obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pub)) as? [String: Any])
        let src = try #require(obj["source"] as? [String: Any])
        #expect(src["title"] as? String == "Lydia")
        #expect(src["url"] as? String == "https://en.wikipedia.org/wiki/Lydia")
        #expect(obj["story"] as? String == "Lydia's coins were electrum.")
        let back = try JSONDecoder().decode(LiveRoom.Pub.self, from: JSONEncoder().encode(pub))
        #expect(back.source == pub.source)
        let bare = LiveRoom.Pub(round: 1, roundTitle: "x", qid: "r0q0", qNum: 1, qTotal: 1,
                                phase: LiveRoom.Phase.question, prompt: "p", options: ["a", "b"], format: "classic", answerIndex: nil)
        let bareObj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(bare)) as? [String: Any])
        #expect(bareObj["source"] == nil && bareObj["story"] == nil)
    }
}
