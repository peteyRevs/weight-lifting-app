import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F19 S1, criterion 6: `WorkoutReconciler` over seeded partitions (testing-strategy §3 rule 5). Each case is a
/// random two-device workout that each device logged and may have ended on its own, while it held only some of
/// the other's envelopes.
@Suite("WorkoutReconciler · properties", .tags(.domain, .property))
struct WorkoutReconcilerPropertyTests {
    @Test("Any order and grouping of the same envelopes merges and resolves the same", arguments: PropertySeed.all)
    func test_reconciler_property_shuffleInvariant(seed: PropertySeed) throws {
        var rng = SeededGenerator(seed: seed.value ^ 0x5EED)
        let logs = Partition(seed: seed)
        let merged = try WorkoutReconciler.merge([logs.phone, logs.watch])
        #expect(Reconciling.difference(merged, logs.full.sorted()) == nil, "\(seed)")
        let pieces = (logs.phone + logs.watch).shuffled(using: &rng)
        let cuts = (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in
            Int.random(in: 0 ... pieces.count, using: &rng)
        }
        let bounds = [0] + cuts.sorted() + [pieces.count]
        let chunks = zip(bounds, bounds.dropFirst()).map { Array(pieces[$0 ..< $1]) }
        let regrouped = try WorkoutReconciler.merge(chunks)
        #expect(Reconciling.difference(regrouped, merged) == nil, "\(seed)")
        let state = WorkoutReconciler.resolve(merged)
        #expect(Reconciling.difference(WorkoutReconciler.resolve(pieces), state) == nil, "\(seed)")
        #expect(Reconciling.difference(WorkoutReconciler.resolve(regrouped.reversed()), state) == nil, "\(seed)")
        #expect((state?.phase == .live) == !logs.full.contains { $0.event.endsWorkout }, "\(seed)")
    }

    @Test("Merging again with either log changes neither the log nor the state", arguments: PropertySeed.all)
    func test_reconciler_property_idempotent(seed: PropertySeed) throws {
        let logs = Partition(seed: seed)
        let merged = try WorkoutReconciler.merge([logs.phone, logs.watch])
        let again = try WorkoutReconciler.merge([merged, logs.watch])
        #expect(Reconciling.difference(again, merged) == nil, "\(seed)")
        #expect(try Reconciling.difference(WorkoutReconciler.merge([logs.phone, merged, merged]), merged) == nil)
        let state = WorkoutReconciler.resolve(merged)
        #expect(Reconciling.difference(WorkoutReconciler.resolve(again), state) == nil, "\(seed)")
        #expect(Reconciling.difference(WorkoutReconciler.resolve(merged + logs.phone), state) == nil, "\(seed)")
    }

    @Test("merge(a, b) and merge(b, a) are the same log and resolve the same", arguments: PropertySeed.all)
    func test_reconciler_property_commutative(seed: PropertySeed) throws {
        let logs = Partition(seed: seed)
        let forward = try WorkoutReconciler.merge(local: logs.phone, remote: logs.watch)
        let backward = try WorkoutReconciler.merge(local: logs.watch, remote: logs.phone)
        #expect(Reconciling.difference(forward, backward) == nil, "\(seed)")
        let state = WorkoutReconciler.resolve(forward)
        #expect(Reconciling.difference(WorkoutReconciler.resolve(backward), state) == nil, "\(seed)")
        if let state, state.doneSets > 0, logs.full.contains(where: { $0.endedAt != nil }) {
            #expect(state.phase == .finished, "R2: \(seed)")
        }
    }

    @Test(
        "Criterion 6: two devices that each finished hold one finished workout with every set either logged",
        arguments: PropertySeed.all
    )
    func test_reconciler_property_bothFinish_keepEverySet(seed: PropertySeed) throws {
        var random = RandomWorkout(seed: seed)
        var rng = SeededGenerator(seed: seed.value ^ 0xF19)
        let session = random.session()
        let started = EventBuilders.envelope(.started(session), seq: 1, at: EventBuilders.start)
        let phone = BothFinish.log(of: session, by: Engine.phone, firstSeq: 2, using: &rng)
        let watch = BothFinish.log(of: session, by: Engine.watch, firstSeq: 1, using: &rng)
        let merged = try WorkoutReconciler.merge([[started] + phone.log, [started] + watch.log])
        let state = try #require(WorkoutReconciler.resolve(merged), "\(seed)")
        #expect(state.phase == .finished, "\(seed)")
        #expect(state.endedAt == min(phone.finish, watch.finish).endedAt, "\(seed)")
        let done = Set(state.exercises.flatMap(\.sets).filter(\.isDone).map(\.id))
        let logged = phone.logged.union(watch.logged)
        #expect(logged.subtracting(done).isEmpty, "\(logged.subtracting(done).count) sets lost, \(seed)")
        #expect(done.count == logged.count, "\(seed)")
        let reversed = try WorkoutReconciler.merge([[started] + watch.log.reversed(), phone.log])
        #expect(Reconciling.difference(WorkoutReconciler.resolve(reversed), state) == nil, "\(seed)")
    }
}

