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
    case thisOrThat  // binary pick — which came first (E1 chronology)
    case closestCall // estimate a number on a slider, scored by proximity (E1)
    case ordering    // arrange items chronologically, partial credit (E1)
    case matching    // link each key to its value, partial credit (E1)
    case typeAnswer  // free-text recall, alias-matched (E1); tvOS self-marks
    case oddOneOut   // which doesn't belong — plain MCQ, outlier is the answer
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
        case .thisOrThat: return "Which First?"
        case .closestCall: return "Closest Call"
        case .ordering:   return "In Order"
        case .matching:   return "Match Up"
        case .typeAnswer: return "Name It"
        case .oddOneOut:  return "Odd One Out"
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
        case .thisOrThat: return "Which came first?"
        case .closestCall: return "How close can you get?"
        case .ordering:   return "Arrange them in time."
        case .matching:   return "Link each pair."
        case .typeAnswer: return "Type the answer."
        case .oddOneOut:  return "Which doesn't belong?"
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
        case .thisOrThat: return "arrow.left.arrow.right"
        case .closestCall: return "target"
        case .ordering:   return "arrow.up.arrow.down"
        case .matching:   return "link"
        case .typeAnswer: return "keyboard"
        case .oddOneOut:  return "questionmark.diamond.fill"
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
        case .thisOrThat: return Tidbits.Palette.grape
        case .closestCall: return Tidbits.Palette.yellow
        case .ordering:   return Tidbits.Palette.blue
        case .matching:   return Tidbits.Palette.coral
        case .typeAnswer: return Tidbits.Palette.mint
        case .oddOneOut:  return Tidbits.Palette.grape
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
        case .thisOrThat: return 12    // snap binary call
        case .closestCall: return 25   // estimation deserves a beat of thought
        case .ordering:   return 35    // reordering takes a moment
        case .matching:   return 40    // linking pairs takes thought
        case .typeAnswer: return 25
        case .oddOneOut:  return 20
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
        case .thisOrThat: return 10
        case .closestCall: return 8
        case .ordering:   return 6
        case .matching:   return 6
        case .typeAnswer: return 8
        case .oddOneOut:  return 8
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
