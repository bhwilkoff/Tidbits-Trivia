import Foundation
import Observation

/// The shared, cross-platform **Trivia Night host** — informal games with friends,
/// hostable from any platform. It rides the SAME Firebase RTDB `live/{code}`
/// backend as Tidbits Live (owner architecture, amends Decision 033): a lightweight
/// game master vs the macOS-only, feature-rich Tidbits Live cockpit. Builds the
/// night, opens a room (players join by code / QR via the unified LivePlayerClient),
/// publishes each question with the answer withheld until reveal, auto-scores on
/// reveal, and paces Reveal → Next. Core only — no UI, no per-platform types.
@MainActor
@Observable
final class LiveNightHost {
    enum Stage { case lobby, playing, ended }

    let net = LiveHostNet()
    private(set) var stage: Stage = .lobby
    private(set) var questions: [Question] = []
    private(set) var index = 0
    private(set) var revealed = false
    private(set) var opening = false
    private(set) var errorText: String?

    private let plan: NightPlan
    private let category: TriviaCategory
    let title: String
    /// Points a correct answer earns (casual default; host could expose later).
    var pointsPerCorrect = 1

    init(plan: NightPlan, category: TriviaCategory, title: String = "Trivia Night") {
        self.plan = plan
        self.category = category
        self.title = title
    }

    // MARK: Read-model the host UI observes

    var code: String { net.code }
    var isOpen: Bool { net.isOpen }
    var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    var standings: [LiveHostNet.Joined] { net.joined }
    var playerCount: Int { net.teams.count }
    var answeredCount: Int { net.answers.count }
    var roundIndex: Int { current?.roundIndex ?? 0 }
    var roundNumber: Int { roundIndex + 1 }
    var roundCount: Int { max(plan.rounds.count, 1) }
    var roundTitle: String {
        plan.rounds.indices.contains(roundIndex) ? plan.rounds[roundIndex].kind.nightRoundTitle : ""
    }
    var questionInRound: (n: Int, of: Int) {
        let inRound = questions.enumerated().filter { $0.element.roundIndex == roundIndex }
        let pos = (inRound.firstIndex { $0.offset == index } ?? 0) + 1
        return (pos, inRound.count)
    }

    // MARK: Lifecycle / pacing

    /// Open the room so players can join (shows the code + QR). Idempotent.
    func openRoom() async {
        guard !net.isOpen, !opening else { return }
        opening = true; errorText = nil
        if await net.open(name: title) == nil { errorText = "Couldn't open a room. Check your connection." }
        opening = false
    }

    /// Build the night and publish the first question.
    func start() async {
        if !net.isOpen { await openRoom() }
        guard net.isOpen else { return }
        // QuestionProvider returns round-ordered, roundIndex-tagged questions.
        questions = await QuestionProvider.shared.nightQuestions(plan: plan, category: category)
        guard !questions.isEmpty else { errorText = "No questions available."; return }
        index = 0; revealed = false; stage = .playing
        await net.setState("live")
        await net.publish(pub())
    }

    /// Show the answer on every device at once, then award points.
    func reveal() async {
        guard stage == .playing, current != nil, !revealed else { return }
        revealed = true
        await net.publish(pub())          // answerIndex now included
        await autoScore()
    }

    /// Advance everyone, or end the night.
    func next() async {
        guard stage == .playing, revealed else { return }
        revealed = false
        index += 1
        if current == nil { await end() } else { await net.publish(pub()) }
    }

    func end() async {
        stage = .ended
        await net.setState("ended")
        await net.publish(endedPub())
    }

    func close() async { await net.close() }

    // MARK: Internals

    private func pub() -> LiveRoom.Pub {
        guard let q = current else { return endedPub() }
        let inR = questionInRound
        let fmt = plan.rounds.indices.contains(roundIndex) ? plan.rounds[roundIndex].kind.rawValue : ""
        return LiveRoom.Pub(round: roundNumber, roundTitle: roundTitle,
                            qid: LiveRoom.qid(round: q.roundIndex ?? 0, question: index),
                            qNum: inR.n, qTotal: inR.of,
                            phase: revealed ? LiveRoom.Phase.reveal : LiveRoom.Phase.question,
                            prompt: q.prompt, options: q.options, format: fmt,
                            answerIndex: revealed ? q.correctIndex : nil)
    }

    private func endedPub() -> LiveRoom.Pub {
        LiveRoom.Pub(round: roundNumber, roundTitle: roundTitle, qid: "end", qNum: 0, qTotal: 0,
                     phase: LiveRoom.Phase.ended, prompt: "", options: nil, format: "", answerIndex: nil)
    }

    /// Award points to every team whose submitted choice matches the answer.
    private func autoScore() async {
        guard let q = current else { return }
        for (uid, ans) in net.answers where ans.choice == q.correctIndex {
            await net.setScore(uid, (net.scores[uid] ?? 0) + pointsPerCorrect)
        }
    }
}
