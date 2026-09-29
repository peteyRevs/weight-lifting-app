import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Fix round 2, orchestrator decision A, as the re-plan (2026-09-29, decision 2) narrowed it:
/// `EventEnvelope.isWellFormed` has no time window. One clause per test, and what `reduce` and `replay`
/// do with a malformed envelope (nothing).
@Suite("EventEnvelope · well-formedness (decision A, re-plan)", .tags(.domain))
struct EnvelopeWellFormedTests {
    static let hour = WorkoutEngine.longestRest
    static let day: TimeInterval = 86400

    /// `event` from the watch, stamped at 100 s.
    static func stamped(_ event: WorkoutEvent, at seconds: TimeInterval = 100) -> EventEnvelope {
        Engine.envelope(event, seconds, from: Engine.watch, seq: 1)
    }

    /// A date `offset` seconds from the 100 s stamp.
    static func near(_ offset: TimeInterval) -> Date {
        Engine.at(100 + offset)
    }

    /// Any finite date is well-formed, however far from the stamp; a non-finite one never is.
    static let dates: [(Date, Bool)] = [
        (near(0), true),
        (near(-day - 0.001), true),
        (near(30 * day), true),
        (Date(timeIntervalSinceReferenceDate: 1e21), true),
        (Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude), true),
        (.distantFuture, true),
        (Date(timeIntervalSinceReferenceDate: .infinity), false),
        (Date(timeIntervalSinceReferenceDate: -.infinity), false),
        (Date(timeIntervalSinceReferenceDate: .nan), false)
    ]

    @Test("Every payload date must be finite; there is no window around the stamp")
    func payloadDates_mustBeFinite() {
        for (date, wellFormed) in Self.dates {
            let set = LoggedSet(
                id: SetID(EventBuilders.uuid(0xADD)),
                weight: .zero,
                reps: .one,
                kind: .added,
                doneAt: date
            )
            let events: [WorkoutEvent] = [
                .setLogged(exerciseIndex: 0, setID: Engine.set(0, 0), weight: .pounds(185), reps: .one, doneAt: date),
                .setAdded(exerciseIndex: 0, set: set),
                .restStarted(endsAt: date, total: .seconds(90)),
                .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: date),
                .finished(endedAt: date),
                .discarded(endedAt: date)
            ]
            for event in events {
                #expect(Self.stamped(event).isWellFormed == wellFormed, "\(event)")
            }
        }
    }

    @Test("A stamp that is not finite makes any envelope malformed, even one that carries no date")
    func nonFiniteStamp_isMalformed() {
        for seconds in [Double.nan, .infinity, -.infinity] {
            let envelope = EventBuilders.envelope(
                .restSkipped, device: Engine.watch, seq: 1, at: Date(timeIntervalSinceReferenceDate: seconds)
            )
            #expect(!envelope.isWellFormed)
        }
        // A finite but absurd stamp is only an ordering key; F17's drift bound owns it.
        #expect(Self.stamped(.restSkipped, at: 1e21).isWellFormed)
        #expect(Self.stamped(.exerciseSelected(exerciseIndex: -1, setIndex: .max)).isWellFormed)
    }

    @Test("A rest length must lie in 0…longestRest, for restStarted and for +30s")
    func restLengths_liesWithinTheBound() {
        let lengths: [(Duration, Bool)] = [
            (.zero, true),
            (Self.hour, true),
            (Duration(attoseconds: -1), false),
            (Self.hour + Duration(attoseconds: 1), false),
            (Duration(attoseconds: .max), false),
            (Duration(attoseconds: .min), false)
        ]
        for (length, wellFormed) in lengths {
            #expect(Self.stamped(.restStarted(endsAt: Self.near(60), total: length)).isWellFormed == wellFormed)
            let extend = WorkoutEvent.restExtended(amount: length, extendsShownRest: false, tappedAt: Self.near(0))
            #expect(Self.stamped(extend).isWellFormed == wellFormed)
        }
    }

    @Test("A started snapshot: every date it carries finite, and a rest length the engine could hold")
    func startedSnapshot_isInternallyPossible() {
        func started(_ edit: (inout WorkoutState) -> Void) -> EventEnvelope {
            var snapshot = EventBuilders.seedSession()
            edit(&snapshot)
            return Engine.envelope(.started(snapshot), 0, seq: 1)
        }
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        let far = Date(timeIntervalSinceReferenceDate: 1e21)
        #expect(started { _ in }.isWellFormed)
        // Far but finite dates, and a rest ending long after the start: no window, so well-formed.
        #expect(started { $0.startedAt = far }.isWellFormed)
        #expect(started { $0.rest = RestTimer(endsAt: $0.startedAt.addingTimeInterval(7200), total: Self.hour) }
            .isWellFormed)
        #expect(!started { $0.startedAt = Date(timeIntervalSinceReferenceDate: .infinity) }.isWellFormed)
        #expect(!started { $0.endedAt = nan }.isWellFormed)
        #expect(!started { $0.exercises[0].sets[0].doneAt = nan }.isWellFormed)
        #expect(!started { $0.rest = RestTimer(endsAt: nan, total: .seconds(60)) }.isWellFormed)
        // Finding 16a: a last performance's date is a date the snapshot carries too.
        #expect(!started { $0.exercises[0].lastPerformance = LastPerformance(
            date: nan, sets: 3, reps: 8, load: .pounds(50)
        ) }.isWellFormed)
        // Internally impossible rests: a negative total, or one longer than the engine keeps.
        #expect(!started { $0.rest = RestTimer(endsAt: $0.startedAt, total: .seconds(-1)) }.isWellFormed)
        #expect(!started { $0.rest = RestTimer(endsAt: $0.startedAt, total: Self.hour * 2) }.isWellFormed)
    }

    @Test("reduce: a malformed envelope changes nothing and emits nothing, not even persist or transmit")
    func reduce_ignoresMalformed() throws {
        let live = try Engine.live()
        let absurd = Self.stamped(Engine.logged(0, 0, at: .nan))
        #expect(!absurd.isWellFormed)
        let (state, effects) = WorkoutEngine.reduce(live, absurd)
        #expect(state == live)
        #expect(effects.isEmpty)
        var hostile = EventBuilders.seedSession()
        hostile.rest = RestTimer(endsAt: Engine.at(0), total: Self.hour * 2)
        #expect(WorkoutEngine.reduce(nil, Engine.started(hostile)) == (nil, []))
    }

    @Test("replay: malformed envelopes are dropped before the fold, so a malformed started never picks the workout")
    func replay_dropsMalformed() {
        var hostile = EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(0xBAD)))
        hostile.startedAt = Date(timeIntervalSinceReferenceDate: .nan)
        let early = EventBuilders.envelope(.started(hostile), device: Engine.watch, seq: 1, at: Engine.at(-5))
        let log = [early, Engine.started(), Engine.envelope(Engine.logged(0, 0, at: .infinity), 10, seq: 2)]
        #expect(WorkoutEngine.foldOrder(log) == [Engine.started()])
        #expect(WorkoutEngine.replay(log) == WorkoutEngine.replay([Engine.started()]))
        #expect(ModelOracle.replay(log) == WorkoutEngine.replay(log))
    }
}
