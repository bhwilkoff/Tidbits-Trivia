import Foundation

// Trivia Night wire golden test — Apple side (docs/NIGHT-WIRE-SCHEMA.md).
// Compiles the REAL repo wire files (NightProtocol/NightTransport + models) and:
//   1. decodes every golden/messages/*.json and asserts the canonical facts;
//   2. encodes each into a framed AES-GCM message (key from room code "GOLD")
//      and writes golden/frames/apple-<name>.hex — Android's GoldenWireTest
//      must decode these;
//   3. decodes any golden/frames/android-<name>.hex Android wrote — proving the
//      Kotlin-encoded frames open on Swift.
// Run: tools/night-wire/run_golden.sh (or see NIGHT-WIRE-SCHEMA.md §Golden tests).

@main
@MainActor
struct AppleGolden {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        if ok { print("  ok: \(what)") } else { failures += 1; print("  FAIL: \(what)") }
    }

    static func assertFacts(_ m: NightMessage, fixture: String) {
        switch fixture {
        case "roster":
            check(m.kind == .roster, "roster kind")
            check(m.players?.count == 2, "roster has 2 players")
            check(m.players?[0].isHost == true && m.players?[0].score == 3 && m.players?[0].answered == true,
                  "roster host row (score 3, answered)")
            check(m.players?[1].name == "Ana" && m.players?[1].score == 0, "roster joiner row")
        case "night":
            check(m.kind == .night, "night kind")
            check(m.plan?.rounds.count == 2, "night has 2 rounds")
            check(m.plan?.rounds[0].kind == .classic && m.plan?.rounds[0].count == 2, "round 0 classic x2")
            check(m.plan?.rounds[1].kind == .closestCall && m.plan?.rounds[1].count == 1, "round 1 closestCall x1")
            check(m.plan?.teams.isEmpty == true, "night teams empty")
            check(m.questionIds?.count == 3, "night ships 3 question ids")
            check(m.questions?.count == 2, "night ships 2 full questions (q-gamma is id-only)")
            check(m.questions?[0].correctIndex == 2 && m.questions?[0].options.count == 4, "q-alpha MCQ shape")
            check(m.questions?[0].imageUrl == "https://upload.wikimedia.org/einstein.jpg", "q-alpha image url")
            check(m.questions?[1].closest?.answer == 6371.0 && m.questions?[1].closest?.unit == "km",
                  "q-beta closest spec")
            check(m.questions?[1].toQuestion().closest?.tolerance == 1500.0, "q-beta resolves to a local Question")
        case "welcome":
            check(m.kind == .welcome && m.seat == 1 && m.roomName == "Tidbits GOLD", "welcome facts")
        case "answered":
            check(m.kind == .answered && m.score == 5 && m.correct == true, "answered facts")
        case "future-kind":
            // Forward-compat: Apple decodes an unknown kind to .unknown and ignores it.
            check(m.kind == .unknown, "future kind decodes to .unknown")
        default:
            check(false, "unexpected fixture \(fixture) — add its facts here")
        }
    }

    static func main() throws {
        let goldenDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
            ? CommandLine.arguments[1] : "tools/night-wire/golden")
        let messagesDir = goldenDir.appendingPathComponent("messages")
        let framesDir = goldenDir.appendingPathComponent("frames")

        let key = RoomCode.presharedKey(for: "GOLD")
        let files = try FileManager.default.contentsOfDirectory(at: messagesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { print("FAIL: no fixtures at \(messagesDir.path)"); exit(1) }

        print("== golden messages (decode + assert) ==")
        var decoded: [(name: String, message: NightMessage)] = []
        for f in files {
            let name = f.deletingPathExtension().lastPathComponent
            print(" \(name):")
            do {
                let m = try JSONDecoder().decode(NightMessage.self, from: Data(contentsOf: f))
                assertFacts(m, fixture: name)
                decoded.append((name, m))
            } catch {
                failures += 1
                print("  FAIL: decode threw \(error)")
            }
        }

        print("== apple frames (encode -> self round-trip -> write hex) ==")
        for (name, m) in decoded where name != "future-kind" {
            guard let frame = NightTransport.encode(m, key: key) else {
                failures += 1; print("  FAIL: encode \(name)"); continue
            }
            let back = NightFramer(key: key).ingest(frame)
            check(back.count == 1 && back[0].kind == m.kind, "\(name) round-trips through NightFramer")
            let hex = frame.map { String(format: "%02x", $0) }.joined()
            try hex.write(to: framesDir.appendingPathComponent("apple-\(name).hex"), atomically: true, encoding: .utf8)
        }

        print("== android frames (cross-decode) ==")
        let androidFrames = (try? FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("android-") && $0.pathExtension == "hex" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        if androidFrames.isEmpty {
            print("  (none present — run the Android GoldenWireTest to generate, then re-run)")
        } else {
            for f in androidFrames {
                let name = f.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "android-", with: "")
                let hex = (try String(contentsOf: f, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
                var bytes = Data(); var i = hex.startIndex
                while i < hex.endIndex {
                    let j = hex.index(i, offsetBy: 2)
                    bytes.append(UInt8(hex[i..<j], radix: 16)!)
                    i = j
                }
                print(" \(name):")
                let msgs = NightFramer(key: key).ingest(bytes)
                if msgs.count == 1 {
                    assertFacts(msgs[0], fixture: name)
                } else {
                    failures += 1; print("  FAIL: android frame did not open (\(msgs.count) messages)")
                }
            }
        }

        print(failures == 0 ? "PASS: night wire golden (apple)" : "FAIL: \(failures) assertion(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
