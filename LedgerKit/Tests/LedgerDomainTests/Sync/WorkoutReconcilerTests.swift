import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F19 S1: `WorkoutReconciler`'s merge and its rulings R1 and R2 (criterion 6). The seeded properties are in
/// `WorkoutReconcilerPropertyTests`.
@Suite("WorkoutReconciler", .tags(.domain))
struct WorkoutReconcilerTests {
    // MARK: merge

    @Test("The union keeps one envelope per (device, seq), however many logs hold it")
    func test_reconciler_unionDedupesByDeviceSeq() throws {
        let started = Engine.started()
        let phoneSet = Engine.envelope(Engine.logged(0, 0, at: 10), 10, seq: 2)
        let phoneSkip = Engine.envelope(.restSkipped, 20, seq: 3)
        let watchSet = Engine.envelope(Engine.logged(1, 0, at: 15), 15, from: Engine.watch, seq: 1)
        let phone = [started, phoneSet, phoneSkip]
        let watch = [started, phoneSet, watchSet, watchSet]
        let merged = try WorkoutReconciler.merge([phone, watch, phone])
        #expect(merged.count == 4)
        #expect(Set(merged.map(\.key)).count == 4)
        #expect(Reconciling.difference(merged, [started, phoneSet, watchSet, phoneSkip]) == nil)
        #expect(try WorkoutReconciler.merge([]).isEmpty)
        let pair = try WorkoutReconciler.merge(local: phone, remote: watch)
        #expect(try Reconciling.difference(pair, WorkoutReconciler.merge([phone, watch])) == nil)
    }

