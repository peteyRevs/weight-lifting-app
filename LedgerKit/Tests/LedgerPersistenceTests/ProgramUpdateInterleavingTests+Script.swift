import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization

/// The seeded scripts: the model the stores are held to, the calls, and how a script is drawn.
extension ProgramUpdateInterleavingTests {
    /// Thirty seeds whatever the lane sets: the scripts `scripts_holdEveryKindOfCall` vouches for. The first
    /// thirty of `PropertySeed.all`'s sequence.
    static let fixedSeeds = (0 ..< 30).map { PropertySeed(value: UInt64($0) &* 7919 &+ 17) }

    /// The thirty fixed scripts in the PR lane and on the host; every seed of `LEDGER_PROPERTY_SEED_COUNT` in
    /// the nightly one, and never fewer than the thirty (testing-strategy §6).
    static let seeds = TestLane.runsSlowTests && PropertySeed.all.count > fixedSeeds.count
        ? PropertySeed.all
        : fixedSeeds

    /// How many random calls a script holds after the save that opens it.
    static let length = 24

    /// The stored program as the calls applied one at a time leave it: no store, no rows, no lock.
    struct Model: Sendable {
        var program: Program
        var isDeleted = false

        /// What `active()` must answer.
        var active: Program? {
            isDeleted ? nil : program
        }

        /// What a workout's save writes into the program: the misses of the slots it lists, whole, and the
        /// exercise of the slots its swaps name. A slot the program no longer has is skipped.
        mutating func write(misses slots: [Slot], swaps: [SlotID: ExerciseID]) {
            guard !isDeleted else {
                return
            }
            for day in program.days.indices {
                for index in program.days[day].slots.indices {
                    let id = program.days[day].slots[index].id
                    if let written = slots.last(where: { $0.id == id }) {
                        program.days[day].slots[index].misses = written.misses
                    }
                    if let exercise = swaps[id] {
                        program.days[day].slots[index].exerciseID = exercise
                    }
                }
            }
        }
    }

    /// One call of a script: what it is, what the model makes of it and must hear in answer, and the call.
    struct Step: Sendable {
        let label: String
        let expect: @Sendable (inout Model) throws -> String
        let body: @Sendable (Side) async throws -> String
    }

    /// What concurrent updates saw, in the order a store took them.
    final class Taken: Sendable {
        let order = Mutex<[Int]>([])
    }

    /// A change that adds one to a number the program holds (its days a week), and tells `taken` the number
    /// it saw. It does some work between the read and the write, so that updates overlap wherever a store
    /// lets them: one that did would lose an update on any machine with two cores.
    static func counting(into taken: Taken) -> @Sendable (Program) throws -> Program {
        { stored in
            var changed = stored
            let seen = stored.daysPerWeek ?? 0
            taken.order.withLock { $0.append(seen) }
            _ = try JSONEncoder().encode(stored)
            changed.daysPerWeek = seen + 1
            return changed
        }
    }

    /// A program in a line: its name, whether it is active, its weeks (`d` for a deload), and each day as its
    /// tag, a `+` for each time it was renamed, and its slots: the end of the id, the sets, the end of the
    /// exercise's id and the misses.
    static func line(_ program: Program?) -> String {
        guard let program else {
            return "no program"
        }
        let weeks = program.weeks.map { $0.isDeload ? "d" : "w" }.joined()
        let days = program.days.map { day in
            let slots = day.slots.map { slot in
                let (id, exercise) = (
                    slot.id.rawValue.uuidString.suffix(2),
                    slot.exerciseID.rawValue.uuidString.suffix(1)
                )
                return "\(id)×\(slot.sets)e\(exercise)m\(slot.misses.sorted().map(String.init).joined())"
            }
            return "\(day.tag)\(day.name.filter { $0 == "+" })[\(slots.joined(separator: " "))]"
        }
        return "\(program.name) \(program.isActive ? "active" : "inactive") \(weeks) \(days.joined(separator: " "))"
    }

    static func threw(_ error: any Error) -> String {
        "threw \(error)"
    }

    /// The program every script opens with, active: four weeks, three days of three slots.
    static func opening() throws -> Program {
        try Seeders.program(number: 1, weeks: 4, days: 3, slotsPerDay: 3, exercises: Contract.exercises.map(\.id))
    }

    /// The first call of `seed`'s script after which a store's answer, or its program, is not the model's.
    static func firstMismatch(_ seed: PropertySeed) async throws -> String? {
        let (stored, faked) = try await (Stores.database.side(), Stores.inMemory.side())
        var model = try Model(program: opening(), isDeleted: true)
        for (index, step) in try script(seed).enumerated() {
            let expected = try step.expect(&model)
            for (name, side) in [("GRDB", stored), ("the fake", faked)] {
                let outcome = await side.outcome(step.body)
                guard outcome == expected else {
                    return "call \(index), \(step.label): \(name) answered \(outcome.prefix(200)), "
                        + "the calls in order \(expected.prefix(200))"
                }
                guard try await side.programs.active() == model.active else {
                    let held = try await line(side.programs.active())
                    return "call \(index), \(step.label): \(name) holds \(held), "
                        + "the calls in order \(line(model.active))"
                }
            }
        }
        return nil
    }

