import Foundation
import LedgerDomain
import LedgerTestSupport

/// What a script's updates send: a builder's edits, and the results a store refuses.
extension ProgramUpdateInterleavingTests {
    /// A builder's edit, written by hand (S1's editing functions are on another branch): a total function of
    /// the stored program, which returns it unchanged when what it would edit is not there. `index` is the
    /// call's place in its script, which keeps the ids of added weeks and slots apart. None writes the misses
    /// or the exercise of a slot the program already has, as no function of S1 does.
    struct Edit: Sendable {
        let name: String
        let change: @Sendable (Program, Int) throws -> Program
    }

    /// An update that stores nothing: what its change returns or throws, and the error both stores must throw.
    struct Refusal: Sendable {
        let name: String
        let error: any Error
        let change: @Sendable (Program) throws -> Program
    }

    /// What a refused change throws itself.
    struct ChangeRefused: Error, Equatable {}

    /// An id no program of a script holds.
    static let stranger = ProgramID(EventBuilders.uuid(0x0B99_0000))

    static let edits: [Edit] = [
        Edit(name: "nothing changed") { program, _ in program },
        Edit(name: "the block renamed") { program, _ in
            var changed = program
            changed.name += "+"
            return changed
        },
        Edit(name: "a deload toggled") { program, _ in
            var changed = program
            changed.weeks[1].isDeload.toggle()
            return changed
        },
        Edit(name: "a week added") { program, index in
            var changed = program
            let last = program.weeks[program.weeks.count - 1]
            let id = WeekID(EventBuilders.uuid(0x0B77_0000 + index))
            changed.weeks.append(Week(id: id, index: last.index + 1, isDeload: false, schedule: last.schedule))
            return changed
        },
        Edit(name: "the last week removed") { program, _ in
            var changed = program
            if changed.weeks.count > 2 {
                changed.weeks.removeLast()
            }
            return changed
        },
        Edit(name: "a day renamed") { program, _ in
            var changed = program
            changed.days[changed.days.count - 1].name += "+"
            return changed
        },
        Edit(name: "a day removed") { program, _ in
            guard program.days.count > 1 else {
                return program
            }
            var changed = program
            let removed = changed.days.removeLast()
            for week in changed.weeks.indices {
                changed.weeks[week].schedule = changed.weeks[week].schedule.filter { $0.value != removed.id }
            }
            return changed
        }
    ] + slotEdits

    static let slotEdits: [Edit] = [
        Edit(name: "a slot's sets changed") { program, _ in
            var changed = program
            if let day = changed.days.firstIndex(where: { !$0.slots.isEmpty }) {
                changed.days[day].slots[0].sets = changed.days[day].slots[0].sets % 12 + 1
            }
            return changed
        },
        Edit(name: "slots reordered") { program, _ in
            var changed = program
            if let day = changed.days.firstIndex(where: { $0.slots.count > 1 }) {
                changed.days[day].slots.swapAt(0, 1)
            }
            return changed
        },
        Edit(name: "a slot removed") { program, _ in
            var changed = program
            if let day = changed.days.lastIndex(where: { !$0.slots.isEmpty }) {
                changed.days[day].slots.removeFirst()
            }
            return changed
        },
        Edit(name: "a slot added") { program, index in
            var changed = program
            // A slot under an id of its own, with no misses, as the library adds one.
            let exercises = Contract.exercises.map(\.id)
            try changed.days[0].slots.append(Seeders.slot(40 + index, day: 0, position: 0, last: false, exercises))
            return changed
        }
    ]

    static let refusals: [Refusal] = [
        Refusal(name: "a change that throws", error: ChangeRefused()) { _ in throw ChangeRefused() },
        Refusal(
            name: "a result under another id",
            error: RepositoryError.duplicateIdentifier("program \(stranger.rawValue.uuidString)")
        ) { program in
            try Program(
                id: stranger,
                name: program.name,
                startDate: program.startDate,
                weeks: program.weeks,
                days: program.days,
                isActive: program.isActive
            )
        },
        Refusal(name: "one week", error: ProgramValidationError.tooFewWeeks(count: 1)) { program in
            var result = program
            result.weeks = [program.weeks[0]]
            return result
        },
        Refusal(name: "a name holding U+0000", error: RepositoryError.nulInText("program.name")) { program in
            var result = program
            result.name += "\u{0}"
            return result
        }
    ]
}
