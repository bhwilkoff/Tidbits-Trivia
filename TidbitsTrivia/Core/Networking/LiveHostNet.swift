import Foundation

/// The SHARED Firebase RTDB host bridge (the `live/{code}` contract in
/// LiveRoom.swift) — used by BOTH the macOS Tidbits Live cockpit AND the
/// cross-platform Trivia Night host (`LiveNightHost`), since both products ride
/// one backend (owner architecture, amends Decision 033). The host owns the room:
/// it publishes `pub` as it advances, streams the joined `teams` + their
/// `answers`, and writes `scores`. Platform-agnostic (Core) — no UI, no
/// per-platform types.
@MainActor
@Observable
final class LiveHostNet {
    private let db = FirebaseRTDB.shared

    private(set) var code = ""
    /// The host's own anon uid (owns meta/pub/scores). Also used when the host
    /// plays along (host-plays-too mode) — they self-register as a team.
    private(set) var hostUid = ""
    /// Joined phone/web teams (uid → name+score), merged from `teams` + `scores`.
    private(set) var teams: [String: LiveRoom.Team] = [:]
    private(set) var scores: [String: Int] = [:]
    /// Submissions for the CURRENT question (uid → answer), reset each question.
    private(set) var answers: [String: LiveRoom.Answer] = [:]
    private(set) var lastError: String?

