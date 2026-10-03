import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3 (G2 after fix round 2): `EventEnvelope.isWellFormed` (decision A). False positives that drop
/// a legitimate envelope, and dates or rests it lets through.
@Suite("EventEnvelope · well-formedness (adversarial, round 3)", .tags(.domain))
struct Round3WellFormedAdversarialTests {
    typealias Adv = EngineAdv

    static let hour: Double = 3600
    static let day: Double = 86400

    @Test(
        """
        Held: a 3-hour workout, a 45-minute rest before a set, a +30s after an hour's pause and a finish 20 h \
        after the last set are all well-formed and applied
        """
    )
    func realisticLongSessions_areWellFormed() throws {
        let log = [
            Adv.start(),
            Adv.env(Adv.logged(0, 0, doneAt: 600), seq: 2, at: 600),
            Adv.env(Adv.logged(0, 1, doneAt: 600 + 45 * 60), seq: 3, at: 600 + 45 * 60),
            Adv.env(Adv.extend(shown: false, tappedAt: 3 * Self.hour), seq: 4, at: 3 * Self.hour),
            Adv.env(.finished(endedAt: engineTime(3 * Self.hour)), Adv.watch, seq: 1, at: 23 * Self.hour)
        ]
        let wellFormed = log.allSatisfy(\.isWellFormed)
        #expect(wellFormed)
        let state = try #require(WorkoutEngine.replay(log))
        #expect(state.phase == .finished && state.doneSets == 2)
        #expect(WorkoutEngine.summary(state, prs: []).elapsed == .seconds(3 * 3600))
    }

    /// F23 criterion 6 (decision #8): a live workout idle for 4 h prompts "Still lifting?" on the next
    /// open, and Finish "uses the last activity time as endedAt". The next open can be days later.
    static func stillLifting(openedAfter hours: Double) -> WorkoutState? {
        let lastSet = 3600.0
        let opened = lastSet + hours * 3600
        return WorkoutEngine.replay([
            Adv.start(),
            Adv.env(Adv.logged(0, 0, doneAt: lastSet), seq: 2, at: lastSet),
            Adv.env(.finished(endedAt: engineTime(lastSet)), seq: 3, at: opened)
        ])
    }

    @Test(
        """
        Finding 15: "Still lifting?" → Finish, opened 30 h after the last set, ends the workout at the last \
        set (F23 criterion 6); the 24 h payload window drops it and the workout stays live
        """
    )
    func stillLifting_finishOpenedDaysLater_isKept() throws {
        let control = try #require(Self.stillLifting(openedAfter: 20))
        #expect(control.phase == .finished)
        let weekend = try #require(Self.stillLifting(openedAfter: 30))
        #expect(weekend.phase == .finished, "the lifter's Finish was ignored")
        #expect(weekend.endedAt == engineTime(3600))
        #expect(WorkoutEngine.summary(weekend, prs: []).elapsed == .seconds(3600))
    }

    /// Final fix round (decision 2, no time windows): the 24.5 h row used to be dropped; now every skew is kept.
    @Test(
        """
        Held, and a note for F17: with a peer 23 h, 24.5 h or 30 days ahead, the HLC drags this device's \
        stamps that far past its payload times, and its actions stay well-formed (there is no window)
        """
    )
    func peerClockADayAhead_dragsStamps() async throws {
        for skew in [23.0, 24.5, 30.0 * 24] {
            var phone = LiteralHost(Adv.phone, offset: 0)
            var watch = LiteralHost(Adv.watch, offset: skew * Self.hour)
            try await phone.create(.started(EventBuilders.seedSession()), real: 0)
            try await watch.receive(phone.outbox)
            try await watch.create(.restSkipped, real: 5)
            try await phone.receive(watch.outbox)
            let tap = try await phone.create(Adv.logged(0, 0, doneAt: 60), real: 60)
            #expect(tap != nil, "skew \(skew) h")
            #expect(Adv.row(phone.state, 0, 0)?.isDone == true)
        }
    }

