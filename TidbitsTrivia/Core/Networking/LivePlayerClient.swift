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
            watch(code, uid: uid)
        } catch {
            joining = false
            errorText = "Couldn't join. Check the code and your connection."
        }
    }

    func submit(choice: Int) async {
        guard let pub, pub.phase == LiveRoom.Phase.question, submittedQid != pub.qid, let uid else { return }
        chosen = choice; submittedQid = pub.qid
        let ans = LiveRoom.Answer(choice: choice, text: nil, ts: Self.nowMS())
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
    private func streamTask(_ path: String, _ apply: @escaping @MainActor (FirebaseRTDB.StreamEvent) -> Void) -> Task<Void, Never> {
        Task { [db] in
            guard let stream = try? await db.stream(path) else { return }
            do { for try await ev in stream { await MainActor.run { apply(ev) } } } catch {}
        }
    }

    private func applyPub(_ ev: FirebaseRTDB.StreamEvent) {
        guard let d = ev.dataJSON, let p = try? JSONDecoder().decode(LiveRoom.Pub.self, from: d) else { pub = nil; return }
        if p.qid != pub?.qid { submittedQid = nil; chosen = nil }
        pub = p
    }
    private func applyMeta(_ ev: FirebaseRTDB.StreamEvent) {
        if let d = ev.dataJSON, let m = try? JSONDecoder().decode(LiveRoom.Meta.self, from: d) { meta = m }
    }
    private func applyScore(_ ev: FirebaseRTDB.StreamEvent) {
        if let d = ev.dataJSON, let v = try? JSONDecoder().decode(Int.self, from: d) { score = v } else { score = 0 }
    }

    static func nowMS() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
}
