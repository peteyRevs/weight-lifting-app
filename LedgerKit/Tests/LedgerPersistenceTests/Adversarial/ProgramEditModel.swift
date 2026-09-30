import Foundation
import LedgerDomain

/// A seeded random editor of one program, for `ProgramEditModelAdversarialTests`: what a builder (F11) could
/// send to `save`, including ids it removed earlier and now adds back. The model is the program itself.
struct ProgramEditor {
    var program: Program
    var generator: SeededGenerator
    private var nextNumber = 50000
    private var removedSlots: [Slot] = []
    private var removedDays: [DayTemplateID] = []
    private var removedWeeks: [WeekID] = []

    init(program: Program, seed: UInt64) {
        self.program = program
        generator = SeededGenerator(seed: seed)
    }

    private mutating func number() -> Int {
        nextNumber += 1
        return nextNumber
    }

    private mutating func pick(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &generator)
    }

    mutating func randomSlot(id: SlotID) throws -> Slot {
        let reps = pick(1 ... 30)
        let loads: [Weight?] = [
            nil,
            .pounds(Decimal(pick(0 ... 100_000)) / 100),
            .kilograms(Decimal(pick(0 ... 400)) * 1.25)
        ]
        let steps: [Weight?] = [nil, .pounds(2.5), .kilograms(1.25), .pounds(Decimal(pick(1 ... 999)) / 100)]
        return try Slot(
            id: id,
            exerciseID: S2Kit.exerciseID(pick(0 ... 7)),
            sets: pick(1 ... 12),
            reps: reps,
            repsHi: pick(reps + 1 ... 40),
            rpe: Decimal(pick(10 ... 20)) / 2,
            restSeconds: 30 + 15 * pick(0 ... 18),
            progression: Progression.allCases[pick(0 ... 2)],
            startLoad: loads[pick(0 ... 2)],
            step: steps[pick(0 ... 3)],
            isSupersetWithPrevious: Bool.random(using: &generator),
            dropSets: pick(0 ... 1),
            misses: Set((-1 ... 10).filter { _ in pick(0 ... 3) == 0 })
        )
    }

    /// One to three random edits, rebuilt through `Program.init`.
    mutating func edit() throws {
        var days = program.days
        var weeks = program.weeks
        for _ in 0 ..< pick(1 ... 3) {
            try editOnce(days: &days, weeks: &weeks)
        }
        weeks = weeks.enumerated().map { Week(id: $1.id, index: $0, isDeload: $1.isDeload, schedule: $1.schedule) }
        let dayIDs = Set(days.map(\.id))
        weeks = weeks.map { Week(id: $0.id, index: $0.index, isDeload: $0.isDeload, schedule: $0.schedule.filter {
            dayIDs.contains($0.value)
        }) }
        program = try program.rebuilt(weeks: weeks, days: days)
    }
}

extension ProgramEditor {
    private typealias Edit = @Sendable (inout ProgramEditor, inout [DayTemplate], inout [Week]) throws -> Void

    /// One edit a builder can make; each does nothing when it does not apply.
    private static let edits: [Edit] = [
        { editor, days, _ in try editor.changeSlot(&days) },
        { editor, days, _ in try editor.addSlot(&days) },
        { editor, days, _ in editor.removeSlot(&days) },
        { editor, days, _ in editor.moveSlot(&days) },
        { editor, days, _ in editor.reorder(&days) },
        { editor, days, weeks in editor.addDay(&days, &weeks) },
        { editor, days, _ in editor.removeDay(&days) },
        { editor, days, weeks in editor.addWeek(days, &weeks) },
        { editor, _, weeks in editor.removeWeek(&weeks) },
        { editor, days, weeks in editor.reschedule(days, &weeks) },
        { editor, days, _ in try editor.toggleMiss(&days) },
        { _, _, _ in }
    ]

    private mutating func editOnce(days: inout [DayTemplate], weeks: inout [Week]) throws {
        let edit = Self.edits[pick(0 ... Self.edits.count - 1)]
        try edit(&self, &days, &weeks)
        if pick(0 ... 12) == 0 {
            try changeHeader()
        }
    }

    /// A random (day, slot) position, if any day has a slot.
    private mutating func anySlot(_ days: [DayTemplate]) -> (day: Int, slot: Int)? {
        let slotted = days.indices.filter { !days[$0].slots.isEmpty }
        guard !slotted.isEmpty else {
            return nil
        }
        let day = slotted[pick(0 ... slotted.count - 1)]
        return (day, pick(0 ... days[day].slots.count - 1))
    }

