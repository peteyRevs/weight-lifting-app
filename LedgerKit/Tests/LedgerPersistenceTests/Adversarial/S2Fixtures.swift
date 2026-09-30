import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Synchronization

/// F05 S2 adversarial round 1: builders for the exercise and program attacks, written from the brief and the
/// public interfaces only (never from the implementer's tests or `Seeders`), so the fixtures cannot share a
/// blind spot with them.
enum S2Kit {
    // MARK: - Identifiers

    /// A deterministic UUID: `family` names the kind of row, `number` the row.
    static func uuid(_ family: UInt16, _ number: Int) -> UUID {
        let text = String(format: "AD52%04X-0000-4000-8000-%012llX", family, UInt64(number))
        guard let uuid = UUID(uuidString: text) else {
            preconditionFailure("bad fixture uuid \(text)")
        }
        return uuid
    }

    static func exerciseID(_ number: Int) -> ExerciseID {
        ExerciseID(uuid(0xE, number))
    }

    static func programID(_ number: Int) -> ProgramID {
        ProgramID(uuid(0xA, number))
    }

    static func weekID(_ number: Int) -> WeekID {
        WeekID(uuid(0xB, number))
    }

    static func dayID(_ number: Int) -> DayTemplateID {
        DayTemplateID(uuid(0xD, number))
    }

    static func slotID(_ number: Int) -> SlotID {
        SlotID(uuid(0x5, number))
    }

    // MARK: - Exercises

    static func exercise(
        _ number: Int,
        _ name: String,
        short: String? = nil,
        equipment: Equipment = .barbell,
        muscle: MuscleGroup = .chest,
        secondary: [MuscleGroup] = [],
        pattern: MovementPattern = .horizontalPush,
        loads: [Units: Weight] = [.lb: .pounds(45), .kg: .kilograms(20)],
        isCustom: Bool = false,
        alternatives: [ExerciseID] = []
    ) -> Exercise {
        Exercise(
            id: exerciseID(number),
            name: name,
            shortName: short ?? name,
            equipment: equipment,
            primaryMuscle: muscle,
            secondaryMuscles: secondary,
            pattern: pattern,
            defaultStartLoad: loads,
            isCustom: isCustom,
            curatedAlternatives: alternatives
        )
    }

    /// Eight plain exercises that slots can name (`exerciseID(0 ..< 8)`).
    static let slotExercises: [Exercise] = (0 ..< 8).map { exercise($0, "Lift \($0)") }

    // MARK: - Programs

    static func slot(
        _ number: Int,
        exercise: Int = 0,
        sets: Int = 3,
        reps: Int = 8,
        repsHi: Int = 10,
        rpe: Decimal = 8,
        rest: Int = 90,
        progression: Progression = .linear,
        startLoad: Weight? = nil,
        step: Weight? = nil,
        superset: Bool = false,
        drop: Int = 0,
        misses: Set<Int> = []
    ) throws -> Slot {
        try Slot(
            id: slotID(number),
            exerciseID: exerciseID(exercise),
            sets: sets,
            reps: reps,
            repsHi: repsHi,
            rpe: rpe,
            restSeconds: rest,
            progression: progression,
            startLoad: startLoad,
            step: step,
            isSupersetWithPrevious: superset,
            dropSets: drop,
            misses: misses
        )
    }