    var isOpen: Bool { !code.isEmpty }
    var joined: [Joined] {
        teams.map { Joined(id: $0.key, name: $0.value.name, score: scores[$0.key] ?? 0) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
    }
    struct Joined: Identifiable, Hashable { let id: String; let name: String; let score: Int }

    /// F-006: rules deny the host deleting other uids' answer nodes, so a
    /// reused room code cannot have its stale ledger cleared server-side.
    /// Instead the host IGNORES answers written before this session opened —
    /// which protects both the answered-count and reveal scoring.
    private var sessionStartMS: Int = 0

    private var streamTasks: [Task<Void, Never>] = []
    private var answersTask: Task<Void, Never>?
    private var currentQid = ""

    // MARK: Lifecycle

    /// Open a room and start streaming joins. Returns the code. `name`/`venue`
    /// come from the host product (a Tidbits Live event, or a Trivia Night).
    @discardableResult
    func open(name: String, venue: String = "") async -> String? {
        do {
            let host = try await db.ensureAuth()
            sessionStartMS = Self.nowMS()
            // TIDBITS_LIVE_CODE pins a known code for deterministic device/CI testing.
            let code = ProcessInfo.processInfo.environment["TIDBITS_LIVE_CODE"] ?? FirebaseRTDB.newRoomCode()
            let meta = LiveRoom.Meta(host: host, createdAt: Self.nowMS(), name: name,
                                     venue: venue, state: "lobby")
            try await db.putJSON("\(LiveRoom.path(code))/meta", try JSONEncoder().encode(meta))
            // F-006: a room code reused across sessions (host crash-recovery,
            // or the QA loop's pinned code) inherits the previous night's
            // answers for matching question ids — a fresh night read
            // "1 answered" before anyone played. A new session owns a clean
            // answer ledger; scores/teams persist deliberately (rejoin-safe).
            try? await db.delete("\(LiveRoom.path(code))/answers")
            self.code = code
            self.hostUid = host
            watchTeams(code)
            watchScores(code)
            return code
        } catch {
            lastError = "Couldn't open a networked room: \(error)"
            return nil
        }
    }

    /// Publish the current question state for players to render.
    func publish(_ pub: LiveRoom.Pub) async {
        guard isOpen else { return }
        if pub.qid != currentQid {          // new question → re-key the answers watch
            currentQid = pub.qid
            answers = [:]
            watchAnswers(code, qid: pub.qid)
        }
        guard let json = try? JSONEncoder().encode(pub) else { return }
        try? await db.putJSON("\(LiveRoom.path(code))/pub", json)
    }

    func setState(_ state: String) async {
        guard isOpen else { return }
        try? await db.patch("\(LiveRoom.path(code))/meta", ["state": state])
    }

    /// Push a team's authoritative score (host owns scoring / manual override).
    func setScore(_ uid: String, _ score: Int) async {
        guard isOpen else { return }
        try? await db.put("\(LiveRoom.path(code))/scores/\(uid)", max(0, score))
    }

    /// Host-plays-too: register the host as a team so they appear in the roster +
    /// standings (their uid is `hostUid`; the rules allow it since it's their own).
    func joinAsHost(name: String) async {
        guard isOpen, !hostUid.isEmpty else { return }
        let t = LiveRoom.Team(name: name, joinedAt: Self.nowMS())
        if let json = try? JSONEncoder().encode(t) { try? await db.putJSON("\(LiveRoom.path(code))/teams/\(hostUid)", json) }
    }

    /// Host-plays-too: submit the host's own answer for a question (auto-scored on
    /// reveal alongside every other player).
    func submitHostAnswer(qid: String, choice: Int) async {
        guard isOpen, !hostUid.isEmpty else { return }
        let a = LiveRoom.Answer(choice: choice, text: nil, ts: Self.nowMS())
        if let json = try? JSONEncoder().encode(a) { try? await db.putJSON("\(LiveRoom.path(code))/answers/\(qid)/\(hostUid)", json) }
    }

    /// Tear the room down (host-only delete allowed by the rules).
    func close() async {
        streamTasks.forEach { $0.cancel() }; answersTask?.cancel()
        streamTasks = []; answersTask = nil
        let code = self.code
        self.code = ""
        guard !code.isEmpty else { return }
        try? await db.delete(LiveRoom.path(code))
    }

    // MARK: Streams

    // Each watcher self-reconnects: if the host's SSE connection drops (lock,
    // background, signal loss, token expiry) the stream ends; we back off and
    // re-open. RTDB re-sends the whole node on re-subscribe, so the roster /
    // answers / scores resync — the host keeps running the game through a drop.
    private func watchTeams(_ code: String) {
        streamTasks.append(Task { [weak self, db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/teams") {
                    do { for try await ev in stream { await self?.applyTeams(ev) } } catch { }
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        })
    }
    private func watchScores(_ code: String) {
        streamTasks.append(Task { [weak self, db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/scores") {
                    do { for try await ev in stream { await self?.applyScores(ev) } } catch { }
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        })
    }
    private func watchAnswers(_ code: String, qid: String) {
        answersTask?.cancel()
        answersTask = Task { [weak self, db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/answers/\(qid)") {
                    do { for try await ev in stream { await self?.applyAnswers(ev, qid: qid) } } catch { }
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        }
    }

    private func applyTeams(_ ev: FirebaseRTDB.StreamEvent) {
        Self.merge(ev, into: &teams, as: LiveRoom.Team.self)
    }
    private func applyScores(_ ev: FirebaseRTDB.StreamEvent) {
        Self.merge(ev, into: &scores, as: Int.self)
    }
    private func applyAnswers(_ ev: FirebaseRTDB.StreamEvent, qid: String) {
        guard qid == currentQid else { return }
        Self.merge(ev, into: &answers, as: LiveRoom.Answer.self)
        // Drop pre-session answers (see sessionStartMS). A missing ts is kept:
        // only provably-stale entries are excluded.
        answers = answers.filter { $0.value.ts >= sessionStartMS }
    }

    /// Fold an RTDB SSE event into a `[uid: T]` dict. Path "/" replaces the whole
    /// node; "/uid" upserts (or removes on null) one child.
    private static func merge<T: Decodable>(_ ev: FirebaseRTDB.StreamEvent, into dict: inout [String: T], as: T.Type) {
        if ev.path == "/" {
            dict = [:]
            if let d = ev.dataJSON, let map = try? JSONDecoder().decode([String: T].self, from: d) { dict = map }
        } else {
            let key = String(ev.path.dropFirst())
            if let d = ev.dataJSON, let v = try? JSONDecoder().decode(T.self, from: d) { dict[key] = v }
            else { dict.removeValue(forKey: key) }
        }
    }

    static func nowMS() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
}
