import Foundation
import LedgerDomain
import LedgerTestSupport

/// A session client that records what `StartWorkoutUseCase` asks of it, over the fake (which runs the real
/// engine), and can fail a start or let another caller in after a look (F10 S2 adversarial round 1).
actor SpySession: WorkoutSessionClient {
    enum Entry: Equatable {
        case current, updates, start(WorkoutID), apply, finish(Date), discard(Date)
    }

    struct StartRefused: Error, Equatable {}

    let inner: FakeWorkoutSessionClient
    private(set) var asked: [Entry] = []
    private var failsNextStart = false
    private var afterLook: (@Sendable (FakeWorkoutSessionClient) async throws -> Void)?

    init(live: WorkoutState? = nil) {
        inner = FakeWorkoutSessionClient(live: live)
    }

    /// The next `start` throws `StartRefused` and starts nothing, as a host whose store refuses the append.
    func failNextStart() {
        failsNextStart = true
    }

    /// Runs `intrusion` on the fake once, right after the next `current()` has answered.
    func afterNextLook(_ intrusion: @escaping @Sendable (FakeWorkoutSessionClient) async throws -> Void) {
        afterLook = intrusion
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        asked.append(.updates)
        return await inner.updates()
    }

    func current() async throws -> WorkoutState? {
        asked.append(.current)
        let live = await inner.current()
        if let intrusion = afterLook {
            afterLook = nil
            try await intrusion(inner)
        }
        return live
    }

    func start(_ initial: WorkoutState) async throws {
        asked.append(.start(initial.id))
        if failsNextStart {
            failsNextStart = false
            throw StartRefused()
        }
        try await inner.start(initial)
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        asked.append(.apply)
        return try await inner.apply(event)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        asked.append(.finish(endedAt))
        return try await inner.finish(endedAt: endedAt)
    }

    func discard(endedAt: Date) async throws {
        asked.append(.discard(endedAt))
        try await inner.discard(endedAt: endedAt)
    }
}

/// The in-memory stores holding a block of four days and five slots a day over a synthetic catalog, a week of
/// history, and `StartWorkoutUseCase` over them with a fixed clock, device and new id.
struct StartBench {
    static let now = EventBuilders.start.addingTimeInterval(30 * 86400)
    static let device = DeviceID(EventBuilders.uuid(0xD0D0))
    static let newID = EventBuilders.uuid(0x57A27)

    struct Missing: Error {}

    let stores: InMemoryStores
    let session: SpySession

    static func make(settings: Settings = .default, live: WorkoutState? = nil) async throws -> StartBench {
        let catalog = Seeders.catalog(count: 14, version: 1)
        let program = try Seeders.program(exercises: catalog.exercises.map(\.id))
        let lookup = Dictionary(uniqueKeysWithValues: catalog.exercises.map { ($0.id, $0) })
        // Last week's first day, every set done as prescribed: the "Last" line of this week's.
        var done = try SessionBuilder.build(
            program: program, weekIndex: 0, day: program.days[0], exercises: lookup, history: [:],
            settings: settings, id: WorkoutID(EventBuilders.uuid(0x0157)), device: device,
            now: now.addingTimeInterval(-7 * 86400)
        )
        for exercise in done.exercises.indices {
            for set in done.exercises[exercise].sets.indices {
                done.exercises[exercise].sets[set].doneAt = done.startedAt.addingTimeInterval(600)
            }
        }
        done.phase = .finished
        done.endedAt = done.startedAt.addingTimeInterval(3600)
        let seed = InMemoryStores.Seed(
            catalog: catalog.exercises, catalogVersion: catalog.version, programs: [program], workouts: [done],
            settings: settings
        )
        return StartBench(stores: InMemoryStores(seed: seed, now: { now }), session: SpySession(live: live))
    }

    func useCase(
        exercises: (any ExerciseRepository)? = nil,
        settings: (any SettingsRepository)? = nil
    ) -> StartWorkoutUseCase {
        StartWorkoutUseCase(
            session: session,
            programs: stores.programs,
            exercises: exercises ?? stores.exercises,
            stats: stores.stats,
            settings: settings ?? stores.settings,
            device: Self.device,
            now: { Self.now },
            newID: { Self.newID }
        )
    }

    func program() async throws -> Program {
        guard let program = try await stores.programs.active() else {
            throw Missing()
        }
        return program
    }

    /// Week `week`, day `day` of the stored block.
    func source(week: Int = 1, day: Int = 0) async throws -> WorkoutSource {
        let program = try await program()
        return WorkoutSource(programID: program.id, weekIndex: week, dayTemplateID: program.days[day].id)
    }

    /// What `SessionBuilder` builds for `source` from what the stores hold now, called here.
    func built(_ source: WorkoutSource, id: UUID = newID, now: Date = now) async throws -> WorkoutState {
        let program = try await program()
        guard let day = program.days.first(where: { $0.id == source.dayTemplateID }) else {
            throw Missing()
        }
        var history: [ExerciseID: LastPerformance] = [:]
        for slot in day.slots {
            history[slot.exerciseID] = try await stores.stats.lastPerformance(exerciseID: slot.exerciseID)
        }
        return try await SessionBuilder.build(
            program: program,
            weekIndex: source.weekIndex,
            day: day,
            exercises: Dictionary(uniqueKeysWithValues: stores.exercises.all().map { ($0.id, $0) }),
            history: history,
            settings: stores.settings.load(),
            id: WorkoutID(id),
            device: Self.device,
            now: now
        )
    }

    /// How `start` ended: its outcome in a word and the workout it carries, or the error.
    func outcome(
        _ source: WorkoutSource,
        replacingLive: Bool = false,
        with useCase: StartWorkoutUseCase? = nil
    ) async -> String {
        do {
            switch try await (useCase ?? self.useCase()).start(source, replacingLive: replacingLive) {
            case let .started(workout): return "started \(workout.id.rawValue.uuidString.suffix(5))"
            case let .resumed(workout): return "resumed \(workout.id.rawValue.uuidString.suffix(5))"
            case let .conflict(workout): return "conflict \(workout.id.rawValue.uuidString.suffix(5))"
            }
        } catch {
            return "\(error)"
        }
    }
}

/// The exercise store with one exercise gone: deleted from the library after the day was written.
struct ExercisesWithout: ExerciseRepository {
    let base: any ExerciseRepository
    let gone: ExerciseID

    func all() async throws -> [Exercise] {
        try await base.all().filter { $0.id != gone }
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        id == gone ? nil : try await base.exercise(id: id)
    }

    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
        try await base.search(query, equipment: equipment, muscle: muscle).filter { $0.id != gone }
    }

    func save(_ exercise: Exercise) async throws {
        try await base.save(exercise)
    }

    func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
        try await base.seedIfNeeded(catalog, version: version)
    }

    func observeAll() -> AsyncStream<[Exercise]> {
        base.observeAll()
    }
}

/// Settings that cannot be read.
struct UnreadableSettings: SettingsRepository {
    struct Unreadable: Error, Equatable {}

    func load() async throws -> Settings {
        throw Unreadable()
    }

    func save(_: Settings) async throws {}

    func observe() -> AsyncStream<Settings> {
        AsyncStream { $0.finish() }
    }
}
