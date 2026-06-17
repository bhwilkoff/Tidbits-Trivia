import SwiftUI

/// The v1 single-player modes. Multiplayer modes (head-to-head, team,
/// living-room) layer on top in Phase 2 — they reuse the same GameEngine
/// loop, only the win condition and scoring shell differ.
enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case classic     // 10 questions, accuracy + speed bonus
    case timeAttack  // as many as you can in 60s
    case survival    // keep going until one wrong answer
    case daily       // one fixed daily set, streak-bearing, shareable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:    return "Classic"
        case .timeAttack: return "Time Attack"
        case .survival:   return "Survival"
        case .daily:      return "Daily Tidbit"
        }
    }

    var blurb: String {
        switch self {
        case .classic:    return "Ten questions. Speed counts."
        case .timeAttack: return "How many in 60 seconds?"
        case .survival:   return "One wrong answer ends it."
        case .daily:      return "Everyone's puzzle. Keep your streak."
        }
    }

    var symbol: String {
        switch self {
        case .classic:    return "list.number"
        case .timeAttack: return "timer"
        case .survival:   return "heart.fill"
        case .daily:      return "sun.max.fill"
        }
    }

    var accent: Color {
        switch self {
        case .classic:    return Tidbits.Palette.blue
        case .timeAttack: return Tidbits.Palette.coral
        case .survival:   return Tidbits.Palette.grape
        case .daily:      return Tidbits.Palette.yellow
        }
    }

    /// Per-question time budget in seconds (nil = the mode's own clock).
    var perQuestionSeconds: Double? {
        switch self {
        case .classic:    return 20
        case .timeAttack: return nil   // global 60s clock
        case .survival:   return 15
        case .daily:      return 30
        }
    }

    var questionCount: Int {
        switch self {
        case .classic:    return 10
        case .timeAttack: return 99    // bounded by the clock
        case .survival:   return 99    // bounded by a wrong answer
        case .daily:      return 7
        }
    }

    var globalClockSeconds: Double? { self == .timeAttack ? 60 : nil }
}
