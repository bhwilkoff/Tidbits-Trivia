import Foundation
import Observation

/// Orchestrates a networked Trivia Night across devices (Decision 033). It owns
/// the host- or joiner-side transport AND drives the device's local `GameEngine`,
/// so every platform's existing game view just plays — the coordinator wires the
/// network signals to the engine and back.
///
/// The model is host-paced, everyone-plays: the host builds the night once and
/// ships it to all devices; each device runs its own engine over the identical
/// list and scores itself; the host reveals + advances for everyone. Core only —
/// no UI imports (the engine takes plain closures).
@Observable
@MainActor
final class LiveNight {
    enum Role { case host, joiner }
    /// Coordinator-level phase: are we still gathering players, in the game, or done.
    enum Stage { case lobby, playing, finished }

    let role: Role
    let engine: GameEngine
    private(set) var host: NightHost?
    private(set) var client: NightClient?
    private(set) var stage: Stage = .lobby

    private let plan: NightPlan
    private let category: TriviaCategory

    // MARK: Host

    /// Stand up a room and wait in the lobby for joiners. The host configures the
    /// plan first; `startNight()` builds the questions and kicks everyone off.
    init(hostingPlan plan: NightPlan, category: TriviaCategory, hostName: String, engine: GameEngine) {
        self.role = .host
        self.plan = plan
        self.category = category
        self.engine = engine
        let h = NightHost()
        self.host = h
        h.start(hostName: hostName)
        engine.onLocalAnswer = { [weak self] _, score, correct in
            self?.host?.setHostAnswered(score: score, correct: correct)
        }
    }

    /// Build the night, ship it to everyone, and begin the first question. The
    /// host's own engine plays alongside (the host is a player too).
    func startNight() async {
        guard role == .host, let host else { return }
        let qs = await QuestionProvider.shared.nightQuestions(plan: plan, category: category)
        guard !qs.isEmpty else { return }
        host.broadcastNight(plan: plan, questions: qs)
        engine.startNight(plan: plan, category: category, questions: qs, hostPaced: true)
        host.broadcastBegin(index: 0)
        stage = .playing
    }

    /// Host taps "Reveal" — show the answer on every device at once.
    func reveal() {
        guard role == .host, let host else { return }
        engine.releaseReveal()
        host.broadcastReveal(index: engine.index)
    }

    /// Host taps "Next" — advance everyone, or end the night.
    func next() {
        guard role == .host, let host else { return }
        engine.advance()
        if engine.phase == .finished {
            host.broadcastFinished()
            stage = .finished
        } else {
            host.broadcastBegin(index: engine.index)
        }
    }

    // MARK: Joiner

    /// Discover + join a room, then follow the host's pacing. The engine is driven
    /// entirely by the host's `night` / `begin` / `reveal` / `finished` signals.
    init(joiningEngine engine: GameEngine) {
        self.role = .joiner
        self.plan = .quick
        self.category = .named("mixed")
        self.engine = engine
        let c = NightClient()
        self.client = c
        c.onNight = { [weak self] plan, qs in
            guard let self else { return }
            self.engine.startNight(plan: plan, category: .named("mixed"), questions: qs, hostPaced: true)
            self.stage = .playing
        }
        c.onBegin = { [weak self] i in self?.engine.goToQuestion(i) }
        c.onReveal = { [weak self] _ in self?.engine.releaseReveal() }
        c.onFinished = { [weak self] in
            self?.engine.finishExternally()
            self?.stage = .finished
        }
        engine.onLocalAnswer = { [weak self] _, score, correct in
            self?.client?.reportAnswer(score: score, correct: correct)
        }
    }

    func join(code: String, name: String) {
        client?.join(code: code, name: name)
    }

    // MARK: Shared read-model (the views observe these)

    /// Live standings — the host owns the authoritative roster; a joiner mirrors it.
    var players: [NightPlayer] { host?.players ?? client?.players ?? [] }
    var roomCode: String { host?.roomCode ?? "" }
    var roomName: String { client?.roomName ?? (host.map { "Tidbits \($0.roomCode)" } ?? "") }
    /// The seat THIS device occupies (host is always seat 0).
    var mySeat: Int? { role == .host ? NightHost.hostSeat : client?.seat }
    var answeredCount: Int { host?.answeredCount ?? 0 }
    var everyoneAnswered: Bool { host?.everyoneAnswered ?? false }
    var playerCount: Int { players.count }
    var leaderSeat: Int? {
        guard let top = players.max(by: { $0.score < $1.score }), top.score > 0 else { return nil }
        return top.seat
    }

    func end() {
        host?.stop()
        client?.leave()
        engine.onLocalAnswer = nil
        engine.quit()
    }
}
