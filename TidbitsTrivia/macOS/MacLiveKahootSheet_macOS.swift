#if os(macOS)
import Foundation

// MARK: - Kahoot spreadsheet export (QUIZ-FORMATS-RESEARCH §4)

/// Write a night as Kahoot's own `.xlsx` import template, so a host can hand a
/// Tidbits night to someone who runs Kahoot. Their importer accepts ONLY xlsx,
/// so a CSV would be useless here; this builds a minimal but valid OOXML
/// workbook (inline strings, one sheet, no styles) laid out exactly like the
/// template they publish: instructions in rows 1-6, the header in row 8, data
/// from row 9, with the row number in column A.
///
/// Their caps are real constraints of THEIR importer (95 characters for a
/// question, 60 for an answer), so text is truncated to fit — and every
/// truncation is REPORTED, never silently applied. Anything that is not a
/// multiple-choice question cannot be represented in their sheet at all and is
/// named instead of being turned into something a player could not answer.
enum LiveKahootSheet {
    static let questionCap = 95
    static let answerCap = 60
    /// The only values their importer accepts; anything else silently becomes 20.
    static let allowedTimes = [5, 10, 20, 30, 60, 90, 120, 240]

    static let header = ["Question - max 95 characters",
                         "Answer 1 - max 60 characters", "Answer 2 - max 60 characters",
                         "Answer 3 - max 60 characters", "Answer 4 - max 60 characters",
                         "Time limit (sec) - 5,10,20,30,60,90 or 120 secs",
                         "Correct answer(s) - choose at least one"]

    static let instructions = [
        "Quiz template",
        "Exported from Tidbits Trivia. Add or edit questions below, then upload this file to Kahoot.",
        "Questions have a limit of 95 characters and answers 60 characters. If several answers are correct, separate them with a comma.",
        "The header row below must stay exactly as it is — Kahoot's importer reads it.",
    ]

    struct Row {
        var prompt: String
        var answers: [String]     // 2...4
        var seconds: Int
        var correct: [Int]        // 1-based
    }

    /// Which questions can travel, and what could not. Pure, so it is tested
    /// without writing a file.
    static func rows(for questions: [Question], seconds: Int?) -> (rows: [Row], notes: [String]) {
        var rows: [Row] = []
        var notes: [String] = []
        for (i, q) in questions.enumerated() {
            let n = i + 1
            guard LiveNightHost.isMCQ(q) else {
                notes.append("Q\(n): a \(kindName(q)) has no form in Kahoot's sheet — left out")
                continue
            }
            let answers = q.options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard answers.count >= 2 else {
                notes.append("Q\(n): fewer than two answer choices — left out")
                continue
            }
            if answers.count > 4 {
                notes.append("Q\(n): Kahoot allows four answers; the last \(answers.count - 4) were left out")
            }
            let kept = Array(answers.prefix(4))
            guard let correctText = q.options.indices.contains(q.correctIndex) ? q.options[q.correctIndex] : nil,
                  let correctIdx = kept.firstIndex(of: correctText) else {
                notes.append("Q\(n): the correct answer is not among the first four choices — left out")
                continue
            }
            if q.prompt.count > questionCap {
                notes.append("Q\(n): the question was \(q.prompt.count) characters and Kahoot allows \(questionCap) — shortened")
            }
            for (j, a) in kept.enumerated() where a.count > answerCap {
                notes.append("Q\(n): answer \(j + 1) was \(a.count) characters and Kahoot allows \(answerCap) — shortened")
            }
            if q.imageURL != nil {
                notes.append("Q\(n): Kahoot's sheet carries no pictures — add it in their editor after uploading")
            }
            rows.append(Row(prompt: clip(q.prompt, questionCap),
                            answers: kept.map { clip($0, answerCap) },
                            seconds: nearestTime(seconds),
                            correct: [correctIdx + 1]))
        }
        return (rows, notes)
    }

    private static func kindName(_ q: Question) -> String {
        if q.closest != nil { return "numeric question" }
        if q.ordering != nil { return "put-in-order question" }
        if q.matching != nil { return "match-up question" }
        if q.enumerate != nil { return "name-as-many question" }
        if q.accepted != nil { return "type-the-answer question" }
        return "question"
    }

    static func nearestTime(_ seconds: Int?) -> Int {
        guard let s = seconds, s > 0 else { return 20 }
        return allowedTimes.min(by: { abs($0 - s) < abs($1 - s) }) ?? 20
    }

    private static func clip(_ s: String, _ cap: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        return flat.count <= cap ? flat : String(flat.prefix(cap - 1)) + "…"
    }

    // MARK: The workbook

    static func xlsx(_ rows: [Row]) -> Data {
        var sheet = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        sheet += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
        for (i, line) in instructions.enumerated() {
            sheet += "<row r=\"\(i + 1)\">" + cell("B", i + 1, text: line) + "</row>"
        }
        sheet += "<row r=\"8\">"
        for (i, h) in header.enumerated() {
            sheet += cell(column(1 + i + 1), 8, text: h)   // B..H
        }
        sheet += "</row>"
        for (i, r) in rows.enumerated() {
            let n = 9 + i
            var cells = cell("A", n, number: i + 1) + cell("B", n, text: r.prompt)
            for j in 0..<4 {
                cells += cell(column(3 + j), n, text: j < r.answers.count ? r.answers[j] : "")
            }
            cells += cell("G", n, number: r.seconds)
            cells += cell("H", n, text: r.correct.map(String.init).joined(separator: ","))
            sheet += "<row r=\"\(n)\">" + cells + "</row>"
        }
        sheet += "</sheetData></worksheet>"

        let contentTypes = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>"#
        let rels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#
        let workbook = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"#
        let workbookRels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#

        return ZipContainer.write([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet.utf8)),
        ])
    }

    /// A..Z is all this sheet needs (it is eight columns wide).
    static func column(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(64 + max(1, min(26, index)))))
    }

    private static func cell(_ col: String, _ row: Int, text: String) -> String {
        text.isEmpty ? "" : "<c r=\"\(col)\(row)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(text))</t></is></c>"
    }
    private static func cell(_ col: String, _ row: Int, number: Int) -> String {
        "<c r=\"\(col)\(row)\"><v>\(number)</v></c>"
    }

    static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         // A control character is not legal in XML at all and would make the
         // workbook unopenable rather than merely wrong.
         .filter { $0 == "\t" || $0 == "\n" || $0.unicodeScalars.allSatisfy { $0.value >= 32 } }
    }
}
#endif
