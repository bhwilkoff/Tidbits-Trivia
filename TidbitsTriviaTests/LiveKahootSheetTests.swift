#if os(macOS)
import Foundation
import Testing

/// QUIZ-FORMATS-RESEARCH §4 — a Tidbits night as Kahoot's own import template.
@Suite("Kahoot sheet export")
struct LiveKahootSheetTests {
    private func mcq(_ prompt: String, _ options: [String], _ correct: Int) -> Question {
        Question(id: UUID().uuidString, prompt: prompt, options: options, correctIndex: correct,
                 categoryID: "history", difficulty: 3, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "t")
    }

    @Test("only multiple choice travels; every other type is named, not mangled")
    func whatTravels() {
        let typeIn = Question(id: "a", prompt: "Name it", options: ["Lydia"], correctIndex: 0, categoryID: "history",
                              difficulty: 3, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "t",
                              accepted: ["Lydia"])
        let numeric = Question(id: "b", prompt: "How many?", options: ["7"], correctIndex: 0, categoryID: "science",
                               difficulty: 3, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "t",
                               closest: ClosestSpec(answer: 7, min: 0, max: 20, step: 1, tolerance: 2, unit: ""))
        let (rows, notes) = LiveKahootSheet.rows(
            for: [mcq("Which kingdom minted the first coins?", ["Lydia", "Phrygia", "Caria", "Lycia"], 0), typeIn, numeric],
            seconds: 30)
        #expect(rows.count == 1)
        #expect(rows[0].correct == [1] && rows[0].seconds == 30)
        #expect(notes.contains { $0.contains("type-the-answer") } && notes.contains { $0.contains("numeric") })
    }

    @Test("their caps are applied and reported, never applied silently")
    func caps() {
        let long = String(repeating: "x", count: 200)
        let (rows, notes) = LiveKahootSheet.rows(for: [mcq(long, [String(repeating: "y", count: 90), "b", "c", "d"], 0)], seconds: nil)
        #expect(rows[0].prompt.count == LiveKahootSheet.questionCap)
        #expect(rows[0].answers[0].count == LiveKahootSheet.answerCap)
        #expect(notes.contains { $0.contains("shortened") })
        #expect(rows[0].seconds == 20)   // no round timer → their default
    }

    @Test("a fifth answer is dropped, and a correct answer that falls outside the four is refused")
    func fiveAnswers() {
        let keepable = mcq("A?", ["one", "two", "three", "four", "five"], 1)
        let broken = mcq("B?", ["one", "two", "three", "four", "five"], 4)
        let (rows, notes) = LiveKahootSheet.rows(for: [keepable, broken], seconds: nil)
        #expect(rows.count == 1 && rows[0].answers.count == 4 && rows[0].correct == [2])
        #expect(notes.contains { $0.contains("not among the first four") })
    }

    @Test("time snaps to a value their importer accepts")
    func times() {
        #expect(LiveKahootSheet.nearestTime(45) == 30)
        #expect(LiveKahootSheet.nearestTime(75) == 60)
        #expect(LiveKahootSheet.nearestTime(nil) == 20)
        #expect(LiveKahootSheet.allowedTimes.contains(LiveKahootSheet.nearestTime(200)))
    }

    @Test("the workbook is a real xlsx: the five OOXML parts, their header in row 8, data from row 9")
    func workbook() throws {
        let (rows, _) = LiveKahootSheet.rows(
            for: [mcq("Which kingdom minted the first coins?", ["Lydia", "Phrygia", "Caria", "Lycia"], 2)], seconds: 60)
        let data = LiveKahootSheet.xlsx(rows)
        let files = try ZipContainer.readAll(data)
        #expect(Set(files.keys) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                    "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml"])
        let sheet = String(decoding: files["xl/worksheets/sheet1.xml"]!, as: UTF8.self)
        #expect(sheet.contains("<row r=\"8\">") && sheet.contains("Question - max 95 characters"))
        #expect(sheet.contains("r=\"H8\"") )                       // their correct-answer column
        #expect(sheet.contains("<row r=\"9\">"))
        #expect(sheet.contains("<c r=\"B9\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Which kingdom minted the first coins?"))
        #expect(sheet.contains("<c r=\"C9\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Lydia"))
        #expect(sheet.contains("<c r=\"G9\"><v>60</v>"))
        #expect(sheet.contains("<c r=\"H9\" t=\"inlineStr\"><is><t xml:space=\"preserve\">3"))   // 1-based index
    }

    @Test("XML-hostile text cannot produce an unopenable workbook")
    func escaping() throws {
        let (rows, _) = LiveKahootSheet.rows(for: [mcq("Fish & chips <or> \"pie\"?", ["a & b", "b", "c", "d"], 0)], seconds: nil)
        let sheet = String(decoding: try ZipContainer.readAll(LiveKahootSheet.xlsx(rows))["xl/worksheets/sheet1.xml"]!, as: UTF8.self)
        #expect(sheet.contains("Fish &amp; chips &lt;or&gt; &quot;pie&quot;?"))
        #expect(!sheet.contains("<or>"))
    }
}
#endif
