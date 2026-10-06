import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 adversarial round 1, criterion 7: nothing is lost between a builder and a workout's save. The losing
/// sequence; counters under real concurrency; and six lanes that race updates, workout saves, reads and other
/// writes, each lane owning one slot, so that what must be stored at the end is known whatever the order was.
@Suite("Adversarial F11 S3 · no update is lost", .tags(.persistence, .property), .timeLimit(.minutes(2)))
struct ProgramUpdateLostAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Fixture = LinkedFixture

    /// The builder's edit of the losing sequence: it names a day and one slot's sets, and nothing else.
    static let edit: @Sendable (Program) -> Program = { program in
        UpdateRefusal.changed(program) { changed in
            changed.days[0].name = "Edited"
            changed.days[0].slots[0].sets = 11
        }
    }

    /// Slot 0 of program 1 as `stores` hold it, in a line: its exercise, misses and sets, and its day's name.
    static func line(_ stores: LinkedStores) async throws -> String {
        let program = try await UpdateKit.read(stores, 1)
        guard let day = program?.days.first, let slot = day.slots.first else {
            return "no slot"
        }
        return "\(LinkedDifference.name(slot.exerciseID)) \(slot.misses.sorted()) \(slot.sets) \(day.name)"
    }

    @Test(
        "Read, a workout's save, then the builder's write: `save` loses the miss and the swap, `update` keeps both",
        arguments: Place.allCases
    )
    func losingSequence_throughUpdate_keepsTheMissAndTheSwap(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "losingA")
        let (twin, second) = try await UpdateKit.make(place, "losingB")
        defer { // cleanup only
            try? directory?.remove()
            try? second?.remove()
        }
        let slot = try Fixture.slot(0)
        let swapped = Fixture.other(than: slot)
        let workout = Fixture.workout(1, updates: [slot.id: swapped])
        var lines: [String] = []
        for (target, isUpdate) in [(stores, true), (twin, false)] {
            let copy = try #require(try await UpdateKit.read(target, 1))
            let outcome = await target.save(workout, slots: [Fixture.missing(slot, [0, 2])], droppingLog: false)
            try #require(outcome == "false", "the workout's save answered \(outcome.prefix(80))")
            if isUpdate {
                let returned = try await target.programs.update(UpdateKit.one, Self.edit)
                let isStored = try await returned == UpdateKit.read(target, 1)
                #expect(isStored, "update returned another program than the one stored")
            } else {
                try await target.programs.save(Self.edit(copy))
            }
            try await lines.append(Self.line(target))
        }
        let (old, new) = (LinkedDifference.name(slot.exerciseID), LinkedDifference.name(swapped))
        #expect(lines == ["\(new) [0, 2] 11 Edited", "\(old) \(slot.misses.sorted()) 11 Edited"], "\(place): \(lines)")
    }

    @Test(
        "A hundred concurrent updates that each add one end at a hundred, each returning its own count",
        arguments: Place.allCases
    )
    func concurrentIncrements_allCount(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        // On a database, every other call goes through a second repository over the same queue.
        let second: any ProgramRepository = stores.queue.map { GRDBProgramRepository($0) } ?? stores.programs
        let returned = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0 ..< 100 {
                group.addTask {
                    let programs = index.isMultiple(of: 2) ? stores.programs : second
                    return try await UpdateKit.count(programs.update(UpdateKit.one, UpdateKit.increment))
                }
            }
            return try await group.reduce(into: [Int]()) { $0.append($1) }
        }
        let stored = try await UpdateKit.count(UpdateKit.read(stores, 1))
        let isEveryCount = returned.sorted() == Array(1 ... 100)
        #expect(stored == 100, "\(place): \(stored) of 100 updates are stored")
        #expect(isEveryCount, "\(place): \(Set(returned).count) distinct counts were returned for 100 calls")
    }

    @Test("Two connections to one file: every update that returns is stored, and one that is not stored throws")
    func twoConnections_everyReturnedUpdateIsStored() async throws {
        let (stores, directory) = try await UpdateKit.make(.file)
        defer { try? directory?.remove() } // cleanup only
        let url = try #require(directory).file("ledger.sqlite")
        let other = try UpdateKit.opened(url, stores.clock)
        try await UpdateKit.zero(stores)
        let outcomes = await withTaskGroup(of: String.self) { group in
            for index in 0 ..< 60 {
                group.addTask {
                    let programs = index.isMultiple(of: 2) ? stores.programs : other.programs
                    return await UpdateKit.attempt(programs, UpdateKit.one, UpdateKit.increment)
                }
            }
            return await group.reduce(into: [String]()) { $0.append($1) }
        }
        let succeeded = outcomes.count { $0 == "stored" }
        let (here, there) = try await (
            UpdateKit.count(UpdateKit.read(stores, 1)),
            UpdateKit.count(UpdateKit.read(other, 1))
        )
        let refused = Set(outcomes.filter { $0 != "stored" }.map { String($0.prefix(60)) })
        #expect(
            here == succeeded && there == succeeded,
            "\(succeeded) returned, \(here) and \(there) stored; \(refused)"
        )
        #expect(succeeded > 0, "no update over two connections was stored: \(refused)")
    }

    @Test(
        "Six lanes race updates, workout saves, reads and other writes: every lane's last miss, swap and edit stand",
        arguments: Place.allCases,
        PropertySeed.all.prefix(8)
    )
    func racingLanes_loseNothing(place: Place, seed: PropertySeed) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "lanes\(seed.value)")
        defer { try? directory?.remove() } // cleanup only
        // Odd seeds go through the probe, whose calls give way before they reach the store.
        let probed = ProbedStores(
            events: stores.events,
            workouts: stores.workouts,
            programs: stores.programs,
            yields: 2
        )
        let programs: any ProgramRepository = seed.value.isMultiple(of: 2) ? stores.programs : probed.programs
        let (issues, made) = try await UpdateLane.race(stores, programs, seed: seed.value)
        #expect(issues.isEmpty, "\(place), \(seed): \(issues.prefix(3).joined(separator: "; ")) (\(issues.count))")
        #expect(made > 20, "\(seed) made only \(made) updates: the script does not race them")
    }

    @Test(
        "The attacks notice an update made in three steps: the lanes and the counter both lose some",
        arguments: [Place.database, .memory]
    )
    func threeStepUpdate_isCaughtLosing(place: Place) async throws {
        var caught = 0
        for seed in PropertySeed.all.prefix(8) {
            let (stores, _) = try await UpdateKit.make(place)
            let (issues, _) = try await UpdateLane.race(
                stores,
                ThreeStepPrograms(base: stores.programs),
                seed: seed.value
            )
            caught += issues.isEmpty ? 0 : 1
        }
        // A loss needs two callers to overlap, which no seed promises: most seeds show one, and half must.
        #expect(caught >= 4, "\(place): the lanes found a three-step update losing on only \(caught) of 8 seeds")
        let (stores, _) = try await UpdateKit.make(place)
        try await UpdateKit.zero(stores)
        let lossy = ThreeStepPrograms(base: stores.programs)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { _ = await UpdateKit.attempt(lossy, UpdateKit.one, UpdateKit.increment) }
            }
        }
        let stored = try await UpdateKit.count(UpdateKit.read(stores, 1))
        #expect(stored < 100, "\(place): a hundred three-step increments all counted, so the counter proves nothing")
    }
}
