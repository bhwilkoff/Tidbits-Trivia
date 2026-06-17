import Foundation

/// Deterministic RNG so the Daily puzzle is identical for everyone on a
/// given day, and so distractor selection is reproducible. Splitmix64.
nonisolated struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// Stable 64-bit hash (FNV-1a) — used to seed daily/topic generation
    /// reproducibly across launches (Swift's Hasher is per-run salted).
    var stableSeed: UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        for byte in utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001B3 }
        return hash
    }
}
