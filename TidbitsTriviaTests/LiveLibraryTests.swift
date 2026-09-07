#if os(macOS)
import Foundation
import Testing

/// LIVE-PACKAGE-FORMAT §6 — the host's own question bank across nights.
@Suite("Live library — save, find, re-use, and move as a bank package")
struct LiveLibraryTests {
    private func q(_ id: String, _ prompt: String, _ answer: String, category: String = "history",
                   tags: [String] = [], image: String? = nil) -> Question {
        Question(id: id, prompt: prompt, options: [answer, "b", "c", "d"], correctIndex: 0, categoryID: category,
                 difficulty: 3, explanation: "", sourceTitle: "", sourceURL: nil, templateID: "t", tags: tags,
                 imageURL: image.flatMap(URL.init(string:)))
    }
    private func item(_ q: Question, source: String = "Friday") -> LibraryItem {
        LibraryItem(id: q.id, question: q, savedAt: .now, source: source)
    }

    @Test("every search term must appear somewhere the host would look; category narrows first")
    func search() {
        let coins = item(q("1", "Which kingdom minted the first coins?", "Lydia", tags: ["money"]))
        let flags = item(q("2", "Which flag is this?", "Chad", category: "geography", image: "tidbits-media:abc"))
        #expect(LiveLibrary.matches(coins, query: "coins lydia", category: nil))
        #expect(LiveLibrary.matches(coins, query: "money", category: nil))          // a tag
        #expect(LiveLibrary.matches(coins, query: "friday", category: nil))         // the source night
        #expect(!LiveLibrary.matches(coins, query: "coins flag", category: nil))    // both terms must hit
        #expect(!LiveLibrary.matches(coins, query: "", category: "geography"))
        #expect(LiveLibrary.matches(flags, query: "", category: "geography"))
        #expect(LiveLibrary.matches(flags, query: "", category: nil))
    }

    @Test("saving is keyed by prompt + answer: a round saved twice does not double")
    @MainActor func dedupe() {
        UserDefaults.standard.removeObject(forKey: "tidbits.liveLibrary")
        let lib = LiveLibraryStore()
        lib.items = []
        let a = q("1", "Which kingdom minted the first coins?", "Lydia")
        #expect(lib.add(a, source: "Friday") == true)
        #expect(lib.add(q("99", "which kingdom minted the first coins?  ", "lydia"), source: "Saturday") == false)
        #expect(lib.items.count == 1)
        #expect(lib.items[0].source == "Saturday")   // refreshed, not duplicated
        #expect(lib.add([a, q("3", "Capital of Peru?", "Lima")], source: "Sunday") == 1)
        #expect(lib.items.count == 2)
        UserDefaults.standard.removeObject(forKey: "tidbits.liveLibrary")
    }

    @Test("a bank event groups the library by category, one folder per category, in first-seen order")
    func bank() {
        let items = [item(q("1", "A?", "a", category: "history")), item(q("2", "B?", "b", category: "geography")),
                     item(q("3", "C?", "c", category: "history"))]
        let ev = LiveLibrary.bankEvent(items, name: "Question library")
        #expect(ev.rounds.map(\.categoryID) == ["history", "geography"])
        #expect(ev.rounds[0].questions.map(\.id) == ["1", "3"])
        #expect(ev.rounds[0].title == "History")
    }

    @Test("a bank package round-trips through the same container with kind = bank")
    func bankPackage() throws {
        let items = [item(q("1", "A?", "a", category: "history")), item(q("2", "B?", "b", category: "science"))]
        let bank = LiveLibrary.bankEvent(items, name: "Question library")
        let (data, dropped) = try LivePackage.export(bank, createdBy: "test", kind: "bank")
        #expect(dropped.isEmpty)
        let back = try LivePackage.read(data)
        #expect(back.manifest.kind == "bank")
        #expect(back.document.event.rounds.count == 2)
        #expect(back.document.event.rounds.flatMap(\.questions).map(\.prompt) == ["A?", "B?"])
    }
}
#endif