    private mutating func changeSlot(_ days: inout [DayTemplate]) throws {
        if let (day, slot) = anySlot(days) {
            days[day].slots[slot] = try randomSlot(id: days[day].slots[slot].id)
        }
    }

    /// Adds a slot removed earlier when one is free, else a new one.
    private mutating func addSlot(_ days: inout [DayTemplate]) throws {
        guard !days.isEmpty else {
            return
        }
        let present = Set(days.flatMap(\.slots).map(\.id))
        let slot = try removedSlots.first { !present.contains($0.id) } ?? randomSlot(id: S2Kit.slotID(number()))
        removedSlots.removeAll { $0.id == slot.id }
        let day = pick(0 ... days.count - 1)
        days[day].slots.insert(slot, at: pick(0 ... days[day].slots.count))
    }

    private mutating func removeSlot(_ days: inout [DayTemplate]) {
        if let (day, slot) = anySlot(days) {
            removedSlots.append(days[day].slots.remove(at: slot))
        }
    }

    private mutating func moveSlot(_ days: inout [DayTemplate]) {
        guard days.count > 1, let (day, index) = anySlot(days) else {
            return
        }
        let slot = days[day].slots.remove(at: index)
        let target = pick(0 ... days.count - 1)
        days[target].slots.insert(slot, at: pick(0 ... days[target].slots.count))
    }

    private mutating func reorder(_ days: inout [DayTemplate]) {
        days.shuffle(using: &generator)
        for index in days.indices where Bool.random(using: &generator) {
            days[index].slots.shuffle(using: &generator)
        }
    }

    /// Adds a day removed earlier (its slots stay removed) when one is free, else a new one, and schedules it.
    private mutating func addDay(_ days: inout [DayTemplate], _ weeks: inout [Week]) {
        guard days.count < 7 else {
            return
        }
        let present = Set(days.map(\.id))
        let id = removedDays.first { !present.contains($0) } ?? S2Kit.dayID(number())
        removedDays.removeAll { $0 == id }
        days.insert(DayTemplate(id: id, name: "Day \(pick(0 ... 99))", tag: "D"), at: pick(0 ... days.count))
        weeks[pick(0 ... weeks.count - 1)].schedule[Weekday.allCases[pick(0 ... 6)]] = id
    }

    private mutating func removeDay(_ days: inout [DayTemplate]) {
        guard !days.isEmpty else {
            return
        }
        let day = days.remove(at: pick(0 ... days.count - 1))
        removedDays.append(day.id)
        removedSlots += day.slots
    }

    /// Appends a week removed earlier when one is free, else a new one.
    private mutating func addWeek(_ days: [DayTemplate], _ weeks: inout [Week]) {
        let present = Set(weeks.map(\.id))
        let id = removedWeeks.first { !present.contains($0) } ?? S2Kit.weekID(number())
        removedWeeks.removeAll { $0 == id }
        weeks.append(Week(id: id, index: weeks.count, schedule: days.first.map { [.saturday: $0.id] } ?? [:]))
    }

    private mutating func removeWeek(_ weeks: inout [Week]) {
        if weeks.count > 2 {
            removedWeeks.append(weeks.remove(at: pick(0 ... weeks.count - 1)).id)
        }
    }

    private mutating func reschedule(_ days: [DayTemplate], _ weeks: inout [Week]) {
        guard !days.isEmpty else {
            return
        }
        let week = pick(0 ... weeks.count - 1)
        let weekday = Weekday.allCases[pick(0 ... 6)]
        weeks[week].schedule[weekday] = Bool.random(using: &generator) ? days[pick(0 ... days.count - 1)].id : nil
        weeks[week].isDeload.toggle()
    }

    /// Logs or clears one miss (rule 13).
    private mutating func toggleMiss(_ days: inout [DayTemplate]) throws {
        guard let (day, slot) = anySlot(days) else {
            return
        }
        var misses = days[day].slots[slot].misses
        let week = pick(-1 ... 10)
        if misses.remove(week) == nil {
            misses.insert(week)
        }
        days[day].slots[slot] = try days[day].slots[slot].with(misses: misses)
    }

    private mutating func changeHeader() throws {
        let goal: TrainingGoal? = Bool.random(using: &generator) ? nil : .hypertrophy
        program = try program.rebuilt(
            name: "Block \(pick(0 ... 9))",
            startDate: CivilDate(year: pick(1990 ... 2090), month: 1, day: 5),
            goal: .some(goal),
            daysPerWeek: .some(pick(0 ... 1) == 0 ? nil : 3)
        )
    }
}
