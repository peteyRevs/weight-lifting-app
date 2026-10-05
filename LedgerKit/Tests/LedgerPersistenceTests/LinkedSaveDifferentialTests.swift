import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 criterion 6: LedgerFakes' linked stores against the GRDB ones, over seeded random scripts of the
/// saves this slice changed. A script materialises workouts whose program updates name slots of their own
/// program, of the other one, slots a save has dropped and slots no program holds, with stored and unknown
/// exercises, with misses, with the log dropped or kept, and sometimes refused; between them it saves, deletes
/// and activates the two programs, appends to the logs and compacts them.
///
/// After every step both stores must have thrown the same error or answered the same, and the active program,
/// the recent workouts and every log must agree; at the end both programs are read, activated in turn. The
/// contract's linked clauses pin the rules by name; this looks where they are silent.
@Suite("In-memory stores · linked saves against GRDB", .tags(.persistence, .property), .timeLimit(.minutes(1)))
struct LinkedSaveDifferentialTests {
    typealias Contract = WorkoutRepositoryContract

    /// Thirty seeds whatever the lane sets: the scripts `scripts_holdEveryKindOfStep` vouches for, which must
    /// not depend on how many seeds a run was given. The first thirty of `PropertySeed.all`'s sequence.
    static let fixedSeeds = (0 ..< 30).map { PropertySeed(value: UInt64($0) &* 7919 &+ 17) }

    /// The thirty fixed scripts in the PR lane and on the host; every seed of `LEDGER_PROPERTY_SEED_COUNT` in
    /// the nightly one, and never fewer than the thirty.
    static let seeds = TestLane.runsSlowTests && PropertySeed.all.count > fixedSeeds.count
        ? PropertySeed.all
        : fixedSeeds

    /// How many random steps a script holds, between the two saves that open it and the two reads that end it.
    static let length = 18

    /// The first step of `seed`'s script at which the two sides differ, or `nil`.
    static func firstMismatch(_ seed: PropertySeed) async throws -> String? {
        let repositories = try await Repositories.withProgramExercises()
        let fakes = try await InMemoryContractTests.stores()
        let stored = Side(workouts: repositories.workouts, programs: repositories.programs, events: repositories.events)
        let faked = Side(workouts: fakes.workouts, programs: fakes.programs, events: fakes.events)
        for (index, step) in try script(seed).enumerated() {
            repositories.clock.advance()
            let outcomes = await (stored.outcome(step.body), faked.outcome(step.body))
            guard outcomes.0 == outcomes.1 else {
                return "step \(index), \(step.label): GRDB \(outcomes.0.prefix(120)), fake \(outcomes.1.prefix(120))"
            }
            let readings = try await (stored.reading(), faked.reading())
            if let line = zip(readings.0, readings.1).first(where: { $0 != $1 }) {
                return "step \(index), \(step.label): GRDB \(line.0.prefix(160)), fake \(line.1.prefix(160))"
            }
        }
        return nil
    }

    @Test(
        "Random saves with program updates, misses and dropped logs: the fake answers and reads as GRDB does",
        arguments: seeds
    )
    func linkedSaves_fakeMatchesGRDB(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstMismatch(seed)
        #expect(mismatch == nil, "\(seed): \(mismatch ?? "")")
    }

    @Test("Thirty scripts hold every kind of step: saves that drop a log and that keep it, of every kind of workout")
    func scripts_holdEveryKindOfStep() throws {
        let labels = try Self.fixedSeeds.flatMap { try Self.script($0).map(\.label) }
        let kinds = Set(labels.map { String($0.prefix { $0 != " " }) })
        #expect(kinds == ["materialize", "append", "save", "delete", "setActive", "compact"])
        #expect(labels.contains { $0.hasSuffix("dropping true") } && labels.contains { $0.hasSuffix("dropping false") })
        #expect(labels.contains { $0.contains(" ad hoc, ") } && labels.contains { $0.contains("3 updates") })
        #expect(labels.contains { $0.contains(" refused") } && labels.contains { $0.contains("2 misses") })
    }
}

/// The two sides, and a script's steps.
extension LinkedSaveDifferentialTests {
    /// The stores of one side: the GRDB ones over a fresh database, or the linked in-memory ones.
    struct Side: Sendable {
        let workouts: any WorkoutRepository
        let programs: any ProgramRepository
        let events: any WorkoutEventStore

        /// What `body` answered, or the error it threw, as text: the two sides must give the same.
        func outcome(_ body: (Side) async throws -> String) async -> String {
            do {
                return try await body(self)
            } catch {
                return "threw \(error)"
            }
        }

        /// The active program, the recent workouts and the three logs, each as a short line.
        func reading() async throws -> [String] {
            let active = try await programs.active()
            let slots = active?.days.flatMap(\.slots) ?? []
            let recent = try await workouts.recent(limit: 10)
            var lines = [
                "active \(active?.name ?? "none"), \(slots.count) slots",
                "exercises \(slots.map { $0.exerciseID.rawValue.uuidString.suffix(4) }.joined(separator: " "))",
                "misses \(slots.map { $0.misses.sorted() })",
                "recent \(recent.map(\.name)), \(recent.map(\.doneSets))"
            ]
            for number in 1 ... 3 {
                let log = try await events.envelopes(for: Seeders.workoutID(number))
                lines.append("log \(number): \(log.map(\.seq).sorted())")
            }
            return lines
        }
    }

    /// One step of a script: what it is, and what it does to a side and answers.
    struct Step: Sendable {
        let label: String
        let body: @Sendable (Side) async throws -> String
    }

