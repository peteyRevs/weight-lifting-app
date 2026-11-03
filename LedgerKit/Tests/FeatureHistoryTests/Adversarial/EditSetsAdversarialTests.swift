import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S3 adversarial (G2): the sheet's saves, what it hands the repository, a snapshot gone stale, and its words.
@MainActor
@Suite("Adversarial F13 S3 · the sheet's saves and words", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct EditSetsAdversarialTests {
    private typealias Scene = EditAdversarialScene
    static let newest = EditAdversarialScene.newest

    // MARK: - Saving

    @Test("N12. A failed save runs once per tap: fail, fail, succeed are three writes, and the last one stores")
    func retries_areOneWriteEach() async throws {
        let scene = Scene(failures: 2)
        let sheet = scene.sheet(EditSetsRequest(workout: Self.newest, units: .lb))
        let set = try #require(Self.newest.exercises.first?.sets.first)
        sheet.send(.step(set.id, .weight, .upward))
        for attempt in 1 ... 2 {
            sheet.send(.save)
            #expect(sheet.attempt == attempt)
            await sheet.save()
            await sheet.save() // the task running again changes nothing
            #expect(sheet.phase == .editing)
            #expect(sheet.saveFailed)
            #expect(scene.workouts.saveCount == attempt)
        }
        sheet.send(.save)
        #expect(sheet.saveFailed == false, "the line goes as the retry starts")
        await sheet.save()
        #expect(sheet.phase == .saved)
        #expect(scene.workouts.saveCount == 3)
        sheet.send(.save)
        await sheet.save()
        #expect(scene.workouts.saveCount == 3, "a saved sheet writes no more")
    }

    @Test("N12. While a write is held: no step, no second write, no close, and everything is off")
    func whileSaving_nothingMoves() async throws {
        let scene = Scene(holdsSaves: true)
        let sheet = scene.sheet(EditSetsRequest(workout: Self.newest, units: .lb))
        let set = try #require(Self.newest.exercises.first?.sets.first)
        sheet.send(.step(set.id, .reps, .upward))
        sheet.send(.save)
        let run = Task { await sheet.save() }
        #expect(await settles { scene.workouts.heldCount == 1 })
        let drawn = sheet.draft
        sheet.send(.step(set.id, .weight, .upward))
        sheet.send(.save)
        await sheet.save()
        #expect(sheet.draft == drawn)
        #expect(scene.workouts.saveCount == 1)
        #expect(sheet.canClose == false)
        #expect(sheet.model.isEnabled == false)
        #expect(sheet.model.foot.action == nil)
        scene.workouts.release()
        await run.value
        #expect(sheet.phase == .saved)
    }
}

extension EditSetsAdversarialTests {
    // MARK: - What the sheet edits

    @Test("A sheet only hands over exercises it changed: another exercise changed since it opened survives its save")
    func sheetSave_leavesOtherExercisesAlone() async throws {
        let workout = EditFixtures.partlyLogged()
        let stores = InMemoryStores(seed: InMemoryStores.Seed(workouts: [workout], settings: Fixtures.settingsLb))
        let seen = ScriptedWorkouts(base: stores.workouts, scripted: false)
        let sheet = withTestDependencies {
            $0.workoutRepository = seen
        } operation: {
            EditSetsStore(EditSetsRequest(workout: workout, units: .lb))
        }
        var other = workout.exercises[1].sets
        other[0].reps = Reps(clamping: 11)
        try await stores.workouts.updateSets([workout.exercises[1].id: other], of: workout.id)
        sheet.send(.step(workout.exercises[0].sets[0].id, .weight, .upward))
        sheet.send(.save)
        await sheet.save()
        let stored = try #require(try await stores.workouts.workout(id: workout.id))
        #expect(stored.exercises[1].sets == other)
    }

    @Test("F13-S3-3: Edit reopened before the observation's next value opens on the saved sets; the first fix stays")
    func reopenedBeforeTheNextValue_opensTheSave() async throws {
        let scene = Scene(scripted: true)
        let run = scene.run()
        defer { run.cancel() }
        await Self.shows(Self.newest, scene)
        scene.detail.edit()
        let first = try scene.sheet(#require(scene.detail.editing))
        let (setOne, setTwo) = (Self.newest.exercises[0].sets[0], Self.newest.exercises[0].sets[1])
        first.send(.step(setOne.id, .weight, .upward))
        first.send(.save)
        await first.save()
        scene.detail.editClosed(.saved(first.draft))
        // GRDB's value is on its way, and has not landed.
        scene.detail.edit()
        let second = try #require(scene.detail.editing)
        #expect(second.workout == first.draft, "the second sheet shows what the first saved")
        let again = scene.sheet(second)
        again.send(.step(setTwo.id, .reps, .upward))
        again.send(.save)
        await again.save()
        scene.detail.editClosed(.saved(again.draft))
        let stored = try #require(try await scene.memory.workouts.workout(id: Self.newest.id))
        #expect(stored.exercises[0].sets[0] == first.draft.exercises[0].sets[0], "the first fix stands")
        #expect(stored.exercises[0].sets[1] == again.draft.exercises[0].sets[1])
        scene.detail.edit()
        #expect(scene.detail.editing?.workout == again.draft, "still before the value: the last save")
    }

    @Test("F13-S3-3: once the observation shows a new value, Edit opens on it, not on an older save")
    func afterTheNextValue_opensWhatIsShown() async throws {
        let scene = Scene(scripted: true)
        let run = scene.run()
        defer { run.cancel() }
        await Self.shows(Self.newest, scene)
        scene.detail.edit()
        let sheet = try scene.sheet(#require(scene.detail.editing))
        sheet.send(.step(Self.newest.exercises[0].sets[0].id, .weight, .upward))
        sheet.send(.save)
        await sheet.save()
        scene.detail.editClosed(.saved(sheet.draft))
        let stored = try #require(try await scene.memory.workouts.workout(id: Self.newest.id))
        await Self.shows(stored, scene)
        scene.detail.edit()
        #expect(scene.detail.editing?.workout == stored)
        scene.detail.editSheet = nil
        #expect(scene.detail.editing == nil, "a swipe closes it")
        let elsewhere = Self.raised(stored, to: 777)
        await Self.shows(elsewhere, scene)
        scene.detail.edit()
        #expect(scene.detail.editing?.workout == elsewhere, "an edit made elsewhere is what opens")
    }

    /// Yields `workout` to the scripted observation and waits until the detail draws its first set.
    private static func shows(_ workout: WorkoutState, _ scene: Scene) async {
        scene.workouts.observation.yield(scene.recorded(workout))
        let first = workout.exercises[0].sets[0].weight.formatted(in: .lb)
        await eventually {
            guard case let .loaded(model) = scene.detail.state else {
                return false
            }
            return model.receipt.rows.first?.chips.first?.contains(first) == true
        }
    }

    /// `workout` with its first set at `pounds`.
    private static func raised(_ workout: WorkoutState, to pounds: Decimal) -> WorkoutState {
        var raised = workout
        raised.exercises[0].sets[0].weight = .pounds(pounds)
        return raised
    }

    @Test("As built: an exercise gone from a workout that is still stored says \"This workout was deleted\"")
    func missingExercise_saysDeleted_whileTheWorkoutStands() async throws {
        let scene = Scene()
        let read = Self.newest
        let sheet = scene.sheet(EditSetsRequest(workout: read, units: .lb))
        let set = try #require(read.exercises[0].sets.first)
        var trimmed = read
        trimmed.exercises.removeFirst()
        _ = try await scene.memory.workouts.materialize(trimmed, slotUpdates: [], droppingLog: false)
        sheet.send(.step(set.id, .reps, .upward))
        sheet.send(.save)
        await sheet.save()
        #expect(sheet.phase == .workoutGone)
        #expect(try await scene.memory.workouts.workout(id: read.id) != nil, "the workout is there")
    }

    @Test("A set's number counts logged sets across a gap; kg and lb words come from one exact value")
    func numbering_andWords() {
        var workout = Seeders.workout(number: 7, endedAt: Fixtures.date(2026, 9, 16, hour: 8), [
            .straight(HistoryFixtures.bench, sets: 3, reps: 5, pounds: 190)
        ])
        workout.exercises[0].sets[1].doneAt = nil
        let model = EditSetsPresentation.make(EditSetsInput(
            draft: workout,
            units: .kg,
            locale: Fixtures.locale,
            hasChanges: false,
            isSaving: false,
            saveFailed: false,
            workoutGone: false
        ))
        let rows = model.exercises[0].sets
        #expect(rows.map(\.id) == [workout.exercises[0].sets[0].id, workout.exercises[0].sets[2].id])
        #expect(rows.map(\.weight.label) == ["Set 1 weight", "Set 2 weight"])
        #expect(rows[0].weight.value == "86.2 kg")
        #expect(rows[0].weight.spokenValue == "86.2 kilograms")
    }

    @Test("The sheet writes a weight and its reps in the digits the receipt uses, in every locale", arguments: [
        "en_US", "de_DE", "fr_FR", "ar_EG", "hi_IN", "ja_JP"
    ])
    func digits_matchTheReceipt(_ identifier: String) throws {
        let locale = Locale(identifier: identifier)
        let workout = Seeders.workout(number: 7, endedAt: Fixtures.date(2026, 9, 16, hour: 8), [
            .straight(HistoryFixtures.bench, sets: 1, reps: 12, pounds: Decimal(string: "187.5") ?? 0)
        ])
        let sheet = EditSetsPresentation.make(EditSetsInput(
            draft: workout,
            units: .lb,
            locale: locale,
            hasChanges: false,
            isSaving: false,
            saveFailed: false,
            workoutGone: false
        ))
        let detail = WorkoutDetailPresentation.make(WorkoutDetailInput(
            recorded: RecordedWorkout(workout: workout, records: []),
            units: .lb,
            calendar: Fixtures.calendar,
            locale: locale
        ))
        let row = try #require(sheet.exercises.first?.sets.first)
        let chip = try #require(detail.receipt.rows.first?.chips.first)
        #expect(chip.contains(row.reps.value), "\(identifier): reps \(row.reps.value) in chip \(chip)")
    }
}
