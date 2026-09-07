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

    // §6.1: a named header decides — and it need not be the FIRST row. Kahoot's
    // spreadsheet template carries instruction rows above its header, so the
    // header is looked for in the first dozen rows and everything above it is
    // ignored. Any spreadsheet in QUIZ-FORMATS-RESEARCH §1 is read by its names.
    var header: CSVHeader? = nil
    if let (at, h) = CSVHeader.find(in: rows) {
        header = h
        rows.removeFirst(at + 1)
    }

    var out: [Question] = []
    for f in rows {
        if let header {
            guard f.count >= 2 else { continue }
            if let q = question(from: f, header: header) { out.append(q) }
        } else {
            guard f.count >= 5, !f[0].isEmpty else { continue }
            if let q = question(from: f, header: nil) { out.append(q) }
        }
    }
    return out
}

/// A named header, read by NORMALIZED names so the spreadsheets of other tools
/// map onto ours: "Question Text" (Crowdpurr, Blooket), "Question - max 95
/// characters" and "Answer 1 - max 60 characters" (Kahoot), "Incorrect Answer 1"
/// (Gimkit), "Answer Option 1", "Correct Answer(s)", "Question Media URL"…
struct CSVHeader {
    let columns: [String: Int]     // normalized name -> column
    let promptColumn: Int
    let optionColumns: [Int]       // in sheet order

