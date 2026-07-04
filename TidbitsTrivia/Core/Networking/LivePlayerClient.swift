import Foundation

/// A player joining a Mac-hosted Tidbits Live event (the LiveRoom contract over
/// Firebase RTDB). Shared by the iOS and tvOS join surfaces — same verb, native
/// idiom on top. The web twin is js/live.js; Android is FirebaseNet.kt.
///
/// The player owns `teams/{uid}` + `answers/{qid}/{uid}`; it streams the host's
/// `pub` (current question), `meta` (lifecycle), and its own `scores/{uid}`.
@MainActor
@Observable
final class LivePlayerClient {
    private let db = FirebaseRTDB.shared

    private(set) var code = ""
    private(set) var joined = false
    private(set) var joining = false
    private(set) var pub: LiveRoom.Pub?
    private(set) var meta: LiveRoom.Meta?
    private(set) var score = 0
    private(set) var submittedQid: String?
    private(set) var chosen: Int?
    private(set) var errorText: String?

    // Live→profile bridge: tally MCQ accuracy across the night, then feed the portable
    // profile once when the game ends (a live night keeps your streak + counts).
    private var liveAnswered = 0
    private var liveCorrect = 0
    private var talliedQid: String?
    private var recordedEnd = false
    private var uid: String?
    private var tasks: [Task<Void, Never>] = []

    /// The player has locked an answer for the current question.
    var hasAnswered: Bool { pub != nil && submittedQid == pub?.qid }

    func join(code rawCode: String, team rawTeam: String) async {
        let code = rawCode.uppercased().filter { $0.isLetter || $0.isNumber }
        let team = rawTeam.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else { errorText = "Enter the 4-letter code from the screen."; return }
        guard !team.isEmpty else { errorText = "Enter a team name."; return }
        joining = true; errorText = nil
        do {
            let uid = try await db.ensureAuth()
            self.uid = uid
            let t = LiveRoom.Team(name: team, joinedAt: Self.nowMS())
            try await db.putJSON("\(LiveRoom.path(code))/teams/\(uid)", try JSONEncoder().encode(t))
            self.code = code; self.joined = true; self.joining = false
            liveAnswered = 0; liveCorrect = 0; talliedQid = nil; recordedEnd = false
            Self.remember(code: code, team: team)   // easy one-tap rejoin after a restart
            watch(code, uid: uid)
        } catch {
            joining = false
            errorText = "Couldn't join. Check the code and your connection."
        }
    }

    func submit(choice: Int) async { chosen = choice; await send(LiveRoom.Answer(choice: choice, ts: Self.nowMS())) }
    func submit(number: Double) async { await send(LiveRoom.Answer(number: number, ts: Self.nowMS())) }
    func submit(text: String) async { await send(LiveRoom.Answer(text: text, ts: Self.nowMS())) }
    func submit(order: [Int]) async { await send(LiveRoom.Answer(order: order, ts: Self.nowMS())) }
    func submit(pairs: [Int]) async { await send(LiveRoom.Answer(pairs: pairs, ts: Self.nowMS())) }
    func submit(list: [String]) async { await send(LiveRoom.Answer(list: list, ts: Self.nowMS())) }

    /// Write a submission for the current question (any shape) — first-write wins;
    /// the host auto-scores it on reveal from its local Question.
    private func send(_ ans: LiveRoom.Answer) async {
        guard let pub, pub.phase == LiveRoom.Phase.question, submittedQid != pub.qid, let uid else { return }
        submittedQid = pub.qid
        do { try await db.putJSON("\(LiveRoom.path(code))/answers/\(pub.qid)/\(uid)", try JSONEncoder().encode(ans)) }
        catch { chosen = nil; submittedQid = nil; errorText = "Answer didn't send — tap again." }
    }

    func leave() async {
        tasks.forEach { $0.cancel() }; tasks = []
        if joined, let uid { try? await db.delete("\(LiveRoom.path(code))/teams/\(uid)") }
        joined = false; pub = nil; meta = nil; score = 0; code = ""; submittedQid = nil; chosen = nil
    }

    private func watch(_ code: String, uid: String) {
        tasks.append(streamTask("\(LiveRoom.path(code))/pub") { [weak self] ev in self?.applyPub(ev) })
        tasks.append(streamTask("\(LiveRoom.path(code))/meta") { [weak self] ev in self?.applyMeta(ev) })
        tasks.append(streamTask("\(LiveRoom.path(code))/scores/\(uid)") { [weak self] ev in self?.applyScore(ev) })
    }
    /// A self-reconnecting SSE subscription. If the connection drops (lock,
    /// background, signal loss, token expiry) the stream ends; we back off briefly
    /// and re-open. RTDB re-sends the whole node on re-subscribe, so the player
    /// transparently resyncs to the current question + score — no manual rejoin for
    /// a transient drop. (The Firebase SDK does this natively on Android/web; the
    /// hand-rolled Apple REST client must do it here.)
    private func streamTask(_ path: String, _ apply: @escaping @MainActor (FirebaseRTDB.StreamEvent) -> Void) -> Task<Void, Never> {
        Task { [db] in
            while !Task.isCancelled {
                if let stream = try? await db.stream(path) {
                    do { for try await ev in stream { await MainActor.run { apply(ev) } } } catch {}
                }
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1.5)) }
            }
        }
    }

    private func applyPub(_ ev: FirebaseRTDB.StreamEvent) {
        guard let d = ev.dataJSON, let p = try? JSONDecoder().decode(LiveRoom.Pub.self, from: d) else { pub = nil; return }
        if p.qid != pub?.qid { submittedQid = nil; chosen = nil }
        pub = p
        // Tally MCQ accuracy once per question, at reveal (answerIndex is present then).
        if p.phase == LiveRoom.Phase.reveal, talliedQid != p.qid {
            talliedQid = p.qid
            if p.options != nil, submittedQid == p.qid {   // an MCQ we answered
                liveAnswered += 1
                if chosen == p.answerIndex { liveCorrect += 1 }
            }
        }
        recordIfEnded()
    }
    private func applyMeta(_ ev: FirebaseRTDB.StreamEvent) {
        if let d = ev.dataJSON, let m = try? JSONDecoder().decode(LiveRoom.Meta.self, from: d) { meta = m }
        recordIfEnded()
    }

    /// Feed the portable profile ONCE when the night ends — a live night keeps the
    /// cross-context streak + counts, and MCQ accuracy nudges the rating.
    private func recordIfEnded() {
        guard joined, !recordedEnd, meta?.state == "ended" || pub?.phase == LiveRoom.Phase.ended else { return }
        recordedEnd = true
        let correct = liveCorrect, answered = liveAnswered
        Task { await PlayerIdentityStore.shared.recordLiveGame(correct: correct, answered: answered) }
    }
    private func applyScore(_ ev: FirebaseRTDB.StreamEvent) {
        if let d = ev.dataJSON, let v = try? JSONDecoder().decode(Int.self, from: d) { score = v } else { score = 0 }
    }

    static func nowMS() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    // MARK: Rejoin memory — pre-fill the last game so reconnecting after an app
    // restart is one tap (the anon uid persists, so the team's score is intact).
    private static let codeKey = "tidbits.live.lastCode"
    private static let teamKey = "tidbits.live.lastTeam"
    static var lastCode: String { UserDefaults.standard.string(forKey: codeKey) ?? "" }
    static var lastTeam: String { UserDefaults.standard.string(forKey: teamKey) ?? "" }
    static func remember(code: String, team: String) {
        UserDefaults.standard.set(code, forKey: codeKey)
        UserDefaults.standard.set(team, forKey: teamKey)
    }
}
