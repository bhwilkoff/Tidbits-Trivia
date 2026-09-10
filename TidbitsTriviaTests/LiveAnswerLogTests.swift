import Testing
import Foundation

/// A3.8 — the answer sheet: every team's submission and credit per question, as CSV.
@Suite("Live answer log")
struct LiveAnswerLogTests {
    private func q(accepted: [String]? = nil, closest: ClosestSpec? = nil) -> Question {
        var q = Question(id: "q1", prompt: "Who, \"Neo\"?", options: ["Keanu Reeves", "B", "C", "D"], correctIndex: 0,
                         categoryID: "film", difficulty: 4, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "hand")
        q.accepted = accepted; q.closest = closest
        return q
    }

    @Test("submissions render for typed, chosen, numeric and listed answers")
    func submitted() {
        #expect(LiveAnswerLog.submitted(q(accepted: ["Keanu Reeves"]), LiveRoom.Answer(text: "keanu", ts: 1)) == "keanu")
        #expect(LiveAnswerLog.submitted(q(), LiveRoom.Answer(choice: 0, ts: 1)) == "Keanu Reeves")
        #expect(LiveAnswerLog.submitted(q(), LiveRoom.Answer(list: ["a", "b"], ts: 1)) == "a · b")
        #expect(LiveAnswerLog.submitted(q(), LiveRoom.Answer(ts: 1)) == "")
    }

    @Test("the CSV is long-format, quoted where needed, teams alphabetical")
    func csv() {
        let rec = LiveAnswerRecord(qid: "r0q0", round: 1, number: 1, prompt: "Who, \"Neo\"?", answer: "Keanu Reeves",
                                   lines: [.init(uid: "b", team: "Zed", submitted: "keanu reaves", points: 0),
                                           .init(uid: "a", team: "Alpha, Beta", submitted: "Keanu Reeves", points: 3)])
        let csv = LiveAnswerLog.csv([rec])
        #expect(csv.hasPrefix("round,question,prompt,answer,team,submitted,points\n"))
        #expect(csv.contains("1,1,\"Who, \"\"Neo\"\"?\",Keanu Reeves,\"Alpha, Beta\",Keanu Reeves,3\n"))
        #expect(csv.contains("1,1,\"Who, \"\"Neo\"\"?\",Keanu Reeves,Zed,keanu reaves,0\n"))
        #expect(csv.range(of: "Alpha")!.lowerBound < csv.range(of: "Zed")!.lowerBound)
    }
}
