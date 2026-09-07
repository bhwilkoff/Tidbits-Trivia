#if os(macOS)
import SwiftUI

// MARK: - The question library (LIVE-PACKAGE-FORMAT §6, macOS-DESIGN §A2.2)

/// One saved question: the host's own bank, kept across nights. A question is
/// saved from a round, found again by text or category, and added to any round
/// of any later night; a `kind: bank` package moves the whole library between
/// machines. Dedupe is by prompt + answer, so saving a round twice does not
/// double it.
struct LibraryItem: Identifiable, Codable, Hashable {
    var id: String
    var question: Question
    var savedAt: Date
    var source: String     // the night it was saved from, or the file it came in on

    static func key(for q: Question) -> String {
        (q.prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "|" + q.correctAnswer.lowercased())
    }
}

enum LiveLibrary {
    /// The search a picker runs: every space-separated term must appear in the
    /// prompt, an option, the explanation, a tag or the category; a category
    /// filter narrows first. Pure, so it is tested without a view.
    static func matches(_ item: LibraryItem, query: String, category: String?) -> Bool {
        if let category, !category.isEmpty, item.question.categoryID != category { return false }
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return true }
        let q = item.question
        let hay = ([q.prompt, q.explanation, q.categoryID, item.source] + q.options + q.tags + (q.accepted ?? []))
            .joined(separator: " ").lowercased()
        return terms.allSatisfy { hay.contains($0) }
    }

    /// A library as a `bank` event: one round per category, so a bank package
    /// opens on either host and reads as folders (LIVE-PACKAGE-FORMAT §6.1).
    static func bankEvent(_ items: [LibraryItem], name: String) -> LiveEvent {
        var byCat: [String: [Question]] = [:]
        var order: [String] = []
        for it in items {
            if byCat[it.question.categoryID] == nil { order.append(it.question.categoryID) }
            byCat[it.question.categoryID, default: []].append(it.question)
        }
        var ev = LiveEvent(name: name)
        ev.rounds = order.map { cat in
            LiveRound(title: TriviaCategory.named(cat).name, format: .classic, categoryID: cat, questions: byCat[cat] ?? [])
        }
        return ev
    }
}

@Observable
@MainActor
final class LiveLibraryStore {
    private static let key = "tidbits.liveLibrary"
    var items: [LibraryItem] = LiveLibraryStore.load()

    static func load() -> [LibraryItem] {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([LibraryItem].self, from: d)) ?? []
    }
    private func persist() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(items) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    /// Save (or refresh) a question. Returns true when it was NEW.
    @discardableResult
    func add(_ q: Question, source: String) -> Bool {
        let k = LibraryItem.key(for: q)
        if let i = items.firstIndex(where: { LibraryItem.key(for: $0.question) == k }) {
            items[i].question = q; items[i].savedAt = .now; items[i].source = source
            persist(); return false
        }
        items.insert(LibraryItem(id: UUID().uuidString, question: q, savedAt: .now, source: source), at: 0)
        persist(); return true
    }

    /// Save a whole round (or a whole bank). Returns how many were new.
    @discardableResult
    func add(_ qs: [Question], source: String) -> Int {
        qs.reduce(0) { $0 + (add($1, source: source) ? 1 : 0) }
    }

    func remove(_ item: LibraryItem) { items.removeAll { $0.id == item.id }; persist() }

    func search(_ query: String, category: String? = nil) -> [LibraryItem] {
        items.filter { LiveLibrary.matches($0, query: query, category: category) }
    }
}

// MARK: - The picker sheet (§5.6 native work surface: a searchable table)

struct LiveLibraryPicker_macOS: View {
    @Bindable var library: LiveLibraryStore
    let onAdd: (Question) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var category = ""
    @State private var added: Set<String> = []

    private var results: [LibraryItem] { library.search(query, category: category.isEmpty ? nil : category) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search your library", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Text("Any category").tag("")
                    ForEach(TriviaCategory.all) { Text($0.name).tag($0.id) }
                }
                .frame(width: 180)
            }
            .padding(14)
            Divider()
            if library.items.isEmpty {
                ContentUnavailableView("Your library is empty",
                                       systemImage: "books.vertical",
                                       description: Text("Save a question from any round with its ••• menu, or import a bank package."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { item in
                    HStack(alignment: .top, spacing: 10) {
                        if item.question.imageURL != nil {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.question.prompt).lineLimit(2)
                            Text("\(item.question.correctAnswer) · \(TriviaCategory.named(item.question.categoryID).name) · D\(item.question.difficulty) · from \(item.source)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if added.contains(item.id) {
                            Label("Added", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Button("Add") { onAdd(item.question); added.insert(item.id) }
                                .controlSize(.small)
                        }
                        Button(role: .destructive) { library.remove(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Remove from the library")
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Text("\(results.count) of \(library.items.count) saved").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Add all shown") {
                    for item in results where !added.contains(item.id) { onAdd(item.question); added.insert(item.id) }
                }
                .disabled(results.isEmpty || results.allSatisfy { added.contains($0.id) })
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 720, height: 520)
    }
}
#endif
