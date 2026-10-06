import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criteria 1 and 4 as readers meet them: a save is one step. A screen that watches
/// the active program or the recent workouts hears one change for it, whole, and none for a save that changes
/// nothing; and a reader racing the saves never sees a workout without its misses' partner, its swap, or
/// with its log still there.
@Suite("Adversarial F10 S3 · one save, one change", .tags(.persistence), .timeLimit(.minutes(1)))
struct LinkedSaveObserverAdversarialTests {
    typealias Kind = LinkedStores.Kind
    typealias Fixture = LinkedFixture

    /// The first value `stream` gives a reader that was already waiting when `change` ran: a change that
    /// published something it should not have is the one it hears.
    static func heardFirst<Value: Sendable>(
        on stream: AsyncStream<Value>,
        after change: @Sendable () async throws -> Void
    ) async throws -> Value? {
        var values = stream.makeAsyncIterator()
        _ = await values.next()
        let listening = Task { [values] in
            var waiting = values
            return await waiting.next()
        }
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        try await change()
        return await listening.value
    }

    @Test("The active program's watcher hears a save's misses and swap as one value", arguments: Kind.allCases)
    func observeActive_oneSave_hearsOneWholeProgram(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        let expected = try Fixture.program(1).changing(slot.id) {
            $0.exerciseID = swapped
            $0.misses = [0, 1, 2]
        }
        let heard = try await Self.heardFirst(on: stores.programs.observeActive()) {
            let workout = Fixture.workout(1, updates: [slot.id: swapped])
            _ = await stores.save(workout, slots: [Fixture.missing(slot, [0, 1, 2])], droppingLog: true)
        }
        let issue = LinkedDifference.of(heard ?? nil, expected, "the first value after the save")
        #expect(issue == nil, "\(issue ?? "")")
    }

    @Test("A save that changes no program tells the program's watcher nothing", arguments: Kind.allCases)
    func observeActive_saveThatChangesNoProgram_hearsNothing(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let workout = Fixture.workout(1, updates: [slot.id: Fixture.other(than: slot)])
        _ = await stores.save(workout, slots: [Fixture.missing(slot, [1])], droppingLog: false)
        var renamed = try #require(try await stores.programs.active())
        renamed.name = "Marked"
        let marked = renamed
        let heard = try await Self.heardFirst(on: stores.programs.observeActive()) {
            // The same save again, an ad-hoc save, and an update to the exercise the slot holds: no change.
            _ = await stores.save(workout, slots: [Fixture.missing(slot, [1])], droppingLog: true)
            _ = await stores.save(
                Fixture.workout(2, ofProgram: nil, updates: workout.programUpdates),
                droppingLog: true
            )
            try await stores.programs.save(marked)
        }
        #expect(heard??.name == "Marked", "heard a program named \(heard??.name ?? "nil") first")
    }

    @Test(
        "The recent workouts' watcher hears a new workout once, and nothing when it is saved again",
        arguments: Kind.allCases
    )
    func observeRecent_savedAgain_hearsNothing(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let (one, two) = (Fixture.workout(1, updates: [slot.id: Fixture.other(than: slot)]), Fixture.workout(2))
        let first = try await Self.heardFirst(on: stores.workouts.observeRecent(limit: 5)) {
            _ = await stores.save(one, slots: [Fixture.missing(slot, [1])], droppingLog: true)
        }
        #expect(first?.map(\.id) == [one.id])
        let next = try await Self.heardFirst(on: stores.workouts.observeRecent(limit: 5)) {
            _ = await stores.save(one, slots: [Fixture.missing(slot, [1])], droppingLog: true)
            _ = await stores.save(two, droppingLog: true)
        }
        #expect(next?.map(\.id) == [two.id, one.id], "heard \(next?.count ?? 0) workouts first")
    }

    /// What one reader of a race found wrong, if anything.
    static func raceIssue(
        _ stores: LinkedStores,
        slot: Slot,
        workouts: [WorkoutState],
        seed: UInt64
    ) async throws -> String? {
        var random = SeededGenerator(seed: seed)
        let exercises = Fixture.exercises.map(\.id)
        for _ in 0 ..< 250 {
            let workout = workouts[Int.random(in: 0 ..< workouts.count, using: &random)]
            if Bool.random(using: &random) {
                // In history, so its log went with it.
                if try await stores.workouts.workout(id: workout.id) != nil, try await stores.logCount(workout) != 0 {
                    return "a workout was in history while its log was still stored"
                }
            } else {
                let isDropped = try await stores.logCount(workout) == 0
                if isDropped, try await stores.workouts.workout(id: workout.id) == nil {
                    return "a workout's log was gone and the workout was not in history"
                }
            }
            // Each save writes the slot's exercise and its misses to match: never one without the other.
            let slots = try await stores.programs.active()?.days.flatMap(\.slots) ?? []
            guard let stored = slots.first(where: { $0.id == slot.id }), stored.misses != slot.misses else {
                continue
            }
            if stored.misses != [exercises.firstIndex(of: stored.exerciseID).map { $0 % 3 } ?? -1] {
                return "the slot held \(LinkedDifference.name(stored.exerciseID)) with misses \(stored.misses.sorted())"
            }
            await Task.yield()
        }
        return nil
    }

    @Test("Readers racing forty saves never see half of one", arguments: Kind.allCases)
    func readers_racingSaves_neverSeeHalfASave(kind: Kind) async throws {
        let stores = try await LinkedStores.make(kind)
        let slot = try Fixture.slot(0)
        let exercises = Fixture.exercises.map(\.id)
        let workouts = (1 ... 40).map { number in
            Fixture.workout(number, updates: [slot.id: exercises[number % exercises.count]])
        }
        for workout in workouts {
            _ = try await stores.events.append(Fixture.log(of: workout, count: 3))
        }
        let issues = try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                for (index, workout) in workouts.enumerated() {
                    let misses: Set<Int> = [((index + 1) % exercises.count) % 3]
                    let outcome = await stores.save(workout, slots: [Fixture.missing(slot, misses)], droppingLog: true)
                    if outcome != "true" {
                        return "a save answered \(outcome.prefix(80))"
                    }
                    await Task.yield()
                }
                return nil
            }
            for reader in 0 ..< 3 {
                group.addTask { try await Self.raceIssue(stores, slot: slot, workouts: workouts, seed: UInt64(reader)) }
            }
            return try await group.reduce(into: [String]()) { $0 += [$1].compactMap(\.self) }
        }
        #expect(issues.isEmpty, "\(issues.first ?? "")")
        #expect(try await stores.events.uncompactedWorkoutIDs().isEmpty)
    }
}
