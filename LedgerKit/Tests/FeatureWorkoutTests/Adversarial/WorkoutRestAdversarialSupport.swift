import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// How many seeds a seeded test of the rest takes: `LEDGER_PROPERTY_SEED_COUNT`, as every other target's
/// property tests, and 40 when it is unset (the PR lane's count: a store on a host is not a pure function).
nonisolated enum RestSeeds {
    static let all: [UInt64] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        return (0 ..< max(1, configured ?? 40)).map { UInt64($0) &* 7919 &+ 17 }
    }()
}

/// A test clock that says when the last sleep begun on it is due, so a test can tell a task that is asleep
/// from one that was woken and has not yet slept again. Nothing waits on real time.
nonisolated struct RestProbeClock: Clock {
    let base = TestClock<Duration>()
    let sleeps = LockIsolated(0)
    let due = LockIsolated<TestClock<Duration>.Instant?>(nil)

    var now: TestClock<Duration>.Instant {
        base.now
    }

    var minimumResolution: Duration {
        base.minimumResolution
    }

    /// The time since the clock was made.
    var elapsed: Duration {
        TestClock<Duration>.Instant().duration(to: base.now)
    }

    func sleep(until deadline: TestClock<Duration>.Instant, tolerance: Duration?) async throws {
        due.setValue(deadline)
        sleeps.withValue { $0 += 1 }
        try await base.sleep(until: deadline, tolerance: tolerance)
    }
}

/// One phone under test (G2, F10 S6): the real host, a cover over it whose three tasks run as `WorkoutRoot`
/// runs them (`follow()`, `pump()`, and `keepRestTime()` started again whenever `shownRest` changes, the
/// one before cancelled), haptics that record, and time the test moves.
///
/// **Time.** The wall clock is the store's clock plus a skew: `run` moves both together, as a phone that
/// is awake; `suspend` moves the wall clock alone and then lets the pending wait end, as an app that was
/// away or a main actor that was busy; `back` sets the wall clock back. A wait that ends in the middle of
/// a `run` reads the wall clock of that very instant.
@MainActor
final class RestCover {
    let scene: WorkoutScene
    let haptics = FakeHaptics()
    let clock = RestProbeClock()
    let skew = LockIsolated<TimeInterval>(0)
    private(set) var store: WorkoutStore
    private var following: Task<Void, Never>?
    private var pumping: Task<Void, Never>?
    private var keeper: Task<Void, Never>?
    private var keptFor: RestTimer?
    private(set) var isKeeperDone = true
    /// How many stores this phone has made: one for each time the cover went up.
    private(set) var covers = 1

    init(_ running: WorkoutState) async throws {
        scene = try await WorkoutScene.onHost(live: running)
        store = Self.makeStore(scene, haptics, clock, skew)
        await start()
    }

    private static func makeStore(
        _ scene: WorkoutScene,
        _ haptics: FakeHaptics,
        _ clock: RestProbeClock,
        _ skew: LockIsolated<TimeInterval>
    ) -> WorkoutStore {
        scene.store {
            $0.haptics = haptics
            $0.continuousClock = clock
            $0.date = DateGenerator { Self.wallClock(clock, skew) }
        }
    }

