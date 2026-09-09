import Foundation
import Testing

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
