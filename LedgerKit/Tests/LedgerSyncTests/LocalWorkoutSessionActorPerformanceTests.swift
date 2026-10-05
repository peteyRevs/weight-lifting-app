import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 12 (architecture §15, the brief's "Non-functional"): an `apply`, including its append to
/// the GRDB store on a real file, takes under 30 ms. A timing is only meaningful without other suites
/// competing for the CPU, so it runs in the nightly lane only (testing-strategy §6). By hand:
/// `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter LocalWorkoutSessionActorPerformanceTests`.
@Suite(
    "LocalWorkoutSessionActor · apply timing",
    .tags(.sync, .performance, .slow),
    .enabled(if: TestLane.isNightly, "nightly lane only"),
    .timeLimit(.minutes(5))
)
struct LocalWorkoutSessionActorPerformanceTests {
    @Test(
        "An apply with its append to the database file is under 30 ms (95th percentile of 20, on a log of 200 events)"
    )
    func apply_withItsAppend_isUnderBudget() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LedgerSyncTests-\(ProcessInfo.processInfo.processIdentifier)-applyTiming")
        try? FileManager.default.removeItem(at: directory) // absent unless an earlier run crashed
        defer { try? FileManager.default.removeItem(at: directory) } // cleanup only
        let stores = try LedgerStores.open(
            at: directory.appending(path: "ledger.sqlite"),
            kind: .phone,
            now: { EventBuilders.start },
            newID: { EventBuilders.phone.rawValue }
        )
        let host = LocalWorkoutSessionActor(
            events: stores.events, workouts: stores.workouts, programs: stores.programs,
            device: stores.deviceID, now: { EventBuilders.start }
        )
        try await host.start(Sample.session)
        // A long workout's log, and the warm-up: the cost of an apply must not grow with the log.
        for number in 0 ..< 200 {
            try await host.apply(Sample.retargeted(0, number % 5, pounds: Decimal(100 + number)))
        }
        let clock = ContinuousClock()
        var timings: [Duration] = []
        for number in 0 ..< PerformanceBudget.runs {
            let event = number.isMultiple(of: 2)
                ? Sample.logged(number % 5, 0, at: Double(60 * number))
                : Sample.retargeted(1, number % 3, pounds: Decimal(50 + number))
            try await timings.append(clock.measure { try await host.apply(event) })
        }
        timings.sort()
        let slowest = timings[PerformanceBudget.runs * 95 / 100 - 1]
        let report = "p95 \(slowest); median \(timings[PerformanceBudget.runs / 2]); runs \(timings)"
        #expect(slowest < PerformanceBudget.apply, "\(report)")
        Attachment.record(report, named: "session-apply.txt")
        #expect(try await stores.events.highestSeq(for: Sample.session.id, device: stores.deviceID) == 221)
    }
}
