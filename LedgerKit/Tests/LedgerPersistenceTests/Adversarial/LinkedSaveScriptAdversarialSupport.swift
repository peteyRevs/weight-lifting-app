import Foundation
import LedgerDomain
import LedgerTestSupport

/// One step of a seeded script of saves (F10 S3 adversarial round 1).
enum LinkedStep: CustomStringConvertible {
    /// A log of `count` envelopes for workout `number`, as its host left it.
    case log(Int, count: Int)
    case save(WorkoutState, slots: [Slot], droppingLog: Bool)
    case deleteProgram(Int)
    /// The program is saved again as the fixture builds it: it comes back, or loses the changes made to it.
    case restoreProgram(Int)
    /// The program is saved without one of its slots.
    case removeSlot(program: Int, day: Int, slot: Int)

    var description: String {
        switch self {
        case let .log(number, count):
            return "log \(count) of workout \(number)"
        case let .save(workout, slots, droppingLog):
            let updates = workout.programUpdates
                .map { "\(LinkedDifference.name($0.key))→\(LinkedDifference.name($0.value))" }
            let program = workout.source.map { LinkedDifference.name($0.programID) } ?? "none"
            return "save \(workout.tag) of program \(program), updates \(updates.sorted()), "
                + "misses for \(slots.map { LinkedDifference.name($0.id) }), droppingLog \(droppingLog)"
        case let .deleteProgram(number): return "delete program \(number)"
        case let .restoreProgram(number): return "save program \(number) as built"
        case let .removeSlot(program, day, slot): return "program \(program) loses slot \(slot) of day \(day)"
        }
    }
}

/// Writes a script step by step: saves of new workouts and of ones saved before, of either program or none,
/// with updates and misses drawn from slots that are stored, another program's, removed or never there, and
/// exercises that are stored, not stored or already the slot's; and, between them, the program edits that
/// make a slot go away.
struct LinkedScriptWriter {
    var random: SeededGenerator
    private var saved: [Int] = []
    private var next = 0

    init(seed: UInt64) {
        random = SeededGenerator(seed: seed)
    }

    mutating func step() throws -> LinkedStep {
        switch Int.random(in: 0 ..< 20, using: &random) {
        case 0 ..< 3: .log(
                Int.random(in: max(1, next - 2) ... next + 1, using: &random),
                count: Int.random(in: 1 ... 6, using: &random)
            )
        case 3: .deleteProgram(Int.random(in: 1 ... 2, using: &random))
        case 4, 5: .restoreProgram(Int.random(in: 1 ... 2, using: &random))
        case 6: .removeSlot(
                program: Int.random(in: 1 ... 2, using: &random),
                day: Int.random(in: 0 ... 1, using: &random),
                slot: 0
            )
        default: try save()
        }
    }

    private mutating func save() throws -> LinkedStep {
        // One save in four is of a workout saved before: as it was, or asking for something else.
        let again = saved.randomElement(using: &random)
        let number: Int
        if let again, Int.random(in: 0 ..< 4, using: &random) == 0 {
            number = again
        } else {
            next += 1
            number = next
            saved.append(number)
        }
        let program = [1, 1, 1, 2, nil][Int.random(in: 0 ..< 5, using: &random)]
        var updates: [SlotID: ExerciseID] = [:]
        for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
            let slot = try slot()
            updates[slot.id] = exercise(for: slot)
        }
        var slots: [Slot] = []
        for _ in 0 ..< Int.random(in: 0 ... 2, using: &random) {
            let misses = Set((0 ..< 3).filter { _ in Bool.random(using: &random) })
            try slots.append(LinkedFixture.missing(slot(), misses))
        }
        let workout = LinkedFixture.workout(number, ofProgram: program, updates: updates)
        return .save(workout, slots: slots, droppingLog: Bool.random(using: &random))
    }

    /// A slot of either program as built, or one no program ever held.
    private mutating func slot() throws -> Slot {
        let index = Int.random(in: 0 ..< 13, using: &random)
        guard index < 12 else {
            var stranger = try LinkedFixture.slot(0)
            stranger = try Slot(
                id: LinkedFixture.unknownSlot, exerciseID: stranger.exerciseID, sets: 3, reps: 5, repsHi: 8,
                rpe: 8, restSeconds: 90, progression: .linear
            )
            return stranger
        }
        return try LinkedFixture.slot(index % 6, of: 1 + index / 6)
    }

    /// A stored exercise, the one the slot was built with, or one no store holds.
    private mutating func exercise(for slot: Slot) -> ExerciseID {
        switch Int.random(in: 0 ..< 8, using: &random) {
        case 0: LinkedFixture.unknownExercise
        case 1: slot.exerciseID
        default: LinkedFixture.exercises[Int.random(in: 0 ..< LinkedFixture.exercises.count, using: &random)].id
        }
    }
}

