import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 adversarial round 1, criterion 7 as a model: seeded scripts of updates, workout saves, a builder's
/// stale whole saves, deletions and activations, taken one at a time. After every call the database and the
/// in-memory stores must each hold what `UpdateModel` holds, which knows programs as values and nothing of rows.
@Suite("Adversarial F11 S3 · updates against a model", .tags(.persistence, .property), .timeLimit(.minutes(2)))
struct ProgramUpdateModelAdversarialTests {
    typealias Place = UpdateKit.Place

    @Test(
        "After every call of a seeded script the store holds what the model holds",
        arguments: [Place.database, .memory],
        PropertySeed.all.prefix(40)
    )
    func script_everyStep_matchesTheModel(place: Place, seed: PropertySeed) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        var script = try UpdateScript(seed: seed.value)
        var issue: String?
        for step in 0 ..< 36 where issue == nil {
            issue = try await script.step(step, on: stores)
        }
        #expect(issue == nil, "\(place), \(seed): \(issue ?? "")")
    }

    @Test("The scripts reach every kind of call, a refusal, a missing program and a stale save over a workout's")
    func scripts_reachEveryCase() async throws {
        var reached: Set<String> = []
        for seed in PropertySeed.all.prefix(40) {
            let stores = try await LinkedStores.make(.memory)
            var script = try UpdateScript(seed: seed.value)
            for step in 0 ..< 36 {
                _ = try await script.step(step, on: stores)
            }
            reached.formUnion(script.reached)
        }
        let wanted = Set(UpdateScript.Edit.allCases.map { "update \($0) stored" } + [
            "update threw", "update refused", "update missing", "workout", "stale save", "delete", "activate"
        ])
        #expect(wanted.subtracting(reached).isEmpty, "never reached: \(wanted.subtracting(reached).sorted())")
    }
}

/// The programs a store holds, as values: what each call of `ProgramRepository` and a workout's save leave,
/// written from the protocols' doc comments and F11 S3's criteria.
struct UpdateModel {
    var programs: [ProgramID: Program]
    let exercises = Set(LinkedFixture.exercises.map(\.id))

    mutating func save(_ program: Program) {
        if program.isActive {
            for id in programs.keys {
                programs[id]?.isActive = false
            }
        }
        programs[program.id] = program
    }

    /// `false` when the program is not stored.
    mutating func activate(_ id: ProgramID) -> Bool {
        guard programs[id] != nil else {
            return false
        }
        for other in programs.keys {
            programs[other]?.isActive = other == id
        }
        return true
    }

    /// A workout's save: the listed misses for a stored slot, whole; the swap for a stored slot of its own
    /// program, when the exercise is stored.
    mutating func workout(of own: ProgramID, slot: SlotID, misses: Set<Int>, exercise: ExerciseID) {
        for (id, program) in programs {
            programs[id] = program.changing(slot) { $0.misses = misses }
        }
        if exercises.contains(exercise), let program = programs[own] {
            programs[own] = program.changing(slot) { $0.exerciseID = exercise }
        }
    }
}

/// One seeded script and the model it keeps.
struct UpdateScript {
    typealias Fixture = LinkedFixture

    /// The builder's edits, each safe on whatever the program has become.
    enum Edit: String, CaseIterable {
        case rename, deload, sets, removeSlot, addSlot, miss, reorder, activity, restoreSlots
    }

    var random: SeededGenerator
    var model: UpdateModel
    /// Copies a builder read earlier, to save whole later.
    var copies: [ProgramID: Program] = [:]
    let slots: [[SlotID]]
    var reached: Set<String> = []

