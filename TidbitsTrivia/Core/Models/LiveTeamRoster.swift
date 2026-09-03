import Foundation

/// G7 — several phones, one team.
///
/// Today a device IS a team, which is right for a table that shares one phone and
/// wrong for the table that does not: three friends each open the app, each
/// becomes a separate team, and the table's night is split three ways with three
/// near-identical rows in the standings.
///
/// So a device joins a NAMED team, and the rules below decide what that means.
/// They are pure functions because six stacks have to agree on them: which typed
/// names are the same team, whose answer counts, and who leads.
struct LiveMember: Codable, Hashable, Identifiable {
    var uid: String
    var teamName: String
    var joinedAt: Int          // epoch ms, from the SERVER
    var id: String { uid }
}

struct RosterTeam: Hashable, Identifiable {
    var key: String            // the normalised name — what makes two typings one team
    var name: String           // the display name, as the LEADER typed it
    var members: [LiveMember]  // earliest first
    var id: String { key }

    var leader: LiveMember? { members.first }
    var size: Int { members.count }
}

enum LiveTeamRoster {

    /// Two people typing the same team name must land on the SAME team, so the key
    /// folds the things a person varies without meaning to: surrounding space,
    /// case, and runs of whitespace ("the  quizzinators " == "The Quizzinators").
    ///
    /// It deliberately does NOT fold punctuation or accents. "St. Elmo" and
    /// "St Elmo" are plausibly different tables, and silently merging two teams is
    /// worse than showing two rows: the host can merge, but cannot un-merge a
    /// night's scoring.
    static func key(_ teamName: String) -> String {
        teamName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Group members into teams, earliest joiner first within each.
    ///
    /// Ordering is by `joinedAt` and then by uid. The uid tiebreak is not
    /// decoration: two phones can be stamped the same millisecond by the server,
    /// and without it the leader — and therefore whose answer counts — would differ by
    /// stack and by run.
    static func teams(_ members: [LiveMember]) -> [RosterTeam] {
        var byKey: [String: [LiveMember]] = [:]
        for m in members where !key(m.teamName).isEmpty {
            byKey[key(m.teamName), default: []].append(m)
        }
        return byKey.map { k, v in
            let ordered = v.sorted {
                $0.joinedAt == $1.joinedAt ? $0.uid < $1.uid : $0.joinedAt < $1.joinedAt
            }
            // The display name is the LEADER's spelling. Someone joining "the
            // quizzinators" does not get to restyle the row the table already has.
            return RosterTeam(key: k, name: ordered.first?.teamName ?? k, members: ordered)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The team a uid belongs to.
    static func team(of uid: String, in members: [LiveMember]) -> RosterTeam? {
        teams(members).first { $0.members.contains { $0.uid == uid } }
    }

    /// Whose answer counts for a team, given who has answered.
    ///
    /// The FIRST answer by server stamp stands, and later members cannot replace
    /// it. Any other rule lets the loudest phone at the table overwrite a
    /// teammate — or lets a team change its mind after watching the tally move.
    /// Same ordering the buzzer uses, for the same reason.
    static func answeringMember(team: RosterTeam,
                                answeredAt: [String: Int]) -> String? {
        var bestUID: String?
        var bestAt = Int.max
        for member in team.members {
            guard let at = answeredAt[member.uid] else { continue }
            if at < bestAt || (at == bestAt && member.uid < (bestUID ?? "")) {
                bestAt = at
                bestUID = member.uid
            }
        }
        return bestUID
    }

    /// Who leads after `gone` have left.
    ///
    /// A team whose leader closes their phone is not disbanded — the earliest
    /// remaining member leads. A table does not stop playing because one person
    /// went to the bar.
    static func leaderAfterDepartures(team: RosterTeam, gone: Set<String>) -> LiveMember? {
        team.members.first { !gone.contains($0.uid) }
    }
}
