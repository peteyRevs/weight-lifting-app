import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization
import Testing

/// One of six concurrent callers. It owns slot `index` of program 1: only its workout saves write that slot's
/// misses and exercise, only its updates that slot's sets, and every update of any lane appends a token to the
/// program's name. Its own calls come one after another, so it knows what its slot must hold at every moment.
struct UpdateLane: Sendable {
    typealias Fixture = LinkedFixture

    let index: Int
    let slot: Slot
    var random: SeededGenerator
    var misses: Set<Int>
    var exercise: ExerciseID
    var sets: Int
    var tokens: [String] = []
    var issues: [String] = []

    init(_ index: Int, seed: UInt64) throws {
        self.index = index
        slot = try Fixture.slot(index)
        random = SeededGenerator(seed: seed &* 31 &+ UInt64(index))
        (misses, exercise, sets) = (slot.misses, slot.exerciseID, slot.sets)
    }

    /// Six lanes of 24 steps each over `programs`: what they found wrong, and how many updates they made.
    static func race(
        _ stores: LinkedStores,
        _ programs: any ProgramRepository,
        seed: UInt64
    ) async throws -> ([String], Int) {
        let lanes = try await withThrowingTaskGroup(of: UpdateLane.self) { group in
            for number in 0 ..< 6 {
                group.addTask {
                    var racer = try UpdateLane(number, seed: seed)
                    try await racer.run(steps: 24, stores: stores, programs: programs)
                    return racer
                }
            }
            return try await group.reduce(into: [UpdateLane]()) { $0.append($1) }
        }
        let stored = try #require(try await UpdateKit.read(stores, 1))
        let found = try lanes.flatMap(\.issues) + UpdateLane.issues(in: stored, after: lanes)
        return (found, lanes.map(\.tokens.count).reduce(0, +))
    }

    func mine(in program: Program?) -> Slot? {
        program?.days.flatMap(\.slots).first { $0.id == slot.id }
    }

    /// What is wrong with this lane's slot as `program` holds it, by what the lane itself wrote last.
    func fault(in program: Program?, _ moment: String) -> String? {
        guard let held = mine(in: program) else {
            return "lane \(index), \(moment): its slot is gone"
        }
        guard held.misses == misses, held.exerciseID == exercise, held.sets == sets else {
            let found = "\(LinkedDifference.name(held.exerciseID)) \(held.misses.sorted()) \(held.sets)"
            return "lane \(index), \(moment): slot holds \(found), expected " +
                "\(LinkedDifference.name(exercise)) \(misses.sorted()) \(sets)"
        }
        return nil
    }

    mutating func run(steps: Int, stores: LinkedStores, programs: any ProgramRepository) async throws {
        for step in 0 ..< steps {
            for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
                await Task.yield()
            }
            switch Int.random(in: 0 ..< 10, using: &random) {
            case 0 ... 3:
                try await update(step, programs)
            case 4 ... 6:
                try await saveWorkout(step, on: stores)
            case 7:
                try await issues += [fault(in: programs.active(), "read at step \(step)")].compactMap(\.self)
            case 8:
                var other = try Fixture.program(2)
                other.name = "Two \(index).\(step)"
                try await stores.programs.save(other)
            default:
                try await stores.programs.setActive(UpdateKit.one)
            }
        }
    }

    /// A finished workout that records misses and a swap on this lane's slot.
    mutating func saveWorkout(_ step: Int, on stores: LinkedStores) async throws {
        misses = [step % 3, (step / 3) % 3]
        exercise = Fixture.exercises[(index + step) % Fixture.exercises.count].id
        let workout = Fixture.workout(index * 100 + step + 1, updates: [slot.id: exercise])
        let outcome = await stores.save(workout, slots: [Fixture.missing(slot, misses)], droppingLog: false)
        if outcome != "false" {
            issues.append("lane \(index): a workout's save answered \(outcome.prefix(80))")
        }
    }

    /// An update that appends this lane's token and sets its slot's sets; the change itself checks that the
    /// program it is given holds what this lane's last workout save wrote.
    private mutating func update(_ step: Int, _ programs: any ProgramRepository) async throws {
        let (token, before, target, newSets) = ("\(index).\(step);", self, slot.id, 1 + step % 12)
        let seen = Mutex<[String]>([])
        let returned = try await programs.update(UpdateKit.one) { program in
            let fault = before.fault(in: program, "inside the change at step \(step)")
            seen.withLock { $0.append(fault ?? "") }
            var changed = program.changing(target) { $0.sets = newSets }
            changed.name += token
            return changed
        }
        sets = newSets
        tokens.append(token)
        let faults = seen.withLock { $0 }
        if faults.count != 1 {
            issues.append("lane \(index): the change ran \(faults.count) times")
        }
        issues += faults.filter { !$0.isEmpty }
        issues += [fault(in: returned, "returned at step \(step)")].compactMap(\.self)
        if !returned.name.contains(token) {
            issues.append("lane \(index): the returned program lacks the update's own token")
        }
    }

    /// What is wrong with the program stored at the end: a token lost, doubled or out of its lane's order, a
    /// lane's slot that is not as the lane left it, or anything else that differs from the fixture.
    static func issues(in stored: Program, after lanes: [UpdateLane]) throws -> [String] {
        var found = lanes.compactMap { $0.fault(in: stored, "at the end") }
        let fixture = try Fixture.program(1)
        let applied = stored.name.dropFirst(fixture.name.count).split(separator: ";").map { "\($0);" }
        for lane in lanes where applied.filter({ $0.hasPrefix("\(lane.index).") }) != lane.tokens {
            let kept = applied.count { $0.hasPrefix("\(lane.index).") }
            found.append("lane \(lane.index): \(kept) of its \(lane.tokens.count) updates are in the name, in order")
        }
        var rest = stored
        rest.name = fixture.name
        for original in fixture.days.flatMap(\.slots) {
            rest = rest.changing(original.id) { $0 = original }
        }
        if rest != fixture {
            found.append("the program differs outside the lanes' slots and its name")
        }
        return found
    }
}