    /// Criterion 2's shape: `weeks` weeks of `days` days of `slotsPerDay` slots, every slot with misses and
    /// its own loads, the last week a deload; each week schedules day `d` on weekday `d` (Mon, Tue …).
    /// Ids: program `number`, weeks `number × 100 + w`, days `number × 100 + d`, slots `number × 1000 + s`.
    static func program(
        _ number: Int = 1,
        weeks: Int = 8,
        days: Int = 4,
        slotsPerDay: Int = 5,
        isActive: Bool = true
    ) throws -> Program {
        var slotNumber = number * 1000
        let dayTemplates = try (0 ..< days).map { day in
            let slots = try (0 ..< slotsPerDay).map { index in
                slotNumber += 1
                return try slot(
                    slotNumber,
                    exercise: (day + index) % slotExercises.count,
                    sets: 1 + (slotNumber % 12),
                    reps: 1 + (slotNumber % 29),
                    repsHi: 2 + (slotNumber % 29) + (slotNumber % 10),
                    rpe: 5 + Decimal(slotNumber % 11) / 2,
                    rest: 30 + 15 * (slotNumber % 19),
                    progression: Progression.allCases[slotNumber % 3],
                    startLoad: slotNumber.isMultiple(of: 3) ? nil : .pounds(Decimal(slotNumber) / 100),
                    step: slotNumber.isMultiple(of: 4) ? nil : .kilograms(1.25),
                    superset: index > 0 && slotNumber.isMultiple(of: 5),
                    drop: slotNumber % 2,
                    misses: Set((0 ..< weeks).filter { ($0 + slotNumber).isMultiple(of: 3) })
                )
            }
            return DayTemplate(id: dayID(number * 100 + day), name: "Day \(day) — focus", tag: "D\(day)", slots: slots)
        }
        let weekList = (0 ..< weeks).map { week in
            var schedule: [Weekday: DayTemplateID] = [:]
            for day in 0 ..< min(days, 7) {
                schedule[Weekday.allCases[day]] = dayTemplates[day].id
            }
            return Week(id: weekID(number * 100 + week), index: week, isDeload: week == weeks - 1, schedule: schedule)
        }
        return try Program(
            id: programID(number),
            name: "Block \(number)",
            startDate: CivilDate(year: 2026, month: 9, day: 14) ?? CivilDate.min,
            weeks: weekList,
            days: dayTemplates,
            goal: .strength,
            daysPerWeek: days,
            isActive: isActive
        )
    }
}

extension CivilDate {
    static var min: CivilDate {
        CivilDate(year: 1, month: 1, day: 1).unsafelyUnwrapped
    }

    static var max: CivilDate {
        CivilDate(year: 9999, month: 12, day: 31).unsafelyUnwrapped
    }
}

extension Slot {
    /// A copy with some fields changed, rebuilt through `init` (the way an editor must).
    func with(
        exercise: ExerciseID? = nil,
        sets: Int? = nil,
        reps: Int? = nil,
        repsHi: Int? = nil,
        rpe: Decimal? = nil,
        rest: Int? = nil,
        progression: Progression? = nil,
        startLoad: Weight?? = nil,
        step: Weight?? = nil,
        drop: Int? = nil,
        misses: Set<Int>? = nil
    ) throws -> Slot {
        try Slot(
            id: id,
            exerciseID: exercise ?? exerciseID,
            sets: sets ?? self.sets,
            reps: reps ?? self.reps,
            repsHi: repsHi ?? self.repsHi,
            rpe: rpe ?? self.rpe.value,
            restSeconds: rest ?? self.rest.seconds,
            progression: progression ?? self.progression,
            startLoad: startLoad ?? self.startLoad,
            step: step ?? self.step,
            isSupersetWithPrevious: isSupersetWithPrevious,
            dropSets: drop ?? dropSets,
            misses: misses ?? self.misses
        )
    }
}

extension Program {
    /// A copy rebuilt through `init` with new weeks and days (and optionally other fields).
    func rebuilt(
        weeks: [Week]? = nil,
        days: [DayTemplate]? = nil,
        name: String? = nil,
        startDate: CivilDate? = nil,
        goal: TrainingGoal?? = nil,
        daysPerWeek: Int?? = nil
    ) throws -> Program {
        try Program(
            id: id,
            name: name ?? self.name,
            startDate: startDate ?? self.startDate,
            weeks: weeks ?? self.weeks,
            days: days ?? self.days,
            goal: goal ?? self.goal,
            daysPerWeek: daysPerWeek ?? self.daysPerWeek,
            isActive: isActive
        )
    }

    /// A copy with `isActive` set, rebuilt through `init`.
    func withActive(_ flag: Bool) throws -> Program {
        try Program(
            id: id, name: name, startDate: startDate, weeks: weeks, days: days, goal: goal, daysPerWeek: daysPerWeek,
            isActive: flag
        )
    }
}

/// Awaits stream values until one satisfies `predicate`; `nil` if the stream ends first.
func firstValue<Value: Sendable>(
    _ iterator: inout AsyncStream<Value>.Iterator,
    where predicate: (Value) -> Bool
) async -> Value? {
    while let value = await iterator.next() {
        if predicate(value) {
            return value
        }
    }
    return nil
}
