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
    /// Host-plays-too (owner: "I'll play too" toggle). When on, the host also
    /// answers each question on this device and is scored in the standings.
    var hostPlays = false
    var hostName = "Host"
    /// The host's selected option for the current question (host-plays mode).
    private(set) var hostChoice: Int?
    var hostAnswered: Bool { hostChoice != nil }
    /// Per-question display shuffles, computed ONCE when a question becomes current
    /// so publish and reveal agree on indices (ordering/matching). The correct
    /// order/pairing is never shipped — the host scores from its local Question.
    private(set) var shuffledOrder: [String] = []
    private(set) var shuffledValues: [String] = []

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
        if hostPlays { await net.joinAsHost(name: hostName.isEmpty ? "Host" : hostName) }
        index = 0; revealed = false; hostChoice = nil; stage = .playing
        prepareQuestion()
        await net.setState("live")
        await net.publish(pub())
    }

    /// Compute the display shuffles for the current question (once), so the
    /// ordering/matching indices are stable across publish + reveal.
    private func prepareQuestion() {
        shuffledOrder = current?.ordering?.shuffled() ?? []
        shuffledValues = current?.matching?.values.shuffled() ?? []
    }

    /// Host-plays mode: the host answers the current question on this device.
    func hostAnswer(_ i: Int) async {
        guard hostPlays, stage == .playing, !revealed, hostChoice == nil, let q = current else { return }
        hostChoice = i
        await net.submitHostAnswer(qid: LiveRoom.qid(round: q.roundIndex ?? 0, question: index), choice: i)
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
        hostChoice = nil
        index += 1
        if current == nil { await end() } else { prepareQuestion(); await net.publish(pub()) }
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
        // MCQ = no structured spec (classic/describe/cloze/oddOneOut/thisOrThat/pictureId).
        let mcq = q.closest == nil && q.ordering == nil && q.matching == nil && q.accepted == nil && q.enumerate == nil
        var p = LiveRoom.Pub(round: roundNumber, roundTitle: roundTitle,
                             qid: LiveRoom.qid(round: q.roundIndex ?? 0, question: index),
                             qNum: inR.n, qTotal: inR.of,
                             phase: revealed ? LiveRoom.Phase.reveal : LiveRoom.Phase.question,
                             prompt: q.prompt, options: mcq ? q.options : nil, format: fmt,
                             answerIndex: (revealed && mcq) ? q.correctIndex : nil)
        p.imageURL = q.imageURL?.absoluteString                   // pictureId (also MCQ)
        if let c = q.closest { p.numeric = LiveRoom.Numeric(min: c.min, max: c.max, step: c.step, unit: c.unit) }
        if q.ordering != nil { p.orderItems = shuffledOrder }     // correct order withheld
        if let m = q.matching { p.matchKeys = m.keys; p.matchValues = shuffledValues }
        if let e = q.enumerate { p.enumTarget = e.total }
        return p
    }

    private func endedPub() -> LiveRoom.Pub {
        LiveRoom.Pub(round: roundNumber, roundTitle: roundTitle, qid: "end", qNum: 0, qTotal: 0,
                     phase: LiveRoom.Phase.ended, prompt: "", options: nil, format: "", answerIndex: nil)
    }

    /// On reveal, score every player's submission against the host's LOCAL Question
    /// (every question type). Nothing that could leak an answer was ever published.
    private func autoScore() async {
        guard let q = current else { return }
        for (uid, ans) in net.answers {
            let pts = Self.score(q, ans, shuffledOrder: shuffledOrder, shuffledValues: shuffledValues, mcqPoints: pointsPerCorrect)
            if pts > 0 { await net.setScore(uid, (net.scores[uid] ?? 0) + pts) }
        }
    }

    /// Points for one submission, by question type (partial credit for ordering /
    /// matching / enumerate; proximity for numeric; alias-match for typed).
    static func score(_ q: Question, _ a: LiveRoom.Answer, shuffledOrder: [String], shuffledValues: [String], mcqPoints: Int) -> Int {
        if let c = q.closest { return a.number.map { c.points(for: $0) } ?? 0 }
        if let correctOrder = q.ordering, let order = a.order {
            let seq = order.compactMap { shuffledOrder.indices.contains($0) ? shuffledOrder[$0] : nil }
            return zip(seq, correctOrder).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }   // +1 per correct position
        }
        if let m = q.matching, let pairs = a.pairs {
            var pts = 0
            for (i, _) in m.keys.enumerated() where i < pairs.count && shuffledValues.indices.contains(pairs[i]) {
                if shuffledValues[pairs[i]] == m.values[i] { pts += 1 }               // +1 per correct pairing
            }
            return pts
        }
        if let accepted = q.accepted, let text = a.text {
            return GameEngine.matchesAccepted(text, accepted) ? mcqPoints : 0
        }
        if let e = q.enumerate, let list = a.list {
            var filled = Set<Int>()
            for name in list {
                for (gi, group) in e.groups.enumerated() where !filled.contains(gi) {
                    if GameEngine.matchesAccepted(name, group) { filled.insert(gi); break }
                }
            }
            return filled.count                                                       // +1 per unique set member
        }
        return a.choice == q.correctIndex ? mcqPoints : 0                             // MCQ / picture / T-or-T / odd
    }

    /// True for the option-based types (classic/describe/cloze/oddOneOut/thisOrThat/
    /// pictureId) — the host renders options; everything else has a bespoke surface.
    static func isMCQ(_ q: Question) -> Bool {
        q.closest == nil && q.ordering == nil && q.matching == nil && q.accepted == nil && q.enumerate == nil
    }
    /// The host-facing correct answer to read out on reveal (all types).
    static func answerLine(_ q: Question) -> String {
        if let c = q.closest { return c.formattedAnswer }
        if let acc = q.accepted { return acc.first ?? q.correctAnswer }
        if let ord = q.ordering { return ord.joined(separator: " → ") }
        if let m = q.matching { return zip(m.keys, m.values).map { "\($0.0) = \($0.1)" }.joined(separator: ", ") }
        if let e = q.enumerate { return e.displayNames.joined(separator: ", ") }
        return q.correctAnswer
    }
}
