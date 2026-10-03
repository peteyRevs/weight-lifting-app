import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: LedgerFakes' program and exercise repositories against the GRDB ones over seeded
/// random scripts: builder edits, ids another program holds or held, U+0000, deletes and activations; catalog
/// seeds and upgrades at random versions, clashing names and saves. Outcomes and reads must agree at every step.
@Suite(
    "Adversarial F07 S1 · program and exercise fakes against GRDB",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct FakesCatalogDifferentialAdversarialTests {
    typealias History = HistoryModelAdversarialTests
    typealias Action = @Sendable (any ProgramRepository) async throws -> Void

    static let seeds = Array(PropertySeed.all.prefix(60))

    /// The ids program 1 holds or has held, for program 2 to try to take.
    struct Held {
        var slots: [SlotID] = []
        var days: [DayTemplateID] = []
        var weeks: [WeekID] = []

        mutating func add(_ program: Program) {
            slots = Array(Set(slots + program.days.flatMap(\.slots).map(\.id)))
                .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            days = Array(Set(days + program.days.map(\.id))).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            weeks = Array(Set(weeks + program.weeks.map(\.id)))
                .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        }
    }

    /// `program` with one of its slot, day or week ids replaced by one `held` names.
    static func stealing(into program: Program, _ held: Held, using random: inout SeededGenerator) throws -> Program {
        var days = program.days
        var weeks = program.weeks
        switch Int.random(in: 0 ... 2, using: &random) {
        case 0:
            let slot = days[0].slots[0]
            days[0].slots[0] = try Slot(
                id: held.slots[Int.random(in: 0 ..< held.slots.count, using: &random)],
                exerciseID: slot.exerciseID, sets: slot.sets, reps: slot.reps, repsHi: slot.repsHi,
                rpe: slot.rpe.value, restSeconds: slot.rest.seconds, progression: slot.progression,
                startLoad: slot.startLoad, step: slot.step, isSupersetWithPrevious: slot.isSupersetWithPrevious,
                dropSets: slot.dropSets, misses: slot.misses
            )
        case 1:
            let (old, id) = (days[0].id, held.days[Int.random(in: 0 ..< held.days.count, using: &random)])
            days[0] = DayTemplate(id: id, name: days[0].name, tag: days[0].tag, slots: days[0].slots)
            weeks = weeks.map { week in
                Week(id: week.id, index: week.index, isDeload: week.isDeload, schedule: week.schedule.mapValues {
                    $0 == old ? id : $0
                })
            }
        default:
            let week = weeks[0]
            let id = held.weeks[Int.random(in: 0 ..< held.weeks.count, using: &random)]
            weeks[0] = Week(id: id, index: week.index, isDeload: week.isDeload, schedule: week.schedule)
        }
        return try program.rebuilt(weeks: weeks, days: days)
    }

    /// Program 1 edited with U+0000 in a day's tag, maybe its name, maybe a slot repeated.
    static func withNul(_ program: Program, using random: inout SeededGenerator) throws -> Program {
        var days = program.days
        if !days.isEmpty {
            days[0].tag += "\u{0}"
            if Bool.random(using: &random), days[0].slots.count > 1 {
                days[0].slots[1] = days[0].slots[0]
            }
        }
        return try program.rebuilt(days: days, name: Bool.random(using: &random) ? "N\u{0}" : nil)
    }

    /// One random step of the program script.
    static func programStep(
        _ editor: inout ProgramEditor,
        _ held: inout Held,
        other: Program,
        using random: inout SeededGenerator
    ) throws -> (String, Action) {
        let ids = [editor.program.id, other.id, S2Kit.programID(77)]
        switch Int.random(in: 0 ..< 100, using: &random) {
        case 0 ..< 45:
            try editor.edit()
            held.add(editor.program)
            let saved = editor.program
            return ("edit 1", { try await $0.save(saved) })
        case 45 ..< 65:
            let saved = try stealing(into: other, held, using: &random)
            return ("program 2 takes an id of 1", { try await $0.save(saved) })
        case 65 ..< 75:
            let saved = try withNul(editor.program, using: &random)
            return ("edit 1 with U+0000", { try await $0.save(saved) })
        case 75 ..< 85:
            let id = ids[Int.random(in: 0 ... 1, using: &random)]
            return ("delete \(id)", { try await $0.delete(id) })
        default:
            let id = ids[Int.random(in: 0 ... 2, using: &random)]
            return ("setActive \(id)", { try await $0.setActive(id) })
        }
    }

    static func firstProgramMismatch(_ seed: PropertySeed) async throws -> String? {
        let stack = try await S2Kit.stack()
        let fake = InMemoryProgramRepository()
        let start = try S2Kit.program(1, weeks: 3, days: 3, slotsPerDay: 3)
        let other = try S2Kit.program(2, weeks: 2, days: 2, slotsPerDay: 2, isActive: false)
        var (editor, random, held) = (ProgramEditor(program: start, seed: seed.value), seed.generator, Held())
        held.add(start)
        for program in [start, other] {
            try await stack.programs.save(program)
            try await fake.save(program)
        }
        for step in 0 ..< 12 {
            stack.clock.advance()
            let (label, action) = try programStep(&editor, &held, other: other, using: &random)
            let stored = await History.outcome { try await action(stack.programs) }
            let faked = await History.outcome { try await action(fake) }
            guard stored == faked else {
                return "step \(step), \(label): GRDB \(stored), fake \(faked)"
            }
            guard try await stack.programs.active() == fake.active() else {
                return "step \(step), \(label): the active programs differ"
            }
        }
        return nil
    }

    @Test(
        "Builder edits, id takeovers, U+0000, deletes and activations: the fake refuses and keeps as GRDB does",
        arguments: seeds
    )
    func programs_fakeMatchesGRDB(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstProgramMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }
}

// MARK: - Exercises: saving, seeding and upgrades

extension FakesCatalogDifferentialAdversarialTests {
    static let names = ["Lift", "lift", "Lïft", "Ｌｉｆｔ", "Press %", "Row_1"]

    /// A random exercise of eight ids, with a name that may clash with another's, rarely holding U+0000.
    static func entry(_ random: inout SeededGenerator) -> Exercise {
        let number = Int.random(in: 0 ..< 8, using: &random)
        var name = "\(names[Int.random(in: 0 ..< names.count, using: &random)]) \(number)"
        if Int.random(in: 0 ..< 25, using: &random) == 0 {
            name += "\u{0}"
        }
        return S2Kit.exercise(
            number,
            name,
            equipment: [.barbell, .dumbbell, .cable][Int.random(in: 0 ... 2, using: &random)],
            muscle: [.chest, .back][Int.random(in: 0 ... 1, using: &random)],
            isCustom: Bool.random(using: &random)
        )
    }

    /// Every read, labelled, compared as values (`defaultStartLoad`'s description lists its keys in any order).
    static func exerciseReads(_ repository: any ExerciseRepository) async throws -> [(String, [Exercise])] {
        var reads = try await [("all", repository.all())]
        for number in 0 ..< 8 {
            let found = try await repository.exercise(id: S2Kit.exerciseID(number))
            reads.append(("exercise(\(number))", found.map { [$0] } ?? []))
        }
        for query in ["", "lift", "LIFT 3", "lïft", "ｌｉｆｔ", "%", "_", " 1", "zzz"] {
            for equipment in [nil, Equipment.barbell] {
                for muscle in [nil, MuscleGroup.back] {
                    let found = try await repository.search(query, equipment: equipment, muscle: muscle)
                    reads.append(("search(\(query), \(equipment as Any), \(muscle as Any))", found))
                }
            }
        }
        return reads
    }

    static func firstExerciseMismatch(_ seed: PropertySeed) async throws -> String? {
        var random = seed.generator
        let stored = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        let fake = InMemoryExerciseRepository()
        for step in 0 ..< 14 {
            let label: String
            let action: @Sendable (any ExerciseRepository) async throws -> Void
            if Int.random(in: 0 ..< 100, using: &random) < 55 {
                let catalog = (0 ..< Int.random(in: 0 ... 6, using: &random)).map { _ in entry(&random) }
                let version = Int.random(in: 0 ... 4, using: &random)
                (label, action) = ("seed v\(version) \(catalog.map(\.name))", {
                    try await $0.seedIfNeeded(catalog, version: version)
                })
            } else {
                let exercise = entry(&random)
                (label, action) = (
                    "save \(exercise.name), custom \(exercise.isCustom)",
                    { try await $0.save(exercise) }
                )
            }
            let storedOutcome = await History.outcome { try await action(stored) }
            let fakeOutcome = await History.outcome { try await action(fake) }
            guard storedOutcome == fakeOutcome else {
                return "step \(step), \(label): GRDB \(storedOutcome), fake \(fakeOutcome)"
            }
            let pairs = try await zip(exerciseReads(stored), exerciseReads(fake))
            if let (actual, wanted) = pairs.first(where: { $0.1 != $1.1 }) {
                return "step \(step), \(label): \(actual.0) GRDB \(actual.1.map(\.name)), fake \(wanted.1.map(\.name))"
            }
        }
        return nil
    }

    @Test("Seeds, upgrades and saves: the fake's catalog, lookups and searches match GRDB's", arguments: seeds)
    func exercises_fakeMatchesGRDB(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstExerciseMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }
}