    @Test("Two different envelopes with one key are refused, not deduped to whichever came first")
    func merge_refusesAConflictingEnvelope() {
        let phoneSet = Engine.envelope(Engine.logged(0, 0, at: 10), 10, seq: 2)
        let reused = Engine.envelope(.restSkipped, 10, seq: 2)
        #expect(throws: WorkoutReconciler.MergeError.conflictingEnvelope(phoneSet.key)) {
            try WorkoutReconciler.merge([[Engine.started(), phoneSet], [reused]])
        }
    }

    @Test("An envelope with a date that is not finite is dropped, as an F17 host drops it before storing")
    func merge_dropsANonFiniteEnvelope() throws {
        let stamp = EventBuilders.envelope(.restSkipped, seq: 2, at: Date(timeIntervalSinceReferenceDate: .nan))
        let payload = Engine.envelope(.finished(endedAt: Date(timeIntervalSinceReferenceDate: .infinity)), 30, seq: 3)
        let merged = try WorkoutReconciler.merge([[Engine.started(), stamp, payload], [stamp]])
        #expect(merged.map(\.seq) == [1])
    }

    @Test("A malformed envelope with finite dates, and one before the started, are kept: the log must agree")
    func merge_keepsMalformedAndEarlyEnvelopes() throws {
        let early = Engine.envelope(.restSkipped, -5, from: Engine.watch, seq: 1)
        let tooLong = Engine.envelope(.restStarted(endsAt: Engine.at(9000), total: .seconds(9000)), 20, seq: 2)
        let merged = try WorkoutReconciler.merge([[Engine.started(), tooLong], [early]])
        #expect(merged.map(\.key) == [early.key, Engine.started().key, tooLong.key])
        #expect(Reconciling.difference(WorkoutReconciler.resolve(merged), WorkoutEngine.replay(merged)) == nil)
    }

    @Test("The order is wallClock, then device ID, then seq")
    func test_reconciler_orderIsWallClockDeviceSeq() throws {
        #expect(Engine.phone.rawValue < Engine.watch.rawValue)
        let watchFirst = Engine.envelope(.restSkipped, 10, from: Engine.watch, seq: 1)
        let phoneTie = Engine.envelope(.restSkipped, 20, seq: 3)
        let watchTie = Engine.envelope(.restSkipped, 20, from: Engine.watch, seq: 2)
        let phoneSameClock = Engine.envelope(.restSkipped, 20, seq: 2)
        let merged = try WorkoutReconciler.merge([[phoneTie, Engine.started()], [watchTie, phoneSameClock, watchFirst]])
        let expected = [Engine.started(), watchFirst, phoneSameClock, phoneTie, watchTie]
        #expect(Reconciling.difference(merged, expected) == nil)
    }

    @Test("Envelopes of two workouts are refused, both workouts named in rawValue order")
    func merge_refusesMixedWorkoutIDs() {
        let other = WorkoutID(EventBuilders.uuid(0xF101))
        let otherStart = EventBuilders.envelope(
            .started(EventBuilders.session(EventBuilders.seedExercises, id: other)),
            seq: 1,
            at: Engine.at(0),
            workoutID: other
        )
        let expected = [EventBuilders.workoutID, other].sorted { $0.rawValue < $1.rawValue }
        #expect(throws: WorkoutReconciler.MergeError.mixedWorkouts(expected)) {
            try WorkoutReconciler.merge([[otherStart], [Engine.started()]])
        }
        #expect(throws: WorkoutReconciler.MergeError.mixedWorkouts(expected)) {
            try WorkoutReconciler.merge([[Engine.started(), otherStart]])
        }
    }

    // MARK: resolve: R1

    @Test("Criterion 6: both devices finished, so the earlier finish in fold order ends the workout")
    func test_reconciler_firstTerminalWins() throws {
        let watchFinish = Engine.envelope(.finished(endedAt: Engine.at(140)), 140, from: Engine.watch, seq: 2)
        let phone = [Engine.started(), Engine.envelope(.finished(endedAt: Engine.at(100)), 100, seq: 2)]
        let watch = [Engine.started(), Engine.envelope(Engine.logged(0, 0, at: 50), 50, from: Engine.watch, seq: 1)]
        let state = try #require(try WorkoutReconciler.resolve(WorkoutReconciler.merge([phone, watch + [watchFinish]])))
        #expect(state.phase == .finished)
        #expect(state.endedAt == Engine.at(100))
        #expect(state.doneSets == 1)
    }

    @Test("R1: a set the watch logged after the phone finished is kept; elapsed may end before that set")
    func resolve_keepsALateSetAfterTheOtherFinish() throws {
        let phone = [Engine.started(), Engine.envelope(.finished(endedAt: Engine.at(100)), 100, seq: 2)]
        let watch = [
            Engine.envelope(Engine.logged(0, 0, at: 90), 90, from: Engine.watch, seq: 1),
            Engine.envelope(Engine.logged(0, 1, pounds: 190, at: 120), 120, from: Engine.watch, seq: 2),
            Engine.envelope(.finished(endedAt: Engine.at(130)), 130, from: Engine.watch, seq: 3)
        ]
        let merged = try WorkoutReconciler.merge([phone, watch])
        let state = try #require(WorkoutReconciler.resolve(merged))
        #expect(state.phase == .finished)
        #expect(state.endedAt == Engine.at(100))
        #expect(state.exercises[0].sets[1].doneAt == Engine.at(120))
        #expect(state.exercises[0].sets[1].weight == .pounds(190))
        #expect(state.doneSets == 2)
        #expect(state.rest == nil)
        #expect(state.elapsed(at: Engine.at(500)) == .seconds(100))
        // The live fold stops at the phone's finish, which is why the reconciler holds terminals back.
        #expect(WorkoutEngine.replay(merged)?.doneSets == 1)
    }

    @Test("With no terminal held back, resolve folds as replay")
    func resolve_withoutTerminal_isReplay() throws {
        let log = [
            Engine.started(),
            Engine.envelope(Engine.logged(0, 0, at: 10), 10, seq: 2),
            Engine.envelope(Engine.extend(tapped: 20), 20, from: Engine.watch, seq: 1)
        ]
        let state = try #require(WorkoutReconciler.resolve(log.reversed()))
        #expect(state.phase == .live)
        #expect(state.endedAt == nil)
        #expect(Reconciling.difference(state, WorkoutEngine.replay(log)) == nil)
        #expect(WorkoutReconciler.resolve([Engine.envelope(.restSkipped, 5, seq: 2)]) == nil)
        #expect(WorkoutReconciler.resolve([]) == nil)
    }

    // MARK: resolve: R2

    @Test("R2: a finish beats an earlier discard when the merged workout has a done set")
    func resolve_finishBeatsDiscard_whenASetIsDone() throws {
        let phone = [Engine.started(), Engine.envelope(.discarded(endedAt: Engine.at(30)), 30, seq: 2)]
        let watch = [
            Engine.envelope(Engine.logged(0, 0, at: 40), 40, from: Engine.watch, seq: 1),
            Engine.envelope(.finished(endedAt: Engine.at(60)), 60, from: Engine.watch, seq: 2)
        ]
        let state = try #require(try WorkoutReconciler.resolve(WorkoutReconciler.merge([phone, watch])))
        #expect(state.phase == .finished)
        #expect(state.endedAt == Engine.at(60))
        #expect(state.doneSets == 1)
    }

    @Test("R2: a discard wins over an earlier finish when no set is done on either device")
    func resolve_discardWins_onAnEmptyWorkout() throws {
        let phone = [Engine.started(), Engine.envelope(.finished(endedAt: Engine.at(30)), 30, seq: 2)]
        let watch = [
            Engine.envelope(Engine.logged(0, 0, at: 10), 10, from: Engine.watch, seq: 1),
            Engine.envelope(.setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0)), 20, from: Engine.watch, seq: 2),
            Engine.envelope(.discarded(endedAt: Engine.at(60)), 60, from: Engine.watch, seq: 3)
        ]
        let state = try #require(try WorkoutReconciler.resolve(WorkoutReconciler.merge([phone, watch])))
        #expect(state.phase == .discarded)
        #expect(state.endedAt == Engine.at(60))
        let finishOnly = try #require(WorkoutReconciler.resolve(phone))
        #expect(finishOnly.phase == .finished)
    }

    @Test("R2: of two discards the earlier applies, even with done sets and no finish")
    func resolve_twoDiscards_earliestApplies() throws {
        let phone = [
            Engine.started(),
            Engine.envelope(Engine.logged(0, 0, at: 10), 10, seq: 2),
            Engine.envelope(.discarded(endedAt: Engine.at(80)), 80, seq: 3)
        ]
        let watch = [Engine.envelope(.discarded(endedAt: Engine.at(50)), 50, from: Engine.watch, seq: 1)]
        let state = try #require(try WorkoutReconciler.resolve(WorkoutReconciler.merge([phone, watch])))
        #expect(state.phase == .discarded)
        #expect(state.endedAt == Engine.at(50))
    }
}

