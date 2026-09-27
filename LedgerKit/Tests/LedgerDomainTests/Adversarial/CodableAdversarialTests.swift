import Foundation
@testable import LedgerDomain
import Testing

/// Every persisted/transmitted model must decode to exactly what was encoded (standards §5).
@Suite("Codable round-trips (adversarial)", .tags(.domain))
struct CodableAdversarialTests {
    static let oddInstant = Fixtures.now.addingTimeInterval(0.123_456)

    static func liveWorkout() throws -> WorkoutState {
        var workout = try SessionBuilderAdversarialTests.build(week: 7, day: Fixtures.upperB())
        workout.exercises[0].sets[0].doneAt = oddInstant
        workout.exercises[0].lastPerformance = LastPerformance(date: oddInstant, sets: 3, reps: 12, load: pounds("75"))
        workout.exercises[0].exerciseID = Fixtures.bench.id
        workout.cursor = Cursor(exerciseIndex: 0, setIndex: 1)
        workout.rest = RestTimer(endsAt: oddInstant, total: .milliseconds(90500))
        workout.endedAt = oddInstant.addingTimeInterval(3600.5)
        workout.phase = .finished
        workout.autoRest = false
        return workout
    }

    static func records() throws -> [PersonalRecord] {
        try [
            PersonalRecord(
                exerciseID: Fixtures.bench.id,
                kind: .estimatedOneRepMax(pounds("225")),
                previous: .estimatedOneRepMax(pounds("219")),
                achievedAt: oddInstant,
                workoutID: Fixtures.workoutID
            ),
            PersonalRecord(
                exerciseID: Fixtures.bench.id,
                kind: .weightAtReps(pounds("200"), Fixtures.reps(5)),
                previous: nil,
                achievedAt: oddInstant,
                workoutID: Fixtures.workoutID
            )
        ]
    }
}

