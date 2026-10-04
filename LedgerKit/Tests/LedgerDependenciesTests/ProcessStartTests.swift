import Foundation
import LedgerDependencies
import Testing

/// `ProcessStart`, where launch-to-first-frame begins (product decision #30).
@Suite("Process start")
struct ProcessStartTests {
    @Test("The kernel's start time for this process is in the past, and the same on every read")
    func processStart_isThisProcesses() throws {
        let start = try #require(ProcessStart.date())
        let now = Date()
        #expect(start <= now)
        #expect(now.timeIntervalSince(start) < 24 * 60 * 60, "this test process started \(start)")
        #expect(ProcessStart.date() == start)
    }
}
