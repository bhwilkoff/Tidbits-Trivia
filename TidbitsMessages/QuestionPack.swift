import Foundation

/// One MCQ question, exactly as the extension's bundled pack stores it.
///
/// Deliberately NOT `Core.Question`. Core carries SwiftData, StoreKit, networking and
/// a dozen optional answer-shape specs — none of which an iMessage extension can
/// afford to link or load. The pack is the same questions, flattened to the five
/// fields a message-thread round actually uses.
struct PackQuestion: Decodable, Identifiable {
    let i: String       // id — the only thing that travels on the wire
    let p: String       // prompt
    let o: [String]     // exactly 4 options
    let c: Int          // correct index
    let g: String       // category id
    let d: Int          // difficulty 1…4
    let e: String       // explanation — the learning payload, shown at reveal

    var id: String { i }
    var prompt: String { p }
    var options: [String] { o }
    var correctIndex: Int { c }
    var categoryID: String { g }
    var explanation: String { e }
}

/// The extension's question source.
///
/// **Why a pack and not the corpus.** `corpus.sqlite` is 50MB and app extensions run
/// under much tighter memory ceilings than the host app. This project has already
/// taken a Play rejection traced to a 299MB heap peak and then a repeat from eagerly
/// parsing JSON at boot (`android-corpus-oom-play-rejection`,
/// `android-eager-json-oom-vc85`). An extension is the *worst* place to relearn that
/// lesson, because the crash lands inside Messages.
///
/// So: ~3,200 questions, 849KB, balanced across the eight categories, generated
/// deterministically by `tools/gen_imessage_pack.py`.
///
/// Loaded **once, lazily**, on first use rather than at init — an extension is
/// launched and torn down constantly as the drawer opens and closes, and paying the
/// decode on every construction would be the memory-churn version of the same bug.
final class QuestionPack {
    static let shared = QuestionPack()

    private var loaded: [PackQuestion]?
    private var byID: [String: PackQuestion] = [:]

    private init() {}

    private func load() -> [PackQuestion] {
        if let loaded { return loaded }
        guard let url = Bundle.main.url(forResource: "pack", withExtension: "json"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let decoded = try? JSONDecoder().decode(Pack.self, from: data)
        else {
            // An empty pack is a broken build, not a runtime condition to paper over.
            // Returning [] lets the UI say "couldn't load questions" instead of
            // crashing inside Messages, which is a far worse failure for the user.
            loaded = []
            return []
        }
        loaded = decoded.q
        byID = Dictionary(decoded.q.map { ($0.i, $0) }, uniquingKeysWith: { a, _ in a })
        return decoded.q
    }

    private struct Pack: Decodable { let v: Int; let q: [PackQuestion] }

    func question(id: String) -> PackQuestion? {
        _ = load()
        return byID[id]
    }

    func correctIndex(id: String) -> Int? { question(id: id)?.correctIndex }

    var categories: [String] {
        Array(Set(load().map(\.categoryID))).sorted()
    }

    /// Pick `count` questions for a new round.
    ///
    /// Seeded from the round id so the SAME round is reproducible — every device in
    /// the thread must be able to render the round from the message alone, and a
    /// random draw per device would give everyone different questions under one id.
    func pick(count: Int, category: String?, seed: UInt64) -> [PackQuestion] {
        let pool = category.map { c in load().filter { $0.categoryID == c } } ?? load()
        guard !pool.isEmpty else { return [] }

        var rng = SplitMix64(seed: seed)
        var chosen: [PackQuestion] = []
        var used = Set<Int>()
        while chosen.count < count && used.count < pool.count {
            let i = Int(rng.next() % UInt64(pool.count))
            if used.insert(i).inserted { chosen.append(pool[i]) }
        }
        return chosen
    }
}

/// A tiny deterministic RNG so a round is reproducible from its seed.
///
/// `SystemRandomNumberGenerator` would give a different draw on every device, which
/// for a shared round means everyone answering different questions under the same id.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
