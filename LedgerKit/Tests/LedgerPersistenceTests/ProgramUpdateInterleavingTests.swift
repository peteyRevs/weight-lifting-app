import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 criterion 7: a builder's edit and a finished workout's save both write into the program, and neither
/// may undo the other.
///
/// The suite opens with the sequence that loses (the builder reads; a workout is saved; the builder writes),
/// once through `save`, which is why `update` exists, and once through `update`. Then seeded scripts of
/// updates, workout saves, deletions and whole saves run on the GRDB stores and on LedgerFakes' linked ones:
/// after every call both must have answered, and must hold, what the calls applied one at a time in that
/// order give (`Model`). Last, updates and saves made at once from many tasks lose nothing.
@Suite("Program updates · interleaved with workout saves", .tags(.persistence, .property), .timeLimit(.minutes(1)))
struct ProgramUpdateInterleavingTests {
    typealias Contract = WorkoutRepositoryContract
    typealias Side = LinkedSaveDifferentialTests.Side

    /// The stores a case runs on: the GRDB ones over a fresh database, or the linked in-memory ones, each
    /// holding the contract's exercises.
    enum Stores: String, CaseIterable, Sendable, CustomStringConvertible {
        case database, inMemory

        var description: String {
            rawValue
        }

        func side() async throws -> Side {
            switch self {
            case .database:
                let stores = try await Repositories.withProgramExercises()
                return Side(workouts: stores.workouts, programs: stores.programs, events: stores.events)
            case .inMemory:
                let stores = try await InMemoryContractTests.stores()
                return Side(workouts: stores.workouts, programs: stores.programs, events: stores.events)
            }
        }
    }

    /// The losing sequence up to the builder's write: the program is saved and read, as a builder reads it
    /// when it opens, and then a workout of week 3 finishes with a miss on the first day's first slot, whose
    /// exercise it also swapped ("Also update program").
    struct Opened {
        let side: Side
        /// The program as the builder read it, before the workout's save.
        let copy: Program
        let slot: Slot
        let swapped: ExerciseID

        init(on stores: Stores) async throws {
            side = try await stores.side()
            let program = try ProgramRepositoryContract.program()
            try await side.programs.save(program)
            copy = try #require(await side.programs.active())
            slot = program.days[0].slots[0]
            swapped = Contract.replacement(for: slot)
            var workout = Contract.workout(of: program)
            workout.programUpdates = [slot.id: swapped]
            var missed = slot
            missed.misses.insert(2)
            try await side.workouts.materialize(workout, slotUpdates: [missed])
        }

        /// The builder's edit: week 6 becomes a deload, and the second day is renamed.
        static func edit(_ program: Program) -> Program {
            var edited = program
            edited.weeks[5].isDeload.toggle()
            edited.days[1].name = "Pull, edited"
            return edited
        }

        /// The first day's first slot as stored now, and whether the builder's edit is stored.
        func stored() async throws -> (slot: Slot, isEdited: Bool) {
            let program = try #require(await side.programs.active())
            return (program.days[0].slots[0], program.weeks[5].isDeload && program.days[1].name == "Pull, edited")
        }
    }

    @Test(
        "Why update exists: a builder's copy saved whole after a workout's save loses the save's miss and swap",
        arguments: Stores.allCases
    )
    func wholeSave_afterAWorkoutsSave_losesItsMissAndItsSwap(stores: Stores) async throws {
        let opened = try await Opened(on: stores)
        try await opened.side.programs.save(Opened.edit(opened.copy))
        let stored = try await opened.stored()
        #expect(stored.isEdited)
        // Gone, silently: next week's load now goes up where it should hold, and the old exercise is back.
        #expect(stored.slot.misses == opened.slot.misses)
        #expect(stored.slot.misses.contains(2) == false)
        #expect(stored.slot.exerciseID == opened.slot.exerciseID)
    }

