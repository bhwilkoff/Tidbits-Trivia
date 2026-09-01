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

static func parseCSVQuestions(_ text: String) -> [Question] {
    var out: [Question] = []
    for raw in text.split(whereSeparator: \.isNewline) {
        let f = splitCSVLine(String(raw))
        guard f.count >= 5, !f[0].isEmpty, !f[1].isEmpty else { continue }
        if ["prompt", "question"].contains(f[0].lowercased()) { continue }   // header row
        var opts = [f[1], f[2], f[3], f[4]].filter { !$0.isEmpty }
        while opts.count < 4 { opts.append("—") }
        opts = Array(opts.prefix(4)).shuffled()
        let ci = opts.firstIndex(of: f[1]) ?? 0
        let cat = (f.count > 5 && !f[5].isEmpty) ? f[5].lowercased() : "mixed"
        let diff = min(5, max(1, f.count > 6 ? (Int(f[6]) ?? 3) : 3))
        let expl = f.count > 7 ? f[7] : ""
        out.append(Question(id: UUID().uuidString, prompt: f[0], options: opts, correctIndex: ci,
                            categoryID: cat, difficulty: diff, explanation: expl,
                            sourceTitle: "", sourceURL: nil, templateID: "csv"))
    }
    return out
}

/// Minimal quote-aware CSV line split (handles "commas, in fields").
static func splitCSVLine(_ line: String) -> [String] {
    var fields: [String] = []; var cur = ""; var inQuotes = false
    for ch in line {
        if ch == "\"" { inQuotes.toggle() }
        else if ch == ",", !inQuotes { fields.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
        else { cur.append(ch) }
    }
    fields.append(cur.trimmingCharacters(in: .whitespaces))
    return fields
}
}
#endif
