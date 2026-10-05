import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization

/// Shared pieces of the F10 S1 adversarial suites (G2 round 1): the session seam (`WorkoutSessionClient`,
/// `FakeWorkoutSessionClient`, `WorkoutSessionClientContract`). Every expected value comes from the brief's
/// criteria and from `WorkoutEngine.reduce` run here (`SeamOracle`), never from the fake or the contract.
enum Seam {
    typealias Update = WorkoutSessionUpdate

    static let infinity = Date(timeIntervalSinceReferenceDate: .infinity)
    static let minusInfinity = Date(timeIntervalSinceReferenceDate: -.infinity)
    static let notANumber = Date(timeIntervalSinceReferenceDate: .nan)
    /// The dates ADR-004 has the engine ignore.
    static let nonFinite = [infinity, minusInfinity, notANumber]

    /// `seconds` after the fixture start.
    static func at(_ seconds: Double) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    static func workout(_ number: Int) -> WorkoutID {
        WorkoutID(EventBuilders.uuid(0xAD0000 + number))
    }

    /// A live snapshot for workout `number`.
    static func session(
        _ number: Int,
        _ specs: [EventBuilders.ExerciseSpec] = EventBuilders.seedExercises,
        autoRest: Bool = true
    ) -> WorkoutState {
        EventBuilders.session(specs, id: workout(number), autoRest: autoRest)
    }

    /// The set of row (`exerciseIndex`, `setIndex`) of `session(number)`.
    static func setID(_ exerciseIndex: Int, _ setIndex: Int, in number: Int) -> SetID {
        EventBuilders.setID(exerciseIndex, setIndex, workout: workout(number))
    }

    /// A set no session holds until it is added.
    static func freshSet(_ number: Int) -> LoggedSet {
        LoggedSet(id: SetID(EventBuilders.uuid(0x5E0000 + number)), weight: .pounds(45), reps: .one, kind: .added)
    }

