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

    /// Online quick match (Decision 039): the leader device paces the game
    /// automatically (no human host taps) and starts when the room is full.
    let autoPace: Bool
    var expectedPlayers: Int?
    private var paceTask: Task<Void, Never>?
    private var revealShownAt: Date?

    private let plan: NightPlan
    private let category: TriviaCategory

    // MARK: Host

    /// Stand up a room and wait in the lobby for joiners. The host configures the
    /// plan first; `startNight()` builds the questions and kicks everyone off.
    init(hostingPlan plan: NightPlan, category: TriviaCategory, hostName: String, engine: GameEngine,
         transport: (any NightHostTransport)? = nil, roomCode: String? = nil,
         autoPace: Bool = false, expectedPlayers: Int? = nil) {
        self.role = .host
        self.plan = plan
        self.category = category
        self.engine = engine
        self.autoPace = autoPace
        self.expectedPlayers = expectedPlayers
        let h = transport.map { NightHost(transport: $0) } ?? NightHost()
        self.host = h
        h.start(hostName: hostName, code: roomCode)
        if autoPace { startAutoPace() }
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
    init(joiningEngine engine: GameEngine, transport: (any NightClientTransport)? = nil) {
        self.role = .joiner
        self.plan = .quick
        self.category = .named("mixed")
        self.engine = engine
        self.autoPace = false
        let c = transport.map { NightClient(transport: $0) } ?? NightClient()
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

    /// The leader's auto-pilot for online matches: start when the room fills,
    /// reveal when everyone answered (or the clock + grace runs out), advance
    /// a beat after each reveal — the pacing a human host does by hand in a
    /// living-room night.
    private func startAutoPace() {
        paceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.6))
                guard let self, self.stage != .finished else { break }
                guard self.role == .host, let host = self.host else { continue }
                switch self.stage {
                case .lobby:
                    if let expected = self.expectedPlayers, host.players.count >= expected {
                        await self.startNight()
                    }
                case .playing:
                    if self.engine.phase == .reveal && !self.engine.awaitingReveal {
                        // Reveal is showing — hold a readable beat, then advance.
                        if let shown = self.revealShownAt {
                            if Date().timeIntervalSince(shown) >= 6 { self.revealShownAt = nil; self.next() }
                        } else { self.revealShownAt = Date() }
                    } else if host.everyoneAnswered {
                        self.reveal()
                    }
                case .finished:
                    break
                }
            }
        }
    }

    func end() {
        paceTask?.cancel()
        host?.stop()
        client?.leave()
        engine.onLocalAnswer = nil
        engine.quit()
    }
}
