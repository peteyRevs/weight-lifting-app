import Foundation
@testable import LedgerDomain
import Testing

/// Shared by the `ProgramEditing` and `DayEditing` suites: seeded programs and days, the checks that a result
/// is one the model accepts, and short differences.
///
/// A suite never hands a whole program, day or array of slots to `#expect`: a failure would write both values
/// into the result bundle. It compares ids or small fields, or expects `difference(_:_:)` to be empty, which
/// prints a few words.
enum EditingTestSupport {
    static let exercises = [
        Fixtures.bench,
        Fixtures.inclineDB,
        Fixtures.chestSupportedRow,
        Fixtures.latPulldown,
        Fixtures.lateralRaise,
        Fixtures.backSquat,
        Fixtures.barbellCurl
    ]

    /// An id no seeded program, day or slot uses.
    static let unknown = Fixtures.uuid(77777)

    // MARK: - Seeded values

    /// A valid slot with random numbers, progression, loads, misses and exercise.
    static func randomSlot(id: Int, joined: Bool, using generator: inout SeededGenerator) throws -> Slot {
        let reps = Int.random(in: Slot.repsRange, using: &generator)
        let loads: [Weight?] = [nil, .zero, .pounds(45), .pounds(52.5), .kilograms(81.25), .pounds(dec("181.3"))]
        let steps: [Weight?] = [nil, nil, .pounds(2.5), .pounds(5), .kilograms(1.25), .kilograms(2)]
        return try Slot(
            id: SlotID(Fixtures.uuid(id)),
            exerciseID: (exercises.randomElement(using: &generator) ?? Fixtures.bench).id,
            sets: Int.random(in: Slot.setsRange, using: &generator),
            reps: reps,
            repsHi: Int.random(in: (reps + 1) ... Slot.repsHiRange.upperBound, using: &generator),
            rpe: Decimal(Int.random(in: 10 ... 20, using: &generator)) / 2,
            restSeconds: 15 * Int.random(in: 2 ... 20, using: &generator),
            progression: Progression.allCases.randomElement(using: &generator) ?? .linear,
            startLoad: loads.randomElement(using: &generator) ?? nil,
            step: steps.randomElement(using: &generator) ?? nil,
            isSupersetWithPrevious: joined,
            dropSets: Int.random(in: 0 ... 1, using: &generator),
            misses: Set((0 ..< 3).map { _ in Int.random(in: -1 ... 12, using: &generator) })
        )
    }

    /// Day `number` with a random count of valid slots, in normal form, with random flags after the first.
    /// Its id is `uuid(1000 + 100 × number)` and its slots' ids follow it.
    static func randomDay(
        _ number: Int,
        slots count: ClosedRange<Int> = 0 ... 8,
        using generator: inout SeededGenerator
    ) throws -> DayTemplate {
        let base = 1000 + number * 100
        let slots = try (0 ..< Int.random(in: count, using: &generator)).map { index in
            try randomSlot(id: base + index + 1, joined: index > 0 && Bool.random(using: &generator), using: &generator)
        }
        return DayTemplate(
            id: DayTemplateID(Fixtures.uuid(base)),
            name: "Day \(number)",
            tag: "T\(number)",
            slots: slots
        )
    }

    /// A valid block of 2–12 weeks and 0–6 days of 0–5 slots, with random schedules and deload flags.
    static func randomProgram(using generator: inout SeededGenerator) throws -> Program {
        let days = try (0 ..< Int.random(in: 0 ... 6, using: &generator)).map {
            try randomDay($0, slots: 0 ... 5, using: &generator)
        }
        let weeks = (0 ..< Int.random(in: 2 ... 12, using: &generator)).map { index in
            var schedule: [Weekday: DayTemplateID] = [:]
            for weekday in Weekday.allCases where Bool.random(using: &generator) {
                schedule[weekday] = days.randomElement(using: &generator)?.id
            }
            return Fixtures.week(index, deload: Int.random(in: 0 ... 4, using: &generator) == 0, schedule: schedule)
        }
        return try Program(
            id: Fixtures.programID,
            name: "Block",
            startDate: Fixtures.civil(2026, 8, 17),
            weeks: weeks,
            days: days
        )
    }

    // MARK: - What the model accepts

    /// `slot` built again through `Slot.init`, which throws for a slot the model refuses.
    static func rebuilt(_ slot: Slot) throws(SlotValidationError) -> Slot {
        try Slot(
            id: slot.id,
            exerciseID: slot.exerciseID,
            sets: slot.sets,
            reps: slot.reps,
            repsHi: slot.repsHi,
            rpe: slot.rpe.value,
            restSeconds: slot.rest.seconds,
            progression: slot.progression,
            startLoad: slot.startLoad,
            step: slot.step,
            isSupersetWithPrevious: slot.isSupersetWithPrevious,
            dropSets: slot.dropSets,
            misses: slot.misses
        )
    }

    /// `program` built again through `Program.init`, every slot through `Slot.init`.
    static func rebuilt(_ program: Program) throws -> Program {
        try Program(
            id: program.id,
            name: program.name,
            startDate: program.startDate,
            weeks: program.weeks,
            days: program.days.map { day in
                try DayTemplate(id: day.id, name: day.name, tag: day.tag, slots: day.slots.map(rebuilt))
            },
            goal: program.goal,
            daysPerWeek: program.daysPerWeek,
            isActive: program.isActive
        )
    }

    /// Why `day` is not one `DayEditing` may return: a slot `Slot.init` refuses or changes, a slot id held
    /// twice, or a first slot joined to a previous one. Empty when the day is sound.
    static func faults(in day: DayTemplate) -> [String] {
        var faults: [String] = []
        if day.slots.first?.isSupersetWithPrevious == true {
            faults.append("\(day.tag): the first slot is joined")
        }
        if Set(day.slots.map(\.id)).count != day.slots.count {
            faults.append("\(day.tag): a slot id twice")
        }
        for (index, slot) in day.slots.enumerated() {
            do {
                if try rebuilt(slot) != slot {
                    faults.append("\(day.tag) slot \(index): Slot.init changed it")
                }
            } catch {
                faults.append("\(day.tag) slot \(index): \(error)")
            }
        }
        return faults
    }

    /// Why `program` is not one `ProgramEditing` may return: `Program.init` refuses or changes it, week
    /// indices are not 0 … n − 1, a schedule names a missing day, an id is held twice, or a day has a fault.
    static func faults(in program: Program) -> [String] {
        var faults = program.days.flatMap { Self.faults(in: $0) }
        if program.weeks.map(\.index) != Array(program.weeks.indices) {
            faults.append("week indices \(program.weeks.map(\.index))")
        }
        let days = Set(program.days.map(\.id))
        if program.weeks.contains(where: { week in week.schedule.values.contains { !days.contains($0) } }) {
            faults.append("a schedule names a missing day")
        }
        let slots = program.days.flatMap(\.slots)
        let distinct = [days.count, Set(program.weeks.map(\.id)).count, Set(slots.map(\.id)).count]
        if distinct != [program.days.count, program.weeks.count, slots.count] {
            faults.append("an id twice")
        }
        do {
            if try rebuilt(program) != program {
                faults.append("Program.init changed it")
            }
        } catch {
            faults.append("Program.init refused it: \(error)")
        }
        return faults
    }
}