    /// How many of `seed`'s updates and workout saves meet a deleted program.
    static func callsOnADeletedProgram(_ seed: PropertySeed) throws -> Int {
        var model = try Model(program: opening(), isDeleted: true)
        return try script(seed).count { step in
            let wasDeleted = model.isDeleted
            _ = try step.expect(&model)
            return wasDeleted && !step.label.hasPrefix("save") && !step.label.hasPrefix("delete")
        }
    }

    /// `seed`'s script: the opening program saved whole, then `length` calls drawn at random.
    static func script(_ seed: PropertySeed) throws -> [Step] {
        var random = seed.generator
        let opening = try opening()
        var steps = [wholeSave(opening)]
        for index in 0 ..< length {
            switch Int.random(in: 0 ..< 100, using: &random) {
            case 0 ..< 44:
                let edit = edits[Int.random(in: 0 ..< edits.count, using: &random)]
                steps.append(update(opening.id, edit, index))
            case 44 ..< 58:
                let refusal = refusals[Int.random(in: 0 ..< refusals.count, using: &random)]
                steps.append(refused(opening, refusal))
            case 58 ..< 88: steps.append(workoutSave(of: opening, using: &random))
            case 88 ..< 94: steps.append(deletion(opening.id))
            default: steps.append(wholeSave(opening))
            }
        }
        return steps
    }

    /// The opening program saved whole, as a builder that kept its first copy would: it brings a deleted
    /// program back, and writes its copy over everything stored since.
    static func wholeSave(_ opening: Program) -> Step {
        Step(label: "save the opening program") { model in
            model = Model(program: opening)
            return "saved"
        } body: { side in
            try await side.programs.save(opening)
            return "saved"
        }
    }

    static func deletion(_ id: ProgramID) -> Step {
        Step(label: "delete") { model in
            model.isDeleted = true
            return "deleted"
        } body: { side in
            try await side.programs.delete(id)
            return "deleted"
        }
    }

    /// An update with a builder's edit: the model applies it to its program; a deleted program is missing.
    static func update(_ id: ProgramID, _ edit: Edit, _ index: Int) -> Step {
        let change: @Sendable (Program) throws -> Program = { try edit.change($0, index) }
        return Step(label: "update \(edit.name)") { model in
            guard !model.isDeleted else {
                return threw(RepositoryError.missingRow("program \(id.rawValue.uuidString)"))
            }
            model.program = try change(model.program)
            return "updated to \(line(model.program))"
        } body: { side in
            try await "updated to \(line(side.programs.update(id, change)))"
        }
    }

    /// An update the store must refuse, or whose change throws: the model stays as it is.
    static func refused(_ opening: Program, _ refusal: Refusal) -> Step {
        Step(label: "refused \(refusal.name)") { model in
            guard !model.isDeleted else {
                return threw(RepositoryError.missingRow("program \(opening.id.rawValue.uuidString)"))
            }
            return threw(refusal.error)
        } body: { side in
            try await "updated to \(line(side.programs.update(opening.id, refusal.change)))"
        }
    }

    /// A finished workout's save: up to two swaps and the misses of up to two slots, drawn from the slots the
    /// program opened with, which an update may have removed since.
    static func workoutSave(of opening: Program, using random: inout SeededGenerator) -> Step {
        let number = Int.random(in: 1 ... 3, using: &random)
        var workout = Seeders.workout(number: number, endedAt: EventBuilders.start.addingTimeInterval(3600), [
            Seeders.ExerciseLog(Contract.exercises[0], [.init(100, 5), .init(100, 5)])
        ])
        workout.source = WorkoutSource(programID: opening.id, weekIndex: 1, dayTemplateID: opening.days[0].id)
        let slots = opening.days.flatMap(\.slots)
        for _ in 0 ..< Int.random(in: 0 ... 2, using: &random) {
            let slot = slots[Int.random(in: 0 ..< slots.count, using: &random)]
            workout.programUpdates[slot.id] = Contract.exercises[Int.random(in: 0 ..< 6, using: &random)].id
        }
        let misses = (0 ..< Int.random(in: 0 ... 2, using: &random)).map { _ in
            var slot = slots[Int.random(in: 0 ..< slots.count, using: &random)]
            slot.misses = Set((0 ... 3).filter { _ in Bool.random(using: &random) })
            return slot
        }
        let saved = workout
        let label = "materialize \(number), \(saved.programUpdates.count) swaps, \(misses.count) misses"
        return Step(label: label) { model in
            model.write(misses: misses, swaps: saved.programUpdates)
            return "saved"
        } body: { side in
            try await side.workouts.materialize(saved, slotUpdates: misses)
            return "saved"
        }
    }
}
