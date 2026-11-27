import Foundation
import LedgerDependencies
import LedgerDomain

/// What the watch's Health session tells the workout's screens (F18 S3): the sharing status, the running session's
/// heart rate, Apple Workout's takeover and the workout last saved to Health.
nonisolated struct WatchHealth: Equatable, Sendable {
    /// What Health was saved for a workout, as the summary's AVG BPM reads it (criterion 11).
    struct Saved: Equatable, Sendable {
        let workout: WorkoutID
        let record: HealthWorkoutRecord
    }

    /// The sharing status as last read: at the start of the run and at each workout's start. `.denied` shows no
    /// heart rate (spec §9).
    var authorization = HealthAuthorization.notDetermined
    /// The workout whose session runs; nil while none does.
    var running: WorkoutID?
    /// The running session's latest reading; nil while no session runs.
    var heartRate: HeartRateSample?
    /// The workout whose session another app's workout ended (spec §9, "Apple Workout took over · logging
    /// continues"): its logging goes on, with no session and nothing written to Health.
    var takenOver: WorkoutID?
    var saved: Saved?
}

/// The watch's HealthKit session, following the workout (F16, F18 S3; architecture §9: the watch runs the session
/// for every Ledger workout, whichever device started it). Headless: the composition runs it for the app's life,
/// in its live-sync task group, and the workout screen reads `states()`.
///
/// - A workout that becomes live starts the session at the workout's start, once per workout: a session the system
///   kept after the app ended is taken up instead (`recoverActiveSession()`), so a relaunch never splits the
///   workout's heart rate. Without authorization no session starts; the status is shown as it is (F19 asks).
/// - A finished workout ends the session and saves it to Health; a discarded one discards it.
/// - Another live workout in place of the session's (a double start's winner, F17 S5b) keeps the session: it is the
///   winner's now, and the loser writes nothing to Health.
/// - Another app's workout ending ours (`.anotherWorkoutSessionStarted`) leaves the workout logging, with no session.
/// - A recovery the delegate made (`handleActiveWorkoutRecovery()`, criterion 13) gives the live workout its session.
public actor WatchHealthSession {
    private let health: any HealthStore
    private let workouts: any WorkoutSessionClient
    private let programs: any ProgramRepository
    private let logger: LedgerLogger
    private var state = WatchHealth()
    private var readers: [AsyncStream<WatchHealth>.Continuation] = []
    /// The live workout as last heard.
    private var live: WorkoutState?
    /// The workout whose session runs: what `state.running` shows.
    private var owner: WorkoutID?
    /// The workout whose session is being started; a takeover meanwhile clears it.
    private var starting: WorkoutID?
    /// Every workout a session was started for, whatever came of it: none is started twice.
    private var begun: Set<WorkoutID> = []

    public init(
        health: any HealthStore,
        workouts: any WorkoutSessionClient,
        programs: any ProgramRepository,
        logger: LedgerLogger
    ) {
        self.health = health
        self.workouts = workouts
        self.programs = programs
        self.logger = logger
    }

    /// The state now, then each change.
    func states() -> AsyncStream<WatchHealth> {
        let (stream, reader) = AsyncStream.makeStream(of: WatchHealth.self, bufferingPolicy: .bufferingNewest(1))
        reader.yield(state)
        readers.append(reader)
        return stream
    }

    /// Follows the workout, `events` (the session's, from the composition's `HealthEventBroadcast`) and the heart
    /// rate until the caller's task is cancelled. Subscribes to the workout and the heart rate before it reads either.
    public func run(events: AsyncStream<HealthSessionEvent>) async {
        let updates = await workouts.updates()
        let beats = await health.heartRate()
        let authorization = await health.authorization()
        change { $0.authorization = authorization }
        await withTaskGroup(of: Void.self) { group in
            // One update at a time, each awaited to its end: a start, an end or a discard is never under way while
            // the next update is taken, so an end heard during a start is followed after the start has handed the
            // session to its workout (the reentrancy the actor would otherwise allow).
            group.addTask {
                for await update in updates {
                    await self.follow(update.state)
                }
            }
            group.addTask {
                for await event in events {
                    await self.handle(event)
                }
            }
            group.addTask {
                for await beat in beats {
                    await self.show(beat)
                }
            }
        }
    }

    func follow(_ workout: WorkoutState?) async {
        live = workout?.phase == .live ? workout : nil
        guard let workout else {
            return
        }
        switch workout.phase {
        case .live where owner != nil && owner != workout.id:
            hand(to: workout.id)
        case .live where owner == nil && !begun.contains(workout.id):
            await begin(workout)
        case .finished where owner == workout.id:
            await end(workout)
        case .discarded where owner == workout.id:
            await discard(workout)
        default:
            break
        }
    }

    func handle(_ event: HealthSessionEvent) {
        switch event {
        case .recovered:
            if owner == nil, let live {
                hand(to: live.id)
            }
        case .anotherWorkoutSessionStarted:
            guard let lost = owner ?? starting else {
                return
            }
            logger.log.notice("Another app's workout took the session over; logging continues")
            starting = nil
            hand(to: nil)
            change { $0.takenOver = lost }
        default:
            break
        }
    }

    func show(_ beat: HeartRateSample) {
        if owner != nil {
            change { $0.heartRate = beat }
        }
    }

    private func begin(_ workout: WorkoutState) async {
        begun.insert(workout.id)
        let authorization = await health.authorization()
        change { $0.authorization = authorization }
        guard authorization == .authorized else {
            logger.log.notice("No workout session: Health is not authorized")
            return
        }
        starting = workout.id
        defer { starting = nil }
        do {
            if try await !health.recoverActiveSession() {
                try await health.startSession(workoutID: workout.id, at: workout.startedAt)
            }
        } catch HealthError.sessionAlreadyRunning {
            // The delegate's recovery took the session up first: it is this workout's.
        } catch {
            logger.log.error("The workout session did not start: \(String(describing: error), privacy: .public)")
            return
        }
        if starting == workout.id, owner == nil {
            hand(to: workout.id)
        }
    }
}

/// The session's end, and the state the screens read.
private extension WatchHealthSession {
    func end(_ workout: WorkoutState) async {
        hand(to: nil)
        let program = try? await programs.active()
        let metadata = HealthWorkoutMetadata(
            workoutID: workout.id,
            programName: program.flatMap { $0.id == workout.source?.programID ? $0.name : nil },
            dayName: workout.source == nil ? nil : workout.name,
            totalVolume: Weight(grams: workout.volume.gramReps),
            doneSets: workout.doneSets
        )
        do {
            let record = try await health.endSession(metadata: metadata, at: workout.endedAt ?? workout.startedAt)
            change { $0.saved = WatchHealth.Saved(workout: workout.id, record: record) }
        } catch {
            logger.log.error("The workout was not saved to Health: \(String(describing: error), privacy: .public)")
        }
    }

    func discard(_: WorkoutState) async {
        hand(to: nil)
        do {
            try await health.discardSession()
        } catch {
            logger.log.error("The workout session was not discarded: \(String(describing: error), privacy: .public)")
        }
    }

    /// Makes the session `workout`'s, or nobody's; a session that stops shows no heart rate.
    func hand(to workout: WorkoutID?) {
        owner = workout
        change { state in
            state.running = workout
            if workout == nil {
                state.heartRate = nil
            }
        }
    }

    func change(_ edit: (inout WatchHealth) -> Void) {
        var next = state
        edit(&next)
        guard next != state else {
            return
        }
        state = next
        readers.removeAll { reader in
            if case .terminated = reader.yield(next) {
                true
            } else {
                false
            }
        }
    }
}
