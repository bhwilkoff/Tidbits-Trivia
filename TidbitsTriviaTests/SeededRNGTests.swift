import Testing

/// Determinism is the contract: the same seed must replay the same sequence on
/// every launch and every platform. Swift's own Hasher is per-run salted, which
/// is exactly why `stableSeed` exists — a test that only checked "looks random"
/// would pass while the Daily silently differed between two devices.
@Suite("Seeded RNG")
struct SeededRNGTests {

    @Test func sameSeedReplaysTheSameSequence() {
        var a = SeededRNG(seed: 12345)
        var b = SeededRNG(seed: 12345)
        for _ in 0..<64 { #expect(a.next() == b.next()) }
    }

    @Test func differentSeedsDiverge() {
        var a = SeededRNG(seed: 1)
        var b = SeededRNG(seed: 2)
        let lhs = (0..<16).map { _ in a.next() }
        let rhs = (0..<16).map { _ in b.next() }
        #expect(lhs != rhs)
    }

    @Test func stableSeedIsNotSaltedPerRun() {
        // Two independent computations in the same run must agree; the golden
        // value pins it across runs and platforms.
        #expect("daily:2026-07-31:mixed:q1".stableSeed == "daily:2026-07-31:mixed:q1".stableSeed)
        #expect("daily:2026-07-31:mixed:q1".stableSeed == 3_292_667_222_318_249_718)
    }

    @Test func shufflingWithASeedIsReproducible() {
        var a = SeededRNG(seed: "linkwall:tiles:2026-07-31".stableSeed)
        var b = SeededRNG(seed: "linkwall:tiles:2026-07-31".stableSeed)
        let items = Array(1...50)
        #expect(items.shuffled(using: &a) == items.shuffled(using: &b))
    }

    /// A degenerate seed must still produce a usable stream rather than all zeros.
    @Test func zeroSeedStillProducesVariedOutput() {
        var rng = SeededRNG(seed: 0)
        let values = (0..<32).map { _ in rng.next() }
        #expect(Set(values).count > 1)
    }
}
