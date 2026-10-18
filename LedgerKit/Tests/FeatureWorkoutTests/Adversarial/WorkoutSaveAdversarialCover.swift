import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// One cover over a `SaveSession` (G2, F10 S7a): a store, and its work run as `WorkoutRoot` runs it. The
/// follow and the pump run for as long as the cover is up; `discard()` and `save()` run once when the
/// cover goes up and again whenever their attempt's number changes, the run before cancelled
/// (`.task(id:)`). The date is the test's.
@MainActor
final class SaveCover {
    let session: SaveSession
    let store: WorkoutStore
    let running: WorkoutState
    let clock = LockIsolated(Fixtures.now)
    let haptics = FakeHaptics()
    let announcements = FakeAnnouncements()
    private var following: Task<Void, Never>?
    private var pumping: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var discarding: Task<Void, Never>?
    private var ranFor = (save: -1, discard: -1)
    /// Every exit the store showed, as the root's `onChange` hands them on: one at most.
    private(set) var exits: [WorkoutExit] = []
    /// Every receipt the store showed, by its workout, before "Done" was tapped on it (F10 S7b): one at most.
    private(set) var receipts: [WorkoutID] = []

    init(_ change: (inout WorkoutState) -> Void = { _ in }) async {
        var workout = EventBuilders.seedSession()
        for index in [0, 2] {
            workout.exercises[index].lastPerformance = LastPerformance(
                date: Fixtures.now.addingTimeInterval(-7 * 86400), sets: 4, reps: 6, load: .pounds(150)
            )
        }
        change(&workout)
        running = workout
        let client = SaveSession(live: workout)
        session = client
        store = withTestDependencies { [clock, haptics, announcements] in
            $0.workoutSession = client
            $0.haptics = haptics
            $0.announcements = announcements
            $0.date = DateGenerator { clock.value }
        } operation: {
            WorkoutStore()
        }
        startTasks()
        await eventually("the session's first update") { self.store.isHearingTheSession }
    }

    func set(_ exercise: Int, _ row: Int) -> SetID {
        running.exercises[exercise].sets[row].id
    }

    // MARK: The root's tasks

    private func startTasks() {
        following = Task { [store] in await store.follow() }
        pumping = Task { [store] in await store.pump() }
        ranFor = (-1, -1)
        sync()
    }

    /// `.task(id: store.saveAttempt)` and `.task(id: store.discardAttempt)`, and the root's `onChange` of
    /// the exit.
    func sync() {
        if ranFor.save != store.saveAttempt {
            ranFor.save = store.saveAttempt
            saving?.cancel()
            saving = Task { [store] in await store.save() }
        }
        if ranFor.discard != store.discardAttempt {
            ranFor.discard = store.discardAttempt
            discarding?.cancel()
            discarding = Task { [store] in await store.discard() }
        }
        // F10 S7b (edited for the audit): a save this cover made shows its receipt and keeps the cover up.
        // The lifter of these tests taps "Done" as soon as it shows, which closes the cover as saved; the
        // receipts shown are kept, so a test can tell that one was.
        if let saved = store.saved, store.exit == nil {
            receipts.append(saved.id)
            store.send(.done)
        }
        if let exit = store.exit, exits.last != exit {
            exits.append(exit)
        }
    }

    /// The cover's view goes and comes back: every task is cancelled, and all start again on the same store.
    /// With `wait` false the new ones start before the old have ended, as SwiftUI starts them.
    func restartTasks(awaitingTheOld wait: Bool = true) async {
        let old = [following, pumping, saving, discarding]
        for task in old {
            task?.cancel()
        }
        if wait {
            await Self.ended(old, "the cover's old tasks")
        }
        startTasks()
    }

    func close() async {
        let all = [following, pumping, saving, discarding]
        for task in all {
            task?.cancel()
        }
        await session.holdEveryApply(false)
        await session.holdEveryEnd(false)
        while session.waiting.value > 0 {
            await session.release()
        }
        while session.endsWaiting.value > 0 {
            await session.releaseEnd()
        }
        await session.keepStreamsBehind(false)
        await Self.ended(all, "the cover's tasks")
    }

