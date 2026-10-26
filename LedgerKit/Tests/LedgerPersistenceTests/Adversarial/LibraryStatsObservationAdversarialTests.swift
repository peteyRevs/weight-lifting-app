import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F12 S3 adversarial round (G2), N20: `observeLibraryStats` over random scripts (F05 S3's `HistoryScript`:
/// materialisations of new and older workouts, set edits, deletes, refused calls), on GRDB and on the in-memory
/// fakes side by side. After each step, each observation must reach exactly what its own three reads now return
/// (`recentlyLogged`, each recent one's `sessionCount`, `bestSets`), the two must agree, and an observation must
/// never emit a value equal to the one before (`removeDuplicates`). Clause 27 pins seven steps; this walks
/// fourteen random ones, with limits that cut the recent list short and one that keeps it whole.
@Suite(
    "Adversarial F12 S3 · Library stats observed, GRDB against the fakes",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct LibraryStatsObservationAdversarialTests {
    typealias History = HistoryModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(25))

    static func read(_ stats: any StatsQueries, limit: Int) async throws -> LibraryStats {
        let recent = try await stats.recentlyLogged(limit: limit)
        var sessions: [ExerciseID: Int] = [:]
        for id in recent {
            sessions[id] = try await stats.sessionCount(exerciseID: id)
        }
        return try await LibraryStats(recent: recent, sessions: sessions, bestSets: stats.bestSets())
    }

    /// Takes values from `values` until one equals `wanted`; every value taken must differ from the one before it.
    /// Returns what went wrong, or nil.
    static func reach(
        _ wanted: LibraryStats,
        from values: LibraryArrivals<LibraryStats>,
        last: inout LibraryStats?
    ) async -> String? {
        if last == wanted {
            return nil
        }
        while let value = await values.next(within: .seconds(5)) {
            if value == last {
                return "emitted a value equal to the one before"
            }
            last = value
            if value == wanted {
                return nil
            }
        }
        return "never reached \(wanted); last \(String(describing: last))"
    }

    /// The first step whose values went wrong, or nil; and how many steps showed any stats at all.
    static func firstMismatch(_ seed: PropertySeed, limit: Int) async throws -> (String?, shown: Int) {
        var shown = 0
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let stats = stack.stats(now: script.now)
        let now = script.now
        let fakes = InMemoryStores(now: { now })
        let stored = LibraryArrivals(stats.observeLibraryStats(recentLimit: limit))
        let faked = LibraryArrivals(fakes.stats.observeLibraryStats(recentLimit: limit))
        defer {
            stored.cancel()
            faked.cancel()
        }
        var lastStored: LibraryStats?
        var lastFaked: LibraryStats?
        for step in 0 ..< 14 {
            let operation = step == 0 ? nil : script.next()
            if let operation {
                stack.clock.advance()
                _ = await History.apply(operation, to: stack.workouts)
                _ = await History.apply(operation, to: fakes.workouts)
            }
            let wanted = try await read(stats, limit: limit)
            let fakeWanted = try await read(fakes.stats, limit: limit)
            shown += wanted.bestSets.isEmpty ? 0 : 1
            if wanted != fakeWanted {
                return ("step \(step): the reads differ: GRDB \(wanted), fake \(fakeWanted)", shown)
            }
            if let problem = await reach(wanted, from: stored, last: &lastStored) {
                return ("step \(step), \(String(describing: operation)): GRDB \(problem)", shown)
            }
            if let problem = await reach(wanted, from: faked, last: &lastFaked) {
                return ("step \(step), \(String(describing: operation)): fake \(problem)", shown)
            }
        }
        return (nil, shown)
    }

    @Test("Random scripts: each observation reaches its reads after every step, and the two agree")
    func libraryStats_followEveryStep() async throws {
        var proving = 0
        for seed in Self.seeds {
            var shownAny = false
            for limit in [1, 2, 5] {
                let (mismatch, shown) = try await Self.firstMismatch(seed, limit: limit)
                #expect(mismatch == nil, "\(seed), limit \(limit)")
                shownAny = shownAny || shown > 0
            }
            proving += shownAny ? 1 : 0
        }
        // Most scripts must log a set that counts, or the agreement proves little.
        #expect(proving >= Self.seeds.count * 3 / 4, "only \(proving) of \(Self.seeds.count) scripts showed stats")
    }
}

/// The stream's values as they come, read by one task so none is replaced unseen in a buffer of one; `next(within:)`
/// waits for the next for at most a bound (as LedgerTestSupport's internal `StreamArrivals`).
final class LibraryArrivals<Value: Sendable>: Sendable {
    private let received = Mutex<(values: [Value], hasEnded: Bool)>(([], false))
    private let reader = Mutex<Task<Void, Never>?>(nil)

    init(_ stream: AsyncStream<Value>) {
        let task = Task {
            for await value in stream {
                self.received.withLock { $0.values.append(value) }
            }
            self.received.withLock { $0.hasEnded = true }
        }
        reader.withLock { $0 = task }
    }

    func next(within wait: Duration) async -> Value? {
        let deadline = ContinuousClock.now + wait
        while true {
            let (value, hasEnded) = received.withLock { received in
                (received.values.isEmpty ? nil : received.values.removeFirst(), received.hasEnded)
            }
            if let value {
                return value
            }
            if hasEnded || ContinuousClock.now >= deadline {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func cancel() {
        reader.withLock { $0?.cancel() }
    }
}
