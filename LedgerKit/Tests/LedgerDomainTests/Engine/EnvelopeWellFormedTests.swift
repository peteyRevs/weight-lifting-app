import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Fix round 2, orchestrator decision A: `EventEnvelope.isWellFormed`, one clause per test, and what
/// `reduce` and `replay` do with a malformed envelope (nothing).
@Suite("EventEnvelope · well-formedness (decision A)", .tags(.domain))
struct EnvelopeWellFormedTests {
    static let day = EventEnvelope.payloadTimeWindow / .seconds(1)
    static let hour = WorkoutEngine.longestRest

    /// `event` from the watch, stamped at 100 s.
    static func stamped(_ event: WorkoutEvent, at seconds: TimeInterval = 100) -> EventEnvelope {
        Engine.envelope(event, seconds, from: Engine.watch, seq: 1)
    }

    /// A date `offset` seconds from the 100 s stamp.
    static func near(_ offset: TimeInterval) -> Date {
        Engine.at(100 + offset)
    }

    /// Dates on and just beyond the window's edges, plus non-finite ones.
    static let dates: [(Date, Bool)] = [
        (near(0), true),
        (near(-day), true),
        (near(day), true),
        (near(-day - 0.001), false),
        (near(day + 0.001), false),
        (Date(timeIntervalSinceReferenceDate: 1e21), false),
        (Date(timeIntervalSinceReferenceDate: .infinity), false),
        (Date(timeIntervalSinceReferenceDate: -.infinity), false),
        (Date(timeIntervalSinceReferenceDate: .nan), false)
    ]

    @Test("The payload window is a day")
    func payloadWindow_isADay() {
        #expect(EventEnvelope.payloadTimeWindow == .seconds(86400))
    }

    @Test("Every payload date must lie within a day of the stamp; a non-finite one never does")
    func payloadDates_liesWithinTheWindow() {
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

    @Test("A started snapshot: every date within the window, and a rest the engine could hold")
    func startedSnapshot_isInternallyValid() {
        func started(_ edit: (inout WorkoutState) -> Void) -> EventEnvelope {
            var snapshot = EventBuilders.seedSession()
            edit(&snapshot)
            return Engine.envelope(.started(snapshot), 0, seq: 1)
        }
        let absurd = Date(timeIntervalSinceReferenceDate: 1e21)
        #expect(started { _ in }.isWellFormed)
        #expect(started { $0.rest = RestTimer(endsAt: $0.startedAt.addingTimeInterval(3600), total: Self.hour) }
            .isWellFormed)
        #expect(!started { $0.startedAt = absurd }.isWellFormed)
        #expect(!started { $0.endedAt = Date(timeIntervalSinceReferenceDate: .nan) }.isWellFormed)
        #expect(!started { $0.exercises[0].sets[0].doneAt = absurd }.isWellFormed)
        #expect(!started { $0.rest = RestTimer(endsAt: absurd, total: .seconds(60)) }.isWellFormed)
        // Internally invalid: longer than an hour, or ending more than an hour after the workout starts.
        #expect(!started { $0.rest = RestTimer(endsAt: $0.startedAt, total: Self.hour * 2) }.isWellFormed)
        #expect(!started { $0.rest = RestTimer(endsAt: $0.startedAt.addingTimeInterval(3601), total: .seconds(60)) }
            .isWellFormed)
    }

    @Test("reduce: a malformed envelope changes nothing and emits nothing, not even persist or transmit")
    func reduce_ignoresMalformed() throws {
        let live = try Engine.live()
        let absurd = Self.stamped(Engine.logged(0, 0, at: 1e9))
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
        let log = [early, Engine.started(), Engine.envelope(Engine.logged(0, 0, at: 1e9), 10, seq: 2)]
        #expect(WorkoutEngine.foldOrder(log) == [Engine.started()])
        #expect(WorkoutEngine.replay(log) == WorkoutEngine.replay([Engine.started()]))
        #expect(ModelOracle.replay(log) == WorkoutEngine.replay(log))
    }
}
