import Foundation

// Daily-parity golden — Apple side (Decision 037). Compiled against the REAL
// repo DailyPick.swift + SeededRNG.swift (stableSeed); ids come from the
// shipped corpus.sqlite (extracted by run.sh). Writes one line per test day:
// "<day> <id1> … <id7>". run.sh diffs this against the Kotlin + JS outputs.

@main
@MainActor
struct ApplePick {
    static let days = ["2026-07-01", "2026-07-02", "2026-09-01",
                       "2026-12-31", "2027-01-15", "2027-02-28"]

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            print("usage: apple_pick <ids-file> <out-file> <cats-tsv>"); exit(2)
        }
        let ids = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard ids.count > 100 else { print("FAIL: only \(ids.count) ids"); exit(1) }
        var out = ""

        let rows = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)
            .split(separator: "\n").compactMap { line -> (id: String, category: String)? in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            }
        for day in days {
            let picked = DailyPick.pickBalanced(ids: rows, day: day,
                                                categoryID: "mixed", count: 7)
            out += "\(day) \(picked.joined(separator: " "))\n"
        }
        try out.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
        print("apple: \(days.count) days written")
    }
}
