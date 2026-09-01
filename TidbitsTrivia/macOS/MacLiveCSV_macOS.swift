#if os(macOS)
import Foundation

// MARK: - CSV question import (macOS-DESIGN §A2.2 — the host's own question bank)

/// Reading and parsing a host's CSV question bank.
///
/// Pure logic, deliberately out of the builder view: it is the piece most worth
/// testing and the view drags a whole editor in with it. Same reason `LiveTeam`
/// moved to the model file.
enum LiveCSV {
/// Read a host's CSV whatever their spreadsheet wrote it as.
///
/// The old code was `try? String(contentsOf: url, encoding: .utf8)` with a bare
/// `return` on failure, and Excel on Windows commonly writes UTF-16LE with a BOM
/// — so the single most likely CSV a pub host owns silently imported nothing at
/// all, with no message.
///
/// Order matters, and the first version of THIS got it wrong too: UTF-8 decoding
/// of UTF-16LE bytes frequently SUCCEEDS, because a NUL is a valid UTF-8 scalar.
/// It returns "p\0r\0o\0m\0p\0t" — text by the type system, mojibake to a
/// reader — and the UTF-16 branch never runs. So the BOM is checked first, and
/// any candidate containing a NUL is rejected as a misread.
static func readTextFile(at url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }

    // 1. A byte-order mark is unambiguous; trust it over any guess.
    if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
        if let text = String(data: data, encoding: .utf16), plausible(text) { return text }
    }
    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
        if let text = String(data: data.dropFirst(3), encoding: .utf8), plausible(text) { return text }
    }

    // 2. UTF-16 WITHOUT a BOM is only worth trying when the bytes look like it —
    //    a Latin-1 line of even length decodes as UTF-16LE into perfectly
    //    "plausible" CJK mojibake, which is how the Latin-1 case regressed.
    //    Interleaved NULs are the tell for 16-bit text holding ASCII.
    let nulShare = Double(data.prefix(512).filter { $0 == 0 }.count) / Double(max(data.prefix(512).count, 1))
    if nulShare > 0.2 {
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf16] {
            if let text = String(data: data, encoding: encoding), plausible(text) { return text }
        }
    }

    // 3. Then the 8-bit candidates in turn, each one sanity-checked.
    for encoding in [String.Encoding.utf8, .windowsCP1252, .isoLatin1, .macOSRoman] {
        if let text = String(data: data, encoding: encoding), plausible(text) { return text }
    }
    // 4. Last resort: let Foundation guess.
    var used: String.Encoding = .utf8
    if let text = try? String(contentsOf: url, usedEncoding: &used), plausible(text) { return text }
    return nil
}

/// Does this decode look like text a person wrote, rather than a misread?
/// A NUL almost always means UTF-16 bytes read as something else; a replacement
/// character means the encoding was wrong for at least one byte.
private static func plausible(_ text: String) -> Bool {
    !text.isEmpty && !text.contains("\0") && !text.contains("\u{FFFD}")
}

/// Parse a host's CSV question bank, in either of the two shapes Tidbits has
/// shipped — and prefer a NAMED HEADER over both.
///
/// The two clients diverged silently. macOS wrote
/// `prompt, correct, wrong1, wrong2, wrong3, [category], [difficulty], [explanation]`
/// and Windows wrote
/// `prompt, optionA, optionB, optionC, optionD, correct(1-4), [explanation]`.
/// A Windows-format file imported here marked the FIRST option correct — for
/// "…,Phrygia,Lydia,Caria,Lycia,2,…" the answer became Phrygia when the truth is
/// Lydia. Silent, and it marks a correct player wrong. A Mac-format file on
/// Windows imported nothing at all, because field 5 would not parse as 1-4.
///
/// So: a header row decides, whichever order it names. Without one, the shape is
/// inferred from whether field 5 is an answer INDEX (1-4) or a category word.
static func parseCSVQuestions(_ text: String) -> [Question] {
    var rows = text.split(whereSeparator: \.isNewline).map { splitCSVLine(String($0)) }
    guard !rows.isEmpty else { return [] }

    var header: [String: Int]? = nil
    if let first = rows.first, isHeaderRow(first) {
        var map: [String: Int] = [:]
        for (i, name) in first.enumerated() {
            map[name.lowercased().trimmingCharacters(in: .whitespaces)] = i
        }
        header = map
        rows.removeFirst()
    }

    var out: [Question] = []
    for f in rows {
        guard f.count >= 5, !f[0].isEmpty else { continue }
        if let q = question(from: f, header: header) { out.append(q) }
    }
    return out
}

private static func isHeaderRow(_ f: [String]) -> Bool {
    guard let first = f.first?.lowercased() else { return false }
    return first == "prompt" || first == "question"
}

private static func value(_ f: [String], _ header: [String: Int]?, _ names: [String]) -> String? {
    guard let header else { return nil }
    for n in names {
        if let i = header[n], f.indices.contains(i) {
            let v = f[i].trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { return v }
        }
    }
    return nil
}