// MARK: - Generators

/// A random workout's log (`RandomWorkout`) that both devices may end on their own, split as each device holds
/// it: its own envelopes, the `started`, and a random part of the other's.
private struct Partition {
    let full: [EventEnvelope]
    let phone: [EventEnvelope]
    let watch: [EventEnvelope]

    init(seed: PropertySeed) {
        var random = RandomWorkout(seed: seed)
        var rng = SeededGenerator(seed: seed.value ^ 0xA11)
        var log = random.log(steps: 40)
        for device in [Engine.phone, Engine.watch] {
            let last = log.last { $0.device == device }
            let gap = Double.random(in: 0 ... 30, using: &rng)
            let clock = (log.last?.wallClock ?? EventBuilders.start).addingTimeInterval(gap)
            let roll = Int.random(in: 0 ... 99, using: &rng)
            guard roll < 60 else {
                continue
            }
            let event: WorkoutEvent = roll < 40 ? .finished(endedAt: clock) : .discarded(endedAt: clock)
            log.append(EventBuilders.envelope(event, device: device, seq: (last?.seq ?? 0) + 1, at: clock))
        }
        let started = log[0]
        full = log
        phone = [started] + Partition.view(of: log.dropFirst(), owner: Engine.phone, using: &rng)
        watch = [started] + Partition.view(of: log.dropFirst(), owner: Engine.watch, using: &rng)
    }

    /// Every envelope `owner` created and, of the other's, those it received before the partition.
    private static func view(
        of log: ArraySlice<EventEnvelope>,
        owner: DeviceID,
        using rng: inout SeededGenerator
    ) -> [EventEnvelope] {
        log.filter { $0.device == owner || Bool.random(using: &rng) }
    }
}

/// One device's log of a partitioned workout that it finished: sets logged with its own clock, then `finish`.
private struct BothFinish {
    let log: [EventEnvelope]
    let logged: Set<SetID>
    let finish: EventEnvelope

    static func log(
        of session: WorkoutState,
        by device: DeviceID,
        firstSeq: UInt64,
        using rng: inout SeededGenerator
    ) -> Self {
        var clock = EventBuilders.start.addingTimeInterval(Double(Int.random(in: 1 ... 30, using: &rng)))
        var seq = firstSeq
        var envelopes: [EventEnvelope] = []
        var done = Set<SetID>()
        for _ in 0 ..< Int.random(in: 1 ... 12, using: &rng) {
            let exerciseIndex = Int.random(in: session.exercises.indices, using: &rng)
            let set = session.exercises[exerciseIndex].sets.randomElement(using: &rng) ?? session.exercises[0].sets[0]
            let event = WorkoutEvent.setLogged(
                exerciseIndex: exerciseIndex,
                setID: set.id,
                weight: .pounds(Decimal(Int.random(in: 0 ... 300, using: &rng))),
                reps: Reps(clamping: Int.random(in: 1 ... 15, using: &rng)),
                doneAt: clock
            )
            envelopes.append(EventBuilders.envelope(event, device: device, seq: seq, at: clock))
            done.insert(set.id)
            seq += 1
            clock = clock.addingTimeInterval(Double(Int.random(in: 0 ... 40, using: &rng)))
        }
        let end = EventBuilders.envelope(.finished(endedAt: clock), device: device, seq: seq, at: clock)
        return BothFinish(log: envelopes + [end], logged: done, finish: end)
    }
}

private extension EventEnvelope {
    var endedAt: Date? {
        if case let .finished(endedAt) = event {
            return endedAt
        }
        return nil
    }
}

private extension WorkoutEvent {
    var endsWorkout: Bool {
        switch self {
        case .finished, .discarded:
            true
        default:
            false
        }
    }
}