    /// Waits for `tasks` to end, by giving way a bounded number of times: a task that never ends (a follow
    /// that never hears an end) records an issue instead of holding the test until its time limit.
    static func ended(_ tasks: [Task<Void, Never>?], _ what: String) async {
        let done = LockIsolated(0)
        for task in tasks {
            Task {
                await task?.value
                done.withValue { $0 += 1 }
            }
        }
        await eventually("\(what) to end") { done.value == tasks.count }
    }

    // MARK: Taps

    /// What a tap sends, then what the root does about it.
    func send(_ actions: WorkoutAction...) {
        for action in actions {
            store.send(action)
            sync()
        }
    }

    func tap(_ edits: WorkoutEdit...) {
        for edit in edits {
            send(.edit(edit))
        }
    }
}

extension SaveCover {
    /// Gives way until `condition` holds, running the root's part meanwhile; false, with an issue, when it
    /// never does.
    @discardableResult
    func until(
        _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        await eventually(what, sourceLocation: sourceLocation) {
            self.sync()
            return condition()
        }
    }

    /// Everything under way lands: for "nothing more happened".
    func rest() async {
        for _ in 0 ..< 400 {
            await Task.yield()
        }
        sync()
    }

    /// Nothing waits and nothing is behind any more, and the page shows the session's workout or the
    /// cover is closing.
    func settle() async {
        await session.holdEveryApply(false)
        await session.holdEveryEnd(false)
        await session.keepStreamsBehind(false)
        for _ in 0 ..< 400 where session.waiting.value > 0 || session.endsWaiting.value > 0 {
            await session.release()
            await session.releaseEnd()
            await Task.yield()
        }
        // The taps that waited change the session's workout as they land: it is asked again each round.
        for _ in 0 ..< 400 {
            await rest()
            let truth = await session.current()
            let isQuiet = store.queue.isEmpty && !store.isDraining
            if store.exit != nil || store.shown == nil || (store.shown == truth && isQuiet) {
                return
            }
        }
        let state = "queue \(store.queue.count), draining \(store.isDraining), hearing \(store.isHearingTheSession)"
        Issue.record("the cover never came to rest: \(state), saving \(store.isSaving)")
    }

    /// What must hold of a cover at rest, whatever was done to it (criteria 8, 13, 14, 17 and 18): nil
    /// when it does.
    func fault() async -> String? {
        let ended = await session.ended
        let live = await session.current()
        let reached = await session.reached
        let ends = reached.filter { !Self.isChange($0) }
        var faults: [String] = []
        if ends.count > 1 {
            faults.append("the workout was ended \(ends.count) times: \(ends)")
        }
        if exits.count > 1 {
            faults.append("the cover closed more than once: \(exits)")
        }
        if let wrong = Self.exitFault(store.exit, ended: ended, live: live, isShowing: store.shown != nil) {
            faults.append(wrong)
        }
        return faults.isEmpty ? nil : faults.joined(separator: "; ")
    }

    /// Whether the way the cover closed, or its staying up, is what became of the session's workout.
    private nonisolated static func exitFault(
        _ exit: WorkoutExit?,
        ended: WorkoutState?,
        live: WorkoutState?,
        isShowing: Bool
    ) -> String? {
        let workout = name(ended, live)
        switch exit {
        case let .route(.saved(id)):
            return ended?.phase == .finished && ended?.id == id ? nil : "closed as saved; \(workout)"
        case .route(.discarded):
            return ended?.phase == .discarded ? nil : "closed as discarded; \(workout)"
        case .route(.minimized):
            return live != nil ? nil : "closed as minimized; \(workout)"
        case .nothingToShow:
            return live == nil ? nil : "closed with nothing to show; \(workout)"
        case nil:
            return live == nil && isShowing ? "the cover is up on a workout; \(workout)" : nil
        }
    }

    /// What `fault()` says of a cover that closed as saved on a workout that was discarded.
    nonisolated static let savedButDiscarded = "closed as saved; the session's workout is discarded"

    private nonisolated static func isChange(_ call: SaveSession.Reached) -> Bool {
        if case .change = call {
            return true
        }
        return false
    }

    private nonisolated static func name(_ ended: WorkoutState?, _ live: WorkoutState?) -> String {
        if live != nil {
            return "the session's workout is live"
        }
        return "the session's workout is \(ended.map { "\($0.phase)" } ?? "none")"
    }
}
