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
