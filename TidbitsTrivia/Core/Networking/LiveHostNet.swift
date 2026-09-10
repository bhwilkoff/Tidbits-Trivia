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
    /// A3.12: the host's renames (`live/{code}/meta/names/{uid}` — under `meta`, which the deployed rules already hand the host) — a joiner
    /// owns its own `teams/{uid}` node, so a typo the host wants gone from the big
    /// screen is corrected OVER it, not in it. `teams` is the merged view.
    private var rawTeams: [String: LiveRoom.Team] = [:]
    private(set) var names: [String: String] = [:]
    private(set) var scores: [String: Int] = [:]
    /// A2.14: every table's joker pick (`jokers/{uid}`), live. The host locks a round's
    /// picks when it starts (`LiveJoker.played`); this is only what the phones say now.
    private(set) var jokers: [String: LiveRoom.Joker] = [:]
    var jokerPicks: [String: Int] { jokers.mapValues(\.round) }
    /// Submissions for the CURRENT question (uid → answer), reset each question.
    private(set) var answers: [String: LiveRoom.Answer] = [:]
    private(set) var lastError: String?

    var isOpen: Bool { !code.isEmpty }
    var joined: [Joined] {
        teams.map { Joined(id: $0.key, name: $0.value.name, score: scores[$0.key] ?? 0) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
    }
    struct Joined: Identifiable, Hashable { let id: String; let name: String; let score: Int }

    /// G7: the joins as roster members. The wire already carried everything the
    /// roster needs — name and joinedAt, keyed by uid — so several phones on one
    /// team was never a transport problem, only a grouping one.
    var members: [LiveMember] {
        teams.map { LiveMember(uid: $0.key, teamName: $0.value.name, joinedAt: $0.value.joinedAt) }
    }

    /// G7: how many TEAMS have answered.
    ///
    /// `answers.count` counts DEVICES, which was the same number until tables
    /// could group. A host watching for "everyone is in" would read 3 answered
    /// from one table of three phones and move on while two tables were still
    /// thinking.
    var answeredTeamCount: Int {
        var stamps: [String: Int] = [:]
        for (uid, a) in answers { stamps[uid] = a.sv ?? a.ts }
        return LiveTeamRoster.scorableUIDs(members: members, answeredAt: stamps).count
    }

    /// G7: the answer that counts for a team, looked up by the row's id (which is
    /// the LEADER's uid). Any member may have answered, so keying the cockpit's
    /// per-team row on the leader alone reports "no answer" for a table whose
    /// second phone submitted.
    func teamAnswer(forTeamID id: String) -> LiveRoom.Answer? {
        if let mine = answers[id] { return mine }
        guard let team = LiveTeamRoster.team(of: id, in: members) else { return nil }
        var stamps: [String: Int] = [:]
        for m in team.members {
            if let a = answers[m.uid] { stamps[m.uid] = a.sv ?? a.ts }
        }
        guard let uid = LiveTeamRoster.answeringMember(team: team, answeredAt: stamps) else { return nil }
        return answers[uid]
    }

    /// G7: one row per TEAM, not per device. Three phones that typed the same team
    /// name are one row with one score; only one member is ever scored for a
    /// question, so summing the members is the team's score.
    var joinedTeams: [Joined] {
        LiveTeamRoster.teams(members).map { team in
            let score = team.members.reduce(0) { $0 + (scores[$1.uid] ?? 0) }
            return Joined(id: team.leader?.uid ?? team.key, name: team.name, score: score)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
    }

    /// F-006: rules deny the host deleting other uids' answer nodes, so a
    /// reused room code cannot have its stale ledger cleared server-side.
    /// Instead the host IGNORES answers written before this session opened —
    /// which protects both the answered-count and reveal scoring.
    private var sessionStartMS: Int = 0

    private var streamTasks: [Task<Void, Never>] = []
    private var answersTask: Task<Void, Never>?
    private var currentQid = ""

    // MARK: Preview seams (offline renders only — never in normal use)

    /// Make the net look OPEN with a roster, without a network. The projector
    /// renderer uses this to draw the join panel, the team strip and the vote
    /// tally offline; nothing here touches the database.
    func previewSeed(code: String, teams: [String: LiveRoom.Team], scores: [String: Int],
                     answers: [String: LiveRoom.Answer]) {
        self.code = code
        self.hostUid = "preview-host"
        self.teams = teams
        self.scores = scores
        self.answers = answers
    }

    // MARK: Lifecycle

    /// Open a room and start streaming joins. Returns the code. `name`/`venue`
    /// come from the host product (a Tidbits Live event, or a Trivia Night).
    @discardableResult
    /// Open the room. `resuming` is the ONE case where the previous scoreboard must
    /// survive: the host's app died mid-night and is picking the same room back up, so
    /// wiping scores would punish every table for a crash they did not cause (A2.13).
    func open(name: String, venue: String = "", code forced: String? = nil, resuming: Bool = false) async -> String? {
        do {
            let host = try await db.ensureAuth()
            sessionStartMS = Self.nowMS()
            // TIDBITS_LIVE_CODE pins a known code for deterministic device/CI testing.
            let code = forced ?? ProcessInfo.processInfo.environment["TIDBITS_LIVE_CODE"] ?? FirebaseRTDB.newRoomCode()
            let meta = LiveRoom.Meta(host: host, createdAt: Self.nowMS(), name: name,
                                     venue: venue, state: "lobby")
            // A resume PATCHes meta so the host's renames (meta/names, A3.12) survive the
            // crash with the scores; a fresh night PUTs it and starts clean.
            if resuming { try await db.patchJSON("\(LiveRoom.path(code))/meta", try JSONEncoder().encode(meta)) }
            else { try await db.putJSON("\(LiveRoom.path(code))/meta", try JSONEncoder().encode(meta)) }
            // F-006/F-008: a room code reused across sessions (host
            // crash-recovery, or the QA loop's pinned code) inherits the
            // previous night's answers AND scores — a fresh night read
            // "1 answered" and showed a team with last session's points
            // before anyone played. A new session owns a clean answer ledger
            // and a zeroed scoreboard; the host owns scores/ so this delete
            // is rules-legal (the answers/ delete is not — rules deny
            // deleting other uids' nodes — hence the sessionStartMS filter
            // in applyAnswers). teams/ persists deliberately (rejoin-safe:
            // the same anon uid keeps its name across a reload).
            try? await db.delete("\(LiveRoom.path(code))/answers")
            if !resuming {
                try? await db.delete("\(LiveRoom.path(code))/scores")
                try? await db.delete("\(LiveRoom.path(code))/jokers")   // A2.14: last night's picks are not this night's
                scores = [:]; jokers = [:]
            }
            publishedMedia = []
            self.code = code
            self.hostUid = host
            watchTeams(code)
            watchNames(code)
            watchScores(code)
            watchJokers(code)   // A2.14
            watchRemote(code)   // G6
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

    /// Decision 060: write a clip to the room ONCE so every joiner can fetch it.
    /// Returns whether the node is in place (already written counts). The caller
    /// publishes the `pub` that references it only after this returns true — a
    /// reference to a node that is not there is a "Clip unavailable" on forty
    /// phones.
    private var publishedMedia: Set<String> = []
    func publishMedia(id: String, _ media: LiveRoom.RoomMedia) async -> Bool {
        guard isOpen else { return false }
        if publishedMedia.contains(id) { return true }
        guard media.bytes <= LiveRoom.mediaMaxBytes,
              let json = try? JSONEncoder().encode(media) else { return false }
        do {
            try await db.putJSON(LiveRoom.mediaPath(code, id: id), json)
            publishedMedia.insert(id)
            return true
        } catch {
            lastError = "Couldn't send the clip to the room: \(error)"
            return false
        }
    }

    func setState(_ state: String) async {
        guard isOpen else { return }
        try? await db.patch("\(LiveRoom.path(code))/meta", ["state": state])
    }

    /// Push a team's authoritative score (host owns scoring / manual override).
    func setScore(_ uid: String, _ score: Int) async {
        guard isOpen else { return }
        scores[uid] = max(0, score)   // the stream echoes it later; a re-score reads it now
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
    /// G6: the host's phone remote writes here; the desktop reads and DECIDES.
    ///
    /// Deliberately a separate node from `pub`: the remote never writes the show
    /// state, because two writers is how a room sees question 4 while the host
    /// reads question 5. Additive — a host that never pairs a remote simply has an
    /// empty node, and an older client never looks at it.
    private(set) var remotePIN = ""
    private(set) var lastRemoteID = 0
    /// Set by the host view when a command should run. The net layer does the
    /// accept/refuse; the view owns what the verbs MEAN.
    var onRemoteCommand: ((String) -> Void)?

    /// Pair a remote. The PIN is shown on the LAPTOP only — the room code is
    /// printed on the projector, so it authorises nothing.
    func startRemote(pin: String? = nil) -> String {
        if let pin, pin.count == 6 { remotePIN = pin }   // a harness-known PIN (TIDBITS_LIVE_REMOTE_PIN); production never passes one
        else if remotePIN.isEmpty { remotePIN = LiveRemote.makePIN() }
        return remotePIN
    }
    func stopRemote() { remotePIN = "" }

    private func watchRemote(_ code: String) {
        streamTasks.append(Task { [weak self, db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/control") {
                    do { for try await ev in stream { await self?.applyRemote(ev) } } catch { }
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        })
    }

    private func applyRemote(_ ev: FirebaseRTDB.StreamEvent) {
        guard let d = ev.dataJSON,
              let cmd = try? JSONDecoder().decode(RemoteCommand.self, from: d) else { return }
        // Every refusal path lives in Core and is tested there: wrong PIN, unknown
        // verb, and an id already run (so a retried write cannot skip a question).
        guard LiveRemote.accepted(cmd, pin: remotePIN, lastExecutedID: lastRemoteID) else { return }
        lastRemoteID = cmd.id
        onRemoteCommand?(cmd.verb)
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
    private func watchJokers(_ code: String) {
        streamTasks.append(Task { [weak self, db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/jokers") {
                    do { for try await ev in stream { await self?.applyJokers(ev) } } catch { }
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        })
    }
    private func applyJokers(_ ev: FirebaseRTDB.StreamEvent) {
        Self.merge(ev, into: &jokers, as: LiveRoom.Joker.self)
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
        Self.merge(ev, into: &rawTeams, as: LiveRoom.Team.self)
        rebuildTeams()
    }
    private func applyNames(_ ev: FirebaseRTDB.StreamEvent) {
        Self.merge(ev, into: &names, as: String.self)
        rebuildTeams()
    }
    private func rebuildTeams() {
        teams = rawTeams.reduce(into: [:]) { out, kv in
            var t = kv.value
            if let n = names[kv.key]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { t.name = n }
            out[kv.key] = t
        }
    }
    private func watchNames(_ code: String) {
        streamTasks.append(Task { [weak self, db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream("\(LiveRoom.path(code))/meta/names") {
                    do { for try await ev in stream { await self?.applyNames(ev) } } catch { }
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        })
    }
    /// A3.12: rename a joined team for the whole night — the projector, the standings,
    /// the answer sheet and the exports all read the merged name.
    func rename(_ uid: String, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !uid.isEmpty, !n.isEmpty, let json = try? JSONEncoder().encode(String(n.prefix(40))) else { return }
        try? await db.putJSON("\(LiveRoom.path(code))/meta/names/\(uid)", json)
        names[uid] = String(n.prefix(40)); rebuildTeams()   // the stream echoes it; the cockpit should not wait
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
