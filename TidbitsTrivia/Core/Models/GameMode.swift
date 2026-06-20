import SwiftUI

/// The v1 single-player modes. Multiplayer modes (head-to-head, team,
/// living-room) layer on top in Phase 2 — they reuse the same GameEngine
/// loop, only the win condition and scoring shell differ.
enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case classic     // 10 questions, accuracy + speed bonus
    case timeAttack  // as many as you can in 60s
    case survival    // keep going until one wrong answer
    case stake       // bet a fixed budget of confidence chips per question
    case sweep       // fill a themed set; beat your own best (count-scored)
    case pictureId   // identify the subject from its image (E1 enrichment)
    case daily       // one fixed daily set, streak-bearing, shareable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:    return "Classic"
        case .timeAttack: return "Time Attack"
        case .survival:   return "Survival"
        case .stake:      return "Stake"
        case .sweep:      return "Sweep"
        case .pictureId:  return "Picture ID"
        case .daily:      return "Daily Tidbit"
        }
    }

    var blurb: String {
        switch self {
        case .classic:    return "Ten questions. Speed counts."
        case .timeAttack: return "How many in 60 seconds?"
        case .survival:   return "One wrong answer ends it."
        case .stake:      return "Bet your confidence. No risk."
        case .sweep:      return "Fill the set. Beat your best."
        case .pictureId:  return "Name what you see."
        case .daily:      return "Everyone's puzzle. Keep your streak."
        }
    }

    var symbol: String {
        switch self {
        case .classic:    return "list.number"
        case .timeAttack: return "timer"
        case .survival:   return "heart.fill"
        case .stake:      return "chart.bar.fill"
        case .sweep:      return "square.grid.3x3.fill"
        case .pictureId:  return "photo.fill"
        case .daily:      return "sun.max.fill"
        }
    }

    var accent: Color {
        switch self {
        case .classic:    return Tidbits.Palette.blue
        case .timeAttack: return Tidbits.Palette.coral
        case .survival:   return Tidbits.Palette.grape
        case .stake:      return Tidbits.Palette.mint
        case .sweep:      return Tidbits.Palette.teal
        case .pictureId:  return Tidbits.Palette.pink
        case .daily:      return Tidbits.Palette.yellow
        }
    }

    /// Per-question time budget in seconds (nil = the mode's own clock).
    var perQuestionSeconds: Double? {
        switch self {
        case .classic:    return 20
        case .timeAttack: return nil   // global 60s clock
        case .survival:   return 15
        case .stake:      return 30    // generous — calibration shouldn't be rushed
        case .sweep:      return 12    // rapid-fire, but a clock that never punishes score
        case .pictureId:  return 20    // time to look at the image
        case .daily:      return 30
        }
    }

    var questionCount: Int {
        switch self {
        case .classic:    return 10
        case .timeAttack: return 99    // bounded by the clock
        case .survival:   return 99    // bounded by a wrong answer
        case .stake:      return 8     // matches the confidence-chip budget
        case .sweep:      return 12    // a "set" to fill — the grid is the scoreboard
        case .pictureId:  return 10
        case .daily:      return 7
        }
    }

    /// Stake mode only: the fixed budget of confidence chips for one round
    /// (sum of `count` == questionCount). Spending more on one question means
    /// fewer chips for the rest — that scarcity is what makes it calibration,
    /// not "stake max on everything." Adds-only: a wrong answer earns 0 but the
    /// chip is spent; the score can never go negative (Decision 022).
    static let stakeBudget: [(value: Int, label: String, count: Int)] = [
        (3, "Sure", 2), (2, "Likely", 3), (1, "Hunch", 3),
    ]

    var globalClockSeconds: Double? { self == .timeAttack ? 60 : nil }
}
