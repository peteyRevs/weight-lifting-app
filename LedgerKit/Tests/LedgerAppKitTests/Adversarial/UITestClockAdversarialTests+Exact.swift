import Foundation
@testable import LedgerAppKit
import Testing

// F09 S5 adversarial round 2 (G2), criterion 16: the clock argument reads one real instant written exactly.

extension UITestClockAdversarialTests {
    /// Round 2 (criterion 16, "written exactly"): two spellings round 1 saw read and called reasonable are
    /// now refused with the rest, by the fix round's choice. Pinned so that it stays a choice.
    @Test(
        "Fractional seconds, an offset of hours alone and a lower-case or missing zone are refused",
        arguments: [
            "2026-09-17T12:00:00.500Z", "2026-09-17T12:00:00.0Z", "2026-09-17T14:00:00+02", "2026-09-17T12:00:00-00",
            "2026-09-17T12:00:00z", "2026-09-17T12:00:00+2:00", "2026-09-17T12:00:00+02:0", "2026-09-17T12:00:00 Z",
            "2026-09-17T12:00:00+02:00:00", "2026-9-17T12:00:00Z", "2026-09-17T12:0:00Z", "02026-09-17T12:00:00Z"
        ]
    )
    func offset_valueNotWrittenExactly_isRefused(_ value: String) {
        #expect(throws: UITestClock.InvalidInstant(value: value)) {
            try UITestClock.offset(arguments: Self.arguments("-LEDGER_UITEST_NOW", value), launch: Self.launch)
        }
    }

    @Test("A real instant on the last day of February in a leap year, and at 23:59:59, is read")
    func offset_edgesThatExist_areRead() throws {
        let leap = try #require(try Self.instant("2028-02-29T23:59:59Z"))
        let next = try #require(try Self.instant("2028-03-01T00:00:00Z"))
        #expect(next.timeIntervalSince(leap) == 1)
        #expect(try Self.instant("2026-12-31T23:59:59-12:00") != nil)
        #expect(try Self.instant("2026-01-01T00:00:00+14:00") != nil)
        #expect(throws: UITestClock.InvalidInstant(value: "2026-02-29T12:00:00Z")) {
            try Self.instant("2026-02-29T12:00:00Z")
        }
    }
}
