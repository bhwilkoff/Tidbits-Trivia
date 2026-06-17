import SwiftUI

/// A local pass-and-play participant. Multiplayer is the same GameEngine
/// loop per player over a shared, fair question set (Decision 023).
nonisolated struct Player: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String
    var colorIndex: Int
    var score: Int = 0

    @MainActor var color: Color { Tidbits.Palette.pops[colorIndex % Tidbits.Palette.pops.count] }

    static func defaults(_ count: Int) -> [Player] {
        (0..<count).map { Player(name: "Player \($0 + 1)", colorIndex: $0) }
    }
}
