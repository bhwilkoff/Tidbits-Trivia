import Foundation

/// G6 — the host's phone remote, so the emcee can walk the room instead of
/// standing over the laptop.
///
/// Every other Live wire path runs host -> players. This one runs the other way,
/// and that inverts the trust: the phone is now asking the show to advance. Three
/// rules make that safe, and each of them is a way the naive version breaks.
///
/// 1. **The remote REQUESTS; the desktop DECIDES.** The phone writes a command;
///    the host reads it and executes. It never writes `pub` itself. Two writers to
///    the show state is how a room ends up seeing question 4 while the host reads
///    question 5.
/// 2. **Commands carry a MONOTONIC id, not a timestamp.** A retried write or a
///    reconnect can deliver the same command twice, and "next" applied twice skips
///    a question the room never saw. The host runs a command only if its id is
///    strictly greater than the last one it ran, so a replay is a no-op.
/// 3. **The room code is NOT authorisation.** It is printed on the projector —
///    every player in the pub has it. A remote authorised by the code alone would
///    let any table reveal the answer. So the host shows a PIN on the LAPTOP only,
///    and a command without it is refused.
struct RemoteCommand: Codable, Equatable {
    var id: Int          // monotonic within a room
    var verb: String
    var pin: String
}

enum LiveRemote {

    /// What a host can do while walking the room. Deliberately small: this is a
    /// clicker, not a second cockpit. Anything that edits the night — scores,
    /// teams, the question list — stays on the laptop where it can be read
    /// properly before it is changed.
    static let verbs: Set<String> = ["reveal", "next", "skip", "scores", "board"]

    /// A 6-digit pairing PIN. Shown on the host's screen, typed into the phone
    /// once. Six digits because it is read across a room and typed by someone
    /// holding a drink, and because the code it guards is already public.
    static func makePIN() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// Should the host run this command?
    ///
    /// Returns false for a wrong PIN, an unknown verb, or an id that has already
    /// been run — the three ways a command arrives that must not move the show.
    static func accepted(_ cmd: RemoteCommand, pin: String, lastExecutedID: Int) -> Bool {
        guard !pin.isEmpty, cmd.pin == pin else { return false }
        guard verbs.contains(cmd.verb) else { return false }
        return cmd.id > lastExecutedID
    }

    /// The id a remote should send next. The remote tracks its own counter, but a
    /// phone that reconnects has lost it — so it resumes from what the host has
    /// already run rather than restarting at 1, which would be refused forever.
    static func nextID(lastExecutedID: Int) -> Int { lastExecutedID + 1 }
}
