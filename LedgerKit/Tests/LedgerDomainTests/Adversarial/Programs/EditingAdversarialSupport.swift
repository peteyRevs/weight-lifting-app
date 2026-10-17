import Foundation
@testable import LedgerDomain
import Testing

// Helpers for the F11 S1 adversarial suites (gate G2). Every expected value comes from the brief's two
// "Plan amendments" sections, from the planner's rows in the implementation notes and from the reference
// models written here, never from `ProgramEditing` or `DayEditing`.

/// Counts the cases of an exhaustive loop and keeps the first few failures, so that a test makes one
/// expectation with a short message instead of one per case (a red run must not fill the result bundle).
struct Tally {
    private(set) var cases = 0
    private(set) var failures = 0
    private(set) var examples: [String] = []

    mutating func check(_ holds: Bool, _ note: @autoclosure () -> String) {
        cases += 1
        guard !holds else {
            return
        }
        failures += 1
        if examples.count < 4 {
            examples.append(note())
        }
    }

    var passed: Bool {
        failures == 0
    }

    var summary: Comment {
        "\(failures) of \(cases) cases failed; first: \(examples.joined(separator: " | "))"
    }
}

enum EditAdv {
    static func slotID(_ number: Int) -> SlotID {
        SlotID(Fixtures.uuid(number))
    }

    static func dayID(_ number: Int) -> DayTemplateID {
        DayTemplateID(Fixtures.uuid(number))
    }

    static func weekID(_ number: Int) -> WeekID {
        WeekID(Fixtures.uuid(number))
    }

    /// The number a `Fixtures.uuid` was made from, to name a slot or a day in a failure message.
    static func number(_ uuid: UUID) -> Int {
        let bytes = uuid.uuid
        return Int(bytes.12) << 24 | Int(bytes.13) << 16 | Int(bytes.14) << 8 | Int(bytes.15)
    }

    /// "5000 5001+ 5002": the day's slot numbers in order, a "+" after each slot joined to the one before.
    static func brief(_ slots: [Slot]) -> String {
        slots.map { "\(number($0.id.rawValue))\($0.isSupersetWithPrevious ? "+" : "")" }.joined(separator: " ")
    }
}

// MARK: - Programs

extension EditAdv {
    static let fourDayIDs = [300, 310, 320, 330].map(dayID)

    /// The spec's seed schedule (§6.4) with no exercises: UA, LA, UB, LB; eight weeks with ids 200…207;
    /// weeks 1–7 train UA on Monday, LA on Wednesday, UB on Friday and LB on Saturday; week 8 trains the
    /// first three and is the deload.
    static func fourDayProgram(weekCount: Int = 8) throws -> Program {
        let tags = ["UA", "LA", "UB", "LB"]
        let days = zip(fourDayIDs, tags).map { DayTemplate(id: $0, name: "Day \($1)", tag: $1) }
        let deload: [Weekday: DayTemplateID] = [
            .monday: fourDayIDs[0], .wednesday: fourDayIDs[1], .friday: fourDayIDs[2]
        ]
        var training = deload
        training[.saturday] = fourDayIDs[3]
        let weeks = (0 ..< weekCount).map { index in
            Week(id: weekID(200 + index), index: index, isDeload: index == 7, schedule: index == 7 ? deload : training)
        }
        return try program(weeks: weeks, days: days)
    }

    static func program(weeks: [Week], days: [DayTemplate]) throws -> Program {
        try Program(
            id: Fixtures.programID,
            name: "Upper / Lower",
            startDate: Fixtures.civil(2026, 8, 17),
            weeks: weeks,
            days: days,
            goal: .both,
            daysPerWeek: 4,
            isActive: true
        )
    }

    /// `count` weeks with ids 200…, none a deload, none scheduled.
    static func restWeeks(_ count: Int) -> [Week] {
        (0 ..< count).map { Week(id: weekID(200 + $0), index: $0) }
    }

    /// Why `Program.init` refuses `program`, or `nil` when it accepts it and gives the same program back.
    static func rejection(of program: Program) -> String? {
        do {
            let rebuilt = try Program(
                id: program.id,
                name: program.name,
                startDate: program.startDate,
                weeks: program.weeks,
                days: program.days,
                goal: program.goal,
                daysPerWeek: program.daysPerWeek,
                isActive: program.isActive
            )
            if rebuilt != program {
                return "Program.init gives another program back"
            }
            return program.days.lazy.compactMap { rejection(of: $0.slots) }.first
        } catch {
            return "Program.init throws \(error)"
        }
    }
}

