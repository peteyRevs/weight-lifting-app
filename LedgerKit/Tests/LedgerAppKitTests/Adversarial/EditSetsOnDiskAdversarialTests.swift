#if DEBUG
    import Dependencies
    @testable import FeatureHistory
    import Foundation
    import GRDB
    import LedgerDependencies
    import LedgerDomain
    import LedgerPersistence
    import LedgerTestSupport
    import Testing

    /// F13 S3 adversarial (G2): the sheet and the detail over the real database, where the fakes can't stand in: GRDB's
    /// `missingRow` reaching the store's alert, a write that fails being no such alert, a task cancelled mid-write, and
    /// a kg step on a pound workout going all the way to the receipt.
    @MainActor
    @Suite("Adversarial F13 S3 · the sheet on the real database", .serialized, .timeLimit(.minutes(2)))
    struct EditSetsOnDiskAdversarialTests {
        struct Scene {
            let queue: DatabaseQueue
            let workouts: GRDBWorkoutRepository
            let settings: GRDBSettingsRepository
            let workout: WorkoutState

            init(units: Units = .lb) async throws {
                queue = try LedgerDatabase.inMemory()
                workouts = GRDBWorkoutRepository(queue)
                settings = GRDBSettingsRepository(queue)
                var current = Settings.default
                current.units = units
                try await settings.save(current)
                workout = Seeders.workout(number: 7, endedAt: Fixtures.date(2026, 9, 16, hour: 8), [
                    .straight(WorkoutRepositoryContract.exercises[0], sets: 2, reps: 5, pounds: 225),
                    .straight(WorkoutRepositoryContract.exercises[1], sets: 1, reps: 5, pounds: 135)
                ])
                for exercise in WorkoutRepositoryContract.exercises {
                    try await GRDBExerciseRepository(queue).save(exercise)
                }
                try await workouts.materialize(workout, slotUpdates: [])
            }

            func sheet(units: Units = .lb) -> EditSetsStore {
                withTestDependencies {
                    $0.workoutRepository = workouts
                    $0.settingsRepository = settings
                } operation: {
                    EditSetsStore(EditSetsRequest(workout: workout, units: units))
                }
            }

            func detail() -> WorkoutDetailStore {
                withTestDependencies {
                    $0.workoutRepository = workouts
                    $0.settingsRepository = settings
                } operation: {
                    WorkoutDetailStore(workout: workout.id)
                }
            }
        }

        private func settles(_ condition: () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(10)
            while !condition() {
                guard ContinuousClock.now < deadline else {
                    return false
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return true
        }

        @Test("GRDB's missingRow reaches the alert, and the whole flow closes the detail and stores nothing")
        func deletedOnDisk_goneFlow() async throws {
            let scene = try await Scene()
            let detail = scene.detail()
            let run = Task { await detail.run() }
            defer { run.cancel() }
            #expect(await settles {
                if case .loaded = detail.state {
                    true
                } else {
                    false
                }
            })
            detail.edit()
            let sheet = scene.sheet()
            sheet.send(.step(scene.workout.exercises[0].sets[0].id, .weight, .upward))
            try await scene.workouts.delete(id: scene.workout.id)
            sheet.send(.save)
            await sheet.save()
            #expect(sheet.phase == .workoutGone)
            #expect(sheet.saveFailed == false)
            detail.editClosed(workoutGone: true)
            #expect(detail.pendingRoute?.route == .closeWorkout(scene.workout.id))
            #expect(try await scene.workouts.workout(id: scene.workout.id) == nil)
        }

        @Test("A write the database refuses is a failed line, not \"deleted\", and the same draft saves once it can")
        func refusedWrite_isAFailure_thenSaves() async throws {
            let scene = try await Scene()
            let sheet = scene.sheet()
            sheet.send(.step(scene.workout.exercises[0].sets[0].id, .weight, .upward))
            try await scene.queue.write { database in
                try database.execute(sql: """
                CREATE TRIGGER refuse BEFORE UPDATE ON logged_set BEGIN SELECT RAISE(ABORT, 'no'); END
                """)
            }
            sheet.send(.save)
            await sheet.save()
            #expect(sheet.phase == .editing)
            #expect(sheet.saveFailed)
            #expect(try await scene.workouts.workout(id: scene.workout.id) == scene.workout)
            try await scene.queue.write { database in try database.execute(sql: "DROP TRIGGER refuse") }
            sheet.send(.save)
            await sheet.save()
            #expect(sheet.phase == .saved)
            let read = try await scene.workouts.workout(id: scene.workout.id)
            #expect(read?.exercises[0].sets[0].weight == .pounds(230))
        }
    }

    extension EditSetsOnDiskAdversarialTests {
        @Test("A save cancelled at any moment: stored whole or not at all, and no failure line for a cancel")
        func cancelledSave_isWholeOrNothing_andSilent() async throws {
            for yields in 0 ..< (TestSweep.isReduced ? 8 : 30) {
                let scene = try await Scene()
                let sheet = scene.sheet()
                let (first, second) = (scene.workout.exercises[0], scene.workout.exercises[1])
                sheet.send(.step(first.sets[0].id, .weight, .upward))
                sheet.send(.step(second.sets[0].id, .weight, .upward))
                sheet.send(.save)
                let run = Task { await sheet.save() }
                for _ in 0 ..< yields {
                    await Task.yield()
                }
                run.cancel()
                await run.value
                let read = try #require(try await scene.workouts.workout(id: scene.workout.id))
                let firstStored = read.exercises[0].sets[0].weight == .pounds(230)
                let secondStored = read.exercises[1].sets[0].weight != second.sets[0].weight
                #expect(firstStored == secondStored, "half a save at \(yields)")
                #expect(sheet.saveFailed == false, "a cancel said it failed at \(yields)")
                #expect(sheet.phase == (firstStored ? .saved : .editing), "at \(yields): stored \(firstStored)")
            }
        }

        @Test(
            "A kg step on a pound workout: the sibling set keeps its exact pounds, and the detail redraws the new load"
        )
        func kilogramStep_reachesTheDetail_siblingsExact() async throws {
            let scene = try await Scene(units: .kg)
            let detail = scene.detail()
            let run = Task { await detail.run() }
            defer { run.cancel() }
            #expect(await settles {
                if case .loaded = detail.state {
                    true
                } else {
                    false
                }
            })
            detail.edit()
            #expect(detail.editing?.units == .kg)
            let sheet = scene.sheet(units: .kg)
            let sets = scene.workout.exercises[0].sets
            sheet.send(.step(sets[0].id, .weight, .upward)) // 225 lb is 102.06 kg: to 102.5
            sheet.send(.save)
            await sheet.save()
            detail.editClosed(workoutGone: false)
            #expect(sheet.phase == .saved)
            let read = try #require(try await scene.workouts.workout(id: scene.workout.id))
            #expect(read.units == .lb, "the workout's own units stay")
            #expect(read.exercises[0].sets[0].weight == .kilograms(102.5), "exactly")
            #expect(read.exercises[0].sets[1] == sets[1], "exactly 225 lb, not 225.0000x")
            #expect(read.exercises[1] == scene.workout.exercises[1])
            let shows = await settles {
                guard case let .loaded(model) = detail.state else {
                    return false
                }
                return model.receipt.rows.first?.chips.first?.contains("102.5") == true
            }
            #expect(shows, "the detail shows 102.5 kg")
        }
    }
#endif
