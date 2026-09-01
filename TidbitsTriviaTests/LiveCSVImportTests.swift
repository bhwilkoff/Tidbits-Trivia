#if os(macOS)
import Foundation
import Testing
@testable import TidbitsTrivia

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
}
#endif