// MARK: - Days and slots

extension EditAdv {
    /// A day whose slot `i` has the id `base + i`, the flag `flags[i]` and fields no other slot of the day
    /// has, so that a field carried to the wrong slot is seen.
    static func day(flags: [Bool], base: Int = 5000, id: Int = 4000) throws -> DayTemplate {
        let slots = try flags.enumerated().map { index, joined in
            try distinctSlot(index, id: base + index, joined: joined)
        }
        return DayTemplate(id: dayID(id), name: "Day \(id)", tag: "T\(id)", slots: slots)
    }

    static func distinctSlot(_ index: Int, id: Int, joined: Bool) throws -> Slot {
        try Slot(
            id: slotID(id),
            exerciseID: ExerciseID(Fixtures.uuid(700 + index)),
            sets: 1 + index % 12,
            reps: 3 + index,
            repsHi: 6 + index + index % 3,
            rpe: Decimal(10 + index % 11) / 2,
            restSeconds: 30 + 15 * (index % 19),
            progression: Progression.allCases[index % 3],
            startLoad: index % 4 == 3 ? nil : .pounds(Decimal(100 + 5 * index)),
            step: index.isMultiple(of: 2) ? nil : .pounds(2.5),
            isSupersetWithPrevious: joined,
            dropSets: index % 2,
            misses: [index, index + 3]
        )
    }

    /// Every pattern of `count` flags: 2^count of them.
    static func flagPatterns(count: Int) -> [[Bool]] {
        (0 ..< 1 << count).map { bits in (0 ..< count).map { bits >> $0 & 1 == 1 } }
    }

    /// Why `Slot.init` refuses one of `slots`, or `nil` when it accepts each and gives the same slot back.
    static func rejection(of slots: [Slot]) -> String? {
        slots.lazy.compactMap { rejection(of: $0) }.first
    }

    static func rejection(of slot: Slot) -> String? {
        do {
            let rebuilt = try Slot(
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
            return rebuilt == slot ? nil : "Slot.init gives another slot back for \(number(slot.id.rawValue))"
        } catch {
            return "Slot.init throws \(error) for slot \(number(slot.id.rawValue))"
        }
    }

    /// `slot` with its superset flag cleared: everything a move, a join or a break-out must leave alone.
    static func unflagged(_ slot: Slot) -> Slot {
        var copy = slot
        copy.isSupersetWithPrevious = false
        return copy
    }
}

// MARK: - Superset groups, from the plan's definition

extension EditAdv {
    /// "A maximal run of slots in which every slot after the first has the flag"; the first slot's flag is
    /// not read.
    static func groups(_ slots: [Slot]) -> [[SlotID]] {
        var groups: [[SlotID]] = []
        for (index, slot) in slots.enumerated() {
            if index > 0, slot.isSupersetWithPrevious {
                groups[groups.count - 1].append(slot.id)
            } else {
                groups.append([slot.id])
            }
        }
        return groups
    }

    /// The flags of a day in normal form that has these groups: false for each group's first slot.
    static func flags(_ groups: [[SlotID]]) -> [Bool] {
        groups.flatMap { group in group.indices.map { $0 > 0 } }
    }

    /// "Group-aware move, defined", on the groups: a member that is not at its group's edge on that side
    /// changes places with its neighbour; from the edge the group changes places with the next group; at
    /// the day's edge, or for an id no group holds, nothing changes.
    static func moved(_ groups: [[SlotID]], slot: SlotID, _ direction: MoveDirection) -> [[SlotID]] {
        guard let groupIndex = groups.firstIndex(where: { $0.contains(slot) }),
              let memberIndex = groups[groupIndex].firstIndex(of: slot)
        else {
            return groups
        }
        var result = groups
        let offset = direction == .downward ? 1 : -1
        if groups[groupIndex].indices.contains(memberIndex + offset) {
            result[groupIndex].swapAt(memberIndex, memberIndex + offset)
        } else if groups.indices.contains(groupIndex + offset) {
            result.swapAt(groupIndex, groupIndex + offset)
        }
        return result
    }
}
