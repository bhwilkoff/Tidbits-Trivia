import Foundation

/// The night's answer sheet (A3.8 / punch list 10, 2026-09-09): one row per
/// team per revealed question — what they submitted and what the host's scorer
/// paid — kept on the HOST as the night goes, because the room only ever holds
/// the current question's answers. Exported as a long CSV beside the standings.
nonisolated struct LiveAnswerRecord: Equatable, Sendable, Identifiable {
    struct Line: Equatable, Sendable { var uid: String; var team: String; var submitted: String; var points: Int }
    var qid: String
    var round: Int
    var number: Int
    var prompt: String
    var answer: String
    var lines: [Line]
    var id: String { qid }
}

nonisolated enum LiveAnswerLog {
    /// What a team submitted, as text, for any format (the cockpit's review lane
    /// uses the same rendering).
    static func submitted(_ q: Question, _ a: LiveRoom.Answer) -> String {
        if q.accepted != nil { return a.text ?? "" }
        if let c = q.closest, let n = a.number {
            let s = n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
            return c.unit.isEmpty ? s : "\(s) \(c.unit)"
        }
        if let ch = a.choice, q.options.indices.contains(ch) { return q.options[ch] }
        if let list = a.list, !list.isEmpty { return list.joined(separator: " · ") }
        if let order = a.order { return order.map(String.init).joined(separator: ",") }
        if let pairs = a.pairs { return pairs.map(String.init).joined(separator: ",") }
        return a.text ?? ""
    }

    /// round,question,prompt,answer,team,submitted,points — quoted where needed.
    static func csv(_ records: [LiveAnswerRecord]) -> String {
        func esc(_ s: String) -> String {
            (s.contains(",") || s.contains("\"") || s.contains("\n"))
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        var out = "round,question,prompt,answer,team,submitted,points\n"
        for r in records {
            for l in r.lines.sorted(by: { $0.team.localizedCaseInsensitiveCompare($1.team) == .orderedAscending }) {
                out += "\(r.round),\(r.number),\(esc(r.prompt)),\(esc(r.answer)),\(esc(l.team)),\(esc(l.submitted)),\(l.points)\n"
            }
        }
        return out
    }
}
