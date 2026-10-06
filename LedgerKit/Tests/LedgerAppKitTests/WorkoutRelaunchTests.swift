import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 criterion 7 (the brief's criterion 12): kill and relaunch on a real database file. A composition is
/// booted on a file, a workout is started through `StartWorkoutUseCase` and driven to one of five points, and
/// the composition is dropped there: all a killed process leaves is the file. A second composition booted on
/// the file must then show what criterion 6's table says.
///
/// A step the process "dies in" is one a SQLite trigger refuses, so the call before it has committed and the
/// call itself has not. Since F10 S3 the save and the end of the log are one such step: the point "after the
/// save and before the log was dropped" is gone, and the two tests that stood there show what replaced it.
@Suite("Workout · kill and relaunch", .timeLimit(.minutes(1)))
struct WorkoutRelaunchTests {
    nonisolated static let workoutID = WorkoutID(EventBuilders.uuid(0xF500))
    static let refuseSave = "CREATE TRIGGER die BEFORE INSERT ON workout BEGIN SELECT RAISE(ABORT, 'killed'); END"
    static let refuseDrop = "CREATE TRIGGER die BEFORE DELETE ON workout_event BEGIN SELECT RAISE(ABORT, 'killed'); END"

    /// A start on a database with no live workout that did not start one.
    struct NotStarted: Error {}

    @Test("Killed after the start was stored: the workout is live again, as it was built")
    func killedAfterTheStart_resumes() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let started = try await Launch(harness).startUpperA()
        let relaunched = try await Launch(harness)
        #expect(try await relaunched.session.current() == started)
        #expect(started.cursor == Cursor(exerciseIndex: 0, setIndex: 0) && started.source?.weekIndex == 4)
        #expect(try await relaunched.stores.workouts.recent(limit: 5).isEmpty)
        // It goes on from where the log stands: the next event is this device's seq 2.
        try await relaunched.session.apply(.restSkipped)
        #expect(try await relaunched.stores.events
            .highestSeq(for: Self.workoutID, device: relaunched.stores.deviceID) == 2)
    }

    @Test("Killed in the middle, a rest running: the same sets, cursor and rest, and no haptic")
    func killedMidWorkout_resumesTheSameState() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = try await Launch(harness)
        let live = try await first.logTheFirstExercise(of: first.startUpperA())
        #expect(live.doneSets == 5 && live.cursor == Cursor(exerciseIndex: 1, setIndex: 0))
        #expect(live.rest == RestTimer(endsAt: Harness.now.addingTimeInterval(300 + 150), total: .seconds(150)))
        let relaunched = try await Launch(harness)
        #expect(try await relaunched.session.current() == live)
        var updates = await relaunched.session.updates().makeAsyncIterator()
        #expect(await updates.next() == WorkoutSessionUpdate(state: live))
    }

    @Test(
        "Killed after the finish was stored, before the save: the launch saves it, with its misses, and drops the log"
    )
    func killedBeforeTheSave_isSavedAtLaunch() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = try await Launch(harness)
        let live = try await first.logTheFirstExercise(of: first.startUpperA())
        try await first.refuse(Self.refuseSave)
        await #expect(throws: DatabaseError.self) {
            _ = try await first.session.finish(endedAt: Harness.now.addingTimeInterval(3600))
        }
        #expect(try await first.stores.workouts.recent(limit: 5).isEmpty)
        #expect(try await first.stores.events.uncompactedWorkoutIDs() == [Self.workoutID])
        try harness.arrange { try $0.execute(sql: "DROP TRIGGER die") }
        let relaunched = try await Launch(harness)
        #expect(try await relaunched.session.current() == nil)
        let stored = try #require(await relaunched.stores.workouts.workout(id: Self.workoutID))
        #expect(stored.phase == .finished && stored.endedAt == Harness.now.addingTimeInterval(3600))
        #expect(stored.exercises.map(\.sets) == live.exercises.map(\.sets) && stored.doneSets == 5)
        #expect(try await relaunched.stores.events.uncompactedWorkoutIDs().isEmpty)
        #expect(try await relaunched.misses() == [[], [4], [4], [4], [4]])
        #expect(!LaunchAdversarialTests.spelled(harness.log).contains("failed resumeWorkout"))
    }

    /// F10 S3 criteria 4 and 5: the save and the end of the log are one transaction, so the app can no longer
    /// die between them. A drop that fails takes the save with it.
    @Test("A save whose log cannot be dropped saves nothing; the relaunch saves the workout, its misses and its swap")
    func saveThatCannotDropTheLog_savesNothing() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = try await Launch(harness)
        let live = try await first.swapTheSecondExercise(of: first.logTheFirstExercise(of: first.startUpperA()))
        try await first.refuse(Self.refuseDrop)
        await #expect(throws: DatabaseError.self) {
            _ = try await first.session.finish(endedAt: Harness.now.addingTimeInterval(3600))
        }
        let left = try first.rows()
        #expect(left["workout"]?.isEmpty == true && left["logged_set"]?.isEmpty == true)
        #expect(left["slot_miss"]?.isEmpty == true && left["workout_event"]?.count == 8)
        #expect(try await first.exercises()[1] == Fixtures.CatalogID.inclineDBPress)
        #expect(try await first.session.current() == live)
        try harness.arrange { try $0.execute(sql: "DROP TRIGGER die") }
        let relaunched = try await Launch(harness)
        #expect(try await relaunched.session.current() == nil)
        let saved = try relaunched.rows()
        #expect(saved["workout"]?.count == 1 && saved["logged_set"]?.count == 18 && saved["slot_miss"]?.count == 4)
        #expect(saved["workout_event"]?.isEmpty == true)
        #expect(try await relaunched.misses() == [[], [4], [4], [4], [4]])
        #expect(try await relaunched.exercises()[1] == Fixtures.CatalogID.overheadPress)
    }

    /// The row "saved, not compacted" of recovery's table. The host no longer leaves it over the database; a
    /// store that is not one database can, and so could a build from before the save dropped the log.
    @Test("A log left behind a saved workout: the relaunch saves it again, changing no row, and drops the log")
    func logLeftBehindASavedWorkout_isSavedAgainUnchanged() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = try await Launch(harness)
        _ = try await first.swapTheSecondExercise(of: first.logTheFirstExercise(of: first.startUpperA()))
        try await first.refuse(Self.refuseSave)
        await #expect(throws: DatabaseError.self) {
            _ = try await first.session.finish(endedAt: Harness.now.addingTimeInterval(3600))
        }
        let log = try await first.stores.events.envelopes(for: Self.workoutID)
        try harness.arrange { try $0.execute(sql: "DROP TRIGGER die") }
        let second = try await Launch(harness)
        let saved = try second.rows()
        #expect(saved["workout"]?.count == 1 && saved["workout_event"]?.isEmpty == true)
        // The finished log is back beside the saved workout.
        #expect(try await second.stores.events.append(log).count == 8)
        let third = try await Launch(harness)
        #expect(try await third.session.current() == nil)
        #expect(try Launch.difference(third.rows(), from: saved) == nil)
        #expect(!LaunchAdversarialTests.spelled(harness.log).contains("failed resumeWorkout"))
    }

    @Test("Killed after the discard was stored and before the log was dropped: the log is dropped, nothing in history")
    func killedAfterTheDiscard_dropsTheLog() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = try await Launch(harness)
        _ = try await first.logTheFirstExercise(of: first.startUpperA())
        try await first.refuse(Self.refuseDrop)
        await #expect(throws: DatabaseError.self) {
            try await first.session.discard(endedAt: Harness.now.addingTimeInterval(3600))
        }
        #expect(try first.rows()["workout_event"]?.count == 7)
        try harness.arrange { try $0.execute(sql: "DROP TRIGGER die") }
        let relaunched = try await Launch(harness)
        #expect(try await relaunched.session.current() == nil)
        let rows = try relaunched.rows()
        #expect(rows["workout_event"] == [] && rows["workout"] == [] && rows["slot_miss"] == [])
        // The slot is free: the same day starts again.
        #expect(try await relaunched.startUpperA().doneSets == 0)
    }
}

