import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 adversarial round 1, criterion 8 under a race: calls cancelled at seeded moments around the write, and
/// cancelled calls among others that are not. Each is stored whole or not at all, a call that was never
/// cancelled returns, and a workout's save made meanwhile is kept.
@Suite("Adversarial F11 S3 · cancelled updates among others", .tags(.persistence), .timeLimit(.minutes(2)))
struct ProgramUpdateCancelRaceAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Call = Task<Program, any Error>
    typealias Single = ProgramUpdateCancelAdversarialTests

    @Test(
        "Cancelled at eighty moments that close in on the commit: all or nothing each time",
        arguments: Place.allCases
    )
    func cancelledAroundTheCommit_storesAllOrNothing(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        var random = SeededGenerator(seed: 1106)
        var issues: [String] = []
        var endings: Set<String> = []
        // How long the canceller gives way first. A yield is no measure of time (a simulator needs thousands
        // where a Mac needs tens), so a call cancelled too early doubles the wait and one cancelled too late
        // halves it: the rounds settle around the moment of the commit on whatever runs them.
        var wait = 1
        for round in 0 ..< 80 {
            let before = try await UpdateKit.read(stores, 1)
            let call = Call { try await stores.programs.update(UpdateKit.one, Single.wide) }
            for _ in 0 ..< Int.random(in: wait / 2 ... wait, using: &random) {
                await Task.yield()
            }
            call.cancel()
            if let issue = try await Single.verdict(call, on: stores, after: before) {
                issues.append("round \(round): \(issue)")
            }
            let isStored = try await UpdateKit.read(stores, 1) != before
            endings.insert(isStored ? "all" : "none")
            wait = isStored ? max(1, wait / 2) : min(wait * 2, 1 << 18)
        }
        #expect(issues.isEmpty, "\(place): \(issues.prefix(2).joined(separator: "; ")) (\(issues.count) of 80)")
        #expect(endings.contains("all"), "\(place): no cancelled call was ever stored, so the commit was never raced")
        let later = try await Single.stillWorks(stores)
        #expect(later == nil, "\(place): \(later ?? "")")
    }

    /// Sixty increments started at once; every other one is cancelled a seeded number of yields later.
    static func sixtyCalls(on stores: LinkedStores, seed: UInt64) async -> [Call] {
        var random = SeededGenerator(seed: seed)
        var calls: [Call] = []
        for index in 0 ..< 60 {
            let call = Call { try await stores.programs.update(UpdateKit.one, UpdateKit.increment) }
            calls.append(call)
            if index.isMultiple(of: 2) {
                for _ in 0 ..< Int.random(in: 0 ... 20, using: &random) {
                    await Task.yield()
                }
                call.cancel()
            }
        }
        return calls
    }

    @Test(
        "Sixty concurrent updates, half of them cancelled, beside a lane of workout saves: no other caller pays",
        arguments: Place.allCases,
        [UInt64(3), 58, 2026]
    )
    func concurrentCalls_someCancelled_countTheOnesThatReturned(place: Place, seed: UInt64) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "counted\(seed)")
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        let saver = Task {
            var lane = try UpdateLane(3, seed: seed)
            for step in 0 ..< 12 {
                try await lane.saveWorkout(step, on: stores)
                await Task.yield()
            }
            return lane
        }
        let calls = await Self.sixtyCalls(on: stores, seed: seed)
        var returned: [Int] = []
        var faults: [String] = []
        for (index, call) in calls.enumerated() {
            let wasCancelled = index.isMultiple(of: 2)
            switch await call.result {
            case let .success(program):
                returned.append(UpdateKit.count(program))
            case let .failure(error) where error is CancellationError && wasCancelled:
                break
            case let .failure(error):
                faults.append("call \(index), \(wasCancelled ? "cancelled" : "never cancelled"), threw \(error)")
            }
        }
        let lane = try await saver.value
        let stored = try await UpdateKit.read(stores, 1)
        faults += lane.issues + [lane.fault(in: stored, "at the end")].compactMap(\.self)
        let isEveryCount = returned.sorted() == Array(1 ... max(1, returned.count))
        #expect(faults.isEmpty, "\(place), seed \(seed): \(faults.prefix(2))")
        #expect(UpdateKit.count(stored) == returned.count, "\(place), seed \(seed): \(returned.count) returned")
        #expect(isEveryCount && returned.count >= 30, "\(place), seed \(seed): \(returned.count) counts, not 1 to that")
    }
}
