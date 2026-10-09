import Foundation
@testable import LedgerAppKit
import Testing

/// F09 S5 (the orchestrator's ruling of 2026-10-09): a UI test's own date for the app,
/// `-LEDGER_UITEST_NOW <instant>` beside `-LEDGER_UITEST`.
@Suite("UITestClock")
struct UITestClockTests {
    private static let launch = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Thursday 2026-09-17 12:00 UTC.
    private static let thursdayNoon = Date(timeIntervalSince1970: 1_789_646_400)

    private static func arguments(_ extra: String...) -> [String] {
        ["Ledger", "-LEDGER_UITEST", "1"] + extra
    }

    @Test("The launch instant maps to the instant asked for, and time runs on from there")
    func offset_mapsTheLaunchToTheInstant() throws {
        let arguments = Self.arguments("-LEDGER_UITEST_NOW", "2026-09-17T12:00:00Z")
        let offset = try #require(try UITestClock.offset(arguments: arguments, launch: Self.launch))
        #expect(Self.launch.addingTimeInterval(offset) == Self.thursdayNoon)
        let later = Self.launch.addingTimeInterval(90)
        #expect(later.addingTimeInterval(offset) == Self.thursdayNoon.addingTimeInterval(90))
    }

    @Test("An instant written with another zone's offset is the same moment")
    func offset_readsAZoneOffset() throws {
        let arguments = Self.arguments("-LEDGER_UITEST_NOW", "2026-09-17T14:00:00+02:00")
        let offset = try #require(try UITestClock.offset(arguments: arguments, launch: Self.launch))
        #expect(Self.launch.addingTimeInterval(offset) == Self.thursdayNoon)
    }

    @Test("Without -LEDGER_UITEST the argument is ignored, whatever its value")
    func offset_withoutTheUITestArgument_isNil() throws {
        let good = ["Ledger", "-LEDGER_UITEST_NOW", "2026-09-17T12:00:00Z"]
        #expect(try UITestClock.offset(arguments: good, launch: Self.launch) == nil)
        #expect(try UITestClock.offset(arguments: ["Ledger", "-LEDGER_UITEST_NOW", "soon"], launch: Self.launch) == nil)
        #expect(try UITestClock.offset(arguments: ["Ledger", "-LEDGER_UITEST_NOW"], launch: Self.launch) == nil)
    }

    @Test("A UI test that names no instant runs on the device's clock")
    func offset_withoutTheArgument_isNil() throws {
        #expect(try UITestClock.offset(arguments: Self.arguments(), launch: Self.launch) == nil)
        #expect(UITestClock.liveOffset(arguments: Self.arguments()) == nil)
    }

    @Test(
        "A value that is no instant is refused, never read as the real date",
        arguments: ["soon", "2026-09-17", "1789646400", "", "-LEDGER_OTHER"]
    )
    func offset_invalidValue_throws(_ value: String) {
        #expect(throws: UITestClock.InvalidInstant(value: value)) {
            try UITestClock.offset(arguments: Self.arguments("-LEDGER_UITEST_NOW", value), launch: Self.launch)
        }
    }

    @Test("The argument with nothing after it is refused")
    func offset_missingValue_throws() {
        #expect(throws: UITestClock.InvalidInstant(value: nil)) {
            try UITestClock.offset(arguments: Self.arguments("-LEDGER_UITEST_NOW"), launch: Self.launch)
        }
    }

    @Test("The live environment moves the launch's clock and its process start together, and nothing else")
    func liveEnvironment_isMovedByTheOffset() throws {
        let plain = AppComposition.Environment.live(arguments: Self.arguments())
        #expect(plain.clockOffset == nil)
        #expect(abs(plain.now().timeIntervalSinceNow) < 5)

        let moved = AppComposition.Environment.live(
            arguments: Self.arguments("-LEDGER_UITEST_NOW", "2026-09-17T12:00:00Z")
        )
        let offset = try #require(moved.clockOffset)
        #expect(abs(moved.now().timeIntervalSince(Self.thursdayNoon)) < 5, "the launch reads as the instant")
        #expect(abs(moved.now().timeIntervalSinceNow - offset) < 5)
        let start = try #require(moved.processStart)
        let realStart = try #require(plain.processStart)
        #expect(abs(start.timeIntervalSince(realStart) - offset) < 0.001, "launch-to-first-frame is unchanged")
        #expect(moved.preparesDependencies)
    }
}
