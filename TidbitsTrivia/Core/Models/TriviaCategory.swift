import SwiftUI

/// A trivia category. Categories map Wikipedia content domains onto a
/// fixed, recognizable set with a fixed pop color (no ad-hoc hues).
struct TriviaCategory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String   // SF Symbol
    let colorIndex: Int  // index into Tidbits.Palette.pops
    let blurb: String

    var color: Color { Tidbits.Palette.pops[colorIndex % Tidbits.Palette.pops.count] }

    /// The v1 category set. Each maps to Wikipedia category trees /
    /// Vital-Article buckets in the corpus pipeline (see DATA-CONTRACT).
    static let all: [TriviaCategory] = [
        .init(id: "mixed",     name: "Mixed Bag",   symbol: "shuffle",            colorIndex: 0, blurb: "A little of everything."),
        .init(id: "history",   name: "History",     symbol: "scroll.fill",        colorIndex: 1, blurb: "People, places, and the past."),
        .init(id: "science",   name: "Science",     symbol: "atom",               colorIndex: 3, blurb: "How the universe works."),
        .init(id: "geography", name: "Geography",   symbol: "globe.americas.fill",colorIndex: 4, blurb: "The whole wide world."),
        .init(id: "arts",      name: "Arts & Lit",  symbol: "theatermasks.fill",  colorIndex: 5, blurb: "Books, art, and culture."),
        .init(id: "screen",    name: "Film & TV",   symbol: "film.fill",          colorIndex: 0, blurb: "The big and small screen."),
        .init(id: "music",     name: "Music",       symbol: "music.note",         colorIndex: 2, blurb: "From Bach to beats."),
        .init(id: "sports",    name: "Sports",      symbol: "sportscourt.fill",   colorIndex: 1, blurb: "Games and the greats."),
    ]

    static func named(_ id: String) -> TriviaCategory {
        all.first { $0.id == id } ?? all[0]
    }
}
