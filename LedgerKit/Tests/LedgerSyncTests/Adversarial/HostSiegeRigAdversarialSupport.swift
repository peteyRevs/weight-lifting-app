import Foundation
import GRDB
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport

/// A host's three stores, which a test reads directly as the truth, the siege every host reaches them through,
/// and the system clock (F10 S2 adversarial round 1). Expected values come from `WorkoutEngine.replay` of the
/// stored log and from a fresh store of the same kind, never from the host.
struct SiegeRig: Sendable {
    enum Backing: String, Sendable, CaseIterable, CustomStringConvertible {
        /// LedgerFakes' in-memory stores.
        case memory
        /// The GRDB stores over an in-memory database.
        case database

        var description: String {
            rawValue
        }
    }

    /// The uncompacted logs by what the engine replays them to.
    struct Truth: Sendable {
        var live: [WorkoutState] = []
        var ended: [WorkoutState] = []
        var empty: [WorkoutID] = []
    }

    let backing: Backing
    let siege = Siege()
    let clock: SiegeClock
    let events: any WorkoutEventStore
    let workouts: any WorkoutRepository
    let programs: any ProgramRepository
    /// The database beneath the GRDB stores, for a test that damages a row.
    let queue: DatabaseQueue?
    /// All six in-memory stores, for a test that needs the others (`StartWorkoutUseCase`).
    let memory: InMemoryStores?
    let device = EventBuilders.phone
    let yields: Int

    /// Stores of `backing` holding `seed`. `yields` is how often each store call gives way before it reaches
    /// its store, so that a host's `await` is a point another caller does reach.
    static func make(
        _ backing: Backing = .memory,
        seed: InMemoryStores.Seed = .empty,
        yields: Int = 0,
        clock: SiegeClock = SiegeClock(),
        sabotage: SiegeSabotage? = nil
    ) async throws -> SiegeRig {
        switch backing {
        case .memory:
            let stores = InMemoryStores(seed: seed, now: { clock.now })
            return SiegeRig(
                backing: backing, clock: clock,
                events: sabotage == nil ? stores.events : SabotagedEventStore(base: stores.events, sabotage: sabotage),
                workouts: sabotage == .neverSaves ? SabotagedWorkoutRepository(base: stores.workouts) : stores.workouts,
                programs: stores.programs, queue: nil, memory: stores, yields: yields
            )
        case .database:
            let database = try LedgerDatabase.inMemory()
            let stores = LedgerStores(database, deviceID: EventBuilders.phone, now: { clock.now })
            try await stores.exercises.seedIfNeeded(seed.catalog, version: seed.catalogVersion)
            for program in seed.programs {
                try await stores.programs.save(program)
            }
            for workout in seed.workouts {
                try await stores.workouts.materialize(workout, slotUpdates: [])
            }
            for (_, log) in Dictionary(grouping: seed.envelopes, by: \.workoutID) {
                _ = try await stores.events.append(log)
            }
            return SiegeRig(
                backing: backing, clock: clock, events: stores.events, workouts: stores.workouts,
                programs: stores.programs, queue: database, memory: nil, yields: yields
            )
        }
    }

    /// A host over the stores, behind the siege. Building one retires every host built before it, whose
    /// store calls then throw: a relaunch after a kill.
    func host() async -> LocalWorkoutSessionActor {
        let gate = await SiegeGate(siege: siege, generation: siege.nextGeneration(), yields: yields)
        return LocalWorkoutSessionActor(
            events: SiegeEventStore(base: events, gate: gate),
            workouts: SiegeWorkoutRepository(base: workouts, gate: gate),
            programs: SiegeProgramRepository(base: programs, gate: gate),
            device: device,
            now: { [clock] in clock.now }
        )
    }

    // MARK: The truth, read from the stores directly

    /// The workout's stored log, in the order `WorkoutEngine.replay` folds it.
    func log(_ workout: WorkoutID) async throws -> [EventEnvelope] {
        try await events.envelopes(for: workout).sorted()
    }

    func replayed(_ workout: WorkoutID) async throws -> WorkoutState? {
        try await WorkoutEngine.replay(events.envelopes(for: workout))
    }

    /// The workout as it stood before its end: its log replayed without the terminal envelopes.
    func standing(_ workout: WorkoutID) async throws -> WorkoutState? {
        try await WorkoutEngine.replay(events.envelopes(for: workout).filter { !$0.event.isTerminal })
    }

    func uncompacted() async throws -> Set<WorkoutID> {
        try await Set(events.uncompactedWorkoutIDs())
    }

    func truth() async throws -> Truth {
        var truth = Truth()
        for workout in try await uncompacted().sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            guard let state = try await replayed(workout) else {
                truth.empty.append(workout)
                continue
            }
            if state.phase == .live {
                truth.live.append(state)
            } else {
                truth.ended.append(state)
            }
        }
        return truth
    }

    func history() async throws -> [WorkoutState] {
        try await workouts.recent(limit: 100_000)
    }

    /// What a store of this kind gives back for `finished`: the workout written to a fresh one and read.
    func asStored(_ finished: WorkoutState) async throws -> WorkoutState? {
        let fresh = try await SiegeRig.make(backing)
        try await fresh.workouts.materialize(finished, slotUpdates: [])
        return try await fresh.workouts.workout(id: finished.id)
    }

    /// Makes the stored row of (`workout`, this device, `seq`) one this app version cannot read: a later
    /// payload version, as an update the lifter then rolled back would leave it. GRDB stores only.
    func makeUnreadable(_ workout: WorkoutID, seq: UInt64) async throws {
        guard let queue else {
            throw SiegeRigError.needsDatabase
        }
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE workout_event SET payload_version = 9999 WHERE workout_id = ? AND seq = ?",
                arguments: [workout.rawValue.uuidString, Int64(seq)]
            )
            if database.changesCount != 1 {
                throw SiegeRigError.noSuchRow
            }
        }
    }
}

enum SiegeRigError: Error {
    case needsDatabase, noSuchRow
}

/// Reading a host's stream after the fact.
extension SiegeRig {
    /// The envelopes the siege saw stored for `workout`, in the order the store took them.
    func everStored(_ workout: WorkoutID) async -> [EventEnvelope] {
        await siege.stored.filter { $0.workoutID == workout }
    }

    /// The update the engine gives for `envelope` on `state`, as a host must publish it.
    static func update(_ state: WorkoutState?, _ envelope: EventEnvelope) -> WorkoutSessionUpdate? {
        let (next, effects) = WorkoutEngine.reduce(state, envelope)
        return effects.isEmpty ? nil : WorkoutSessionUpdate(state: next, haptics: Seam.haptics(effects))
    }

    /// The updates a host must have published for `envelopes`, its own, in the order it stored them: each
    /// folded by `WorkoutEngine.reduce` on the workout as it stood, a workout at a time.
    static func updates(for envelopes: [EventEnvelope]) -> [WorkoutSessionUpdate] {
        var states: [WorkoutID: WorkoutState] = [:]
        var published: [WorkoutSessionUpdate] = []
        for envelope in envelopes {
            guard let update = update(states[envelope.workoutID], envelope) else {
                continue
            }
            states[envelope.workoutID] = update.state
            published.append(update)
        }
        return published
    }
}
