import Foundation
@testable import LedgerDomain
import Testing

@Suite("SessionBuilder (adversarial)", .tags(.domain))
struct SessionBuilderAdversarialTests {
    static func program() throws -> Program {
        try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
    }

    static func build(
        week: Int,
        day: DayTemplate,
        program: Program? = nil,
        exercises: [ExerciseID: Exercise] = Fixtures.catalog,
        history: [ExerciseID: LastPerformance] = [:],
        settings: Settings = .default,
        id: WorkoutID = Fixtures.workoutID
    ) throws -> WorkoutState {
        try SessionBuilder.build(
            program: program ?? Self.program(),
            weekIndex: week,
            day: day,
            exercises: exercises,
            history: history,
            settings: settings,
            id: id,
            device: Fixtures.deviceID,
            now: Fixtures.now
        )
    }

    /// (weight, reps, kind) of every row, for compact comparisons.
    static func rows(_ exercise: WorkoutExercise) -> [String] {
        exercise.sets.map { "\($0.weight.formatted(in: .lb))×\($0.reps.value) \($0.kind.rawValue)" }
    }
}

extension SessionBuilderAdversarialTests {
    @Test("Week 0 of Upper A builds one exercise per slot with prescribed working rows (rule 14).")
    func build_week0_rowsFromPrescriptions() throws {
        let workout = try Self.build(week: 0, day: Fixtures.upperA())
        #expect(workout.exercises.map { Self.rows($0).count } == [5, 3, 4, 3, 3])
        #expect(Self.rows(workout.exercises[0]) == Array(repeating: "180×5 working", count: 5))
        #expect(Self.rows(workout.exercises[1]) == Array(repeating: "50×10 working", count: 3))
        #expect(Self.rows(workout.exercises[4]) == Array(repeating: "12.5×15 working", count: 3))
        #expect(workout.exercises.allSatisfy { $0.sets.allSatisfy { !$0.isDone } })
        #expect(workout.doneSets == 0)
        #expect(workout.totalSets == 18)
        #expect(workout.volume == .zero)
    }

    @Test("The built workout starts live at cursor (0, 0) with its source, name and device.")
    func build_header_fields() throws {
        let day = try Fixtures.upperA()
        let workout = try Self.build(week: 2, day: day)
        #expect(workout.id == Fixtures.workoutID)
        #expect(workout.cursor == Cursor(exerciseIndex: 0, setIndex: 0))
        #expect(workout.phase == .live)
        #expect(workout.startedAt == Fixtures.now)
        #expect(workout.endedAt == nil)
        #expect(workout.rest == nil)
        #expect(workout.originDevice == Fixtures.deviceID)
        #expect(workout.source == WorkoutSource(programID: Fixtures.programID, weekIndex: 2, dayTemplateID: day.id))
        #expect(workout.name == "Upper A — Push focus")
        #expect(workout.tag == "UA")
        #expect(!workout.isDeload)
    }

    @Test("Later weeks apply the week's progression to every row.")
    func build_week3_appliesProgression() throws {
        // Bench linear 180 + 3 × 5 = 195; incline double adv 3 / span 3 → 52.5 × 10;
        // lateral raise 15–17 double → 12.5 + 2.5 = 15 × 15.
        let workout = try Self.build(week: 3, day: Fixtures.upperA())
        #expect(Self.rows(workout.exercises[0]).first == "195×5 working")
        #expect(Self.rows(workout.exercises[1]).first == "52.5×10 working")
        #expect(Self.rows(workout.exercises[4]).first == "15×15 working")
        #expect(workout.exercises[0].targetLoad == pounds("195"))
    }

    @Test("A drop-set slot appends one drop row at −15 % rounded to the step (rule 15).")
    func build_dropSet_appendsDropRow() throws {
        // Barbell Curl 75 lb, step 5: 75 × 0.85 = 63.75 → 12.75 steps → 13 → 65 lb.
        let curl = try #require(Self.build(week: 0, day: Fixtures.upperB()).exercises.first)
        #expect(Self.rows(curl) == ["75×12 working", "75×12 working", "75×12 working", "65×12 drop"])
        #expect(curl.targetSets == 3)
    }

    @Test("A deload week drops a set, lowers RPE and bases the drop row on the deloaded load.")
    func build_deloadWeek_dropRowFromDeloadedLoad() throws {
        // Curl week 7: adv 7, span 3 → 75 + 2 × 5 = 85 × 13; deload 72.25 → 70 lb, 2 sets, RPE 7;
        // drop 70 × 0.85 = 59.5 → 11.9 steps → 60 lb.
        let workout = try Self.build(week: 7, day: Fixtures.upperB())
        let curl = try #require(workout.exercises.first)
        #expect(workout.isDeload)
        #expect(Self.rows(curl) == ["70×13 working", "70×13 working", "60×13 drop"])
        #expect(curl.targetSets == 2)
        #expect(curl.targetReps == 13)
        #expect(try curl.rpe == (Fixtures.rpe(7)))
    }

    @Test("Each exercise snapshots the slot's rest, step, RPE, equipment, superset flag and targets (rule 16).")
    func build_snapshotsSlotFields() throws {
        let day = try Fixtures.upperA()
        let workout = try Self.build(week: 0, day: day)
        let bench = workout.exercises[0]
        #expect(bench.slotID == day.slots[0].id)
        #expect(bench.exerciseID == Fixtures.bench.id)
        #expect(bench.originalExerciseID == Fixtures.bench.id)
        #expect(bench.name == Fixtures.bench.name)
        #expect(bench.equipment == .barbell)
        #expect(bench.step == pounds("5"))
        #expect(try bench.rest == (Fixtures.rest(150)))
        #expect(bench.targetSets == 5)
        #expect(bench.targetReps == 5)
        #expect(workout.exercises.map(\.isSupersetWithPrevious) == [false, false, false, false, true])
        #expect(try workout.exercises[3].rpe == (Fixtures.rpe(9)))
        #expect(workout.exercises[2].step == pounds("2.5"))
    }

    @Test("History fills lastPerformance only for exercises that have it; a first session has none.")
    func build_history_fillsLastPerformance() throws {
        let last = LastPerformance(date: Fixtures.date(2026, 8, 12), sets: 5, reps: 5, load: pounds("180"))
        let first = try Self.build(week: 0, day: Fixtures.upperA())
        #expect(first.exercises.allSatisfy { $0.lastPerformance == nil })
        let later = try Self.build(week: 0, day: Fixtures.upperA(), history: [Fixtures.bench.id: last])
        #expect(later.exercises[0].lastPerformance == last)
        #expect(later.exercises.dropFirst().allSatisfy { $0.lastPerformance == nil })
    }
}