private static func question(from f: [String], header: [String: Int]?) -> Question? {
    let prompt = f[0].trimmingCharacters(in: .whitespaces)
    guard !prompt.isEmpty else { return nil }

    var options: [String] = []
    var correct = ""
    var category = "mixed"
    var difficulty = 3
    var explanation = ""

    if header != nil {
        // Named columns win, whatever order they came in.
        let opts = ["optiona", "optionb", "optionc", "optiond", "option1", "option2",
                    "option3", "option4", "wrong1", "wrong2", "wrong3", "a", "b", "c", "d"]
            .compactMap { value(f, header, [$0]) }
        let answer = value(f, header, ["correct", "answer", "correctanswer"]) ?? ""
        // "correct" may be the answer TEXT or a 1-based index into the options.
        if let idx = Int(answer), (1...max(opts.count, 4)).contains(idx), opts.indices.contains(idx - 1) {
            correct = opts[idx - 1]
            options = opts
        } else {
            correct = answer
            // Only prepend the answer if the option columns did not already carry
            // it. Prepending unconditionally gave five options, and the prefix(4)
            // below then dropped a real one — caught by the export round-trip.
            options = opts.contains(answer) ? opts : ([answer] + opts).filter { !$0.isEmpty }
        }
        category = (value(f, header, ["category"]) ?? "mixed").lowercased()
        difficulty = Int(value(f, header, ["difficulty"]) ?? "") ?? 3
        explanation = value(f, header, ["explanation", "reveal", "note"]) ?? ""
    } else {
        // No header. Field 5 tells the two shipped shapes apart: an answer INDEX
        // (1-4) means the Windows order, anything else means the macOS order.
        let fifth = f.count > 5 ? f[5].trimmingCharacters(in: .whitespaces) : ""
        if let idx = Int(fifth), (1...4).contains(idx) {
            options = [f[1], f[2], f[3], f[4]].map { $0.trimmingCharacters(in: .whitespaces) }
            correct = options[idx - 1]
            explanation = f.count > 6 ? f[6] : ""
        } else {
            correct = f[1].trimmingCharacters(in: .whitespaces)
            options = [f[1], f[2], f[3], f[4]].map { $0.trimmingCharacters(in: .whitespaces) }
            category = (f.count > 5 && !f[5].isEmpty) ? f[5].lowercased() : "mixed"
            difficulty = f.count > 6 ? (Int(f[6]) ?? 3) : 3
            explanation = f.count > 7 ? f[7] : ""
        }
    }

    var opts = options.filter { !$0.isEmpty }
    guard !correct.isEmpty, opts.contains(correct) || opts.isEmpty else { return nil }
    if opts.isEmpty { opts = [correct] }
    while opts.count < 4 { opts.append("—") }
    opts = Array(opts.prefix(4)).shuffled()
    guard let ci = opts.firstIndex(of: correct) else { return nil }

    return Question(id: UUID().uuidString, prompt: prompt, options: opts, correctIndex: ci,
                    categoryID: category, difficulty: min(5, max(1, difficulty)),
                    explanation: explanation.trimmingCharacters(in: .whitespaces),
                    sourceTitle: "", sourceURL: nil, templateID: "csv")
}

/// Write a question bank back out as CSV — docs/LIVE-EVENT-FILE.md §6.1.
///
/// A host edits their bank in a spreadsheet between weeks; the event file is
/// Tidbits-to-Tidbits and no use for that. Until now import was a one-way door:
/// questions could come in from CSV and never go back out.
///
/// Always emits the NAMED HEADER. It is the only shape neither client can
/// misread, and it is what makes an export re-importable on the other platform.
static func exportCSV(_ questions: [Question]) -> String {
    var out = "prompt,correct,optionA,optionB,optionC,optionD,category,difficulty,explanation\n"
    for q in questions {
        var opts = q.options
        while opts.count < 4 { opts.append("") }
        let fields = [q.prompt, q.correctAnswer,
                      opts[0], opts[1], opts[2], opts[3],
                      q.categoryID, String(q.difficulty), q.explanation]
        out += fields.map(escapeCSVField).joined(separator: ",") + "\n"
    }
    return out
}

/// Quote a field that would otherwise break the row, doubling any inner quote —
/// the same convention `splitCSVLine` reads back.
static func escapeCSVField(_ s: String) -> String {
    guard s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") else { return s }
    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

static func splitCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var cur = ""
    var inQuotes = false
    var i = line.startIndex
    while i < line.endIndex {
        let ch = line[i]
        if inQuotes {
            if ch == "\"" {
                // A doubled quote inside a quoted field is a literal quote — the
                // convention `escapeCSVField` writes and every spreadsheet emits.
                let next = line.index(after: i)
                if next < line.endIndex, line[next] == "\"" { cur.append("\""); i = next }
                else { inQuotes = false }
            } else { cur.append(ch) }
        } else if ch == "\"" {
            inQuotes = true
        } else if ch == "," {
            fields.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
        } else {
            cur.append(ch)
        }
        i = line.index(after: i)
    }
    fields.append(cur.trimmingCharacters(in: .whitespaces))
    return fields
}
}
#endif
