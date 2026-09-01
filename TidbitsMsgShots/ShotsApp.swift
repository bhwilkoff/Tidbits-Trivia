import SwiftUI

/// A harness that renders the iMessage extension's real screens at device size.
///
/// **Why this exists.** The extension's UI lives inside Messages, and Messages cannot
/// be driven: `simctl` has no tap primitive and XCUITest can only automate your own
/// app. `tools/capture-imessage-screenshots.sh` was honest about the consequence — it
/// staged a simulator and left the four App Store shots to be taken by hand. That
/// makes the one surface with no automated capture also the one surface nobody can
/// see change.
///
/// This target hosts the SAME view types the extension uses — `StartRoundView`,
/// `RoundView`, `FinishedRoundView`, `BubbleImage` — compiled from the same files, not
/// copies. So a shot taken here is the real UI, and a regression in it is a regression
/// in the extension. What it deliberately does NOT do is fake the Messages chrome
/// around them; a screenshot that invents a transcript would be a picture of an app
/// that does not exist.
///
/// Never shipped: its own target, not embedded anywhere, absent from the archive.
///
///     TIDBITS_MSG_SHOT=finish  xcrun simctl launch <sim> …MsgShots
@main
struct ShotsApp: App {
    var body: some Scene {
        WindowGroup {
            ShotRoot()
                .preferredColorScheme(.light)      // the extension forces Light too
        }
    }
}

private struct ShotRoot: View {
    private var shot: String {
        ProcessInfo.processInfo.environment["TIDBITS_MSG_SHOT"] ?? "finish"
    }

    var body: some View {
        Group {
            switch shot {
            case "start":    StartRoundView(compact: false, onExpand: {}, onStart: { _, _ in })
            case "question": RoundView(state: ShotFixture.midRound, playerID: ShotFixture.me,
                                       onSend: { _, _ in }, onPlayAgain: {})
            case "reveal":   RoundView(state: ShotFixture.revealed, playerID: ShotFixture.me,
                                       onSend: { _, _ in }, onPlayAgain: {})
            case "finish":   RoundView(state: ShotFixture.finished, playerID: ShotFixture.me,
                                       onSend: { _, _ in }, onPlayAgain: {})
            case "bubble":   BubblePreview(state: ShotFixture.finished)
            default:         Text("unknown shot '\(shot)'").foregroundStyle(.red)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// The bubble artwork as Messages composites it, on the cream ground.
private struct BubblePreview: View {
    let state: RoundState
    var body: some View {
        ZStack {
            MsgPalette.bg.ignoresSafeArea()
            if let img = BubbleImage.render(state: state) {
                Image(uiImage: img)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(24)
            }
        }
    }
}

/// Fixed rounds, built from the real pack.
///
/// Seeded so the shots are reproducible: a screenshot set that changes questions on
/// every run cannot be reviewed, and re-shooting one panel would silently disagree
/// with the other three.
enum ShotFixture {
    static let me = "me00000"

    /// Chosen, not accepted. This seed draws one question from each of five different
    /// categories — business, screen, music, science, geography — with recognisable
    /// subjects. Several other seeds drew three sports questions in a row, which shows
    /// the app honestly but sells it badly.
    private static var questions: [PackQuestion] {
        QuestionPack.shared.pick(count: RoundState.questionCount, category: nil, seed: 555)
    }

    private static func base() -> RoundState {
        var s = RoundState(questionIDs: questions.map(\.i), players: [], index: 0)
        s.upsert(playerID: me, name: "Ben")
        s.upsert(playerID: "maya0001", name: "Maya")
        s.upsert(playerID: "dev00001", name: "Dev")
        return s
    }

    /// Correct index for question `i`, or a deliberate wrong one.
    private static func choice(_ i: Int, correct: Bool) -> Int {
        let key = QuestionPack.shared.correctIndex(id: questions[i].i) ?? 0
        return correct ? key : (key + 1) % 4
    }

    /// Question 2 of 5, nobody has answered it yet — the options screen.
    static var midRound: RoundState {
        var s = base()
        for p in [me, "maya0001", "dev00001"] { s.answer(playerID: p, choice: choice(0, correct: true)) }
        s.index = 1
        return s
    }

    /// The same question, answered by the local player — the explanation screen.
    static var revealed: RoundState {
        var s = midRound
        s.answer(playerID: me, choice: choice(1, correct: true))
        return s
    }

    /// A completed round with a clear winner. Ben 5, Maya 3, Dev 2 — a decisive board
    /// reads better than a tie in a store shot, and the tie paths have their own tests.
    static var finished: RoundState {
        var s = base()
        let plan: [(String, [Bool])] = [
            (me,        [true,  true,  true,  true,  true]),
            ("maya0001", [true,  true,  true,  false, false]),
            ("dev00001", [true,  false, true,  false, false]),
        ]
        for i in 0..<RoundState.questionCount {
            s.index = i
            for (pid, marks) in plan {
                s.answer(playerID: pid, choice: choice(i, correct: marks[i]))
            }
        }
        s.index = RoundState.questionCount - 1
        return s
    }
}
