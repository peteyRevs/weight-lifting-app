import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 4 (G2 close-out after the re-plan, 2026-09-29): the narrowed `isWellFormed`. It rejects only a
/// non-finite date and a rest length outside `0 ... longestRest`; every finite date is kept, and the
/// engine's arithmetic must saturate on it. Written from ADR-004 "Malformed envelopes" and the public API.
@Suite("WorkoutEngine · narrowed well-formedness (adversarial, round 4)", .tags(.domain))
struct Round4WellFormedAdversarialTests {
    typealias Adv = EngineAdv

    static let day: TimeInterval = 86400

    /// A session whose last exercise ends in a drop row, so a snapshot carries every kind of set.
    static func session() -> WorkoutState {
        EventBuilders.session(EventBuilders.seedExercises + [Adv.spec("Dips", sets: 2, rest: 60, drop: true)])
    }

    /// Every place an envelope carries a date, filled with `date`, everything else realistic. The log each
    /// sits in: a `started` snapshot alone, or the plain start then the event.
    static func slots(_ date: Date) -> [(name: String, log: [EventEnvelope])] {
        let start = Adv.start(session())
        let events = eventSlots(date).map { name, event in
            (name, [start, Adv.env(event, Adv.watch, seq: 1, at: 60)])
        }
        let stamp = EventEnvelope(
            event: .restSkipped, workoutID: Adv.workoutID, device: Adv.watch, seq: 1, wallClock: date
        )
        return [("wallClock", [start, stamp])] + events + snapshotSlots(date)
    }

    static func eventSlots(_ date: Date) -> [(String, WorkoutEvent)] {
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD4)), weight: pounds("185"), reps: Reps(clamping: 5), kind: .added,
            doneAt: date
        )
        let logged = WorkoutEvent.setLogged(
            exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("185"), reps: Reps(clamping: 5), doneAt: date
        )
        return [
            ("setLogged.doneAt", logged),
            ("setAdded set.doneAt", .setAdded(exerciseIndex: 1, set: added)),
            ("restStarted.endsAt", .restStarted(endsAt: date, total: .seconds(90))),
            (
                "restExtended.tappedAt, shown",
                .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: date)
            ),
            (
                "restExtended.tappedAt, not shown",
                .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: date)
            ),
            ("finished.endedAt", .finished(endedAt: date)),
            ("discarded.endedAt", .discarded(endedAt: date))
        ]
    }

    static func snapshotSlots(_ date: Date) -> [(String, [EventEnvelope])] {
        func snapshot(_ edit: (inout WorkoutState) -> Void) -> [EventEnvelope] {
            var state = session()
            edit(&state)
            return [Adv.start(state)]
        }
        let last = session().exercises.count - 1
        return [
            ("snapshot.startedAt", snapshot { $0.startedAt = date }),
            ("snapshot.endedAt", snapshot { $0.endedAt = date }),
            ("snapshot.rest.endsAt", snapshot { $0.rest = RestTimer(endsAt: date, total: .seconds(90)) }),
            ("snapshot last exercise's drop row doneAt", snapshot { state in
                state.exercises[last].sets[state.exercises[last].sets.count - 1].doneAt = date
            }),
            ("snapshot last exercise's lastPerformance.date", snapshot {
                $0.exercises[last].lastPerformance = LastPerformance(date: date, sets: 3, reps: 8, load: pounds("50"))
            })
        ]
    }

    @Test(
        "Every non-finite date is caught in every slot, snapshot dates included; reduce and replay ignore it",
        arguments: [Double.infinity, -.infinity, .nan]
    )
    func everyNonFiniteDate_isMalformed(seconds: Double) throws {
        for (name, log) in Self.slots(Date(timeIntervalSinceReferenceDate: seconds)) {
            let hostile = try #require(log.last)
            #expect(!hostile.isWellFormed, "\(name) = \(seconds) is well-formed")
            let before = WorkoutEngine.replay(log.dropLast())
            let (state, effects) = WorkoutEngine.reduce(before, hostile)
            #expect(state == before && effects.isEmpty, "\(name): reduce applied it")
            #expect(WorkoutEngine.replay(log) == before, "\(name): replay applied it")
            #expect(ModelOracle.replay(log) == before, "\(name): the oracle disagrees")
        }
    }

    @Test(
        """
        Rest lengths: 0 and exactly longestRest are well-formed; one attosecond outside, and both Duration \
        extremes, are malformed, in restStarted, restExtended and a snapshot's rest
        """
    )
    func restLengths_outsideTheBound_areMalformed() {
        let hour = WorkoutEngine.longestRest
        let atto = Duration(attoseconds: 1)
        let cases: [(Duration, Bool)] = [
            (.zero, true), (hour, true), (.seconds(30), true),
            (.zero - atto, false), (hour + atto, false),
            (Duration(attoseconds: .max), false), (Duration(attoseconds: .min), false)
        ]
        for (length, wellFormed) in cases {
            var snapshot = Self.session()
            snapshot.rest = RestTimer(endsAt: engineTime(90), total: length)
            let envelopes = [
                Adv.env(.restStarted(endsAt: engineTime(150), total: length), Adv.watch, seq: 1, at: 60),
                Adv.env(
                    .restExtended(amount: length, extendsShownRest: true, tappedAt: engineTime(60)),
                    seq: 2,
                    at: 60
                ),
                Adv.env(
                    .restExtended(amount: length, extendsShownRest: false, tappedAt: engineTime(60)),
                    seq: 3,
                    at: 60
                ),
                Adv.start(snapshot)
            ]
            for envelope in envelopes {
                #expect(envelope.isWellFormed == wellFormed, "\(length) in \(envelope.event)")
                let log = envelope.seq == 1 && envelope.device == Adv.phone ? [envelope] : [Adv.start(), envelope]
                #expect(ModelOracle.replay(log) == WorkoutEngine.replay(log), "\(length): the oracle disagrees")
            }
        }
    }
}

