import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 4 (G2 close-out after the re-plan): with the time windows gone, a finite date can be anything, so
/// the engine's arithmetic must saturate rather than trap, and a replayed state must still equal itself.
@Suite("WorkoutEngine · extreme finite dates (adversarial, round 4)", .tags(.domain))
struct Round4ExtremeDateAdversarialTests {
    typealias Adv = EngineAdv

    static let extremes: [Double] = [
        1e15, -1e15,
        Date.distantFuture.timeIntervalSinceReferenceDate, Date.distantPast.timeIntervalSinceReferenceDate,
        .greatestFiniteMagnitude, -.greatestFiniteMagnitude
    ]

    /// `log` decoded twice from the same bytes, as two devices (or two launches) would read it.
    static func decodedTwice(_ log: [EventEnvelope], json: Bool) throws -> ([EventEnvelope], [EventEnvelope]) {
        if json {
            let data = try JSONEncoder().encode(log)
            return try (
                JSONDecoder().decode([EventEnvelope].self, from: data),
                JSONDecoder().decode([EventEnvelope].self, from: data)
            )
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(log)
        return try (
            PropertyListDecoder().decode([EventEnvelope].self, from: data),
            PropertyListDecoder().decode([EventEnvelope].self, from: data)
        )
    }

    /// Reads every public computed value a host or F05 reads, at the extreme and at ordinary times.
    static func readEverything(_ state: WorkoutState, near date: Date) {
        let nows = [
            date, engineTime(0), Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude),
            Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude)
        ]
        for now in nows {
            _ = state.elapsed(at: now)
            if let rest = state.rest {
                let fill = rest.fraction(at: now)
                #expect(rest.remaining(at: now) >= .zero && fill >= 0 && fill <= 1)
            }
        }
        _ = WorkoutEngine.summary(state, prs: [])
        _ = (state.volume, state.doneSets, state.totalSets)
        _ = WorkoutEngine.effects(from: nil, to: state)
    }

    /// Every slot at once: a snapshot carrying the date everywhere, then every dated event, all stamped
    /// with it too.
    static func everySlot(_ date: Date) -> [EventEnvelope] {
        var snapshot = Round4WellFormedAdversarialTests.session()
        snapshot.startedAt = date
        snapshot.rest = RestTimer(endsAt: date, total: .seconds(90))
        snapshot.exercises[2].sets[3].doneAt = date
        snapshot.exercises[4].lastPerformance = LastPerformance(date: date, sets: 3, reps: 8, load: pounds("50"))
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD5)), weight: pounds("185"), reps: Reps(clamping: 5), kind: .added,
            doneAt: date
        )
        let events: [WorkoutEvent] = [
            .setLogged(
                exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("185"), reps: Reps(clamping: 5), doneAt: date
            ),
            .setAdded(exerciseIndex: 1, set: added),
            .restStarted(endsAt: date, total: .seconds(120)),
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: date),
            .restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: date),
            .setLogged(
                exerciseIndex: 1, setID: Adv.sid(1, 0), weight: pounds("55"), reps: Reps(clamping: 10), doneAt: date
            ),
            .restExtended(amount: WorkoutEngine.longestRest, extendsShownRest: true, tappedAt: date),
            .finished(endedAt: date)
        ]
        let start = EventEnvelope(
            event: .started(snapshot), workoutID: Adv.workoutID, device: Adv.phone, seq: 1, wallClock: date
        )
        return [start] + events.enumerated().map { index, event in
            EventEnvelope(
                event: event,
                workoutID: Adv.workoutID,
                device: Adv.watch,
                seq: UInt64(index + 1),
                wallClock: date
            )
        }
    }

    @Test(
        """
        1e15 s, distantFuture, distantPast and ±greatestFiniteMagnitude in every date slot, one at a time and \
        all at once: well-formed, applied, no trap, the state equals itself across two JSON and two plist \
        decodes, the sorted reduce fold and the oracle agree, and every computed value can be read
        """,
        arguments: extremes
    )
    func extremeFiniteDates_neverTrap_andEqualThemselves(seconds: Double) throws {
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        var logs = Round4WellFormedAdversarialTests.slots(date)
        logs.append(("every slot at once", Self.everySlot(date)))
        for (name, log) in logs {
            let wellFormed = log.allSatisfy(\.isWellFormed)
            #expect(wellFormed, "\(name) = \(seconds) was rejected")
            let state = try #require(WorkoutEngine.replay(log), "\(name): no workout")
            #expect(state == state && WorkoutEngine.replay(log) == state)
            for json in [true, false] {
                let (first, second) = try Self.decodedTwice(log, json: json)
                let replayed = WorkoutEngine.replay(first)
                #expect(replayed == WorkoutEngine.replay(second) && replayed == state, "\(name), json: \(json)")
            }
            #expect(Adv.state(after: log.sorted()) == state, "\(name): the sorted reduce fold differs")
            #expect(ModelOracle.replay(log) == state, "\(name): the oracle differs")
            Self.readEverything(state, near: date)
        }
        let all = try #require(WorkoutEngine.replay(Self.everySlot(date)))
        #expect(all.phase == .finished && all.endedAt == date)
    }
}
