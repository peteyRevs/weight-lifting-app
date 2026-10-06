import Foundation
@testable import LedgerDomain
import Testing

// MARK: - Short differences

extension EditingSupport {
    private static let slotFields: [(name: String, differs: @Sendable (Slot, Slot) -> Bool)] = [
        ("exercise", { $0.exerciseID != $1.exerciseID }),
        ("sets", { $0.sets != $1.sets }),
        ("reps", { $0.reps != $1.reps }),
        ("repsHi", { $0.repsHi != $1.repsHi }),
        ("rpe", { $0.rpe != $1.rpe }),
        ("rest", { $0.rest != $1.rest }),
        ("progression", { $0.progression != $1.progression }),
        ("startLoad", { $0.startLoad != $1.startLoad }),
        ("step", { $0.step != $1.step }),
        ("superset", { $0.isSupersetWithPrevious != $1.isSupersetWithPrevious }),
        ("dropSets", { $0.dropSets != $1.dropSets }),
        ("misses", { $0.misses != $1.misses })
    ]

    /// The names of the fields in which two slots differ.
    static func changedFields(_ lhs: Slot, _ rhs: Slot) -> [String] {
        (lhs.id == rhs.id ? [] : ["id"]) + slotFields.filter { $0.differs(lhs, rhs) }.map(\.name)
    }

    /// What differs between two days, in a few words; empty when they are equal.
    static func difference(_ lhs: DayTemplate, _ rhs: DayTemplate) -> String {
        var parts: [String] = []
        if lhs.id != rhs.id || lhs.name != rhs.name || lhs.tag != rhs.tag {
            parts.append("id, name or tag")
        }
        if lhs.slots.map(\.id) != rhs.slots.map(\.id) {
            parts
                .append(
                    "slot order \(numbers(lhs.slots.map(\.id.rawValue))) vs \(numbers(rhs.slots.map(\.id.rawValue)))"
                )
        } else {
            for (index, pair) in zip(lhs.slots, rhs.slots).enumerated() where pair.0 != pair.1 {
                parts.append("slot \(index): \(changedFields(pair.0, pair.1).joined(separator: " "))")
            }
        }
        return parts.prefix(6).joined(separator: "; ")
    }

    /// What differs between two programs, in a few words; empty when they are equal.
    static func difference(_ lhs: Program, _ rhs: Program) -> String {
        var parts: [String] = []
        if lhs.id != rhs.id || lhs.name != rhs.name || lhs.startDate != rhs.startDate {
            parts.append("id, name or start date")
        }
        if lhs.goal != rhs.goal || lhs.daysPerWeek != rhs.daysPerWeek || lhs.isActive != rhs.isActive {
            parts.append("goal, days per week or active flag")
        }
        if lhs.weeks.map(\.id) != rhs.weeks.map(\.id) {
            parts.append("weeks \(lhs.weeks.count) vs \(rhs.weeks.count)")
        } else {
            parts += zip(lhs.weeks, rhs.weeks).filter { $0 != $1 }.map { "week \($0.0.index)" }
        }
        if lhs.days.map(\.id) != rhs.days.map(\.id) {
            parts.append("days \(lhs.days.map(\.tag)) vs \(rhs.days.map(\.tag))")
        } else {
            parts += zip(lhs.days, rhs.days).filter { $0 != $1 }.map { "day \($0.0.tag): \(difference($0.0, $0.1))" }
        }
        return parts.prefix(6).joined(separator: "; ")
    }

    /// The fixture number of each id (`Fixtures.uuid(_:)` keeps it in the last four bytes).
    static func numbers(_ ids: [UUID]) -> [Int] {
        ids.map { id in
            let bytes = id.uuid
            return [bytes.12, bytes.13, bytes.14, bytes.15].reduce(0) { $0 << 8 | Int($1) }
        }
    }
}

// MARK: - Reading a day

extension EditingSupport {
    static func slot(_ number: Int) -> SlotID {
        SlotID(Fixtures.uuid(number))
    }

    /// A day of bench slots numbered 1, 2, …, each joined to the one before it where `joined` says so.
    static func day(joined flags: [Bool]) throws -> DayTemplate {
        let slots = try flags.enumerated().map { try Fixtures.slot(
            Fixtures.bench,
            id: $0.offset + 1,
            superset: $0.element
        ) }
        return DayTemplate(id: DayTemplateID(Fixtures.uuid(500)), name: "Day", tag: "DY", slots: slots)
    }

    /// The day's slot ids, as their fixture numbers.
    static func ids(_ day: DayTemplate) -> [Int] {
        numbers(day.slots.map(\.id.rawValue))
    }

    static func flags(_ day: DayTemplate) -> [Bool] {
        day.slots.map(\.isSupersetWithPrevious)
    }

    /// `DayEditing.groups(of:)`, as fixture numbers.
    static func groups(_ day: DayTemplate) -> [[Int]] {
        DayEditing.groups(of: day).map { numbers($0.map(\.rawValue)) }
    }

    /// The slot's value for a field, as the field that would set it.
    static func value(_ kind: SlotField.Kind, of slot: Slot) -> SlotField? {
        switch kind {
        case .sets: .sets(slot.sets)
        case .reps: .reps(slot.reps)
        case .repsHi: .repsHi(slot.repsHi)
        case .rpe: .rpe(slot.rpe.value)
        case .rest: .restSeconds(slot.rest.seconds)
        case .startLoad: slot.startLoad.map(SlotField.startLoad)
        }
    }

    static func kind(of field: SlotField) -> SlotField.Kind {
        switch field {
        case .sets: .sets
        case .reps: .reps
        case .repsHi: .repsHi
        case .rpe: .rpe
        case .restSeconds: .rest
        case .startLoad: .startLoad
        }
    }
}
