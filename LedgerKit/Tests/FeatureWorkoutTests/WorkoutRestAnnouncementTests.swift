@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criteria 21 and 22: what VoiceOver is told about a rest, through the announcements client.
/// "Rest, … remaining" once for each shown rest that has time left, at the first pass of the task that
/// keeps its time; "Rest over" exactly where `.restOver` is played, after it.
@MainActor
@Suite("WorkoutStore rest announcements", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutRestAnnouncementTests {
    typealias Bench = RestBench

    @Test("A logged set's rest is announced once, with its time in words; a tick and a second task add nothing")
    func restStart_isAnnouncedOnce() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        #expect(await bench.announcements.announced == [], "the announcement is the time-keeping task's")
        let keeper = await bench.keepingTime()
        #expect(await bench.announcements.announced == ["Rest, 2 minutes, 30 seconds remaining"])
        await bench.seconds(3, keeper)
        #expect(await bench.announcements.announced.count == 1)

        // The cover's tasks start again on the same rest, and the app comes back from the background.
        keeper.task.cancel()
        await keeper.task.value
        let again = await bench.keepingTime()
        await bench.suspended(20, again)
        #expect(await bench.announcements.announced.count == 1)
        again.task.cancel()
        bench.following.cancel()
    }

    @Test("+30s makes a new rest, which is announced with what is then left (O8)")
    func extendedRest_isAnnounced() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(135, keeper)
        keeper.task.cancel()
        await keeper.task.value
        try await bench.tap(.extendRest)
        let next = await bench.keepingTime()
        #expect(await bench.announcements.announced == [
            "Rest, 2 minutes, 30 seconds remaining", "Rest, 45 seconds remaining"
        ])
        next.task.cancel()
        bench.following.cancel()
    }

    @Test("At zero Rest over is announced once, after the haptic; the next set's rest is announced in its turn")
    func restOver_isAnnouncedWithTheHaptic() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(Int(bench.rest), keeper)
        await keeper.task.value
        #expect(await bench.haptics.played == [.setLogged, .restOver])
        #expect(await bench.announcements.announced == ["Rest, 2 minutes, 30 seconds remaining", "Rest over"])

        // A second task on the rest that is over says nothing more.
        let again = await bench.keepingTime()
        await again.task.value
        #expect(await bench.announcements.announced.count == 2)

        try await bench.tap(.log(exerciseIndex: 0, setID: bench.running.exercises[0].sets[1].id))
        let next = await bench.keepingTime()
        #expect(await bench.announcements.announced.last == "Rest, 2 minutes, 30 seconds remaining")
        #expect(await bench.announcements.announced.count == 3)
        next.task.cancel()
        bench.following.cancel()
    }

    @Test("A rest that is skipped, or that ended while the app was away, announces no Rest over")
    func skippedOrLate_announcesNoRestOver() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        await bench.seconds(10, keeper)
        keeper.task.cancel()
        await keeper.task.value
        try await bench.tap(.skipRest)
        let none = await bench.keepingTime()
        await none.task.value
        #expect(await bench.announcements.announced == ["Rest, 2 minutes, 30 seconds remaining"])

        try await bench.tap(.log(exerciseIndex: 0, setID: bench.running.exercises[0].sets[1].id))
        let late = await bench.keepingTime()
        await bench.suspended(400, late)
        await late.task.value
        #expect(await bench.announcements.announced == [
            "Rest, 2 minutes, 30 seconds remaining", "Rest, 2 minutes, 30 seconds remaining"
        ])
        #expect(await bench.haptics.played == [.setLogged, .setLogged])
        bench.following.cancel()
    }

    @Test("A cover that opens on a running rest announces what is left; on a rest already over, nothing")
    func coverOpensOnARest() async throws {
        var resting = try Fixtures.seedSession()
        resting.rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(75), total: .seconds(150))
        resting.exercises[0].sets[0].doneAt = Fixtures.now.addingTimeInterval(-75)
        let bench = try await Bench(resting)
        let keeper = await bench.keepingTime()
        #expect(await bench.announcements.announced == ["Rest, 1 minute, 15 seconds remaining"])
        keeper.task.cancel()
        bench.following.cancel()

        var over = resting
        over.rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(-5), total: .seconds(150))
        let second = try await Bench(over)
        let done = await second.keepingTime()
        await done.task.value
        #expect(second.panel?.status == "Rest over")
        #expect(await second.announcements.announced == [])
        #expect(await second.haptics.played == [])
        second.following.cancel()
    }
}
