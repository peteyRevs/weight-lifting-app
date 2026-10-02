import Foundation
import LedgerDomain

/// Deterministic data for persistence tests (F05): a synthetic exercise catalog, standing in for F03's
/// `ExerciseCatalog.seed()` so F05 does not depend on it, and programs over any exercises.
public enum Seeders {
    /// A shape `program` or `slot` cannot build: it would trap, or give two slots one id.
    public struct UnsupportedShape: Error, Equatable {
        public let parameter: String
        public let value: Int

        public init(parameter: String, value: Int) {
            self.parameter = parameter
            self.value = value
        }
    }

    /// A catalog as `ExerciseRepository.seedIfNeeded(_:version:)` takes it.
    public struct Catalog: Sendable {
        public let exercises: [Exercise]
        public let version: Int
    }

    /// `count` synthetic catalog entries labelled `version`. Entry `i` depends on `i` alone, so a later version
    /// with a larger count is the earlier catalog plus new entries, the additive upgrade F03 promises. Equipment,
    /// muscles and patterns cycle through every case, and start loads are whole steps in both units.
    public static func catalog(count: Int, version: Int) -> Catalog {
        Catalog(exercises: (0 ..< count).map(catalogEntry), version: version)
    }

    /// Entry `index` of every synthetic catalog, e.g. "Catalog barbell horizontalPush 0".
    public static func catalogEntry(_ index: Int) -> Exercise {
        let equipment = Equipment.allCases[index % Equipment.allCases.count]
        let muscles = MuscleGroup.allCases
        let pattern = MovementPattern.allCases[index % MovementPattern.allCases.count]
        return Exercise(
            id: catalogID(index),
            name: "Catalog \(equipment.rawValue) \(pattern.rawValue) \(index)",
            shortName: "C\(index)",
            equipment: equipment,
            primaryMuscle: muscles[index % muscles.count],
            secondaryMuscles: [muscles[(index + 1) % muscles.count], muscles[(index + 3) % muscles.count]],
            pattern: pattern,
            defaultStartLoad: [.lb: .pounds(Decimal(5 * (index % 40))), .kg: .kilograms(Decimal(index % 40) * 2.5)],
            curatedAlternatives: [catalogID(index + 1), catalogID(index + 2)]
        )
    }

    /// The id of catalog entry `index`.
    public static func catalogID(_ index: Int) -> ExerciseID {
        ExerciseID(EventBuilders.uuid(0x0CA0_0000 + index))
    }

    /// A valid block: `weeks` weeks (the last a deload), and `days` training days of `slotsPerDay` slots over
    /// `exercises` in turn. Day `d` runs on the `d`-th weekday from Monday. Slot fields vary with the slot's
    /// place (sets, reps, RPE, rest, progression, loads in lb and kg, a superset, a drop set), and every other
    /// slot has misses, so a round trip compares real values. `number` keeps the ids of two programs apart.
    ///
    /// `days` runs from 0 to 7 (one per weekday) and `slotsPerDay` from 0 to 32 (slot ids leave room for 32 a
    /// day); outside either, or with no `exercises` for its slots, it throws `UnsupportedShape`.
    public static func program(
        number: Int = 0,
        weeks: Int = 8,
        days: Int = 4,
        slotsPerDay: Int = 5,
        exercises: [ExerciseID],
        isActive: Bool = true
    ) throws -> Program {
        guard (0 ... Weekday.allCases.count).contains(days) else {
            throw UnsupportedShape(parameter: "days", value: days)
        }
        guard (0 ... slotsPerDayLimit).contains(slotsPerDay) else {
            throw UnsupportedShape(parameter: "slotsPerDay", value: slotsPerDay)
        }
        let dayTemplates = try (0 ..< days).map { day in
            try DayTemplate(
                id: DayTemplateID(programUUID(number, 0x100 + day)),
                name: "Day \(day + 1) — Block \(number)",
                tag: "D\(day + 1)",
                slots: (0 ..< slotsPerDay).map { position in
                    try slot(number, day: day, position: position, last: position == slotsPerDay - 1, exercises)
                }
            )
        }
        let schedule = Dictionary(uniqueKeysWithValues: dayTemplates.indices.map { day in
            (Weekday.allCases[day % Weekday.allCases.count], dayTemplates[day].id)
        })
        return try Program(
            id: ProgramID(programUUID(number, 0)),
            name: "Block \(number)",
            startDate: blockStart,
            weeks: (0 ..< weeks).map { index in
                Week(
                    id: WeekID(programUUID(number, 0x800 + index)),
                    index: index,
                    isDeload: index == weeks - 1,
                    schedule: schedule
                )
            },
            days: dayTemplates,
            goal: .strength,
            daysPerWeek: days,
            isActive: isActive
        )
    }

    /// Slot `position` (0 to 31) of day `day`; with no `exercises`, or another position, it throws
    /// `UnsupportedShape`.
    public static func slot(
        _ number: Int,
        day: Int,
        position: Int,
        last: Bool,
        _ exercises: [ExerciseID]
    ) throws -> Slot {
        guard !exercises.isEmpty else {
            throw UnsupportedShape(parameter: "exercises", value: 0)
        }
        guard (0 ..< slotsPerDayLimit).contains(position) else {
            throw UnsupportedShape(parameter: "position", value: position)
        }
        let turn = day + position
        let reps = 3 + (2 * position + day) % 10
        let rpes: [Decimal] = [7, 7.5, 8, 8.5, 9]
        return try Slot(
            id: SlotID(programUUID(number, 0x1000 + 0x20 * day + position)),
            exerciseID: exercises[(day * 7 + position) % exercises.count],
            sets: 1 + turn % 5,
            reps: reps,
            repsHi: reps + 2,
            rpe: rpes[turn % rpes.count],
            restSeconds: 60 + 15 * (turn % 8),
            progression: Progression.allCases[turn % Progression.allCases.count],
            startLoad: position.isMultiple(of: 2) ? .pounds(Decimal(95 + 5 * turn)) : .kilograms(Decimal(20 + day)),
            step: [Weight.pounds(2.5), .kilograms(1.25), nil][turn % 3],
            isSupersetWithPrevious: last && position > 0,
            dropSets: position == 1 ? 1 : 0,
            misses: position.isMultiple(of: 2) ? [] : [0, turn % 6 + 1]
        )
    }

    /// Monday 2026-08-17, the spec §6.4 seed block's start (decoded, so a typo throws rather than traps).
    private static var blockStart: CivilDate {
        get throws {
            try JSONDecoder().decode(CivilDate.self, from: Data(#""2026-08-17""#.utf8))
        }
    }

    /// Slot ids are `0x1000 + 0x20 × day + position`, so a day has room for 32.
    private static let slotsPerDayLimit = 0x20

    private static func programUUID(_ number: Int, _ offset: Int) -> UUID {
        EventBuilders.uuid(0x0B00_0000 + number << 16 + offset)
    }
}