/// Runs a script on the database and on the fakes at once, and on the model.
struct LinkedScriptRun {
    let database: LinkedStores
    let memory: LinkedStores
    var model: LinkedModel
    private(set) var trace: [String] = []

    init() async throws {
        database = try await LinkedStores.make(.database)
        memory = try await LinkedStores.make(.memory)
        model = try LinkedModel(programs: [LinkedFixture.program(1), LinkedFixture.program(2)])
    }

    /// `nil` when, through the script of `seed`, the two kinds of store answered alike and held the same,
    /// and the database held what the model holds; else the first difference and the steps before it.
    static func difference(seed: UInt64, steps: Int = 30) async throws -> String? {
        var run = try await LinkedScriptRun()
        var writer = LinkedScriptWriter(seed: seed)
        for index in 0 ..< steps {
            let step = try writer.step()
            run.trace.append("\(index): \(step)")
            if let issue = try await run.take(step) {
                return "\(issue)\n  after: \(run.trace.suffix(8).joined(separator: "\n         "))"
            }
        }
        return nil
    }

    private mutating func take(_ step: LinkedStep) async throws -> String? {
        var answers: [String] = []
        for stores in [database, memory] {
            try await answers.append(Self.perform(step, on: stores, model: model))
            stores.clock.advance()
        }
        guard answers[0] == answers[1] else {
            return "the database answered \(answers[0].prefix(90)), the fakes \(answers[1].prefix(90))"
        }
        if let expected = try note(step, answered: answers[0]), expected != answers[0] {
            return "a save answered \(answers[0].prefix(90)), the model says \(expected)"
        }
        if let issue = try await LinkedComparison.difference(database, memory) {
            return issue
        }
        return try await model.difference(from: database)
    }

    /// How `step` ended on `stores`: what a save answered, "done", or the error.
    private static func perform(
        _ step: LinkedStep,
        on stores: LinkedStores,
        model: LinkedModel
    ) async throws -> String {
        do {
            switch step {
            case let .log(number, count):
                _ = try await stores.events.append(LinkedFixture.log(of: LinkedFixture.workout(number), count: count))
            case let .save(workout, slots, droppingLog):
                return await stores.save(workout, slots: slots, droppingLog: droppingLog)
            case let .deleteProgram(number):
                try await stores.programs.delete(S2Kit.programID(number))
            case let .restoreProgram(number):
                try await stores.programs.save(LinkedFixture.program(number))
            case let .removeSlot(program, day, slot):
                if let edited = removing(slot, ofDay: day, from: model.programs[S2Kit.programID(program)]) {
                    try await stores.programs.save(edited)
                }
            }
            return "done"
        } catch {
            return "\(error)"
        }
    }

    static func removing(_ slot: Int, ofDay day: Int, from program: Program?) -> Program? {
        guard var edited = program, edited.days[day].slots.count > 1 else {
            return nil
        }
        edited.days[day].slots.remove(at: slot)
        return edited
    }

    /// Brings the model up to date with a step both stores took alike. For a save, what it must have answered.
    private mutating func note(_ step: LinkedStep, answered: String) throws -> String? {
        switch step {
        case let .log(number, count):
            let workout = LinkedFixture.workout(number).id
            model.logs[workout] = max(model.logs[workout] ?? 0, count)
        case let .save(workout, slots, droppingLog):
            return "\(model.save(workout, slots: slots, droppingLog: droppingLog))"
        case let .deleteProgram(number):
            model.programs[S2Kit.programID(number)] = nil
        case let .restoreProgram(number) where answered == "done":
            model.programs[S2Kit.programID(number)] = try LinkedFixture.program(number)
        case let .removeSlot(program, day, slot) where answered == "done":
            let id = S2Kit.programID(program)
            model.programs[id] = Self.removing(slot, ofDay: day, from: model.programs[id]) ?? model.programs[id]
        case .restoreProgram, .removeSlot:
            break
        }
        return nil
    }
}