extension CodableAdversarialTests {
    @Test("Typed identifiers encode as the bare UUID string and decode back.")
    func identifiers_bareUUID() throws {
        let uuid = Fixtures.uuid(4242)
        #expect(try Fixtures.json(ExerciseID(uuid)) == "\"\(uuid.uuidString)\"")
        #expect(try Adversarial.roundTrip(ExerciseID(uuid)) == ExerciseID(uuid))
        #expect(try Adversarial.roundTrip(ProgramID(uuid)) == ProgramID(uuid))
        #expect(try Adversarial.roundTrip(WeekID(uuid)) == WeekID(uuid))
        #expect(try Adversarial.roundTrip(DayTemplateID(uuid)) == DayTemplateID(uuid))
        #expect(try Adversarial.roundTrip(SlotID(uuid)) == SlotID(uuid))
        #expect(try Adversarial.roundTrip(WorkoutID(uuid)) == WorkoutID(uuid))
        #expect(try Adversarial.roundTrip(WorkoutExerciseID(uuid)) == WorkoutExerciseID(uuid))
        #expect(try Adversarial.roundTrip(SetID(uuid)) == SetID(uuid))
        #expect(try Adversarial.roundTrip(DeviceID(uuid)) == DeviceID(uuid))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ExerciseID.self, from: Data("\"not-a-uuid\"".utf8))
        }
    }

    @Test("Every enum case round-trips.")
    func enums_roundTrip() throws {
        #expect(try Units.allCases.map(Adversarial.roundTrip) == Units.allCases)
        #expect(try Equipment.allCases.map(Adversarial.roundTrip) == Equipment.allCases)
        #expect(try MuscleGroup.allCases.map(Adversarial.roundTrip) == MuscleGroup.allCases)
        #expect(try MovementPattern.allCases.map(Adversarial.roundTrip) == MovementPattern.allCases)
        #expect(try Progression.allCases.map(Adversarial.roundTrip) == Progression.allCases)
        #expect(try Weekday.allCases.map(Adversarial.roundTrip) == Weekday.allCases)
        #expect(try TrainingGoal.allCases.map(Adversarial.roundTrip) == TrainingGoal.allCases)
        #expect(try SetKind.allCases.map(Adversarial.roundTrip) == SetKind.allCases)
        #expect(try WorkoutPhase.allCases.map(Adversarial.roundTrip) == WorkoutPhase.allCases)
    }

    @Test("Catalog and template models round-trip with every optional and collection filled.")
    func templates_roundTrip() throws {
        var exercise = Fixtures.bench
        exercise.secondaryMuscles = [.triceps, .shoulders]
        exercise.curatedAlternatives = [Fixtures.inclineDB.id]
        exercise.isCustom = true
        #expect(try Adversarial.roundTrip(exercise) == exercise)
        let week = Week(
            id: WeekID(Fixtures.uuid(1)),
            index: 3,
            isDeload: true,
            schedule: [.sunday: DayTemplateID(Fixtures.uuid(2))]
        )
        #expect(try Adversarial.roundTrip(week) == week)
        #expect(try Adversarial.roundTrip(Fixtures.upperA()) == Fixtures.upperA())
        #expect(try Adversarial.roundTrip(Fixtures.upperB()) == Fixtures.upperB())
    }

    @Test("A finished workout with rest timer, sub-second dates and history round-trips unchanged.")
    func workoutState_roundTrip() throws {
        let workout = try Self.liveWorkout()
        #expect(try Adversarial.roundTrip(workout) == workout)
        #expect(try Adversarial.roundTrip(workout.exercises[0]) == workout.exercises[0])
        #expect(try Adversarial.roundTrip(workout.exercises[0].sets) == workout.exercises[0].sets)
        #expect(try Adversarial.roundTrip(workout.rest) == workout.rest)
        #expect(try Adversarial.roundTrip(workout.source) == workout.source)
        var bare = workout
        bare.cursor = nil
        bare.rest = nil
        bare.source = nil
        bare.endedAt = nil
        bare.exercises = []
        #expect(try Adversarial.roundTrip(bare) == bare)
    }

    @Test("A rest timer with a fractional-second total round-trips exactly (brief risk: Duration coding).")
    func restTimer_fractionalDuration_roundTrips() throws {
        let timer = RestTimer(endsAt: Fixtures.now, total: .milliseconds(90500))
        #expect(try Adversarial.roundTrip(timer) == timer)
    }

    @Test("A summary whose elapsed time has sub-second precision round-trips exactly.")
    func summary_fractionalElapsed_roundTrips() throws {
        let workout = try Self.liveWorkout()
        let summary = try WorkoutSummary(
            workoutID: Fixtures.workoutID,
            elapsed: workout.elapsed(at: Self.oddInstant.addingTimeInterval(4000)),
            doneSets: workout.doneSets,
            totalSets: workout.totalSets,
            volume: workout.volume,
            prs: Self.records(),
            rows: workout.exercises.map { ReceiptRow(exercise: $0, units: .lb) }
        )
        #expect(try Adversarial.roundTrip(summary) == summary)
        #expect(try Adversarial.roundTrip(Self.records()) == Self.records())
    }

    @Test("Settings, inventories, week keys and volumes round-trip.")
    func settingsAndValues_roundTrip() throws {
        var settings = Settings.default
        settings.units = .kg
        settings.weekStart = .sunday
        settings.defaultRest = try Fixtures.rest(135)
        settings.plateInventory[.kg] = PlateInventory(bar: kilos("15"), plates: [kilos("25"), kilos("0.5")])
        #expect(try Adversarial.roundTrip(settings) == settings)
        #expect(try Adversarial.roundTrip(Settings.default) == Settings.default)
        #expect(try Adversarial.roundTrip(WeekKey(year: 2025, week: 53)) == WeekKey(year: 2025, week: 53))
        #expect(try Adversarial.roundTrip(Volume(gramReps: Decimal(Int.max))) == Volume(gramReps: Decimal(Int.max)))
        #expect(try Adversarial.roundTrip(PRKind.weightAtReps(.zero, .one)) == .weightAtReps(.zero, .one))
    }
}