    init(seed: UInt64) throws {
        random = SeededGenerator(seed: seed)
        let programs = try [Fixture.program(1), Fixture.program(2)]
        model = UpdateModel(programs: Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) }))
        slots = programs.map(\.slotIDs)
    }

    static func apply(_ edit: Edit, _ step: Int, to program: Program) throws -> Program {
        var changed = program
        switch edit {
        case .rename:
            changed.name += "r\(step)"
        case .deload:
            changed.weeks[step % changed.weeks.count].isDeload.toggle()
        case .activity:
            changed.isActive.toggle()
        case .sets, .removeSlot, .addSlot, .miss, .reorder, .restoreSlots:
            try applyToSlots(edit, step, of: &changed)
        }
        return changed
    }

    private static func applyToSlots(_ edit: Edit, _ step: Int, of changed: inout Program) throws {
        let (first, last) = (changed.days[0].slots.indices.first, changed.days[1].slots.indices.last)
        switch edit {
        case .sets:
            if let first {
                changed.days[0].slots[first].sets = 1 + step % 12
            }
        case .removeSlot:
            _ = changed.days[1].slots.popLast()
        case .addSlot:
            try changed.days[step % 2].slots.append(S2Kit.slot(9000 + step, exercise: step % 8))
        case .miss:
            if let last {
                changed.days[1].slots[last].misses.formSymmetricDifference([step % 3])
            }
        case .reorder:
            changed.days[0].slots.reverse()
        default:
            // Brings back the fixture's slots of the second day that were removed, as they were at first.
            let held = changed.slotIDs
            let fixture = try Fixture.program(changed.id == UpdateKit.one ? 1 : 2).days[1].slots
            changed.days[1].slots += fixture.filter { slot in !held.contains(slot.id) }
        }
    }

    /// Takes step `step` on the stores and on the model; the first thing that then differs, if any.
    mutating func step(_ step: Int, on stores: LinkedStores) async throws -> String? {
        let number = Int.random(in: 1 ... 2, using: &random)
        let id = S2Kit.programID(number)
        var said: String?
        switch Int.random(in: 0 ..< 12, using: &random) {
        case 0 ... 4:
            said = try await update(id, step, on: stores)
        case 5 ... 7:
            said = try await workout(step, ofProgram: number, on: stores)
        case 8:
            copies[id] = model.programs[id] ?? copies[id]
        case 9:
            if let copy = copies[id] {
                try await stores.programs.save(copy)
                model.save(copy)
                reached.insert("stale save")
            }
        case 10:
            try await stores.programs.delete(id)
            model.programs[id] = nil
            reached.insert("delete")
        default:
            let isStored = model.activate(id)
            var outcome = "stored"
            do {
                try await stores.programs.setActive(id)
            } catch {
                outcome = "\(error)"
            }
            said = (outcome == "stored") == isStored ? nil : "step \(step): setActive answered \(outcome.prefix(80))"
            reached.insert("activate")
        }
        if let said {
            return said
        }
        return try await difference(from: stores).map { "step \(step): \($0)" }
    }

    /// A finished workout of program `number` that lists misses for one fixture slot of either program and asks
    /// for an exercise, stored or not, on it.
    private mutating func workout(_ step: Int, ofProgram number: Int, on stores: LinkedStores) async throws -> String? {
        let slot = slots[Int.random(in: 0 ... 1, using: &random)][Int.random(in: 0 ..< 6, using: &random)]
        let misses = Set([0, 1, 2].filter { _ in Bool.random(using: &random) })
        let choice = Int.random(in: 0 ... 8, using: &random)
        let exercise = choice == 8 ? Fixture.unknownExercise : Fixture.exercises[choice].id
        let workout = Fixture.workout(step + 1, ofProgram: number, updates: [slot: exercise])
        let listed = try Self.slot(slot, like: Fixture.slot(0).with(misses: misses))
        let outcome = await stores.save(workout, slots: [listed], droppingLog: false)
        model.workout(of: S2Kit.programID(number), slot: slot, misses: misses, exercise: exercise)
        reached.insert("workout")
        return outcome == "false" ? nil : "step \(step): a workout's save answered \(outcome.prefix(80))"
    }

    /// A slot with `id` and the misses and other fields of `slot`.
    static func slot(_ id: SlotID, like slot: Slot) throws -> Slot {
        try Slot(
            id: id, exerciseID: slot.exerciseID, sets: slot.sets, reps: slot.reps, repsHi: slot.repsHi,
            rpe: slot.rpe.value, restSeconds: slot.rest.seconds, progression: slot.progression, misses: slot.misses
        )
    }

    /// One update: a change that throws (kind 0), a result of no weeks (kind 1), or an edit.
    private mutating func update(_ id: ProgramID, _ step: Int, on stores: LinkedStores) async throws -> String? {
        let kind = Int.random(in: 0 ..< 10, using: &random)
        let edit = Edit.allCases[Int.random(in: 0 ..< Edit.allCases.count, using: &random)]
        var returned: Program?
        var outcome = "stored"
        do {
            returned = try await stores.programs.update(id) { program in
                if kind == 0 {
                    throw UpdateKit.Thrown(code: step)
                }
                let empty = UpdateRefusal.changed(program) { $0.weeks = [] }
                return try kind == 1 ? empty : Self.apply(edit, step, to: program)
            }
        } catch {
            outcome = "\(error)"
        }
        guard let stored = model.programs[id] else {
            reached.insert("update missing")
            let expected = "\(RepositoryError.missingRow("program \(ColumnCodec.text(id))"))"
            return outcome == expected ? nil : "step \(step): update of a missing program gave \(outcome.prefix(80))"
        }
        guard kind > 1 else {
            reached.insert(kind == 0 ? "update threw" : "update refused")
            let isRight = kind == 0 ? outcome == "\(UpdateKit.Thrown(code: step))" : outcome != "stored"
            return isRight ? nil : "step \(step): a change that \(kind == 0 ? "threw" : "left no week") gave \(outcome)"
        }
        try model.save(Self.apply(edit, step, to: stored))
        reached.insert("update \(edit) stored")
        let isTheModel = returned == model.programs[id]
        return isTheModel ? nil : "step \(step): update(\(edit)) gave \(outcome.prefix(60)) or returned another program"
    }

    func difference(from stores: LinkedStores) async throws -> String? {
        for number in [1, 2] {
            let stored = try await UpdateKit.read(stores, number)
            let expected = model.programs[S2Kit.programID(number)]
            if stored != expected {
                let line = LinkedDifference.of(stored, expected, "program \(number)")
                return line ?? "program \(number) is \(stored?.isActive == true ? "active" : "inactive"), not the model"
            }
        }
        let active = try await stores.programs.active()?.id
        return active == model.programs.values.first(where: \.isActive)?.id ? nil : "another program is active"
    }
}
