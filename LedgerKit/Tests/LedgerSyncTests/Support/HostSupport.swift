import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import Synchronization

/// The system clock of a host under test: a test sets what it reads.
final class SettableClock: Sendable {
    private let reading: Mutex<Date>

    init(_ date: Date = EventBuilders.start) {
        reading = Mutex(date)
    }

    var now: Date {
        reading.withLock { $0 }
    }

    func set(_ date: Date) {
        reading.withLock { $0 = date }
    }
}

/// A host over in-memory stores behind a `StoreProbe`, with the clock it reads: what the host's own suites
/// build. `relaunched()` is the host a new launch builds over what the last one stored.
struct Subject: Sendable {
    typealias Update = WorkoutSessionUpdate

    static let device = EventBuilders.phone

    let stores: InMemoryStores
    let probed: ProbedStores
    let clock: SettableClock
    let host: LocalWorkoutSessionActor

    var probe: StoreProbe {
        probed.probe
    }

    /// - Parameter yields: how often each store call gives way before it reaches its store.
    init(seed: InMemoryStores.Seed = .empty, yields: Int = 0, clock: SettableClock = SettableClock()) {
        let memory = InMemoryStores(seed: seed)
        let wrapped = ProbedStores(
            events: memory.events,
            workouts: memory.workouts,
            programs: memory.programs,
            yields: yields
        )
        self.init(stores: memory, probed: wrapped, clock: clock)
    }

    private init(stores: InMemoryStores, probed: ProbedStores, clock: SettableClock) {
        self.stores = stores
        self.probed = probed
        self.clock = clock
        host = LocalWorkoutSessionActor(
            events: probed.events,
            workouts: probed.workouts,
            programs: probed.programs,
            device: Self.device,
            now: { clock.now }
        )
    }

    /// A new host over the same stores and clock, as after the app was killed and launched again.
    func relaunched() -> Subject {
        Subject(stores: stores, probed: probed, clock: clock)
    }

    /// The stored log of `workout`, in the engine's order.
    func log(of workout: WorkoutID = EventBuilders.workoutID) async -> [EventEnvelope] {
        await stores.events.envelopes(for: workout).sorted()
    }

    /// The store calls made since the last `clearCalls()` that write.
    func writes() async -> [StoreProbe.Call] {
        await probe.calls.filter { [.append, .materialize, .compact].contains($0) }
    }
}

/// One subscriber's stream, read without waiting on a clock: a test makes a change it can recognise and
/// reads everything before it.
struct Listener {
    typealias Update = WorkoutSessionUpdate

    private var iterator: AsyncStream<Update>.AsyncIterator

    init(_ client: any WorkoutSessionClient) async {
        iterator = await client.updates().makeAsyncIterator()
    }

    mutating func next() async -> Update? {
        await iterator.next()
    }

    /// Every update before the one whose state is `mark`; the stream is left just after it.
    mutating func updates(before mark: WorkoutState) async -> [Update] {
        var seen: [Update] = []
        while let update = await iterator.next(), update.state != mark {
            seen.append(update)
        }
        return seen
    }
}

/// How a call on a host ended, for a test that expects a throw.
func failure(of body: () async throws -> Void) async -> (any Error)? {
    do {
        try await body()
        return nil
    } catch {
        return error
    }
}

/// A rest no suite starts itself, which a `Listener` reads up to: on a live workout only.
func mark(_ client: any WorkoutSessionClient) async throws -> WorkoutState {
    try await client.apply(.restStarted(endsAt: EventBuilders.start.addingTimeInterval(86400), total: .seconds(1)))
}

/// The stores a host keeps the contract over (F10 S2 criterion 1).
enum HostStores: String, CaseIterable, Sendable, CustomStringConvertible {
    /// `LedgerFakes`' in-memory stores, as they are.
    case inMemory
    /// The GRDB stores over a migrated in-memory database.
    case database
    /// The in-memory stores, giving way inside every call: where a host's `await` lets another caller in.
    case suspending

    var description: String {
        rawValue
    }

    func host() throws -> LocalWorkoutSessionActor {
        let now: @Sendable () -> Date = { EventBuilders.start }
        switch self {
        case .inMemory:
            let stores = InMemoryStores()
            return LocalWorkoutSessionActor(
                events: stores.events, workouts: stores.workouts, programs: stores.programs,
                device: Subject.device, now: now
            )
        case .database:
            let stores = try LedgerStores(LedgerDatabase.inMemory(), deviceID: Subject.device, now: now)
            return LocalWorkoutSessionActor(
                events: stores.events, workouts: stores.workouts, programs: stores.programs,
                device: Subject.device, now: now
            )
        case .suspending:
            return Subject(yields: 3).host
        }
    }
}

/// A host as a contract run meets it: over which stores, and whether the launch has run its recovery or the
/// first protocol call has to.
struct HostSetup: Sendable, CaseIterable, CustomStringConvertible {
    let stores: HostStores
    let isLaunched: Bool

    static let allCases = HostStores.allCases.flatMap { stores in
        [HostSetup(stores: stores, isLaunched: true), HostSetup(stores: stores, isLaunched: false)]
    }

    var description: String {
        "\(stores), \(isLaunched ? "recovered at launch" : "recovery not started")"
    }

    func host() async throws -> LocalWorkoutSessionActor {
        let host = try stores.host()
        if isLaunched {
            try await host.resumeFromStore()
        }
        return host
    }
}

/// The session and the events the host's suites use: spec §6.3's five exercises, ad hoc.
enum Sample {
    static let session = EventBuilders.seedSession()
    static let other = EventBuilders.session(
        EventBuilders.supersetExercises,
        id: WorkoutID(EventBuilders.uuid(0xF101))
    )

    /// `seconds` after the fixture start.
    static func at(_ seconds: Double) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    /// Row (`exerciseIndex`, `setIndex`) of `session` logged at 185 lb × 5.
    static func logged(_ exerciseIndex: Int, _ setIndex: Int, at seconds: Double = 60) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exerciseIndex,
            setID: EventBuilders.setID(exerciseIndex, setIndex),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: at(seconds)
        )
    }

    /// A stepper edit of row (`exerciseIndex`, `setIndex`) of `session`.
    static func retargeted(_ exerciseIndex: Int, _ setIndex: Int, pounds: Decimal) -> WorkoutEvent {
        .setTargetChanged(
            exerciseIndex: exerciseIndex,
            setID: EventBuilders.setID(exerciseIndex, setIndex),
            weight: .pounds(pounds),
            reps: nil
        )
    }

    /// `events` as the phone logs them on `session`, from its `started` at seq 1, ten seconds apart.
    static func log(_ events: [WorkoutEvent], of snapshot: WorkoutState = session) -> [EventEnvelope] {
        EventBuilders.log(from: [.started(snapshot)] + events, workoutID: snapshot.id)
    }
}
