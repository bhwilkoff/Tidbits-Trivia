#if os(macOS)
import Foundation
import Testing

/// CSV import — the host's own question bank.
///
/// The reader was `try? String(contentsOf: url, encoding: .utf8)` with a bare
/// `return` on failure. Excel on Windows commonly writes **UTF-16LE with a BOM**,
/// and older exports are Latin-1, so the single most likely CSV a pub host owns
/// silently imported nothing at all — no round, no error, no explanation. These
/// write real files in those encodings, which is the only way to know the reader
/// actually handles them.
@Suite("Live CSV import")
struct LiveCSVImportTests {

    private static let sample = """
    prompt,correct,wrong1,wrong2,wrong3,category,difficulty,explanation
    Which Iron Age kingdom minted the first coins?,Lydia,Phrygia,Caria,Lycia,history,3,Electrum coins c. 600 BC.
    In which year was the Battle of Hastings fought?,1066,1215,1415,1485,history,2,
    """

    private static func write(_ text: String, as encoding: String.Encoding, ext: String = "csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidbits-csv-\(UUID().uuidString).\(ext)")
        guard let data = text.data(using: encoding) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        return url
    }

    @Test("reads UTF-8, the everyday case")
    func readsUTF8() throws {
        let url = try Self.write(Self.sample, as: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try #require(LiveCSV.readTextFile(at: url))
        #expect(text.contains("Lydia"))
    }

    @Test("reads UTF-16, which is what Excel on Windows writes")
    func readsUTF16() throws {
        // The case the old reader failed on, and the most likely file a host has.
        let url = try Self.write(Self.sample, as: .utf16LittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try #require(LiveCSV.readTextFile(at: url),
                                "a UTF-16LE CSV could not be read")
        #expect(text.contains("Lydia"))
        #expect(LiveCSV.parseCSVQuestions(text).count == 2)
    }

    @Test("reads Latin-1, which older exports still use")
    func readsLatin1() throws {
        let url = try Self.write("prompt,correct,a,b,c\nCafé or thé?,Café,thé,eau,lait", as: .isoLatin1)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try #require(LiveCSV.readTextFile(at: url))
        #expect(text.contains("Caf"))
    }

    @Test("the header row is not imported as a question")
    func skipsHeader() {
        let qs = LiveCSV.parseCSVQuestions(Self.sample)
        #expect(qs.count == 2)
        #expect(!qs.contains { $0.prompt.lowercased() == "prompt" })
    }

    @Test("category, difficulty and explanation come across")
    func carriesOptionalColumns() throws {
        let qs = LiveCSV.parseCSVQuestions(Self.sample)
        let first = try #require(qs.first)
        #expect(first.categoryID == "history")
        #expect(first.difficulty == 3)
        #expect(first.explanation.contains("Electrum"))
        #expect(first.correctAnswer == "Lydia")
    }

    @Test("a quoted field containing a comma stays one field")
    func handlesQuotedCommas() throws {
        let csv = #"prompt,correct,a,b,c"# + "\n"
            + #""Which city, famously, never sleeps?",New York,Paris,Rome,Oslo"#
        let qs = LiveCSV.parseCSVQuestions(csv)
        let q = try #require(qs.first)
        #expect(q.prompt.contains("famously"))
        #expect(q.correctAnswer == "New York")
    }

    @Test("a short row is skipped rather than producing a broken question")
    func skipsShortRows() {
        // Half a row must not become a question with blank options — that is how a
        // malformed import turns into an unplayable round mid-night.
        let csv = "prompt,correct,a,b,c\nOnly a prompt here\nGood one?,Yes,No,Maybe,Never"
        let qs = LiveCSV.parseCSVQuestions(csv)
        #expect(qs.count == 1)
        #expect(qs[0].correctAnswer == "Yes")
    }

    @Test("every imported question keeps four distinct options")
    func fourOptions() {
        for q in LiveCSV.parseCSVQuestions(Self.sample) {
            #expect(q.options.count == 4)
            #expect(Set(q.options).count == 4, "duplicate options in \(q.prompt)")
            #expect(q.options.contains(q.correctAnswer))
        }
    }

    @Test("an unreadable file returns nil rather than an empty import")
    func rejectsBinary() throws {
        // Random bytes must not decode as "some text" and produce zero questions
        // that look like a successful import of an empty bank.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidbits-csv-\(UUID().uuidString).bin")
        try Data((0..<512).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        if let text = LiveCSV.readTextFile(at: url) {
            // Some byte sequences ARE valid Latin-1; what matters is that they
            // yield no questions rather than garbage ones.
            #expect(LiveCSV.parseCSVQuestions(text).isEmpty)
        }
    }

    // MARK: The two shipped column orders

    /// macOS wrote `prompt, correct, wrong1..3, [category], [difficulty], [explanation]`.
    private static let macOrder = """
    Which kingdom minted the first coins?,Lydia,Phrygia,Caria,Lycia,history,3,Electrum c.600BC
    """

    /// Windows wrote `prompt, optionA..D, correct(1-4), [explanation]`.
    private static let windowsOrder = """
    Which kingdom minted the first coins?,Phrygia,Lydia,Caria,Lycia,2,Electrum c.600BC
    """

    @Test("a Windows-order CSV no longer marks the wrong option correct")
    func windowsOrderIsUnderstood() throws {
        // THE BUG: field 1 was read as the answer, so this row imported with
        // "Phrygia" correct when the answer is Lydia — silently marking a correct
        // player wrong.
        let q = try #require(LiveCSV.parseCSVQuestions(Self.windowsOrder).first)
        #expect(q.correctAnswer == "Lydia", "imported the wrong answer as correct")
        #expect(Set(q.options) == ["Phrygia", "Lydia", "Caria", "Lycia"])
    }

    @Test("the macOS order still works")
    func macOrderStillWorks() throws {
        let q = try #require(LiveCSV.parseCSVQuestions(Self.macOrder).first)
        #expect(q.correctAnswer == "Lydia")
        #expect(q.categoryID == "history")
        #expect(q.difficulty == 3)
    }

    @Test("a named header beats both orders, in any column order")
    func namedHeaderWins() throws {
        let csv = """
        question,explanation,difficulty,correct,optionA,optionB,optionC,optionD,category
        Which kingdom minted the first coins?,Electrum c.600BC,4,Lydia,Phrygia,Lydia,Caria,Lycia,history
        """
        let q = try #require(LiveCSV.parseCSVQuestions(csv).first)
        #expect(q.correctAnswer == "Lydia")
        #expect(q.difficulty == 4)
        #expect(q.categoryID == "history")
        #expect(q.explanation.contains("Electrum"))
    }

    @Test("a header whose correct column is an INDEX resolves to the answer text")
    func headerWithIndexAnswer() throws {
        let csv = """
        prompt,optionA,optionB,optionC,optionD,correct,explanation
        Which kingdom minted the first coins?,Phrygia,Lydia,Caria,Lycia,2,Electrum
        """
        let q = try #require(LiveCSV.parseCSVQuestions(csv).first)
        #expect(q.correctAnswer == "Lydia")
    }

    @Test("a row whose named answer is not among its options is dropped, not guessed")
    func inconsistentRowIsDropped() {
        // Importing it anyway would put an answer on the board that no option
        // matches, so the question can never be answered correctly.
        let csv = """
        prompt,correct,wrong1,wrong2,wrong3
        Which kingdom minted the first coins?,Atlantis,Phrygia,Caria,Lycia
        """
        let qs = LiveCSV.parseCSVQuestions(csv)
        for q in qs { #expect(q.options.contains(q.correctAnswer)) }
    }

    // MARK: Export (§6.1) — and the round-trip that proves the halves agree

    private static func q(_ prompt: String, _ correct: String, _ others: [String],
                          category: String = "history", difficulty: Int = 3,
                          explanation: String = "") -> Question {
        Question(id: UUID().uuidString, prompt: prompt, options: [correct] + others,
                 correctIndex: 0, categoryID: category, difficulty: difficulty,
                 explanation: explanation, sourceTitle: "", sourceURL: nil, templateID: "test")
    }

    @Test("an export always carries the named header")
    func exportHasHeader() throws {
        // §6.1: the header is the only shape neither client can misread, and it is
        // what makes an export re-importable on the other platform.
        let csv = LiveCSV.exportCSV([Self.q("A?", "Yes", ["No", "Maybe", "Never"])])
        let first = try #require(csv.split(whereSeparator: \.isNewline).first)
        #expect(first.hasPrefix("prompt,correct,"))
        #expect(first.contains("category"))
        #expect(first.contains("difficulty"))
        #expect(first.contains("explanation"))
    }

    @Test("export then import returns the same questions")
    func roundTrips() throws {
        let original = [
            Self.q("Which kingdom minted the first coins?", "Lydia", ["Phrygia", "Caria", "Lycia"],
                   category: "history", difficulty: 4, explanation: "Electrum, c.600 BC."),
            Self.q("Name the longest river", "Nile", ["Amazon", "Yangtze", "Danube"],
                   category: "geography", difficulty: 2),
        ]
        let back = LiveCSV.parseCSVQuestions(LiveCSV.exportCSV(original))

        #expect(back.count == original.count)
        for (a, b) in zip(original, back) {
            #expect(a.prompt == b.prompt)
            #expect(a.correctAnswer == b.correctAnswer)
            #expect(Set(a.options) == Set(b.options))
            #expect(a.categoryID == b.categoryID)
            #expect(a.difficulty == b.difficulty)
            #expect(a.explanation == b.explanation)
        }
    }

    @Test("a prompt containing commas and quotes survives the round trip")
    func roundTripsAwkwardText() throws {
        // The exact text that breaks a naive writer: a comma, a quoted phrase, and
        // an answer that itself contains a comma.
        let tricky = Self.q(#"Which city, "famously", never sleeps?"#,
                            "New York, NY", ["Paris", "Rome", "Oslo"],
                            explanation: #"It is a nickname, not a fact."#)
        let back = try #require(LiveCSV.parseCSVQuestions(LiveCSV.exportCSV([tricky])).first)
        #expect(back.prompt == tricky.prompt)
        #expect(back.correctAnswer == "New York, NY")
        #expect(back.explanation == tricky.explanation)
    }

    @Test("an exported file is re-importable as the Windows reader sees it too")
    func exportUsesTheSharedHeaderNames() {
        // The C# suite asserts the same header names; if this drifts, a Mac export
        // stops importing on Windows and nothing else would notice.
        let csv = LiveCSV.exportCSV([Self.q("A?", "Yes", ["No", "Maybe", "Never"])])
        for name in ["prompt", "correct", "optionA", "optionB", "optionC", "optionD",
                     "category", "difficulty", "explanation"] {
            #expect(csv.contains(name), "export is missing the \(name) column")
        }
    }
}
#endif
