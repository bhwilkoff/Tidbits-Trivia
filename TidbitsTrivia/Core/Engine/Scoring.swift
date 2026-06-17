import Foundation

/// Speed-aware scoring. Base points for a correct answer, a speed bonus
/// that rewards (but never requires) quickness, and a streak multiplier
/// that makes a hot run feel hot — capped so it stays a thrill, not a
/// runaway (engagement theory: variable-but-bounded reward).
enum Scoring {
    static let base = 100
    static let maxSpeedBonus = 100
    static let streakStep = 0.1     // +10% per consecutive correct
    static let maxStreakMultiplier = 2.0

    /// Points for one answer.
    /// - secondsTaken / budget normalizes speed across modes.
    static func points(correct: Bool, secondsTaken: Double, budget: Double, streak: Int) -> Int {
        guard correct else { return 0 }
        let speedFraction = max(0, min(1, 1 - secondsTaken / max(budget, 0.001)))
        let speed = Int(Double(maxSpeedBonus) * speedFraction)
        let mult = min(maxStreakMultiplier, 1 + Double(max(0, streak - 1)) * streakStep)
        return Int(Double(base + speed) * mult)
    }
}
