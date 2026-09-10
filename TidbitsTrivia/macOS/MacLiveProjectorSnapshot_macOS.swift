#if os(macOS)
import AppKit
import SwiftUI

/// Offline design-observability for the PROJECTOR: render the real
/// `LiveBigScreen_macOS` with a mock session into PNGs — every state the room
/// can see, at 1280x720 and 1920x1080, with every A8.7 element on and then
/// off. Gated by `TIDBITS_PROJECTOR_SNAPSHOT=<dir>`; never runs in normal use.
///
/// This exists because the screen-region capture graded a terminal window as
/// the projector (screen-region-grades-the-screen) and the owner's report was
/// "literally everything overlaps". A layout that cannot be photographed
/// cannot be fixed; this photographs all of it in one run.
enum LiveProjectorSnapshot {
    @MainActor static func writePNGs(to dir: String) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Run this way the element set is NOT persisted (TIDBITS_LIVE_HIDE is set).
        let elements = LiveProjectorElements.shared

        // A picture the loader can open offline.
        let pic = FileManager.default.temporaryDirectory.appendingPathComponent("projector-snapshot-picture.png")
        if let png = Self.samplePicture() { try? png.write(to: pic) }
        _ = await LiveImageLoader.shared.load(pic)

        func q(_ p: String, _ opts: [String], story: String, picture: Bool = false) -> Question {
            Question(id: UUID().uuidString, prompt: p, options: opts, correctIndex: 2, categoryID: "history",
                     difficulty: 3, explanation: story, sourceTitle: "", sourceURL: nil, templateID: "mcq",
                     imageURL: picture ? pic : nil)
        }
        let longPrompt = "This Iron Age kingdom in western Anatolia, ruled from Sardis, is credited with minting some of the world's oldest coins from electrum in the seventh century BCE — which kingdom?"
        let longStory = "Lydia's coins were struck from electrum, a natural alloy of gold and silver panned from the Pactolus river; the stamped lion of the Mermnad dynasty guaranteed weight, which is what let coins replace weighed metal. Croesus, the last Lydian king, later separated gold and silver into a bimetallic standard."
        let round = LiveRound(title: "Round 1 — General Knowledge", format: .classic, categoryID: "history",
                              questions: [q(longPrompt, ["Kingdom of Portugal", "Pahlavi Iran", "Lydia", "Soviet Union"], story: longStory),
                                          q("Who painted the Mona Lisa?", ["Leonardo da Vinci", "Michelangelo", "Raphael", "Donatello"], story: "It hangs in the Louvre.", picture: true)],
                              timerSeconds: 45)
        // G5: a pick-a-category board round — five columns x five tiers of synthetic
        // questions, so the grid slide is in the set (it was the one slide missing).
        let boardCats = ["history", "science", "geography", "music", "film"]
        var pool: [Question] = []
        for c in boardCats { for t in LiveBoard.defaultTiers {
            pool.append(Question(id: "\(c)-\(t)", prompt: "\(c.capitalized) question worth \(t * 100)", options: ["A", "B", "C", "D"],
                                 correctIndex: 0, categoryID: c, difficulty: t, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "mcq"))
        } }
        let board = LiveBoardBuilder.build(from: pool, categories: boardCats)
        var boardRound = LiveRound(title: "Pick a Category", format: .classic, categoryID: "mixed",
                                   questions: board.cells.compactMap { cell in pool.first { $0.id == cell.questionID } })
        boardRound.board = board
        var event = LiveEvent(name: "Thursday Night Trivia at The Anchor", venue: "The Anchor, Boulder", rounds: [round, boardRound])
        event.sponsor = "Left Hand Brewing"
        let net = LiveHostNet()
        let teamNames = ["The Quizzards of Oz", "Les Quizerables", "Trivia Newton John", "Norfolk Enchants", "Smarty Pints", "Beer Pressure"]
        var teams: [String: LiveRoom.Team] = [:]; var scores: [String: Int] = [:]; var answers: [String: LiveRoom.Answer] = [:]
        for (i, name) in teamNames.enumerated() {
            let uid = "uid\(i)"
            teams[uid] = LiveRoom.Team(name: name, joinedAt: 1_757_000_000_000 + i)
            scores[uid] = [14, 12, 12, 9, 7, 3][i]
            answers[uid] = LiveRoom.Answer(choice: [2, 2, 0, 2, 1, 3][i], ts: 1_757_000_000_000)
        }
        net.previewSeed(code: "QATEST", teams: teams, scores: scores, answers: answers)
        let coord = LiveHostCoordinator()
        coord.net = net

        struct Shot { let name: String; let apply: (LiveHostSession) -> Void }
        let shots: [Shot] = [
            // A2.14: two tables played their joker on this round — the line rides the
            // round's first question and nothing else changes.
            Shot(name: "jokers") { s in s.event.joker = true; s.jokersPlayed[0] = ["Smarty Pints", "The Quizzards of Oz"] },
            Shot(name: "question") { s in s.deadlineMs = LiveHostNet.nowMS() + 32_000 },
            Shot(name: "reveal") { s in s.reveal() },
            Shot(name: "picture") { s in s.next(); s.deadlineMs = LiveHostNet.nowMS() + 32_000 },
            Shot(name: "picture-reveal") { s in s.next(); s.reveal() },
            Shot(name: "scores") { s in s.showScores = true },
            Shot(name: "break") { s in s.onBreak = true },
            Shot(name: "standings") { s in s.finished = true },
            // The board: jump into round 2 and hold the grid.
            Shot(name: "board") { s in s.next(); s.next(); s.showBoard = true; s.boardChooser = "The Quizzards of Oz" },
        ]
        // A video question, when the harness hands us a real clip
        // (TIDBITS_PROJECTOR_SNAPSHOT_VIDEO=<file>): the band the room watches.
        // ImageRenderer draws no AVKit view, so the band is a black box in the PNG —
        // the LAYOUT around it is what this photographs.
        let videoPath = ProcessInfo.processInfo.environment["TIDBITS_PROJECTOR_SNAPSHOT_VIDEO"]
        let sizes: [(String, CGFloat, CGFloat)] = [("720p", 1280, 720), ("1080p", 1920, 1080)]
        for (label, w, h) in sizes {
            let shotsForSize: [Shot] = shots + (videoPath.map { path in
                [Shot(name: "video") { s in
                    LiveVideoPlayer.shared.open(URL(fileURLWithPath: path)); s.deadlineMs = LiveHostNet.nowMS() + 32_000
                }]
            } ?? [])
            for shot in shotsForSize {
                for allOn in [true, false] {
                    if allOn { elements.showEverything() }
                    else { for e in LiveProjectorElements.all { elements.set(e.id, shown: false) } }
                    LiveVideoPlayer.shared.stop()
                    let session = LiveHostSession(event: event)
                    session.deadlineMs = nil
                    shot.apply(session)
                    coord.session = session
                    let view = LiveBigScreen_macOS()
                        .environment(coord)
                        .tint(Tidbits.Palette.blue)
                        .preferredColorScheme(.light)
                        .frame(width: w, height: h)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    let file = "\(dir)/\(label)-\(shot.name)-\(allOn ? "all-on" : "all-off").png"
                    if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: file))
                    }
                }
            }
        }
        LiveVideoPlayer.shared.stop()
        coord.session = nil
    }

    /// A 640x360 two-tone PNG so the picture band has real pixels to lay out.
    private static func samplePicture() -> Data? {
        let w = 640, h = 360
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.29, green: 0.53, blue: 0.91, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 200, y: 60, width: 240, height: 240))
        guard let cg = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
#endif
