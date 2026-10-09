@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

// The steps of a seeded walk, and the three limits of the store the walk steps around (each with the seed that
// found it).

@MainActor
extension TodayWalk {
    // MARK: The steps

    func pick(_ count: Int) -> Int {
        Int.random(in: 0 ..< count, using: &generator)
    }

    func step() async throws {
        let choice = pick(15)
        if choice < 7 {
            try await changeTheStores(choice)
        } else {
            try await changeTheHistoryOrTheRun(choice)
        }
    }

    private func changeTheStores(_ choice: Int) async throws {
        switch choice {
        case 0: try await saveSettings { $0.weekStart = Weekday.allCases[self.pick(7)] }
        case 1: try await saveSettings { $0.units = $0.units == .lb ? .kg : .lb }
        case 2: try await saveSettings { _ in }
        case 3: try await saveProgram { $0.days[self.pick(4)].name = "Day \(self.pick(9))" }
        case 4, 5: try await redateProgram()
        default: try await deleteProgram()
        }
    }

    private func changeTheHistoryOrTheRun(_ choice: Int) async throws {
        switch choice {
        case 7, 8: try await storeWorkout()
        case 9: try await deleteWorkout()
        case 10, 11: try await startOrLog()
        case 12: try await endSession()
        case 13: restart()
        default: moveClock()
        }
    }

    func saveSettings(_ change: (inout Settings) -> Void) async throws {
        var settings = try await scene.stores.settings.load()
        change(&settings)
        trace.append("settings \(settings.weekStart) \(settings.units)")
        try await scene.stores.settings.save(settings)
    }

    func saveProgram(_ change: (inout Program) -> Void) async throws {
        var program = try await scene.stores.programs.active() ?? base
        program.isActive = true
        change(&program)
        trace.append("program from \(program.startDate)")
        try await scene.stores.programs.save(program)
    }

    /// The block begins up to ten weeks ago (over, after eight) or up to two weeks from now, on any weekday.
    func redateProgram() async throws {
        let today = try #require(CivilDate(scene.clock.value, in: calendar))
        let start = try #require(today.adding(days: pick(85) - 70))
        try await saveProgram { $0.startDate = start }
    }

    func deleteProgram() async throws {
        trace.append("program deleted")
        try await scene.stores.programs.delete(base.id)
    }

    /// A finished workout that started within the last sixteen days, of the program or ad hoc.
    func storeWorkout() async throws {
        number += 1
        let start = scene.clock.value.addingTimeInterval(-Double(pick(16 * 86400)))
        let source = pick(3) == 0 ? nil : TodayFixtures.source(of: base, weekIndex: pick(8), dayIndex: pick(4))
        let workout = try TodayFixtures.workout(
            number, pounds: Decimal(100 + pick(900)), startedAt: start, seconds: 60, source: source
        )
        trace.append("workout \(number) at \(start)")
        try await scene.stores.workouts.materialize(workout, slotUpdates: [])
        stored.append(workout.id)
        // The same limit as in `deleteWorkout` (seed 380129: stored with a start in last week, behind five
        // newer ones, it left "−86% from last week" where −90% was true). The store's sign that the history
        // changed is the five workouts finished last, so a workout that arrives behind them is seen by a new
        // run only. The app stores a workout when it ends, which makes it the newest; one that arrives late
        // (the watch's, in M2) will not be. The walk restarts the task for it.
        if try await !scene.stores.workouts.recent(limit: 5).contains(where: { $0.id == workout.id }) {
            restart()
        }
    }

    func deleteWorkout() async throws {
        guard !stored.isEmpty else {
            return
        }
        let id = stored.remove(at: pick(stored.count))
        trace.append("workout deleted")
        try await scene.stores.workouts.delete(id: id)
        // Known and left to F13 (the implementer's "Inputs for later slices"); two seeds found it here. A
        // deleted workout is seen at once only when it was one of the five finished last (seed 269263: the
        // sixth of the week stayed counted), and the session's ended workout stays in the store's input until
        // its task restarts (seed 55450: finished, then deleted, it still counted as today's). Nothing in the
        // app deletes a workout yet; the walk restarts the task, as coming back from History will.
        restart()
    }

    /// Starts a workout of any day and week when none is live; else logs its first open set.
    func startOrLog() async throws {
        guard let workout = live else {
            number += 1
            let started = try TodayFixtures.liveWorkout(
                number, of: base, weekIndex: pick(8), dayIndex: pick(4), startedAt: scene.clock.value
            )
            trace.append("session started \(number)")
            try await scene.fake.start(started)
            live = started
            return
        }
        guard let set = workout.exercises[0].sets.first(where: { !$0.isDone }) else {
            return
        }
        trace.append("set logged")
        live = try await scene.fake.apply(.setLogged(
            exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: scene.clock.value
        ))
    }

    /// Finishes the live workout and stores it, as the app's host does, or discards it.
    func endSession() async throws {
        guard live != nil else {
            return
        }
        live = nil
        if pick(2) == 0 {
            trace.append("session discarded")
            try await scene.fake.discard(endedAt: scene.clock.value)
        } else {
            trace.append("session finished")
            let finished = try await scene.fake.finish(endedAt: scene.clock.value)
            try await scene.stores.workouts.materialize(finished, slotUpdates: [])
            stored.append(finished.id)
            endedInSession = finished
        }
    }

    /// A third limit the walk steps around (seed 475157; a note in the notes, not a defect a lifter meets). The
    /// store hands the presentation the session's ended workout until its task restarts, and the presentation
    /// counts a finished session's workout whenever it started (`withFinishedSession`), while the history's
    /// read holds only the two weeks. A workout that started outside them, finished now, is so marked "Logged"
    /// in the off-schedule list until the next run and not after it. It takes a workout left live for days
    /// and a program re-dated under it.
    func restartIfTheEndedWorkoutLeftTheWeek() async throws {
        guard let ended = endedInSession else {
            return
        }
        let program = try await scene.stores.programs.active()
        let settings = try await scene.stores.settings.load()
        let now = scene.clock.value
        let week = Self.ranges(program: program, weekStart: settings.weekStart, now: now, calendar: calendar).week
        if !week.contains(ended.startedAt) {
            restart()
        }
    }

    /// As SwiftUI restarts a task: the old one is cancelled and not waited for.
    func restart() {
        trace.append("restart")
        endedInSession = nil
        task?.cancel()
        task = Task { [store = scene.store] in await store.run() }
    }

    /// The clock moves on by some hours or days. The store keeps no time, so the root's task restarts with
    /// it: that is how Today meets a new day.
    func moveClock() {
        let hours = [1, 7, 24, 31, 72, 168][pick(6)]
        scene.clock.value = scene.clock.value.addingTimeInterval(Double(hours) * 3600)
        trace.append("clock +\(hours) h")
        restart()
    }
}
