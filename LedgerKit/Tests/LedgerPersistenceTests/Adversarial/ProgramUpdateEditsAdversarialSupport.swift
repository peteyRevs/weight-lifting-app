import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization

// F11 S3 adversarial round 1: the changes the row attacks give to `update`. Routes that end at the program
// they were given, and builder edits with the rows each must write.

/// Routes back to the program a change was given.
enum UpdateRoutes {
    static let unchanged: [(name: String, change: @Sendable (Program) throws -> Program)] = [
        ("as given", { $0 }),
        ("rebuilt through every init, weeks given backwards", { program in
            let days = try program.days.map { day in
                try DayTemplate(id: day.id, name: day.name, tag: day.tag, slots: day.slots.map { try $0.with() })
            }
            return try program.rebuilt(weeks: program.weeks.reversed(), days: days)
        }),
        ("through JSON and back", { program in
            try JSONDecoder().decode(Program.self, from: JSONEncoder().encode(program))
        }),
        ("days and slots reversed, then restored", { program in
            var changed = program
            changed.days.reverse()
            changed.days[0].slots.reverse()
            changed.days[0].slots.reverse()
            changed.days.reverse()
            return changed
        }),
        ("every miss, name and flag taken away and put back", { program in
            var changed = program
            changed.name = ""
            changed.isActive.toggle()
            changed.weeks[1].isDeload.toggle()
            changed.days[0].slots[0].misses = []
            changed.days[0].slots[0].misses = program.days[0].slots[0].misses
            changed.weeks[1].isDeload.toggle()
            changed.isActive.toggle()
            changed.name = program.name
            return changed
        })
    ]
}

/// One builder edit, and the rows of program 1 (ids `…03E9` to `…03EE` for slots 1001 to 1006) it must write.
struct UpdateEdit: Sendable {
    let name: String
    /// `"<last four of the id> <table> <new, written or deleted>"`, or `"slot_miss <state>"` for a miss.
    let rows: [String]
    let change: @Sendable (Program) throws -> Program

    static let all: [UpdateEdit] = [
        UpdateEdit(name: "renamed", rows: ["0001 program written"]) { program in
            UpdateRefusal.changed(program) { $0.name = "Renamed" }
        },
        UpdateEdit(name: "a day renamed", rows: ["0065 day_template written"]) { program in
            UpdateRefusal.changed(program) { $0.days[1].name = "Lower — pull" }
        },
        UpdateEdit(name: "a week made a deload", rows: ["0065 program_week written"]) { program in
            UpdateRefusal.changed(program) { $0.weeks[1].isDeload.toggle() }
        },
        UpdateEdit(name: "a week's schedule moved", rows: ["0064 program_week written"]) { program in
            UpdateRefusal.changed(program) { $0.weeks[0].schedule = [.friday: $0.days[1].id] }
        },
        UpdateEdit(name: "a week added", rows: ["006C program_week new"]) { program in
            UpdateRefusal.changed(program) { $0.weeks.append(Week(id: S2Kit.weekID(108), index: 3)) }
        },
        UpdateEdit(name: "the last week removed", rows: ["0066 program_week deleted"]) { program in
            UpdateRefusal.changed(program) { $0.weeks.removeLast() }
        },
        UpdateEdit(name: "a slot's reps changed", rows: ["03EC slot written"]) { program in
            try UpdateRefusal
                .changed(program) { $0.days[1].slots[0] = try $0.days[1].slots[0].with(reps: 2, repsHi: 3) }
        },
        UpdateEdit(name: "two slots exchanged", rows: ["03E9 slot written", "03EA slot written"]) { program in
            UpdateRefusal.changed(program) { $0.days[0].slots.swapAt(0, 1) }
        },
        // Slot 1003 holds one miss (week 2).
        UpdateEdit(name: "the last slot of a day removed", rows: [
            "03EB slot deleted",
            "slot_miss deleted"
        ]) { program in
            UpdateRefusal.changed(program) { $0.days[0].slots.removeLast() }
        },
        UpdateEdit(name: "a slot added", rows: ["0457 slot new"]) { program in
            try UpdateRefusal.changed(program) { try $0.days[1].slots.append(S2Kit.slot(1111, exercise: 7)) }
        },
        // Slot 1002 has missed week 0; slot 1001 week 1.
        UpdateEdit(name: "a miss recorded", rows: ["slot_miss new"]) { program in
            UpdateRefusal.changed(program) { $0.days[0].slots[1].misses.insert(2) }
        },
        UpdateEdit(name: "a miss cleared", rows: ["slot_miss deleted"]) { program in
            UpdateRefusal.changed(program) { $0.days[0].slots[0].misses = [] }
        },
        UpdateEdit(name: "a slot's exercise exchanged", rows: ["03EE slot written"]) { program in
            UpdateRefusal.changed(program) { $0.days[1].slots[2].exerciseID = S2Kit.exerciseID(7) }
        },
        UpdateEdit(
            name: "a day deleted",
            rows: [
                "0064 program_week written", "0065 program_week written", "0066 program_week written",
                "0065 day_template deleted", "03EC slot deleted", "03ED slot deleted", "03EE slot deleted",
                "slot_miss deleted", "slot_miss deleted", "slot_miss deleted"
            ]
        ) { program in
            UpdateRefusal.changed(program) { changed in
                let removed = changed.days.removeLast().id
                for week in changed.weeks.indices {
                    changed.weeks[week].schedule = changed.weeks[week].schedule.filter { $0.value != removed }
                }
            }
        },
        UpdateEdit(name: "made inactive", rows: ["0001 program written"]) { program in
            UpdateRefusal.changed(program) { $0.isActive = false }
        }
    ]
}

/// A program one task sets and another reads.
final class LockedProgram: Sendable {
    private let held = Mutex<Program?>(nil)

    var value: Program? {
        held.withLock { $0 }
    }

    func set(_ program: Program) {
        held.withLock { $0 = program }
    }
}