    @Test(
        "The same edit sent through update keeps the workout's miss and its swap, and is stored",
        arguments: Stores.allCases
    )
    func update_afterAWorkoutsSave_keepsItsMissAndItsSwap(stores: Stores) async throws {
        let opened = try await Opened(on: stores)
        let returned = try await opened.side.programs.update(opened.copy.id, Opened.edit)
        let stored = try await opened.stored()
        #expect(stored.isEdited)
        #expect(stored.slot.misses == opened.slot.misses.union([2]))
        #expect(stored.slot.exerciseID == opened.swapped)
        #expect(returned.days[0].slots[0].misses == stored.slot.misses)
        #expect(returned.days[0].slots[0].exerciseID == opened.swapped)
    }

    @Test(
        "Seeded updates, workout saves, deletions and whole saves: both stores hold the calls applied in order",
        arguments: seeds
    )
    func interleavedCalls_matchTheCallsAppliedInOrder(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstMismatch(seed)
        #expect(mismatch == nil, "\(seed): \(mismatch ?? "")")
    }

    @Test("Thirty scripts hold every kind of call, every edit and every refusal, also on a deleted program")
    func scripts_holdEveryKindOfCall() throws {
        let labels = try Self.fixedSeeds.flatMap { try Self.script($0).map(\.label) }
        let kinds = Set(labels.map { String($0.prefix { $0 != " " }) })
        #expect(kinds == ["save", "update", "refused", "materialize", "delete"])
        for name in Self.edits.map(\.name) + Self.refusals.map(\.name) {
            #expect(labels.contains { $0.hasSuffix(" \(name)") }, "no script holds \(name)")
        }
        #expect(labels.contains { $0.contains("2 swaps") } && labels.contains { $0.contains("2 misses") })
        let afterDelete = try Self.fixedSeeds.reduce(0) { try $0 + Self.callsOnADeletedProgram($1) }
        #expect(afterDelete > 10)
    }

    /// Each update adds one to a number the program holds. Had an update read the program before another's
    /// write and written after it, two would have seen the same number, and the last would be short.
    @Test(
        "Two hundred updates and eight workout saves made at once lose nothing, and each update saw the one before",
        arguments: Stores.allCases
    )
    func concurrentUpdatesAndSaves_loseNothing(stores: Stores) async throws {
        let side = try await stores.side()
        let program = try ProgramRepositoryContract.program()
        try await side.programs.save(program)
        let slots = program.days.flatMap(\.slots)
        let taken = Taken()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 200 {
                group.addTask { _ = try await side.programs.update(program.id, Self.counting(into: taken)) }
            }
            for number in 0 ..< 8 {
                group.addTask {
                    // Each save writes a slot of its own, so the saves' own order is no matter.
                    var workout = Contract.workout(of: program, number: number + 1)
                    workout.programUpdates = [slots[number].id: Contract.replacement(for: slots[number])]
                    var missed = slots[number]
                    missed.misses = [6, 7]
                    try await side.workouts.materialize(workout, slotUpdates: [missed])
                }
            }
            try await group.waitForAll()
        }
        let first = program.daysPerWeek ?? 0
        var expected = program
        expected.daysPerWeek = first + 200
        let saved = Set(slots.prefix(8).map(\.id))
        for day in expected.days.indices {
            for index in expected.days[day].slots.indices where saved.contains(expected.days[day].slots[index].id) {
                expected.days[day].slots[index].exerciseID = Contract.replacement(for: expected.days[day].slots[index])
                expected.days[day].slots[index].misses = [6, 7]
            }
        }
        let stored = try #require(await side.programs.active())
        // In the order the store took them, each update saw what the one before it wrote.
        let sawEachBefore = taken.order.withLock { $0 } == Array(first ..< first + 200)
        #expect(sawEachBefore)
        #expect(stored.daysPerWeek == first + 200)
        let isExpected = stored == expected
        #expect(isExpected, "\(stored.difference(from: expected) ?? "")")
        #expect(try await side.workouts.recent(limit: 20).count == 8)
    }
}
