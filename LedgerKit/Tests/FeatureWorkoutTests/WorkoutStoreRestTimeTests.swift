import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S6, criteria 3, 4 and 7: the rest's time. `keepRestTime()`, which `WorkoutRoot` runs for the shown
/// rest, reads the injected date at each of the rest's seconds, so the panel counts down by the wall clock
/// and is right at once after any time away; at zero it plays `.restOver`, once. The date is the test's to
/// move and the clock the test's to step (`RestBench`): nothing waits on real time.
@MainActor
@Suite("WorkoutStore · the rest's time", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreRestTimeTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Bench = RestBench

    @Test("Each second of the rest the panel reads the date again: it counts down by the wall clock")
    func keepsTime_bySeconds() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest)))
        await bench.second(keeper)
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 1)))
        // Between two of the rest's seconds nothing is read: the wait is for the whole second.
        let sleeps = bench.clock.sleeps.value
        bench.date.withValue { $0 += 1 }
        await bench.clock.base.advance(by: .milliseconds(250))
        #expect(bench.store.moment == Fixtures.now.addingTimeInterval(1))
        await bench.clock.base.advance(by: .milliseconds(750))
        await bench.settled(keeper, after: sleeps)
        #expect(bench.store.moment == Fixtures.now.addingTimeInterval(2))
        await bench.seconds(8, keeper)
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 10)))
        #expect(bench.panel?.fraction == (bench.rest - 10) / bench.rest)
        #expect(await bench.haptics.played == [.setLogged])
        keeper.task.cancel()
        bench.following.cancel()
    }

    @Test("After 40 s in the background the panel shows the wall clock's time left, at once, and no haptic")
    func background_fortySeconds() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(10, keeper)
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 10)))
        await bench.suspended(40, keeper)
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 50)))
        #expect(bench.panel?.status == "Resting")
        // And it goes on by the second from there.
        await bench.second(keeper)
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 51)))
        #expect(await bench.haptics.played == [.setLogged])
        keeper.task.cancel()
        bench.following.cancel()
    }

    @Test("At zero the panel reads 0:00 and Rest over, .restOver is played once, and the panel stays")
    func zero_playsRestOverOnce() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(Int(bench.rest) - 1, keeper)
        #expect(bench.panel?.clock == "0:01")
        #expect(await bench.haptics.played == [.setLogged])
        await bench.second(keeper)
        await keeper.task.value
        #expect(bench.panel?.clock == "0:00")
        #expect(bench.panel?.fraction == 0)
        #expect(bench.panel?.status == "Rest over")
        #expect(await bench.haptics.played == [.setLogged, .restOver])
        // A redraw, the task run again (the cover's tasks starting again), and time going by: not again,
        // and the panel stays.
        _ = bench.store.model
        await bench.store.keepRestTime()
        bench.date.withValue { $0 += 600 }
        await bench.store.keepRestTime()
        #expect(await bench.haptics.played == [.setLogged, .restOver])
        #expect(bench.panel?.status == "Rest over")
        bench.following.cancel()
    }

    @Test("A rest that ended while the app was away shows Rest over on return and plays nothing: too late")
    func endedInTheBackground_playsNothing() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(10, keeper)
        await bench.suspended(bench.rest + 30, keeper)
        await keeper.task.value
        #expect(bench.panel?.clock == "0:00")
        #expect(bench.panel?.status == "Rest over")
        #expect(await bench.haptics.played == [.setLogged])
        bench.following.cancel()
    }

    @Test("With a date that stands still the task ends: it does not wait for ever on a rest that never shortens")
    func fixedDate_ends() async throws {
        let scene = try WorkoutScene.onFake(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        try store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: Fixtures.seedSession())[0])))
        await store.drain()
        await eventually { store.shownRest != nil }
        // The scene's date is fixed and its clock immediate, as in every other store test.
        await store.keepRestTime()
        #expect(store.moment == Fixtures.now)
        task.cancel()
    }

    @Test("With no rest shown the task does nothing")
    func noRest_doesNothing() async throws {
        let bench = try await Bench()
        await bench.store.keepRestTime()
        #expect(bench.store.moment == nil)
        #expect(await bench.haptics.played == [])
        bench.following.cancel()
    }
}

/// F10 S6, criterion 7: when `.restOver` is played, and when it is not: late, on a rest that had already
/// ended, on a rest that was extended or skipped, and by a wait that outlived its rest.
@MainActor
@Suite("WorkoutStore · .restOver", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreRestOverTests {
    typealias Bench = RestBench

    @Test("A wait that ends a little late still plays; one that ends a second late or more does not", arguments: [
        (0.0, true), (0.9, true), (1.0, false), (5.0, false)
    ])
    func lateness(late: TimeInterval, isPlayed: Bool) async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(Int(bench.rest) - 1, keeper)
        bench.date.withValue { $0 += late }
        await bench.second(keeper)
        await keeper.task.value
        #expect(bench.panel?.status == "Rest over")
        #expect(await bench.haptics.played == (isPlayed ? [.setLogged, .restOver] : [.setLogged]))
        bench.following.cancel()
    }

    @Test("A cover opened on a rest that had already ended shows Rest over and plays nothing")
    func reopenedAfterTheEnd_playsNothing() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        bench.date.withValue { $0 += 1000 }
        let haptics = FakeHaptics()
        let reopened = bench.scene.store { [date = bench.date] in
            $0.haptics = haptics
            $0.date = DateGenerator { date.value }
        }
        let following = Task { await reopened.follow() }
        await eventually { reopened.shownRest != nil }
        #expect(reopened.restPanel == nil, "no moment was read yet: no panel is drawn before the first one")
        await reopened.keepRestTime()
        #expect(reopened.restPanel?.status == "Rest over")
        #expect(reopened.restPanel?.clock == "0:00")
        #expect(await haptics.played == [])
        following.cancel()
        bench.following.cancel()
    }

    @Test("A rest that is extended, or skipped, before its end is not played at its old end")
    func extendedOrSkipped_isNotPlayed() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        var keeper = await bench.keepingTime()
        await bench.seconds(Int(bench.rest) - 1, keeper)
        // "+30s" one second before the end: the root starts the task again for the new rest.
        try await bench.tap(.extendRest)
        keeper.task.cancel()
        await keeper.task.value
        keeper = await bench.keepingTime()
        await bench.second(keeper)
        #expect(await bench.haptics.played == [.setLogged])
        #expect(bench.panel?.clock == "0:30")
        try await bench.tap(.skipRest)
        keeper.task.cancel()
        await keeper.task.value
        #expect(bench.panel == nil)
        #expect(await bench.haptics.played == [.setLogged])
        bench.following.cancel()
    }

    @Test("A wait that outlives its rest plays nothing: the rest shown is no longer the one it waited for")
    func staleWait_playsNothing() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(Int(bench.rest) - 1, keeper)
        try await bench.tap(.skipRest)
        // The old task was not cancelled yet when its wait ends.
        await bench.second(keeper)
        await keeper.task.value
        #expect(await bench.haptics.played == [.setLogged])
        bench.following.cancel()
    }
}