// MARK: - Legitimate envelopes are never dropped

extension Round4WellFormedAdversarialTests {
    @Test(
        """
        "Still lifting?" through two HLC hosts: the phone is opened 30 days after its last set and taps Finish \
        at the last set; both devices end the workout there, and the watch's rebuild materialises it silently
        """
    )
    func stillLifting_thirtyDaysLate_onTwoHosts() async throws {
        var phone = LiteralHost(Adv.phone, offset: 0)
        var watch = LiteralHost(Adv.watch, offset: -7.25)
        try await phone.create(.started(EventBuilders.seedSession()), real: 0)
        try await watch.receive(phone.outbox)
        try await watch.create(Adv.logged(0, 0, doneAt: 60 - 7.25), real: 60)
        try await phone.receive(watch.outbox)
        try await phone.create(Adv.logged(0, 1, doneAt: 3600), real: 3600)
        let finish = try await phone.create(.finished(endedAt: engineTime(3600)), real: 3600 + 30 * Self.day)
        #expect(finish != nil, "the Finish was dropped")
        try await watch.receive(phone.outbox)
        for host in [phone, watch] {
            let state = try #require(host.state)
            #expect(state.phase == .finished && state.endedAt == engineTime(3600), "\(host.device)")
            #expect(WorkoutEngine.summary(state, prs: []).elapsed == .seconds(3600))
            #expect(host.materialized == state && host.mismatches == 0)
        }
        #expect(watch.haptics[.rebuild] == nil, "the watch buzzed for a finished rebuild")
    }

    @Test(
        """
        A 4 h two-device workout (18 sets, +30s taps, ±7 s skew) finishes with every set done and elapsed \
        4 h; a backdated finish before the start ends at elapsed 0; a discard backdated 30 days is kept
        """
    )
    func longWorkout_andBackdatedEnds_areKept() throws {
        var log = [Adv.start()]
        var seqs = [Adv.phone: UInt64(1)]
        func add(_ event: WorkoutEvent, _ device: DeviceID, at seconds: Double) {
            seqs[device, default: 0] += 1
            log.append(Adv.env(event, device, seq: seqs[device, default: 0], at: seconds))
        }
        let rows = EventBuilders.seedSession().exercises.enumerated().flatMap { index, exercise in
            exercise.sets.indices.map { (index, $0) }
        }
        for (step, row) in rows.enumerated() {
            let real = Double(step + 1) * 800
            let device = step.isMultiple(of: 3) ? Adv.watch : Adv.phone
            let clock = real + (device == Adv.watch ? -7 : 0)
            add(Adv.logged(row.0, row.1, doneAt: clock), device, at: real)
            if step.isMultiple(of: 4) {
                add(Adv.extend(shown: true, tappedAt: clock + 20), device, at: real + 20)
            }
        }
        add(.finished(endedAt: engineTime(14400)), Adv.phone, at: 14400)
        let wellFormed = log.allSatisfy(\.isWellFormed)
        #expect(wellFormed)
        let state = try #require(WorkoutEngine.replay(log))
        #expect(state.phase == .finished && state.doneSets == rows.count && rows.count == 18)
        #expect(WorkoutEngine.summary(state, prs: []).elapsed == .seconds(14400))
        #expect(state == Adv.state(after: log) && state == ModelOracle.replay(log.reversed()))
        // The watch, 20 s behind, finishes 10 s after the start: its endedAt is before startedAt.
        let early = try #require(WorkoutEngine.replay([Adv.start(), Adv.env(
            .finished(endedAt: engineTime(-10)), Adv.watch, seq: 1, at: 10
        )]))
        #expect(early.phase == .finished && WorkoutEngine.summary(early, prs: []).elapsed == .zero)
        let discard = Adv.env(.discarded(endedAt: engineTime(60)), seq: 2, at: 60 + 30 * Self.day)
        #expect(WorkoutEngine.replay([Adv.start(), discard])?.phase == .discarded)
    }
}