    private nonisolated static func wallClock(_ clock: RestProbeClock, _ skew: LockIsolated<TimeInterval>) -> Date {
        Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1) + skew.value)
    }

    /// The wall clock, now.
    var now: Date {
        Self.wallClock(clock, skew)
    }

    /// The session's workout.
    func truth() async -> WorkoutState? {
        try? await scene.session.current()
    }

    // MARK: The cover's tasks

    private func start() async {
        following = Task { [store] in await store.follow() }
        pumping = Task { [store] in await store.pump() }
        await eventually("the session's first update") { self.store.isHearingTheSession || self.store.exit != nil }
        keeper = nil
        await sync()
    }

    private func stop() async {
        for task in [following, pumping, keeper] {
            task?.cancel()
        }
        for task in [following, pumping, keeper] {
            await task?.value
        }
        (following, pumping, keeper) = (nil, nil, nil)
    }

    /// `.task(id: store.shownRest)`: when the shown rest is another than the one the running task was
    /// started for, that task is cancelled and one is started for the new value. Returns with the task
    /// asleep or ended.
    func sync() async {
        guard keeper == nil || keptFor != store.shownRest else {
            await asleepOrDone()
            return
        }
        keeper?.cancel()
        await keeper?.value
        keptFor = store.shownRest
        isKeeperDone = false
        let mark = clock.sleeps.value
        keeper = Task { [store] in
            await store.keepRestTime()
            self.isKeeperDone = true
        }
        await eventually("the rest's task asleep or ended") { self.isKeeperDone || self.clock.sleeps.value > mark }
    }

    private func asleepOrDone() async {
        await eventually("the rest's task asleep again or ended") {
            self.isKeeperDone || (self.clock.due.value.map { $0 > self.clock.base.now } ?? true)
        }
    }

    /// The cover's tasks end and start again on the same store (its view went and came back).
    func restartTasks() async {
        await stop()
        await start()
    }

    /// The cover goes down and comes up again: its tasks end, and a new store follows the same session.
    func reopen() async {
        await stop()
        store = Self.makeStore(scene, haptics, clock, skew)
        covers += 1
        await start()
    }

    func close() async {
        await stop()
    }

    // MARK: Time

    /// `seconds` go by with the phone awake.
    func run(_ seconds: Double) async {
        await clock.base.advance(by: .seconds(seconds))
        await asleepOrDone()
    }

    /// The wall clock moves on by `seconds` while nothing of the app runs; then the pending wait, if there
    /// is one, ends: the first thing the rest's task does on the return is read the date.
    func suspend(_ seconds: Double) async {
        skew.withValue { $0 += seconds }
        await endPendingWait()
    }

    /// The wall clock is set back by `seconds`; then the pending wait, if there is one, ends.
    func back(_ seconds: Double) async {
        skew.withValue { $0 -= seconds }
        await endPendingWait()
    }

    private func endPendingWait() async {
        guard !isKeeperDone, let due = clock.due.value, due > clock.base.now else {
            return
        }
        await clock.base.advance(to: due)
        await asleepOrDone()
    }

    // MARK: Taps

    /// Sends the taps, waits for the pump to have applied them and the page to show the session's
    /// workout, then lets the rest's task follow the shown rest.
    func tap(_ edits: WorkoutEdit...) async {
        for edit in edits {
            store.send(.edit(edit))
        }
        await settle()
    }

    func settle() async {
        await eventually("the taps to be applied") { self.store.queue.isEmpty && !self.store.isDraining }
        let truth = await truth()
        await eventually("the page to show the session's workout") {
            self.store.shown == truth || self.store.exit != nil
        }
        await sync()
    }

    var panel: RestPanelModel? {
        store.model.rest
    }
}

extension RestCover {
    /// What was played, once everything under way has landed.
    func played() async -> [Haptic] {
        await giveWay()
        return await haptics.played
    }

    /// What the panel owes the lifter at this instant, from the session's workout and the Domain alone,
    /// compared with what it shows; nil when they agree.
    func panelFault() async -> String? {
        let owed = await truth()?.shownRest
        guard let owed else {
            return panel == nil ? nil : "a panel with no rest shown"
        }
        guard let panel else {
            return "no panel for a shown rest"
        }
        let left = owed.remaining(at: now)
        var faults: [String] = []
        if panel.clock != ClockText.remaining(left) {
            faults.append("reads \(panel.clock), \(ClockText.remaining(left)) is left")
        }
        if panel.isOver != (left <= .zero) {
            faults.append(panel.isOver ? "over while time is left" : "not over at zero")
        }
        if panel.status != (left <= .zero ? "Rest over" : "Resting") {
            faults.append("status \(panel.status)")
        }
        // The ring is drawn at the last second read: at most one second of the rest behind.
        let second = owed.total > .zero ? Duration.seconds(1) / owed.total : 0
        if abs(panel.fraction - owed.fraction(at: now)) > second + 1e-9 || !(0 ... 1).contains(panel.fraction) {
            faults.append("ring \(panel.fraction), owed \(owed.fraction(at: now))")
        }
        return faults.isEmpty ? nil : faults.joined(separator: "; ")
    }
}
