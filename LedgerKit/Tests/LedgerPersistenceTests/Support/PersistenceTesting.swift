import Foundation
import Testing

/// Tags live in the test target, not LedgerTestSupport (F00 implementation notes #6).
extension Tag {
    /// Every LedgerPersistence suite (layer tag).
    @Tag static var persistence: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
    /// Timing tests against a budget in `PerformanceBudget`; nightly lane only (testing-strategy §6).
    @Tag static var performance: Self
}

/// The lane a test plan runs in, from its `LEDGER_TEST_LANE` variable (testing-strategy §6).
enum TestLane {
    /// `.performance` and `.slow` tests run only in the nightly plans; the PR plans and `swift test` skip
    /// them, because a timing is only meaningful without other suites competing for the CPU.
    static var runsSlowTests: Bool {
        ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly"
    }
}

/// Deterministic SplitMix64 generator (testing-strategy §3 rule 5), as in `LedgerDomainTests`: test
/// targets cannot share test-only types, and moving that one to LedgerTestSupport would touch 17 domain
/// test files for no behaviour change.
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

/// One property-test case. A failing case names its seed, which is then added as a fixed regression
/// test (testing-strategy §3 rule 5).
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

/// A fresh directory under the temporary directory (testing-strategy §3 rule 3) for one test's file
/// database, named after the test so parallel tests never share one. Remove it with `remove()`.
struct TemporaryDirectory {
    let url: URL

    init(_ name: String = #function) {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        url = FileManager.default.temporaryDirectory
            .appending(path: "LedgerPersistenceTests-\(ProcessInfo.processInfo.processIdentifier)-\(safe)")
        try? FileManager.default.removeItem(at: url) // absent unless an earlier run of this test crashed
    }

    /// `name` inside the directory.
    func file(_ name: String) -> URL {
        url.appending(path: name)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: url)
    }
}
