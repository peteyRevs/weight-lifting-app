import Foundation
@testable import LedgerDomain
import Testing

// MARK: - Slots, days, programs (spec §6.4 seed)

extension Fixtures {
    /// A slot for `exercise`; `repsHi` defaults to `reps + 2` like the prototype's `mk`.
    static func slot(
        _ exercise: Exercise,
        id: Int,
        sets: Int = 3,
        reps: Int = 8,
        repsHi: Int? = nil,
        rpe: Decimal = 8,
        rest: Int = 90,
        progression: Progression = .linear,
        startLoad: Weight? = nil,
        step: Weight? = nil,
        superset: Bool = false,
        dropSets: Int = 0,
        misses: Set<Int> = []
    ) throws -> Slot {
        try Slot(
            id: SlotID(uuid(id)),
            exerciseID: exercise.id,
            sets: sets,
            reps: reps,
            repsHi: repsHi ?? reps + 2,
            rpe: rpe,
            restSeconds: rest,
            progression: progression,
            startLoad: startLoad,
            step: step,
            isSupersetWithPrevious: superset,
            dropSets: dropSets,
            misses: misses
        )
    }

    /// Spec §6.4 "Upper A — Push focus": five slots, the last two a superset.
    static func upperA() throws -> DayTemplate {
        try DayTemplate(
            id: DayTemplateID(uuid(300)),
            name: "Upper A — Push focus",
            tag: "UA",
            slots: [
                slot(bench, id: 301, sets: 5, reps: 5, rest: 150),
                slot(inclineDB, id: 302, sets: 3, reps: 10, rest: 90, progression: .double),
                slot(chestSupportedRow, id: 303, sets: 4, reps: 8, rest: 90),
                slot(latPulldown, id: 304, sets: 3, reps: 12, rpe: 9, rest: 75, progression: .double),
                slot(lateralRaise, id: 305, sets: 3, reps: 15, rpe: 9, rest: 60, progression: .double, superset: true)
            ]
        )
    }

    /// Spec §6.4 "Upper B — Pull focus", reduced to its drop-set slot (Barbell Curl, 3 × 12, drop 1).
    static func upperB() throws -> DayTemplate {
        try DayTemplate(
            id: DayTemplateID(uuid(400)),
            name: "Upper B — Pull focus",
            tag: "UB",
            slots: [slot(barbellCurl, id: 401, sets: 3, reps: 12, rpe: 9, rest: 60, progression: .double, dropSets: 1)]
        )
    }

    static func week(_ index: Int, deload: Bool = false, schedule: [Weekday: DayTemplateID] = [:]) -> Week {
        Week(id: WeekID(uuid(200 + index)), index: index, isDeload: deload, schedule: schedule)
    }

    /// An 8-week block starting Monday 2026-08-17: `days[0]` on Monday, `days[1]` on Wednesday,
    /// `days[2]` on Friday; week index 7 is the deload (spec §6.4 seed schedule).
    static func program(
        days: [DayTemplate],
        weekCount: Int = 8,
        startDate: Date = date(2026, 8, 17)
    ) throws -> Program {
        let weekdays: [Weekday] = [.monday, .wednesday, .friday]
        let schedule = Dictionary(uniqueKeysWithValues: zip(weekdays, days.map(\.id)))
        let weeks = (0 ..< weekCount).map { week($0, deload: $0 == 7, schedule: schedule) }
        return try Program(id: programID, name: "Upper / Lower", startDate: startDate, weeks: weeks, days: days)
    }
}

// MARK: - Workouts

extension Fixtures {
    /// A logged set in pounds; `done` sets are ticked at `Fixtures.now`.
    static func set(
        _ number: Int,
        pounds: Decimal,
        reps: Int,
        kind: SetKind = .working,
        done: Bool = true
    ) -> LoggedSet {
        LoggedSet(
            id: SetID(uuid(20000 + number)),
            weight: .pounds(pounds),
            reps: Reps(clamping: reps),
            kind: kind,
            doneAt: done ? now : nil
        )
    }

    static func workoutExercise(
        _ exercise: Exercise,
        index: Int,
        sets: [LoggedSet],
        targetSets: Int? = nil,
        targetReps: Int = 5,
        targetLoad: Weight = .pounds(185),
        rest: Int = 90,
        superset: Bool = false
    ) throws -> WorkoutExercise {
        try WorkoutExercise(
            id: WorkoutExerciseID(uuid(10000 + index)),
            slotID: SlotID(uuid(11000 + index)),
            exerciseID: exercise.id,
            originalExerciseID: exercise.id,
            name: exercise.name,
            equipment: exercise.equipment,
            step: exercise.equipment.defaultStep(in: .lb),
            rest: Fixtures.rest(rest),
            rpe: Fixtures.rpe(8),
            isSupersetWithPrevious: superset,
            targetSets: targetSets ?? sets.count(where: { $0.kind == .working }),
            targetReps: targetReps,
            targetLoad: targetLoad,
            sets: sets
        )
    }

    static func workout(_ exercises: [WorkoutExercise], isDeload: Bool = false) -> WorkoutState {
        WorkoutState(
            id: workoutID,
            source: nil,
            name: "Upper A — Push focus",
            tag: "UA",
            isDeload: isDeload,
            exercises: exercises,
            cursor: Cursor(exerciseIndex: 0, setIndex: 0),
            startedAt: date(2026, 9, 16, hour: 5),
            phase: .live,
            originDevice: deviceID
        )
    }
}
