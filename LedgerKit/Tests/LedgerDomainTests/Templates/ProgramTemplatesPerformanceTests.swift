import Foundation
@testable import LedgerDomain
import Testing

/// The brief's budget: writing a block takes under 5 ms. The catalog is given to the generator, so decoding
/// it (a budget of its own, `ExerciseCatalogPerformanceTests`) is outside the measurement. A timing is only
/// meaningful without other suites competing for the CPU, so the suite is tagged `.slow` and runs on the
/// nightly lane only (testing-strategy §6). Run it by hand with
/// `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter ProgramTemplatesPerformanceTests`.
@Suite(
    "ProgramTemplates · performance",
    .tags(.domain, .slow),
    .enabled(if: ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly", "nightly lane only")
)
struct ProgramTemplatesPerformanceTests {
    @Test("program() takes under 5 ms for the largest split (median of 5)")
    func program_sixDays_under5ms() throws {
        let block = TemplateCase(goal: .hypertrophy, days: .six)
        let catalog = try BundledCatalog.exercises()
        _ = try block.program(catalog: catalog)
        let clock = ContinuousClock()
        let timings = try (0 ..< 5).map { _ in try clock.measure { _ = try block.program(catalog: catalog) } }.sorted()
        #expect(timings[2] < .milliseconds(5), "median \(timings[2])")
    }
}
