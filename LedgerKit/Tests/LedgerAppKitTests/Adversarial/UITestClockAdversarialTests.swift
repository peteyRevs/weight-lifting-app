import Foundation
@testable import LedgerAppKit
import Testing

/// F09 S5 adversarial round 1 (G2): the UI tests' date argument, `-LEDGER_UITEST_NOW`, given values a tired
/// hand types, twice, in odd places, and in zones where the day is not 24 hours long.
@Suite("Adversarial F09 S5 · UITestClock")
struct UITestClockAdversarialTests {
    private static let launch = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Thursday 2026-09-17 12:00 UTC.
    private static let thursdayNoon = Date(timeIntervalSince1970: 1_789_646_400)

    private static func arguments(_ extra: String...) -> [String] {
        ["Ledger", "-LEDGER_UITEST", "1"] + extra
    }

    private static func instant(_ value: String) throws -> Date? {
        try UITestClock.offset(arguments: arguments("-LEDGER_UITEST_NOW", value), launch: launch)
            .map { launch.addingTimeInterval($0) }
    }

    /// FINDING F09-S5-5 (low; a test-only tool). The type's promise is "a value that cannot be read stops the
    /// launch: a UI test set up wrongly must not run on the real date and pass or fail by the weekday".
    /// `Date(_:strategy: .iso8601)` reads more than instants: a day or an hour that does not exist is rolled
    /// over to another day (30 February is 2 March, 25:00 is 01:00 the next day, second 60 the next minute),
    /// and whatever follows the instant is ignored. Such a test runs on a day its author did not write, which
    /// is the failure the `fatalError` exists to stop. A fix: format the date read back and require the same
    /// text, or check the fields against the calendar.
    @Test(
        "A date that does not exist, or an instant with something after it, is refused, not moved to another day",
        arguments: [
            "2026-02-30T12:00:00Z", "2026-09-31T12:00:00Z", "2026-09-17T25:00:00Z", "2026-09-17T12:00:60Z",
            "2026-09-17T12:00:00Z trailing", "2026-09-17T12:00:00Z\n", "2026-09-17T12:00:00ZZ",
            "2026-09-17T12:00:00Z;2026-09-18T12:00:00Z"
        ]
    )
    func offset_valueThatIsNoRealInstant_isRefused(_ value: String) {
        #expect(throws: UITestClock.InvalidInstant(value: value)) {
            try UITestClock.offset(arguments: Self.arguments("-LEDGER_UITEST_NOW", value), launch: Self.launch)
        }
    }

    @Test(
        "Values that are plainly no ISO 8601 instant are refused",
        arguments: [
            "2026-09-17T12:00:00", " 2026-09-17T12:00:00Z", "2026-09-17t12:00:00z", "20260917T120000Z",
            "2026-09-17 12:00:00Z", "2026-09-17T12:00Z", "2026-13-01T12:00:00Z", "2026-W38-4T12:00:00Z",
            "२०२६-09-17T12:00:00Z", "2026-09-17T12:00:00+25:00", "2026-09-17T12:00:00−02:00", "now", "0", "-1",
            "-LEDGER_UITEST", "-LEDGER_UITEST_NOW"
        ]
    )
    func offset_malformedValue_isRefused(_ value: String) {
        #expect(throws: UITestClock.InvalidInstant(value: value)) {
            try UITestClock.offset(arguments: Self.arguments("-LEDGER_UITEST_NOW", value), launch: Self.launch)
        }
    }

    @Test("The same moment written in any zone's offset, with or without a colon, is the same instant")
    func offset_anyZoneOffset_isTheSameInstant() throws {
        let spellings = [
            "2026-09-17T12:00:00Z", "2026-09-17T12:00:00+00:00", "2026-09-17T14:00:00+02:00",
            "2026-09-17T14:00:00+0200", "2026-09-17T05:00:00-07:00", "2026-09-18T01:00:00+13:00",
            "2026-09-17T17:30:00+05:30", "2026-09-17T00:00:00-12:00", "2026-09-18T02:00:00+14:00"
        ]
        for spelling in spellings {
            #expect(try Self.instant(spelling) == Self.thursdayNoon, "\(spelling)")
        }
    }

    @Test("The hour a zone repeats when its clocks go back is two instants, told apart by the offset written")
    func offset_theRepeatedHour_isTheOneWritten() throws {
        // Los Angeles, Sunday 2026-11-01: 01:30 happens at -07:00 and, an hour later, at -08:00.
        let first = try #require(try Self.instant("2026-11-01T01:30:00-07:00"))
        let second = try #require(try Self.instant("2026-11-01T01:30:00-08:00"))
        #expect(second.timeIntervalSince(first) == 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(calendar.component(.hour, from: first) == 1)
        #expect(calendar.component(.hour, from: second) == 1)
        // The hour that is skipped in spring does not exist on a wall clock there; written with an offset it
        // is still one instant, an hour on.
        let skipped = try #require(try Self.instant("2026-03-08T02:30:00-08:00"))
        #expect(calendar.component(.hour, from: skipped) == 3)
    }

    @Test("The offset is one number for the whole run: a launch moved across a clock change keeps real seconds")
    func offset_isConstant_acrossAClockChange() throws {
        // Launched, in real time, an hour before Los Angeles' clocks go back, and moved to a summer date.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1,
            hour: 0,
            minute: 30
        )))
        let given = Self.arguments("-LEDGER_UITEST_NOW", "2026-09-17T12:00:00Z")
        let offset = try #require(try UITestClock.offset(arguments: given, launch: start))
        // Two real hours on, across the change, the app's clock has moved two hours too.
        let later = start.addingTimeInterval(7200)
        #expect(later.addingTimeInterval(offset) == Self.thursdayNoon.addingTimeInterval(7200))
        #expect(calendar.component(.hour, from: later) == 1, "the wall clock there moved one hour")
    }

    @Test("Given twice, the first instant is the one used, and a bad first value is refused whatever follows")
    func offset_givenTwice_usesTheFirst() throws {
        let twice = Self.arguments(
            "-LEDGER_UITEST_NOW",
            "2026-09-17T12:00:00Z",
            "-LEDGER_UITEST_NOW",
            "2026-09-18T12:00:00Z"
        )
        let offset = try #require(try UITestClock.offset(arguments: twice, launch: Self.launch))
        #expect(Self.launch.addingTimeInterval(offset) == Self.thursdayNoon)

        let badFirst = Self.arguments("-LEDGER_UITEST_NOW", "soon", "-LEDGER_UITEST_NOW", "2026-09-18T12:00:00Z")
        #expect(throws: UITestClock.InvalidInstant(value: "soon")) {
            try UITestClock.offset(arguments: badFirst, launch: Self.launch)
        }
        // The argument as its own value: the second is read as the first's value, and refused.
        let doubled = Self.arguments("-LEDGER_UITEST_NOW", "-LEDGER_UITEST_NOW", "2026-09-18T12:00:00Z")
        #expect(throws: UITestClock.InvalidInstant(value: "-LEDGER_UITEST_NOW")) {
            try UITestClock.offset(arguments: doubled, launch: Self.launch)
        }
    }

    @Test("Wherever the two arguments stand, the instant is read; in another case or with a prefix it is not there")
    func offset_whereverTheArgumentsStand() throws {
        let before = ["Ledger", "-LEDGER_UITEST_NOW", "2026-09-17T12:00:00Z", "-LEDGER_UITEST", "1"]
        let offset = try #require(try UITestClock.offset(arguments: before, launch: Self.launch))
        #expect(Self.launch.addingTimeInterval(offset) == Self.thursdayNoon)

        for name in [
            "-ledger_uitest_now",
            "--LEDGER_UITEST_NOW",
            "LEDGER_UITEST_NOW",
            "-LEDGER_UITEST_NOW=2026-09-17T12:00:00Z"
        ] {
            #expect(
                try UITestClock.offset(arguments: Self.arguments(name, "soon"), launch: Self.launch) == nil,
                "\(name)"
            )
        }
        #expect(try UITestClock.offset(arguments: [], launch: Self.launch) == nil)
    }

    @Test("Without -LEDGER_UITEST nothing moves the clock: not the argument, not -LEDGER_UITEST in another spelling")
    func offset_withoutTheUITestArgument_neverMoves() throws {
        let good = "2026-09-17T12:00:00Z"
        for flag in ["-ledger_uitest", "-LEDGER_UITEST_", "LEDGER_UITEST", "-LEDGER_UITEST=1", "-LEDGER_UITESTS"] {
            let arguments = ["Ledger", flag, "1", "-LEDGER_UITEST_NOW", good]
            #expect(try UITestClock.offset(arguments: arguments, launch: Self.launch) == nil, "\(flag)")
            let environment = AppComposition.Environment.live(arguments: arguments)
            #expect(environment.clockOffset == nil, "\(flag)")
            #expect(abs(environment.now().timeIntervalSinceNow) < 5, "\(flag)")
        }
    }

    @Test("A far instant gives a finite offset and a clock that still runs")
    func offset_farInstants_stayFinite() throws {
        for value in ["0001-01-01T00:00:00Z", "9999-12-31T23:59:59Z", "1970-01-01T00:00:00Z"] {
            let offset = try #require(try UITestClock.offset(
                arguments: Self.arguments("-LEDGER_UITEST_NOW", value), launch: Self.launch
            ))
            #expect(offset.isFinite, "\(value)")
            let environment = AppComposition.Environment.live(arguments: Self.arguments("-LEDGER_UITEST_NOW", value))
            let first = environment.now()
            #expect(environment.now() >= first, "\(value)")
        }
    }
}
