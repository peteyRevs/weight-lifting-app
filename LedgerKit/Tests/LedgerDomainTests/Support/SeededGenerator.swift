import Foundation

/// Deterministic SplitMix64 generator for property tests (testing-strategy §3 rule 5).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// One property-test case. A failing case names its seed, which is then added as a fixed
/// regression test (testing-strategy §3 rule 5).
struct PropertySeed: Sendable, CustomStringConvertible {
    let value: UInt64

    var description: String {
        "seed \(value)"
    }

    var generator: SeededGenerator {
        SeededGenerator(seed: value)
    }

    /// `LEDGER_PROPERTY_SEED_COUNT` seeds (PR lane 200, nightly 2,000); 200 when unset or invalid.
    static let all: [PropertySeed] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        let count = max(1, configured ?? 200)
        return (0 ..< count).map { PropertySeed(value: UInt64($0) &* 7919 &+ 17) }
    }()
}