/// Helpers shared by the reconciler suites. They compare logs and states without printing them whole.
enum Reconciling {
    /// `nil` when the logs are equal, else their first difference.
    static func difference(_ lhs: [EventEnvelope], _ rhs: [EventEnvelope]) -> String? {
        guard let index = lhs.indices.first(where: { $0 < rhs.count && lhs[$0] != rhs[$0] }) else {
            return lhs.count == rhs.count ? nil : "\(lhs.count) envelopes vs \(rhs.count)"
        }
        return "envelope \(index): \(lhs[index].key) vs \(rhs[index].key)"
    }

    /// `nil` when the states are equal, else what differs first.
    static func difference(_ lhs: WorkoutState?, _ rhs: WorkoutState?) -> String? {
        guard lhs != rhs else {
            return nil
        }
        guard let lhs, let rhs else {
            return "state \(lhs == nil ? "nil" : "present") vs \(rhs == nil ? "nil" : "present")"
        }
        if lhs.phase != rhs.phase || lhs.endedAt != rhs.endedAt {
            return "phase \(lhs.phase) at \(String(describing: lhs.endedAt)) vs \(rhs.phase) at "
                + String(describing: rhs.endedAt)
        }
        let differs = { (index: Int) in index < rhs.exercises.count && lhs.exercises[index] != rhs.exercises[index] }
        if let index = lhs.exercises.indices.first(where: differs) {
            return "exercise \(index) differs"
        }
        return "done \(lhs.doneSets) vs \(rhs.doneSets); cursor, rest or another field differs"
    }
}