extension WorkoutRelaunchTests {
    /// One launch of the app on the harness's file: booted, its launch steps run in the foreground.
    @MainActor
    struct Launch {
        let composition: AppComposition
        let stores: LedgerStores
        let session: LocalWorkoutSessionActor

        init(_ harness: Harness) async throws {
            composition = harness.booted()
            await composition.resume(in: .active)
            stores = try #require(composition.stores)
            session = try #require(composition.session)
        }

        /// Saves the spec's program on the first launch and starts week 5's Upper A, as Today will.
        func startUpperA() async throws -> WorkoutState {
            let program = try Fixtures.seedProgram()
            try await stores.programs.save(program)
            let useCase = StartWorkoutUseCase(
                session: session, programs: stores.programs, exercises: stores.exercises, stats: stores.stats,
                settings: stores.settings, device: stores.deviceID, now: { Harness.now },
                newID: { WorkoutRelaunchTests.workoutID.rawValue }
            )
            let source = WorkoutSource(programID: program.id, weekIndex: 4, dayTemplateID: program.days[0].id)
            guard case let .started(workout) = try await useCase.start(source) else {
                throw NotStarted()
            }
            return workout
        }

        /// Logs every set of the first exercise as prescribed, a minute apart: its last one starts a rest.
        func logTheFirstExercise(of workout: WorkoutState) async throws -> WorkoutState {
            var state = workout
            for (number, set) in workout.exercises[0].sets.enumerated() {
                state = try await session.apply(.setLogged(
                    exerciseIndex: 0,
                    setID: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    doneAt: Harness.now.addingTimeInterval(Double(60 * (number + 1)))
                ))
            }
            return state
        }