    /// The two programs of every script, the first active: two days of two slots each.
    static func programs() throws -> [Program] {
        let exercises = Contract.exercises.map(\.id)
        return try [
            Seeders.program(number: 1, weeks: 3, days: 2, slotsPerDay: 2, exercises: exercises),
            Seeders.program(number: 2, weeks: 3, days: 2, slotsPerDay: 2, exercises: exercises, isActive: false)
        ]
    }

    /// `seed`'s script: both programs saved, `length` random steps, and each program activated, which is the
    /// one way the protocol shows a program.
    static func script(_ seed: PropertySeed) throws -> [Step] {
        var random = seed.generator
        let programs = try programs()
        var steps = programs.map { program in
            Step(label: "save \(program.name)") { side in
                try await side.programs.save(program)
                return "saved"
            }
        }
        for index in 0 ..< length {
            let number = Int.random(in: 1 ... 3, using: &random)
            switch Int.random(in: 0 ..< 100, using: &random) {
            case 0 ..< 50: steps.append(materialisation(number, programs, using: &random))
            case 50 ..< 66: steps.append(logStep(number, seq: UInt64(1 + 2 * index), using: &random))
            default: steps.append(programStep(programs, using: &random))
            }
        }
        return steps + programs.map { program in
            Step(label: "setActive \(program.name), at the end") { side in
                try await side.programs.setActive(program.id)
                return "active"
            }
        }
    }

    /// A save of workout `number`: of either program, of none or of one that is not stored; its program updates
    /// and misses drawn from both programs' slots as first saved, and from no program; one in six refused.
    static func materialisation(_ number: Int, _ programs: [Program], using random: inout SeededGenerator) -> Step {
        let end = EventBuilders.start.addingTimeInterval(3600 * Double(number))
        var workout = Seeders.workout(number: number, endedAt: end, [
            Seeders.ExerciseLog(Contract.exercises[0], [.init(100, 5), .init(100, 5)])
        ])
        let unstored = ProgramID(EventBuilders.uuid(9))
        let owners: [(String, ProgramID?)] = [
            (programs[0].name, programs[0].id), (programs[0].name, programs[0].id), (programs[1].name, programs[1].id),
            ("ad hoc", nil), ("an unstored program", unstored)
        ]
        let owner = owners[Int.random(in: 0 ..< owners.count, using: &random)]
        workout.source = owner.1.map {
            WorkoutSource(programID: $0, weekIndex: 1, dayTemplateID: programs[0].days[0].id)
        }
        let slots = programs.flatMap(\.days).flatMap(\.slots)
        let exercises = Contract.exercises.map(\.id) + [ExerciseID(EventBuilders.uuid(0x404))]
        for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
            let slot = Int.random(in: 0 ... slots.count, using: &random) // one past the end: a slot of no program
            let id = slot < slots.count ? slots[slot].id : SlotID(EventBuilders.uuid(0x73))
            workout.programUpdates[id] = exercises[Int.random(in: 0 ..< exercises.count, using: &random)]
        }
        let misses = (0 ..< Int.random(in: 0 ... 2, using: &random)).map { _ in
            var slot = slots[Int.random(in: 0 ..< slots.count, using: &random)]
            slot.misses = Set((0 ... 3).filter { _ in Bool.random(using: &random) })
            return slot
        }
        let fault = Int.random(in: 0 ..< 12, using: &random)
        if fault == 0 {
            workout.exercises[0].name += "\u{0}"
        } else if fault == 1 {
            workout.phase = .live
        }
        let dropping = Bool.random(using: &random)
        let saved = workout
        let label = "materialize \(number) of \(owner.0), \(saved.programUpdates.count) updates, "
            + "\(misses.count) misses,\(fault < 2 ? " refused," : "") dropping \(dropping)"
        return Step(label: label) { side in
            let dropped = try await side.workouts.materialize(saved, slotUpdates: misses, droppingLog: dropping)
            return "saved, log dropped: \(dropped)"
        }
    }

    /// An append of two envelopes to the log of workout `number`, at `seq` and the next, or its compaction.
    static func logStep(_ number: Int, seq: UInt64, using random: inout SeededGenerator) -> Step {
        let workout = Seeders.workoutID(number)
        guard Int.random(in: 0 ..< 4, using: &random) > 0 else {
            return Step(label: "compact \(number)") { side in
                try await side.events.compact(workout: workout)
                return "compacted"
            }
        }
        let log = EventBuilders.log(from: [.restSkipped, .restSkipped], firstSeq: seq, workoutID: workout)
        return Step(label: "append to \(number)") { side in
            let fresh = try await side.events.append(log)
            return "appended \(fresh.count)"
        }
    }

    /// A save of one of the programs, with its last slot of the first day dropped or not, its deletion, or its
    /// activation.
    static func programStep(_ programs: [Program], using random: inout SeededGenerator) -> Step {
        let program = programs[Int.random(in: 0 ... 1, using: &random)]
        switch Int.random(in: 0 ..< 5, using: &random) {
        case 0 ..< 2:
            var saved = program
            let dropping = Bool.random(using: &random)
            if dropping {
                saved.days[0].slots.removeLast()
            }
            saved.isActive = Bool.random(using: &random)
            let written = saved
            return Step(label: "save \(program.name), dropping \(dropping), active \(written.isActive)") { side in
                try await side.programs.save(written)
                return "saved"
            }
        case 2:
            return Step(label: "delete \(program.name)") { side in
                try await side.programs.delete(program.id)
                return "deleted"
            }
        default:
            return Step(label: "setActive \(program.name)") { side in
                try await side.programs.setActive(program.id)
                return "active"
            }
        }
    }
}