    /// Final fix round (decision 2): the window and its edges are gone, so one millisecond beyond a day is
    /// well-formed too.
    @Test(
        """
        Held: at a realistic fractional stamp, a day either side and a millisecond beyond are well-formed; DST \
        changes nothing
        """
    )
    func edges_atARealisticStamp() {
        let stamp = Date(timeIntervalSinceReferenceDate: 812_345_678.912_345_6)
        func logged(_ offset: Double) -> Bool {
            EventBuilders.envelope(
                .setLogged(
                    exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("185"), reps: Reps(clamping: 5),
                    doneAt: stamp.addingTimeInterval(offset)
                ),
                seq: 2, at: stamp
            ).isWellFormed
        }
        #expect(logged(Self.day) && logged(-Self.day))
        #expect(logged(Self.day + 0.001) && logged(-Self.day - 0.001))
        // 2026-11-01 06:00Z: US clocks fall back an hour. Dates are absolute, so the local repeat is invisible.
        let fallBack = Date(timeIntervalSince1970: 1_793_512_800)
        #expect(EventBuilders.envelope(.finished(endedAt: fallBack), seq: 2, at: fallBack.addingTimeInterval(-1800))
            .isWellFormed)
    }
}

// MARK: - What the predicate lets through, or drops for no reason

extension Round3WellFormedAdversarialTests {
    @Test(
        """
        Finding 16a: a started snapshot's lastPerformance date is not checked; with a NaN one (binary plist) \
        the started is well-formed, two decodes of the same bytes are unequal, and a resent copy is a conflict
        """
    )
    func snapshotLastPerformanceNaN_breaksEquality() async throws {
        var snapshot = EventBuilders.seedSession()
        snapshot.exercises[0].lastPerformance = LastPerformance(
            date: Date(timeIntervalSinceReferenceDate: .nan), sets: 5, reps: 5, load: pounds("180")
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let wire = try encoder.encode(Adv.start(snapshot))
        let (first, resent) = try (
            PropertyListDecoder().decode(EventEnvelope.self, from: wire),
            PropertyListDecoder().decode(EventEnvelope.self, from: wire)
        )
        #expect(!first.isWellFormed, "a non-finite date in the snapshot passes the predicate")
        #expect(WorkoutEngine.replay([first]) == WorkoutEngine.replay([resent]), "the same bytes replay unequal")
        // Final fix round: NaN != NaN, so a store that compares by value still calls the resend a conflict.
        // No predicate can change that; F17 rejects non-finite dates when it decodes a frame, before
        // anything is stored (F17, "Inputs from F04", item 5). This pins why.
        let store = InMemoryWorkoutEventStore()
        _ = try await store.append([first])
        await #expect(throws: EngineError.conflictingEnvelope(first.key)) {
            try await store.append([resent])
        }
    }

    @Test(
        """
        Finding 16b: a setAdded whose set carries a doneAt the engine discards anyway (it adds the row undone) \
        is dropped whole when that date is more than a day from the stamp
        """
    )
    func setAdded_ignoredDoneAt_dropsTheAdd() {
        let row = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD3)), weight: pounds("185"), reps: Reps(clamping: 5), kind: .added,
            doneAt: engineTime(-2 * Self.day)
        )
        let state = WorkoutEngine.replay([Adv.start(), Adv.env(.setAdded(exerciseIndex: 0, set: row), seq: 2, at: 60)])
        #expect(state?.exercises[0].sets.count == 6, "the add was dropped")
    }

    /// Final fix round (decision 2): bounding a rest's end by its stamp is a time window, which Pete ruled
    /// out. The envelopes are kept as given; the ring's arithmetic saturates rather than trap.
    @Test(
        """
        Finding 16c (documents): a restStarted or setLogged that puts a rest's end 23 h after its stamp is \
        well-formed and applied as given; the ring's remaining time and fill stay finite
        """
    )
    func eventRests_farFromTheirStamp_areAppliedAsGiven() {
        let far = engineTime(60 + 23 * Self.hour)
        let started = Adv.env(.restStarted(endsAt: far, total: .seconds(90)), Adv.watch, seq: 1, at: 60)
        let logged = Adv.env(Adv.logged(0, 0, doneAt: 60 + 23 * Self.hour), Adv.watch, seq: 1, at: 60)
        let expected = [RestTimer(endsAt: far, total: .seconds(90)), RestTimer(endsAt: far + 150, total: .seconds(150))]
        for (envelope, rest) in zip([started, logged], expected) {
            #expect(envelope.isWellFormed)
            #expect(WorkoutEngine.replay([Adv.start(), envelope])?.rest == rest)
            #expect(rest.remaining(at: envelope.wallClock) > WorkoutEngine.longestRest)
            #expect(rest.fraction(at: envelope.wallClock) == 1)
        }
    }
}