        /// Swaps the second exercise, the incline dumbbell press, for the overhead press, in the program too.
        func swapTheSecondExercise(of _: WorkoutState) async throws -> WorkoutState {
            try await session.apply(.exerciseSwapped(
                exerciseIndex: 1,
                exerciseID: Fixtures.CatalogID.overheadPress,
                name: "Overhead Press",
                alsoUpdateProgram: true
            ))
        }

        func refuse(_ trigger: String) async throws {
            try await stores.queue.write { try $0.execute(sql: trigger) }
        }

        /// Every stored row of the workout tables, the slots and the log: what a second save may not change.
        func rows() throws -> [String: [Row]] {
            try stores.queue.read { database in
                var rows: [String: [Row]] = [:]
                for table in [
                    "workout",
                    "workout_exercise",
                    "logged_set",
                    "personal_record",
                    "slot_miss",
                    "slot",
                    "workout_event"
                ] {
                    rows[table] = try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY id")
                }
                return rows
            }
        }

        /// The tables whose rows differ between two readings, with their counts, or `nil`: a failure prints
        /// this line, not every row of both.
        static func difference(_ rows: [String: [Row]], from before: [String: [Row]]) -> String? {
            let changed = rows.keys.sorted().filter { rows[$0] != before[$0] }
            guard !changed.isEmpty else {
                return nil
            }
            return changed.map { "\($0): \(rows[$0]?.count ?? 0) rows, were \(before[$0]?.count ?? 0)" }
                .joined(separator: "; ")
        }

        /// The exercise of each of Upper A's five slots, in the stored program.
        func exercises() async throws -> [ExerciseID] {
            try #require(await stores.programs.active()).days[0].slots.map(\.exerciseID)
        }

        /// The weeks missed on each of Upper A's five slots.
        func misses() async throws -> [Set<Int>] {
            try #require(await stores.programs.active()).days[0].slots.map(\.misses)
        }
    }
}