    /// lowercase, alphanumerics only, minus Kahoot's "- max N characters" suffix.
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        if let r = s.range(of: "max[0-9]+characters$", options: .regularExpression) { s.removeSubrange(r) }
        return s
    }

    static let promptNames = ["prompt", "questiontext", "question"]
    static let correctNames = ["correct", "correctanswer", "correctanswers", "answer", "correctoption", "correctanswerindex"]

    static func isOptionName(_ n: String) -> Bool {
        n.range(of: "^((answer|option|answeroption|choice|incorrectanswer|wrong|distractor)([1-9]|[a-d])|[a-d])$",
                options: .regularExpression) != nil
    }

    static func find(in rows: [[String]]) -> (Int, CSVHeader)? {
        for (i, row) in rows.prefix(12).enumerated() {
            var cols: [String: Int] = [:]
            for (c, name) in row.enumerated() {
                let n = normalize(name)
                if !n.isEmpty, cols[n] == nil { cols[n] = c }
            }
            guard let prompt = promptNames.compactMap({ cols[$0] }).first else { continue }
            let options = cols.filter { isOptionName($0.key) }.map { ($0.value, $0.key) }
                .sorted { $0.0 < $1.0 }.map(\.0)
            // "Correct answer(s) - choose at least one" (Kahoot) normalizes to a longer
            // name; a column that STARTS with "correctanswer" is the answer column.
            if !correctNames.contains(where: { cols[$0] != nil }),
               let long = cols.first(where: { $0.key.hasPrefix("correctanswer") }) { cols["correctanswers"] = long.value }
            let hasCorrect = correctNames.contains { cols[$0] != nil }
            // A header names the prompt AND either the answer or at least two choices;
            // a data row whose first cell happens to say "question" does neither.
            guard hasCorrect || options.count >= 2 else { continue }
            return (i, CSVHeader(columns: cols, promptColumn: prompt, optionColumns: options))
        }
        return nil
    }

    func value(_ f: [String], _ names: [String]) -> String? {
        for n in names {
            if let i = columns[n], f.indices.contains(i) {
                let v = f[i].trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    func options(_ f: [String]) -> [String] {
        optionColumns.compactMap { f.indices.contains($0) ? f[$0].trimmingCharacters(in: .whitespaces) : nil }
            .filter { !$0.isEmpty }
    }
}

/// The answer cell of another tool's sheet: text, a 1-based index, a letter,
/// Kahoot's "1,3" (multiple correct → the first), Crowdpurr's "a@@@b".
private static func correctAnswers(_ raw: String, options: [String]) -> [String] {
    let parts = raw.components(separatedBy: "@@@").flatMap { $0.components(separatedBy: ";") }
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !parts.isEmpty else { return [] }
    // "1,3" is an index list only if EVERY piece is an index; "Paris, France" is text.
    let commaPieces = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    if commaPieces.count > 1, commaPieces.allSatisfy({ Int($0) != nil }) {
        return commaPieces.compactMap { Int($0) }.filter { options.indices.contains($0 - 1) }.map { options[$0 - 1] }
    }
    return parts.map { p -> String in
        if let idx = Int(p), options.indices.contains(idx - 1) { return options[idx - 1] }
        if p.count == 1, let li = "abcd".firstIndex(of: Character(p.lowercased())) {
            let n = "abcd".distance(from: "abcd".startIndex, to: li)
            if options.indices.contains(n) { return options[n] }
        }
        return p
    }
}

private static func question(from f: [String], header: CSVHeader?) -> Question? {
    var options: [String] = []
    var correct = ""
    var category = "mixed"
    var difficulty = 3
    var explanation = ""
    var imageURL: URL? = nil
    var accepted: [String]? = nil
    var ordering: [String]? = nil
    let prompt: String

    if let header {
        prompt = (f.indices.contains(header.promptColumn) ? f[header.promptColumn] : "").trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return nil }
        let opts = header.options(f)
        let rawAnswer = header.value(f, CSVHeader.correctNames) ?? ""
        let answers = correctAnswers(rawAnswer, options: opts)
        category = (header.value(f, ["category"]) ?? "mixed").lowercased()
        difficulty = Int(header.value(f, ["difficulty"]) ?? "") ?? 3
        explanation = header.value(f, ["explanation", "reveal", "note", "questionnote", "feedback"]) ?? ""
        if let m = header.value(f, ["questionmediaurl", "mediaurl", "media", "imageurl", "image", "picture", "pictureurl"]),
           m.lowercased().hasPrefix("http"), let u = URL(string: m) { imageURL = u }

        // The question TYPE, where a sheet names one: Crowdpurr's type code, Quizizz's
        // "Fill-in-the-blank", Blooket's typing column. Polls have no right answer
        // and are dropped, never imported as a question nobody can get right.
        let type = (header.value(f, ["questiontypecode", "questiontype", "type"]) ?? "").lowercased()
        let typing = header.value(f, ["typing", "typinganswer", "typeanswer"]) != nil
        if type.contains("poll") || type.contains("survey") || type.contains("yesno") || type.contains("likedislike")
            || type.contains("wordcloud") || type.contains("openended") || type.contains("open-ended") { return nil }
        if type.contains("reorder") || type.contains("order") {
            guard opts.count >= 3 else { return nil }
            ordering = opts; options = opts; correct = opts[0]
        } else if typing || type.contains("text") || type.contains("fill") || type.contains("short") || type.contains("numerical") || type.contains("number") {
            let acc = answers.isEmpty ? opts : answers
            guard let first = acc.first else { return nil }
            accepted = acc; options = [first]; correct = first
        } else {
            guard let first = answers.first else { return nil }
            correct = first
            options = opts.contains(first) ? opts : ([first] + opts).filter { !$0.isEmpty }
        }
    } else {
        prompt = f[0].trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return nil }
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
    if accepted == nil && ordering == nil {
        while opts.count < 4 { opts.append("—") }
        opts = Array(opts.prefix(4)).shuffled()
    }
    guard let ci = opts.firstIndex(of: correct) else { return nil }

    return Question(id: UUID().uuidString, prompt: prompt, options: opts, correctIndex: ci,
                    categoryID: category, difficulty: min(5, max(1, difficulty)),
                    explanation: explanation.trimmingCharacters(in: .whitespaces),
                    sourceTitle: "", sourceURL: nil, templateID: "csv",
                    imageURL: imageURL, ordering: ordering, accepted: accepted)
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
    var out = "prompt,correct,optionA,optionB,optionC,optionD,category,difficulty,explanation,imageURL\n"
    for q in questions {
        var opts = q.options
        while opts.count < 4 { opts.append("") }
        let fields = [q.prompt, q.correctAnswer,
                      opts[0], opts[1], opts[2], opts[3],
                      q.categoryID, String(q.difficulty), q.explanation,
                      q.imageURL?.absoluteString ?? ""]
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
