import Foundation
@testable import LedgerDomain
import Testing

@Suite("SessionBuilder", .tags(.domain))
struct SessionBuilderTests {
    private func build(
        _ program: Program,
        week: Int,
        day: DayTemplate,
        history: [ExerciseID: LastPerformance] = [:],
        settings: Settings = .default
    ) throws(SessionBuilderError) -> WorkoutState {
        try SessionBuilder.build(
            program: program, weekIndex: week, day: day, exercises: Fixtures.catalog, history: history,
            settings: settings, id: Fixtures.workoutID, device: Fixtures.deviceID, now: Fixtures.now
        )
    }

    @Test("Every slot becomes an exercise whose rows carry the week's prescription (rule 14)")
    func build_appliesPrescriptionToEverySet() throws {
        let upperA = try Fixtures.upperA()
        let state = try build(Fixtures.program(days: [upperA]), week: 1, day: upperA)
        #expect(state.exercises.map(\.name) == upperA.slots.compactMap { Fixtures.catalog[$0.exerciseID]?.name })
        let bench = state.exercises[0]
        #expect(bench.sets.count == 5)
        #expect(bench.sets
            .allSatisfy { $0.weight == .pounds(185) && $0.reps.value == 5 && $0.kind == .working && !$0.isDone })
        #expect(bench.targetSets == 5 && bench.targetReps == 5 && bench.targetLoad == .pounds(185))
        let incline = state.exercises[1]
        #expect(incline.sets.map(\.reps.value) == [11, 11, 11])
        #expect(incline.sets.allSatisfy { $0.weight == .pounds(50) })
        #expect(state.totalSets == 18)
        #expect(state.doneSets == 0)
    }

    @Test("The session starts live at (0, 0) with its source, name and settings snapshot")
    func build_initialState() throws {
        let upperA = try Fixtures.upperA()
        var settings = Settings.default
        settings.autoRest = false
        let state = try build(Fixtures.program(days: [upperA]), week: 7, day: upperA, settings: settings)
        #expect(state.cursor == Cursor(exerciseIndex: 0, setIndex: 0))
        #expect(state.phase == .live)
        #expect(state.startedAt == Fixtures.now)
        #expect(state.endedAt == nil && state.rest == nil)
        #expect(state.source == WorkoutSource(programID: Fixtures.programID, weekIndex: 7, dayTemplateID: upperA.id))
        #expect((state.name, state.tag) == ("Upper A — Push focus", "UA"))
        #expect(state.isDeload)
        #expect(!state.autoRest)
        #expect((state.id, state.originDevice) == (Fixtures.workoutID, Fixtures.deviceID))
        #expect(state.exercises[0].sets.count == 4)
    }

    @Test("A drop-set slot gets one extra row at −15 % rounded to the step (rule 15)")
    func build_appendsDropSetAtMinus15PercentRoundedToStep() throws {
        let upperB = try Fixtures.upperB()
        let curl = try build(Fixtures.program(days: [upperB]), week: 0, day: upperB).exercises[0]
        // 75 lb × 0.85 = 63.75 lb → nearest 5 lb (barbell) = 65 lb.
        #expect(curl.sets.map(\.kind) == [.working, .working, .working, .drop])
        #expect(curl.sets.last?.weight == .pounds(65))
        #expect(curl.sets.last?.reps.value == 12)
        #expect(curl.targetSets == 3)
    }

    @Test("Slot fields are copied, so later template edits do not leak into the session (rule 16)")
    func build_snapshotsSlotFieldsSoTemplateEditsDoNotLeak() throws {
        var upperA = try Fixtures.upperA()
        let program = try Fixtures.program(days: [upperA])
        let state = try build(program, week: 0, day: upperA)
        let lateral = state.exercises[4]
        #expect(lateral.isSupersetWithPrevious)
        #expect(lateral.rest.seconds == 60 && lateral.rpe.value == 9 && lateral.step == .pounds(2.5))
        #expect(lateral.equipment == .cable && lateral.slotID == upperA.slots[4].id)
        upperA.slots[4].rest = try Fixtures.rest(120)
        upperA.slots[4].sets = 5
        #expect(state.exercises[4].rest.seconds == 60)
        #expect(state.exercises[4].sets.count == 3)
        #expect(try build(program, week: 0, day: upperA).exercises[4].sets.count == 5)
    }

    @Test("Last performance comes from history and is nil on a first session")
    func build_lastPerformanceLineFromHistory() throws {
        let upperA = try Fixtures.upperA()
        let last = LastPerformance(date: Fixtures.date(2026, 8, 12), sets: 5, reps: 5, load: .pounds(180))
        let state = try build(
            Fixtures.program(days: [upperA]),
            week: 1,
            day: upperA,
            history: [Fixtures.bench.id: last]
        )
        #expect(state.exercises[0].lastPerformance == last)
        #expect(state.exercises[0].lastPerformance?
            .line(units: .lb, calendar: Fixtures.calendar) == "Aug 12 · 5×5 @ 180 lb")
        #expect(state.exercises.dropFirst().allSatisfy { $0.lastPerformance == nil })
    }

    @Test("A live session for the same week and day resumes; anything else builds anew (rule 17)")
    func build_resumesSameWeekAndDay() throws {
        let upperA = try Fixtures.upperA()
        let upperB = try Fixtures.upperB()
        let program = try Fixtures.program(days: [upperA, upperB])
        var live = try build(program, week: 2, day: upperA)
        live.exercises[0].sets[0].doneAt = Fixtures.now
        #expect(SessionBuilder.resumable(live, program: program, weekIndex: 2, day: upperA) == live)
        #expect(SessionBuilder.resumable(live, program: program, weekIndex: 3, day: upperA) == nil)
        #expect(SessionBuilder.resumable(live, program: program, weekIndex: 2, day: upperB) == nil)
        #expect(SessionBuilder.resumable(nil, program: program, weekIndex: 2, day: upperA) == nil)
        live.phase = .finished
        #expect(SessionBuilder.resumable(live, program: program, weekIndex: 2, day: upperA) == nil)
    }

    @Test("Building is deterministic, with derived exercise and set IDs")
    func build_isDeterministic() throws {
        let upperA = try Fixtures.upperA()
        let program = try Fixtures.program(days: [upperA])
        let first = try build(program, week: 1, day: upperA)
        #expect(try build(program, week: 1, day: upperA) == first)
        #expect(first.exercises[1].id == .derived(from: Fixtures.workoutID, index: 1))
        #expect(first.exercises[1].sets[2].id == .derived(from: first.exercises[1].id, index: 2))
        #expect(Set(first.exercises.flatMap(\.sets).map(\.id)).count == first.totalSets)
    }

    @Test("Kilogram settings prescribe in kilograms")
    func build_kilograms() throws {
        let upperA = try Fixtures.upperA()
        var settings = Settings.default
        settings.units = .kg
        let state = try build(Fixtures.program(days: [upperA]), week: 2, day: upperA, settings: settings)
        #expect(state.exercises[0].targetLoad == .kilograms(85))
        #expect(state.exercises[0].step == .kilograms(2.5))
    }

    @Test("An empty day builds a session with no cursor")
    func build_emptyDay_hasNoCursor() throws {
        let empty = DayTemplate(id: DayTemplateID(Fixtures.uuid(500)), name: "New day", tag: "D5")
        let state = try build(Fixtures.program(days: [empty]), week: 0, day: empty)
        #expect(state.exercises.isEmpty)
        #expect(state.cursor == nil)
    }

    @Test("Unknown weeks, days and exercises throw")
    func build_invalidInputs_throw() throws {
        let upperA = try Fixtures.upperA()
        let program = try Fixtures.program(days: [upperA])
        #expect(throws: SessionBuilderError.weekOutOfRange(8)) { try build(program, week: 8, day: upperA) }
        #expect(throws: SessionBuilderError.weekOutOfRange(-1)) { try build(program, week: -1, day: upperA) }
        let upperB = try Fixtures.upperB()
        #expect(throws: SessionBuilderError.dayNotInProgram(upperB.id)) { try build(program, week: 0, day: upperB) }
        var stranger = upperA
        stranger.slots[2].exerciseID = ExerciseID(Fixtures.uuid(999))
        let withStranger = try Fixtures.program(days: [stranger])
        #expect(throws: SessionBuilderError.unknownExercise(ExerciseID(Fixtures.uuid(999)))) {
            try build(withStranger, week: 0, day: stranger)
        }
    }
}
