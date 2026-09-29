import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Every event and envelope survives encode/decode (JSON and binary plist) exactly, dates included,
/// and the envelope order and replay survive with them; the envelope order is a strict total order.
@Suite("WorkoutEngine · Codable and ordering (adversarial)", .tags(.domain))
struct CodableOrderingAdversarialTests {
    typealias Adv = EngineAdv

    static let everyEvent: [WorkoutEvent] = [.started(snapshot())] + rowEvents() + clockEvents()

    /// A snapshot with a sub-second rest, a program update and exact weights.
    static func snapshot() -> WorkoutState {
        var snapshot = EventBuilders.seedSession()
        snapshot.rest = RestTimer(endsAt: engineTime(1.000_000_1), total: .milliseconds(1500))
        snapshot.programUpdates = [SlotID(EventBuilders.uuid(0xE000)): ExerciseID(EventBuilders.uuid(0xA1))]
        return snapshot
    }

    static func rowEvents() -> [WorkoutEvent] {
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: pounds("187.5"), reps: Reps.one, kind: .added,
            doneAt: engineTime(0.3)
        )
        let exact = Weight(grams: dec("83914.58845"))
        return [
            .exerciseSelected(exerciseIndex: Int.max, setIndex: -1),
            .setLogged(
                exerciseIndex: 0,
                setID: Adv.sid(0, 0),
                weight: exact,
                reps: Reps.one,
                doneAt: engineTime(0.123_456_7)
            ),
            .setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)),
            .setTargetChanged(exerciseIndex: 1, setID: Adv.sid(1, 0), weight: nil, reps: Reps(clamping: 12)),
            .setTargetChanged(exerciseIndex: 1, setID: Adv.sid(1, 0), weight: Weight.zero - pounds("2.5"), reps: nil),
            .setAdded(exerciseIndex: 2, set: added),
            .allSetsRepeated(exerciseIndex: 3, weight: .kilograms(dec("102.5")), reps: Reps(clamping: 5)),
            .exerciseSwapped(
                exerciseIndex: 4, exerciseID: ExerciseID(EventBuilders.uuid(0xA2)), name: "Upright Row · \"é\"",
                alsoUpdateProgram: true
            )
        ]
    }

    static func clockEvents() -> [WorkoutEvent] {
        [
            .restStarted(endsAt: .distantFuture, total: .nanoseconds(1)),
            .restExtended(amount: .seconds(-30)),
            .restSkipped,
            .finished(endedAt: engineTime(3600.5)),
            .discarded(endedAt: .distantPast)
        ]
    }

    static func jsonRoundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    static func plistRoundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try PropertyListDecoder().decode(T.self, from: encoder.encode(value))
    }

    @Test("Every WorkoutEvent case round-trips through JSON and binary plist unchanged.")
    func everyEvent_roundTrips() throws {
        for event in Self.everyEvent {
            #expect(try Self.jsonRoundTrip(event) == event, "\(event)")
            #expect(try Self.plistRoundTrip(event) == event, "\(event)")
        }
    }

    @Test("Envelopes round-trip with key, wall clock (sub-microsecond) and order intact.")
    func envelopes_roundTripWithOrder() throws {
        let devices = [Adv.phone, Adv.watch, Adv.tablet]
        let envelopes = Self.everyEvent.enumerated().map { offset, event in
            // Wall clocks 1 ulp-ish apart and ties across devices.
            EventEnvelope(
                event: event, workoutID: Adv.workoutID, device: devices[offset % 3], seq: UInt64.max - UInt64(offset),
                wallClock: engineTime(Double(offset / 3) * 0.000_000_2)
            )
        }
        let decoded = try Self.jsonRoundTrip(envelopes)
        #expect(decoded == envelopes)
        #expect(decoded.map(\.key) == envelopes.map(\.key))
        #expect(decoded.sorted() == envelopes.sorted())
        #expect(try Self.plistRoundTrip(envelopes) == envelopes)
    }

    @Test(
        "A random multi-device log replays to the same state after a JSON round-trip.",
        arguments: PropertySeed.all.prefix(50)
    )
    func log_replaysSameAfterRoundTrip(seed: PropertySeed) throws {
        let (scenario, _) = ConvergencePropertyAdversarialTests.scenario(seed)
        let decoded = try Self.jsonRoundTrip(scenario.all)
        #expect(WorkoutEngine.replay(decoded) == WorkoutEngine.replay(scenario.all))
        #expect(try Self.jsonRoundTrip(WorkoutEngine.replay(scenario.all)) == WorkoutEngine.replay(scenario.all))
    }

    @Test("Reps ≥ 1 is enforced on the wire: an event carrying reps 0 fails to decode.")
    func repsZero_failsToDecode() throws {
        let event = WorkoutEvent.setLogged(
            exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("100"), reps: Reps(clamping: 7),
            doneAt: engineTime(1)
        )
        let text = try #require(String(data: JSONEncoder().encode(event), encoding: .utf8))
        #expect(text.contains("\"reps\":7"))
        let tampered = Data(text.replacingOccurrences(of: "\"reps\":7", with: "\"reps\":0").utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WorkoutEvent.self, from: tampered) }
    }
}

