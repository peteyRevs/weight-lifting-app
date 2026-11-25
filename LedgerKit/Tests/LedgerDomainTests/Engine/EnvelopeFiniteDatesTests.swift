import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F17 S3: `EventEnvelope.hasFiniteDates`, the receipt check a host runs before it stores a peer's envelope
/// (F17 "Inputs from F05"). It names the same dates `isWellFormed` does, and nothing else.
@Suite("EventEnvelope · finite dates", .tags(.domain))
struct EnvelopeFiniteDatesTests {
    static let notANumber = Date(timeIntervalSinceReferenceDate: .nan)

    /// One event of each kind that carries a date, with that date not finite.
    static let nonFinite: [WorkoutEvent] = {
        var started = EventBuilders.seedSession()
        started.startedAt = notANumber
        let swapped = SwappedExercise(
            equipment: .barbell, step: .pounds(5), load: .pounds(100),
            lastPerformance: LastPerformance(date: notANumber, sets: 3, reps: 5, load: .pounds(100))
        )
        return [
            .started(started),
            Engine.logged(0, 0, at: .nan),
            .setAdded(exerciseIndex: 0, set: LoggedSet(
                id: SetID(EventBuilders.uuid(1)), weight: .zero, reps: .one, kind: .added, doneAt: notANumber
            )),
            .exerciseSwapped(
                exerciseIndex: 0,
                exerciseID: ExerciseID(EventBuilders.uuid(2)),
                name: "Dip",
                alsoUpdateProgram: false,
                replacement: swapped
            ),
            .restStarted(endsAt: notANumber, total: .seconds(60)),
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: notANumber),
            .finished(endedAt: notANumber),
            .discarded(endedAt: notANumber)
        ]
    }()

    @Test("A date that is not finite, in any event that carries one, fails the check", arguments: nonFinite)
    func nonFiniteDate_fails(event: WorkoutEvent) {
        let envelope = Engine.envelope(event, 10, from: Engine.watch, seq: 2)
        #expect(!envelope.hasFiniteDates && !envelope.isWellFormed)
    }

    @Test("Every late event of the engine's suites has finite dates, and so does a stamp at any finite time")
    func finiteDates_pass() {
        for event in ReduceTerminalTests.lateEvents {
            #expect(Engine.envelope(event, 10, seq: 2).hasFiniteDates)
        }
        #expect(!EventBuilders.envelope(.restSkipped, seq: 2, at: Self.notANumber).hasFiniteDates)
        #expect(EventBuilders.envelope(.restSkipped, seq: 2, at: .distantFuture).hasFiniteDates)
    }

    @Test("A rest length out of range is malformed, but its dates are finite: the host stores it")
    func badRestLength_hasFiniteDates() {
        let envelope = Engine.envelope(.restStarted(endsAt: Engine.at(100), total: .seconds(-1)), 10, seq: 2)
        #expect(envelope.hasFiniteDates && !envelope.isWellFormed)
    }
}
