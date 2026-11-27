import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
@testable import LedgerWatchAppKit
import SwiftUI
import Testing

/// F18 S7: a UI test's watch (`WatchUITest`), read beside `-LEDGER_UITEST` with the iPhone's argument names: the seed
/// program, a moved clock and the scripted Health store.
@Suite("WatchUITest", .timeLimit(.minutes(1)))
struct WatchUITestTests {
    private static let launch = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Monday 2026-09-14 12:00 UTC.
    private static let mondayNoon = Date(timeIntervalSince1970: 1_789_387_200)

    private static func arguments(_ extra: String...) -> [String] {
        ["LedgerWatch", "-LEDGER_UITEST", "1"] + extra
    }

    @Test("The seed program is asked for beside -LEDGER_UITEST, and only there")
    func seedsProgram_isReadOnlyForAUITest() throws {
        #expect(try WatchUITest.seedsProgram(arguments: Self.arguments("-LEDGER_UITEST_PROGRAM", "seed")))
        #expect(try !WatchUITest.seedsProgram(arguments: Self.arguments()))
        #expect(try !WatchUITest.seedsProgram(arguments: ["LedgerWatch", "-LEDGER_UITEST_PROGRAM", "seed"]))
    }

    @Test("A program value that is missing or is not seed is refused", arguments: [nil, "", "Seed", "1"])
    func seedsProgram_refusesAnyOtherValue(value: String?) {
        let arguments = Self.arguments("-LEDGER_UITEST_PROGRAM") + [value].compactMap(\.self)
        #expect(throws: WatchUITest.InvalidValue(argument: "-LEDGER_UITEST_PROGRAM", value: value)) {
            try WatchUITest.seedsProgram(arguments: arguments)
        }
    }

    @Test("The launch instant maps to the instant asked for; without -LEDGER_UITEST the argument is ignored")
    func clockOffset_mapsTheLaunchToTheInstant() throws {
        let arguments = Self.arguments("-LEDGER_UITEST_NOW", "2026-09-14T12:00:00Z")
        let offset = try #require(try WatchUITest.clockOffset(arguments: arguments, launch: Self.launch))
        #expect(Self.launch.addingTimeInterval(offset) == Self.mondayNoon)
        let plain = ["LedgerWatch", "-LEDGER_UITEST_NOW", "soon"]
        #expect(try WatchUITest.clockOffset(arguments: plain, launch: Self.launch) == nil)
        #expect(try WatchUITest.clockOffset(arguments: Self.arguments(), launch: Self.launch) == nil)
    }

    @Test(
        "Only a UTC instant to the second that exists, and nothing after it, is read",
        arguments: [
            nil, "soon", "2026-09-14", "2026-02-30T12:00:00Z", "2026-09-14T25:00:00Z", "2026-09-14T12:00:60Z",
            "2026-09-14T14:00:00+02:00", "2026-09-14T12:00:00.5Z", "2026-09-14T12:00:00Zjunk", " 2026-09-14T12:00:00Z"
        ]
    )
    func clockOffset_refusesAnythingElse(value: String?) {
        let arguments = Self.arguments("-LEDGER_UITEST_NOW") + [value].compactMap(\.self)
        #expect(throws: WatchUITest.InvalidValue(argument: "-LEDGER_UITEST_NOW", value: value)) {
            try WatchUITest.clockOffset(arguments: arguments, launch: Self.launch)
        }
    }

    @Test("A UI test's launch gets the scripted, authorized Health store and what it asked for; the app gets nothing")
    func live_readsTheLaunch() async throws {
        let app = WatchUITest.live(arguments: ["LedgerWatch", "-LEDGER_UITEST_PROGRAM", "seed"])
        #expect(app.healthStore == nil && app.clockOffset == nil && !app.seedsProgram)
        let uiTest = WatchUITest.live(arguments: Self.arguments("-LEDGER_UITEST_PROGRAM", "seed"))
        let fake = try #require(uiTest.healthStore as? FakeHealthStore)
        #expect(await fake.authorization() == .authorized)
        #expect(uiTest.seedsProgram && uiTest.clockOffset == nil)
        let environment = WatchComposition.Environment.live(arguments: Self.arguments())
        #expect(environment.healthStore is FakeHealthStore)
        let moved = WatchComposition.Environment.live(arguments: Self.arguments(
            "-LEDGER_UITEST_NOW",
            "2026-09-14T12:00:00Z"
        ))
        #expect(abs(moved.now().timeIntervalSince(Self.mondayNoon)) < 60)
    }

    @Test("Asked for, the seed program is saved as the active one; a program already active stays")
    func saveUITestProgram_savesTheSeedWhenNone() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let asked = WatchUITest.Launch(clockOffset: 90, seedsProgram: true)
        let composition = harness.composition(uiTest: asked)
        composition.boot()
        #expect(composition.clockOffset == 90)
        // The launch's pass seeds the catalog the seed program's exercises are in, then saves the program.
        await composition.resume(in: .active)
        await composition.saveUITestProgramIfAsked()
        #expect(try await composition.stores?.programs.active()?.id == Fixtures.seedProgram().id)

        let other = Harness("\(#function)-other")
        defer { other.remove() }
        let mine = other.composition(uiTest: asked)
        mine.boot()
        await mine.database.resume(isForeground: true)
        let programs = try #require(mine.stores?.programs)
        let own = try Fixtures.defaultProgram()
        try await programs.save(own)
        await mine.saveUITestProgramIfAsked()
        #expect(try await programs.active()?.id == own.id)
    }

    @Test("Not asked for, no program is saved, and the clock is not moved")
    func saveUITestProgram_notAsked_savesNothing() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        #expect(composition.clockOffset == 0)
        await composition.saveUITestProgramIfAsked()
        #expect(try await composition.stores?.programs.active() == nil)
    }

    @Test("The script reads 128 BPM every 2 s to the fake store's heart rate, until it is cancelled")
    func scriptHeartRate_readsOnTheClock() async {
        let fake = FakeHealthStore(authorization: .authorized)
        let beats = await fake.heartRate()
        let clock = RestCoverClock()
        let script = Task { await WatchUITest.scriptHeartRate(of: fake, clock: clock, now: { Fixtures.now }) }
        await clock.changed()
        clock.advance(by: WatchUITest.heartRateEvery)
        var iterator = beats.makeAsyncIterator()
        #expect(await iterator.next() == HeartRateSample(bpm: 128, date: Fixtures.now))
        script.cancel()
        await script.value
    }
}