// MARK: - Ordering (rule 12)

extension CodableOrderingAdversarialTests {
    @Test(
        "Rule 12: ties on wall clock break by device (uuidString order) then seq; the order is strict and total.",
        arguments: PropertySeed.all.prefix(50)
    )
    func order_isStrictTotalAndMatchesSpelledOutKey(seed: PropertySeed) {
        var generator = seed.generator
        let devices = (0 ..< 4).map { _ in DeviceID(generator.uuid()) }
        var seen = Set<EnvelopeKey>()
        let envelopes = (0 ..< 40).map { _ in
            Adv.env(
                .restSkipped,
                devices.randomElement(using: &generator) ?? Adv.phone,
                seq: UInt64.random(in: 1 ... 5, using: &generator),
                at: Double(Int.random(
                    in: 0 ... 2,
                    using: &generator
                ))
            )
        }.filter { seen.insert($0.key).inserted }
        for lhs in envelopes {
            #expect(!(lhs < lhs))
            for rhs in envelopes where lhs.key != rhs.key {
                #expect((lhs < rhs) != (rhs < lhs), "not total on \(lhs.key) / \(rhs.key)")
                #expect((lhs < rhs) == ModelOracle.precedes(lhs, rhs))
                let spelled = (lhs.wallClock, lhs.device.rawValue.uuidString, lhs.seq)
                    < (rhs.wallClock, rhs.device.rawValue.uuidString, rhs.seq)
                #expect((lhs < rhs) == spelled)
            }
        }
    }

    /// Finding 7 (orchestrator decision, 2026-09-29): unique keys are a precondition, enforced by
    /// `WorkoutEventStore.append` and checked by F17 on receive; `replay` breaks no tie.
    @Test(
        """
        Rule 12 precondition: of two different envelopes sharing a key, the store keeps whichever came \
        first and rejects the other, so the log that replay reads never holds both.
        """
    )
    func conflictingKey_storeRejectsSecond_replayPrecondition() async throws {
        let logA = Adv.env(Adv.logged(0, 0, doneAt: 10), Adv.watch, seq: 1, at: 10)
        let extendB = Adv.env(.restExtended(amount: .seconds(60)), Adv.watch, seq: 1, at: 10)
        // A reinstalled or restored watch can reuse a seq it already sent (EngineError.conflictingEnvelope).
        for (first, second) in [(logA, extendB), (extendB, logA)] {
            let store: any WorkoutEventStore = InMemoryEventStore()
            _ = try await store.append([Adv.start(), first])
            await #expect(throws: EngineError.conflictingEnvelope(second.key)) {
                try await store.append([second])
            }
            let stored = try await store.envelopes(for: Adv.workoutID)
            #expect(Set(stored) == [Adv.start(), first])
            #expect(WorkoutEngine.replay(stored) == WorkoutEngine.replay([Adv.start(), first]))
        }
    }
}
