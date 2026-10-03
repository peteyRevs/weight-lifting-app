import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: LedgerFakes' history stores against the GRDB ones over seeded random scripts. The
/// contracts pin what they name; these look where they are silent, for a fake kinder (or harsher) than the
/// database later features (F08–F15) are tested against. After every step both must have thrown the same error
/// or neither, a refused call must leave the fake as it was, and every read must agree.
@Suite(
    "Adversarial F07 S1 · history fakes against GRDB",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct FakesHistoryDifferentialAdversarialTests {
    typealias History = HistoryModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(60))

    /// Every read, stats query and `bests(before:for:)` of a workout store and its stats.
    static func everything(
        _ workouts: any WorkoutRepository,
        _ stats: any StatsQueries,
        before live: [WorkoutState],
        _ script: HistoryScript
    ) async throws -> [String] {
        try await History.reads(workouts, script) + History.stats(stats, script)
            + History.bests(stats, before: live, script)
    }

    /// `HistoryScript` (F05 S3's generator) on GRDB and on `InMemoryStores`.
    static func firstHistoryMismatch(_ seed: PropertySeed) async throws -> String? {
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let stats = stack.stats(now: script.now)
        let now = script.now
        let fakes = InMemoryStores(now: { now })
        for step in 0 ..< 14 {
            let operation = script.next()
            stack.clock.advance()
            let before = try await History.reads(fakes.workouts, script)
            let stored = await History.apply(operation, to: stack.workouts)
            let faked = await History.apply(operation, to: fakes.workouts)
            guard stored == faked else {
                return "step \(step), \(operation): GRDB \(stored), fake \(faked)"
            }
            if faked != "ok", try await History.reads(fakes.workouts, script) != before {
                return "step \(step): a refused call changed the fake"
            }
            let live = try await stack.workouts.recent(limit: 100)
            let actual = try await everything(stack.workouts, stats, before: live, script)
            let wanted = try await everything(fakes.workouts, fakes.stats, before: live, script)
            if let mismatch = zip(actual, wanted).first(where: { $0 != $1 }) {
                return "step \(step): GRDB \(mismatch.0), fake \(mismatch.1)"
            }
        }
        return nil
    }

    @Test(
        "Random materialisations, edits and deletes: the fake answers every read and query as GRDB does",
        arguments: seeds
    )
    func history_fakeMatchesGRDB(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstHistoryMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }

    // MARK: - Slot updates reaching the programs

    typealias Step = (
        label: String,
        body: @Sendable (any ProgramRepository, any WorkoutRepository) async throws -> Void
    )

    /// Slot updates naming live, dropped, deleted, unknown and repeated slots, with random misses.
    static func slotUpdates(_ slots: [Slot], using random: inout SeededGenerator) throws -> [Slot] {
        var updates: [Slot] = []
        for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
            let base = slots[Int.random(in: 0 ..< slots.count, using: &random)]
            try updates.append(base.with(misses: Set((-1 ... 3).filter { _ in Bool.random(using: &random) })))
        }
        if Int.random(in: 0 ..< 5, using: &random) == 0 {
            try updates.append(S2Kit.slot(9999, misses: [1]))
        }
        return updates
    }

    /// One random step: a materialisation with slot updates, a program save dropping a slot or not, a program
    /// delete or activation, or a workout delete.
    static func linkedStep(_ programs: [Program], using random: inout SeededGenerator) throws -> Step {
        let pick = Int.random(in: 0 ..< 100, using: &random)
        let program = programs[Int.random(in: 0 ... 1, using: &random)]
        let number = Int.random(in: 1 ... 3, using: &random)
        switch pick {
        case 0 ..< 45:
            let updates = try slotUpdates(programs.flatMap(\.days).flatMap(\.slots), using: &random)
            let workout = S3Kit.workout(
                number,
                endedAt: S3Kit.day(Double(-number)),
                [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])]
            )
            return ("materialize \(number), \(updates.map(\.misses))", { _, workouts in
                try await workouts.materialize(workout, slotUpdates: updates)
            })
        case 45 ..< 65:
            var days = program.days
            let dropping = Bool.random(using: &random)
            if dropping {
                days[0].slots.removeFirst()
            }
            let saved = try program.rebuilt(days: days).withActive(Bool.random(using: &random))
            return ("save \(program.name), dropping \(dropping)", { programs, _ in try await programs.save(saved) })
        case 65 ..< 78:
            return ("delete \(program.name)", { programs, _ in try await programs.delete(program.id) })
        case 78 ..< 92:
            return ("setActive \(program.name)", { programs, _ in try await programs.setActive(program.id) })
        default:
            return (
                "delete workout \(number)",
                { _, workouts in try await workouts.delete(id: S3Kit.workoutID(number)) }
            )
        }
    }

    /// Two programs and random steps on both: outcomes, the active program and the recent workouts.
    static func firstLinkedMismatch(_ seed: PropertySeed) async throws -> String? {
        var random = seed.generator
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores()
        let programs = try [
            S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2),
            S2Kit.program(2, weeks: 3, days: 2, slotsPerDay: 2, isActive: false)
        ]
        for program in programs {
            try await stack.programs.save(program)
            try await fakes.programs.save(program)
        }
        for index in 0 ..< 16 {
            stack.clock.advance()
            let step = try linkedStep(programs, using: &random)
            let stored = await History.outcome { try await step.body(stack.programs, stack.workouts) }
            let faked = await History.outcome { try await step.body(fakes.programs, fakes.workouts) }
            guard stored == faked else {
                return "step \(index), \(step.label): GRDB \(stored), fake \(faked)"
            }
            guard try await stack.programs.active() == fakes.programs.active() else {
                return "step \(index), \(step.label): the active programs differ"
            }
            guard try await stack.workouts.recent(limit: 10) == fakes.workouts.recent(limit: 10) else {
                return "step \(index), \(step.label): the recent workouts differ"
            }
        }
        return nil
    }

    @Test(
        "Slot updates, program saves, deletes and activations: the fake's active program matches GRDB's",
        arguments: seeds
    )
    func slotUpdates_fakeMatchesGRDB(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstLinkedMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }
}
