#if os(macOS)
import Foundation
import Testing

/// QUIZ-FORMATS-RESEARCH §4 — GIFT and Aiken through the one Import button.
@Suite("Text formats — GIFT and Aiken")
struct LiveTextFormatsTests {
    static let gift = """
    // Moodle export
    ::coins:: Which kingdom minted the first coins? {=Lydia ~Phrygia ~Caria ~Lycia ####Electrum c.600BC}

    Croesus was the last king of Lydia. {T}

    ::capital:: The capital of Peru is {=Lima =Ciudad de los Reyes}.

    How many moons does Mars have? {#2:0}

    Match the capital {=France -> Paris =Peru -> Lima =Japan -> Tokyo}

    [html]Which is a spreadsheet\\: app? {~Word =Excel#Yes! ~Outlook}
    """

    @Test("GIFT: multiple choice with feedback, true/false, short answer, numerical, matching, escapes")
    func gift() {
        let qs = LiveTextFormats.parseGIFT(Self.gift)
        #expect(qs.count == 6)
        #expect(qs[0].prompt == "Which kingdom minted the first coins?" && qs[0].correctAnswer == "Lydia")
        #expect(qs[0].options == ["Lydia", "Phrygia", "Caria", "Lycia"] && qs[0].explanation == "Electrum c.600BC")
        #expect(qs[1].options == ["True", "False"] && qs[1].correctIndex == 0)
        #expect(qs[2].prompt == "The capital of Peru is ___ ." && qs[2].accepted == ["Lima", "Ciudad de los Reyes"])
        #expect(qs[3].closest?.answer == 2)
        #expect(qs[4].matching?.keys == ["France", "Peru", "Japan"] && qs[4].matching?.values == ["Paris", "Lima", "Tokyo"])
        #expect(qs[5].prompt == "Which is a spreadsheet: app?" && qs[5].correctAnswer == "Excel")
    }

    static let aiken = """
    Which kingdom minted the first coins?
    A. Phrygia
    B. Lydia
    C. Caria
    D. Lycia
    ANSWER: B

    What is the capital of Peru?
    A) Quito
    B) Lima
    ANSWER: B
    """

    @Test("Aiken: lettered options and an ANSWER line")
    func aiken() {
        let qs = LiveTextFormats.parseAiken(Self.aiken)
        #expect(qs.count == 2)
        #expect(qs[0].correctAnswer == "Lydia" && qs[0].options.count == 4)
        #expect(qs[1].correctAnswer == "Lima")
    }

    @Test("detection reads the shape of the text")
    func detect() {
        #expect(LiveTextFormats.detect(Self.gift) == .gift)
        #expect(LiveTextFormats.detect(Self.aiken) == .aiken)
        #expect(LiveTextFormats.detect("prompt,correct,wrong1\nA?,a,b\n") == .csv)
    }

    @Test("GIFT export re-imports every type it writes")
    func roundTrip() {
        let qs = LiveTextFormats.parseGIFT(Self.gift)
        let back = LiveTextFormats.parseGIFT(LiveTextFormats.exportGIFT(qs))
        #expect(back.count == qs.count)
        #expect(back.map(\.prompt) == qs.map(\.prompt))
        #expect(back[0].options == qs[0].options && back[0].correctAnswer == "Lydia" && back[0].explanation == "Electrum c.600BC")
        #expect(back[2].accepted == qs[2].accepted)
        #expect(back[3].closest?.answer == 2)
        #expect(back[4].matching == qs[4].matching)
    }
}
#endif

#if os(macOS)
import Foundation
import Testing

/// QUIZ-FORMATS-RESEARCH §1 — SpeedQuizzing Quick Questions: the filename IS the
/// question, the file IS the media.
@Suite("SpeedQuizzing Quick Questions")
struct LiveQuickQuestionsTests {
    @Test("the documented filename shape: prefix code, underscores, ^^ for ?, a leading order number")
    func filenames() {
        let a = LiveQuickQuestions.parse(filename: "QQ_Who sang this^^_Dolly Parton.mp3")
        #expect(a?.prompt == "Who sang this?" && a?.answers == ["Dolly Parton"] && a?.isPoll == false)
        let b = LiveQuickQuestions.parse(filename: "05 QQ_What is the capital of Peru^^_Lima_Ciudad de los Reyes.txt")
        #expect(b?.order == 5 && b?.prompt == "What is the capital of Peru?")
        #expect(b?.answers == ["Lima", "Ciudad de los Reyes"])
        // The verbatim example from SpeedQuizzing's own documentation.
        let v = LiveQuickQuestions.parse(filename: "QQV_Who would have won in a cage fight in their prime^^_Mike Tyson_Bruce Lee.txt")
        #expect(v?.isPoll == true)
        // A file with no answer, and one with no question at all.
        #expect(LiveQuickQuestions.parse(filename: "QQ_Just a question^^.txt")?.answers.isEmpty == true)
        #expect(LiveQuickQuestions.parse(filename: ".DS_Store") != nil)   // filtered by the caller, not here
    }

    @Test("a folder becomes a round: media attached, votes skipped, order honoured, notes for the rest")
    func folder() {
        let dir = URL(fileURLWithPath: "/quizpack")
        let files = [
            dir.appendingPathComponent("03 QQ_Who sang this^^_Dolly Parton.mp3"),
            dir.appendingPathComponent("01 QQ_Which building is this^^_Chrysler Building.jpg"),
            dir.appendingPathComponent("02 QQ_Capital of Peru^^_Lima_Ciudad de los Reyes.txt"),
            dir.appendingPathComponent("QQV_Cats or dogs^^_Cats_Dogs.txt"),
            dir.appendingPathComponent("notes.pdf"),
            dir.appendingPathComponent(".DS_Store"),
        ]
        var stored: [String] = []
        let (qs, notes) = LiveQuickQuestions.questions(from: files) { url in
            stored.append(url.lastPathComponent); return "id-" + String(url.pathExtension)
        }
        #expect(qs.count == 3)
        #expect(qs.map(\.prompt) == ["Which building is this?", "Capital of Peru?", "Who sang this?"])
        #expect(qs[0].imageURL?.absoluteString == "tidbits-media:id-jpg")   // the picture rides on the question
        #expect(qs[1].imageURL == nil)
        #expect(qs[1].accepted == ["Lima", "Ciudad de los Reyes"])
        #expect(qs.allSatisfy { $0.accepted != nil })                       // every one is a name-it
        #expect(notes.count == 2)                                          // the vote and the PDF
        #expect(notes.contains { $0.contains("voting") } && notes.contains { $0.contains("notes.pdf") })
    }

    @Test("clip ids line up with the questions, one slot per question")
    func clips() {
        let dir = URL(fileURLWithPath: "/quizpack")
        let files = [
            dir.appendingPathComponent("01 QQ_Which building is this^^_Chrysler Building.jpg"),
            dir.appendingPathComponent("02 QQ_Who sang this^^_Dolly Parton.mp3"),
        ]
        let ids = LiveQuickQuestions.clipIDs(from: files) { "id-" + $0.pathExtension }
        #expect(ids == [nil, "id-mp3"])   // the picture takes no clip slot; the MP3 does
    }
}
#endif