    /// Row (`exerciseIndex`, `setIndex`) of `session(number)` logged at 185 lb × 5.
    static func logged(_ exerciseIndex: Int, _ setIndex: Int, in number: Int, at seconds: Double = 60) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exerciseIndex,
            setID: setID(exerciseIndex, setIndex, in: number),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: at(seconds)
        )
    }

    /// The forwarding rule, written here from criterion 3: the haptics, in the engine's order.
    static func haptics(_ effects: [Effect]) -> [Effect] {
        effects.filter { effect in
            if case .haptic = effect {
                return true
            }
            return false
        }
    }

    /// What the engine makes of `event` on `state`, stamped as any one device would stamp it.
    static func engine(
        _ state: WorkoutState?,
        _ event: WorkoutEvent,
        in workout: WorkoutID
    ) -> (WorkoutState?, [Effect]) {
        let envelope = EventEnvelope(
            event: event,
            workoutID: workout,
            device: EventBuilders.phone,
            seq: 1,
            wallClock: EventBuilders.start
        )
        return WorkoutEngine.reduce(state, envelope)
    }

    /// The update criterion 3 asks for when `event` is applied to `state`; nil when the engine ignores it.
    static func update(after event: WorkoutEvent, on state: WorkoutState) -> Update? {
        let (next, effects) = engine(state, event, in: state.id)
        return effects.isEmpty ? nil : Update(state: next, effects: haptics(effects))
    }

    /// A change no test makes itself, so a reader can stop at it: a seven-second rest ending far after the
    /// start on a live workout, else the start of workout `0x4D0000 + number`. Returns the state it leaves,
    /// computed here.
    static func mark(_ client: any WorkoutSessionClient, _ number: Int = 0) async throws -> WorkoutState {
        guard let live = try await client.current() else {
            let snapshot = session(0x4D0000 + number, EventBuilders.supersetExercises)
            try await client.start(snapshot)
            return snapshot
        }
        let event = markEvent(number)
        try await client.apply(event)
        return engine(live, event, in: live.id).0 ?? live
    }

    /// Marks `client` and returns what `reader` held before the mark: everything published since the
    /// reader's last read. When the stream ended instead, what it held.
    static func heard(
        _ reader: inout SeamReader,
        on client: any WorkoutSessionClient,
        mark number: Int = 0
    ) async throws -> [Update] {
        let end = try await mark(client, number)
        var seen = await reader.through(end)
        if seen.last?.state == end {
            seen.removeLast()
        }
        return seen
    }

    /// What `stream` holds now, without waiting for more: a task that is already cancelled reads what a
    /// stream has buffered and then meets its end. Every client here publishes before its call returns,
    /// so after the last call this is the whole stream, and a missing update is a difference, not a wait.
    static func buffered(_ stream: AsyncStream<Update>) async -> [Update] {
        let reading = Task {
            var seen: [Update] = []
            for await update in stream {
                seen.append(update)
            }
            return seen
        }
        reading.cancel()
        return await reading.value
    }

    static func markEvent(_ number: Int) -> WorkoutEvent {
        .restStarted(endsAt: at(9_000_000 + Double(number)), total: .seconds(7))
    }

    /// `nil` when `seen` is exactly `expected`, else the first place they differ, in a few words.
    static func difference(_ seen: [Update], _ expected: [Update], _ what: String) -> String? {
        if let index = zip(seen, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
            return "\(what): update \(index) is \(brief(seen[index])), expected \(brief(expected[index]))"
        }
        return seen.count == expected.count ? nil : "\(what): \(seen.count) updates, expected \(expected.count)"
    }

    static func brief(_ update: Update) -> String {
        guard let state = update.state else {
            return "(no workout, effects \(update.effects))"
        }
        let rest = state.rest.map { "\($0.endsAt.timeIntervalSince(EventBuilders.start))/\($0.total)" } ?? "none"
        return "(\(state.phase) \(state.id.rawValue.uuidString.suffix(6)), \(state.doneSets)/\(state.totalSets) done, "
            + "cursor \(state.cursor.map { "\($0.exerciseIndex).\($0.setIndex)" } ?? "nil"), rest \(rest), "
            + "effects \(update.effects))"
    }
}

/// One subscriber: a stream from `updates()`, read in order.
struct SeamReader {
    private var iterator: AsyncStream<WorkoutSessionUpdate>.Iterator

    init(_ client: any WorkoutSessionClient) async {
        iterator = await client.updates().makeAsyncIterator()
    }

    init(_ stream: AsyncStream<WorkoutSessionUpdate>) {
        iterator = stream.makeAsyncIterator()
    }

    mutating func next() async -> WorkoutSessionUpdate? {
        await iterator.next()
    }

    /// Every update up to and including the first that carries `mark`, or the whole stream when it ends
    /// first. A stream that never carries `mark` keeps the test waiting until its time limit fails it.
    mutating func through(_ mark: WorkoutState) async -> [WorkoutSessionUpdate] {
        var seen: [WorkoutSessionUpdate] = []
        while let update = await iterator.next() {
            seen.append(update)
            if update.state == mark {
                break
            }
        }
        return seen
    }
}

/// SplitMix64 (testing-strategy §3 rule 5): the sequence depends on the seed alone.
struct SeamRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// One property-test case; a failing case names its seed.
struct SeamSeed: Sendable, CustomStringConvertible {
    let value: UInt64

    var description: String {
        "seed \(value)"
    }

    /// `LEDGER_PROPERTY_SEED_COUNT` seeds (PR lane 200, nightly 2,000); 200 when unset or invalid.
    static let all: [SeamSeed] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        return (0 ..< max(1, configured ?? 200)).map { SeamSeed(value: UInt64($0) &* 6151 &+ 29) }
    }()
}

/// A counter several tasks may share: 1, 2, 3, …
final class SeamCounter: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        count.withLock { count in
            count += 1
            return count
        }
    }

    var value: Int {
        count.withLock { $0 }
    }
}
