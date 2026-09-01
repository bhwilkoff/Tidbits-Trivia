#if os(macOS)
import Foundation
import PDFKit
import SwiftUI
import Testing

/// The printable fallback — the Wi-Fi-dies contingency (macOS-DESIGN §A5.2).
///
/// It shipped rendering ONE `beginPDFPage` whose media box was the size of the
/// whole content, so a five-round question pack became a single 612 x ~3000pt
/// page: Preview showed an endless strip and printing it scaled the entire night
/// onto one sheet. These tests fail against that implementation, which is the
/// only reason to trust them.
@Suite("Live print")
@MainActor
struct LivePrintTests {

    private static func question(_ i: Int) -> Question {
        Question(id: "print:\(i)",
                 prompt: "Question \(i): a prompt long enough to occupy a realistic amount of vertical space on the printed page.",
                 options: ["Right answer \(i)", "Wrong a", "Wrong b", "Wrong c"], correctIndex: 0,
                 categoryID: "history", difficulty: 3, explanation: "",
                 sourceTitle: "", sourceURL: nil, templateID: "test")
    }

    private static func bigEvent(rounds: Int, perRound: Int) -> LiveEvent {
        var ev = LiveEvent(name: "Friday Pub Quiz", venue: "The Anchor")
        var n = 0
        for r in 0..<rounds {
            var qs: [Question] = []
            for _ in 0..<perRound { n += 1; qs.append(question(n)) }
            ev.rounds.append(LiveRound(title: "Round \(r + 1)", format: .classic,
                                       categoryID: "history", questions: qs))
        }
        return ev
    }

    private static func render(_ page: some View, pages expected: (Int) -> Bool,
                               file: String = #filePath) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidbits-print-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try LivePrint.makePDF(page, to: url)
        #expect(expected(written), "renderer reported \(written) pages")
        guard let doc = PDFDocument(url: url) else {
            Issue.record("the written file is not a readable PDF")
            throw CocoaError(.fileReadCorruptFile)
        }
        return doc
    }

    @Test("a long question pack paginates instead of becoming one endless page")
    func questionPackPaginates() throws {
        let event = Self.bigEvent(rounds: 5, perRound: 8)   // 40 questions — a real pub night
        let doc = try Self.render(QuestionPackPage(event: event), pages: { $0 > 1 })
        #expect(doc.pageCount > 1, "40 questions came out as \(doc.pageCount) page(s)")

        // Every page is US Letter. The bug was a media box the height of the whole
        // content, so this is the assertion that actually pins it.
        for i in 0..<doc.pageCount {
            let box = doc.page(at: i)!.bounds(for: .mediaBox)
            #expect(abs(box.width - 612) < 1, "page \(i + 1) is \(box.width)pt wide")
            #expect(abs(box.height - 792) < 1, "page \(i + 1) is \(box.height)pt tall")
        }
    }

    @Test("a short event still prints as exactly one page")
    func shortEventIsOnePage() throws {
        let event = Self.bigEvent(rounds: 1, perRound: 1)
        let doc = try Self.render(QuestionPackPage(event: event), pages: { $0 == 1 })
        #expect(doc.pageCount == 1)
    }

    @Test("the question pack carries the answers the host reads out")
    func questionPackHasAnswers() throws {
        let event = Self.bigEvent(rounds: 1, perRound: 3)
        let doc = try Self.render(QuestionPackPage(event: event), pages: { $0 >= 1 })
        let text = doc.string ?? ""
        #expect(text.contains("Friday Pub Quiz"))
        #expect(text.contains("The Anchor"))
        #expect(text.contains("Right answer 1"), "the host's copy must show the answer")
        #expect(text.contains("Question 1"))
    }

    @Test("the team answer sheet does NOT leak the answers")
    func answerSheetHidesAnswers() throws {
        // The teams' sheet and the host's pack render from the same event, so the
        // one thing worth pinning is that they differ in exactly this way.
        let event = Self.bigEvent(rounds: 2, perRound: 4)
        let doc = try Self.render(AnswerSheetPage(event: event), pages: { $0 >= 1 })
        let text = doc.string ?? ""
        #expect(text.contains("Team name:"))
        #expect(text.contains("Round 1"))
        #expect(!text.contains("Right answer 1"), "the teams' sheet is printing the answers")
    }

    @Test("the results sheet ranks the teams")
    func resultsRanks() throws {
        let teams = [LiveTeam(name: "The Quizzinators", score: 21),
                     LiveTeam(name: "Trivia Newton John", score: 18)]
        let doc = try Self.render(ResultsPage(name: "Friday Pub Quiz", standings: teams),
                                  pages: { $0 >= 1 })
        let text = doc.string ?? ""
        #expect(text.contains("The Quizzinators"))
        #expect(text.contains("Trivia Newton John"))
        #expect(text.contains("21"))
    }
}
#endif
