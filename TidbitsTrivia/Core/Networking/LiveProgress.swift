import Foundation

/// A8.11 — what the BIG SCREEN says about how far the room has got. The cockpit has
/// always known how many tables are in; the room did not, so only the host could tell
/// whether the stragglers were still typing, and the room could not chivvy them.
///
/// Pure and mirrored in C# as `LiveProgress`, so the Mac and Windows projectors cannot
/// word it differently.
nonisolated enum LiveProgress {
    /// "3 of 8 answered", or nil when nobody has joined — "0 of 0 answered" on a
    /// projector is noise, and a lobby is not a question in progress.
    ///
    /// Counts TEAMS, not devices (G7): a table of three phones is one line on the
    /// scoreboard and must be one tick here too, or the room reads "5 of 8" when five
    /// PHONES belonging to two tables have answered.
    static func answersIn(answered: Int, joined: Int) -> String? {
        guard joined > 0 else { return nil }
        return "\(max(0, min(answered, joined))) of \(joined) answered"
    }
}
