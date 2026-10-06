import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import SwiftUI
import Testing

/// One run of the app on a harness's database file (F10 S2 adversarial round 1): booted as `App.init` boots
/// it and resumed as the root view does. A second `AppRun` on the same harness is a relaunch after a kill:
/// nothing of the first is used again, and only the file carries over.
struct AppRun {
    let composition: AppComposition
    let session: LocalWorkoutSessionActor
    let stores: LedgerStores

    /// - Parameter phase: the scene phase the root view resumes in; `nil` leaves the launch step unrun.
    init(_ harness: Harness, now: Date = Harness.now, in phase: ScenePhase? = .active) async throws {
        composition = harness.booted(now: now)
        if let phase {
            await composition.resume(in: phase)
        }
        session = try #require(composition.session)
        stores = try #require(composition.stores)
    }

    func execute(_ sql: String) async throws {
        try await stores.queue.write { try $0.execute(sql: sql) }
    }

    func history() async throws -> [WorkoutState] {
        try await stores.workouts.recent(limit: 100)
    }

    func logs() async throws -> [WorkoutID] {
        try await stores.events.uncompactedWorkoutIDs()
    }

    /// How many rows each of `tables` holds.
    func rows(in tables: [String]) async throws -> [Int] {
        try await stores.queue.read { database in
            try tables.map { try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
    }
}

/// The workout these suites kill the app in, and what the engine makes of it.
enum WorkoutLaunch {
    nonisolated static let session = EventBuilders.seedSession()
    nonisolated static let end = EventBuilders.start.addingTimeInterval(3600)

    /// A store that refuses to save a workout, and one that refuses to drop a log: the app dies there.
    nonisolated static let refuseSave = refusal(of: "INSERT ON workout")
    nonisolated static let refuseDrop = refusal(of: "DELETE ON workout_event")
    nonisolated static let allow = "DROP TRIGGER siege"

    /// The statements of a save's transaction for the seed session, after the workout's own row: its
    /// exercises, its sets, and the end of its log (F10 S3). A first workout sets no record, so the records'
    /// statement is `LinkedSaveFaultAdversarialTests`', where history holds an earlier workout.
    nonisolated static let saveStatements = [
        "INSERT ON workout_exercise", "INSERT ON logged_set", "DELETE ON workout_event"
    ]
    nonisolated static let historyTables = ["workout", "workout_exercise", "logged_set", "personal_record"]

    nonisolated static func refusal(of statement: String) -> String {
        "CREATE TRIGGER siege BEFORE \(statement) BEGIN SELECT RAISE(ABORT, 'no'); END"
    }

    nonisolated static func logged(_ exerciseIndex: Int, _ setIndex: Int, at seconds: Double) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exerciseIndex,
            setID: EventBuilders.setID(exerciseIndex, setIndex),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: EventBuilders.start.addingTimeInterval(seconds)
        )
    }

    /// The middle of a workout: two sets logged (so a rest runs), a third added, a weight changed and the
    /// cursor moved.
    nonisolated static let middle: [WorkoutEvent] = [
        logged(0, 0, at: 60),
        logged(0, 1, at: 240),
        .setAdded(
            exerciseIndex: 1,
            set: LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(50), reps: .one, kind: .added)
        ),
        .setTargetChanged(exerciseIndex: 2, setID: EventBuilders.setID(2, 1), weight: .pounds(75), reps: nil),
        .exerciseSelected(exerciseIndex: 3, setIndex: 1)
    ]

    /// What `WorkoutEngine.reduce` folds the seed session and `events` to, a call at a time.
    nonisolated static func folded(_ events: [WorkoutEvent]) -> WorkoutState? {
        var state: WorkoutState?
        for (index, event) in ([.started(session)] + events).enumerated() {
            let envelope = EventBuilders.envelope(event, seq: UInt64(index + 1), at: EventBuilders.start)
            state = WorkoutEngine.reduce(state, envelope).0
        }
        return state
    }

    /// What the GRDB store gives back for `finished`: written to a fresh database and read.
    nonisolated static func asStored(_ finished: WorkoutState) async throws -> WorkoutState? {
        let fresh = try GRDBWorkoutRepository(LedgerDatabase.inMemory())
        try await fresh.materialize(finished, slotUpdates: [])
        return try await fresh.workout(id: finished.id)
    }

    /// Leaves `log` in the harness's database file before any launch, as a killed app would.
    nonisolated static func leave(_ log: [EventEnvelope], at url: URL) async throws {
        let queue = try LedgerDatabase.open(at: url)
        _ = try await GRDBWorkoutEventStore(queue).append(log)
        try queue.close()
    }

    /// The seed session started and then `events`, as the phone stored them.
    nonisolated static func log(_ events: [WorkoutEvent]) -> [EventEnvelope] {
        EventBuilders.log(from: [.started(session)] + events, device: DeviceID(Harness.deviceUUID), spacing: 1)
    }

    static func steps(_ harness: Harness, _ step: LaunchStep) -> [String] {
        LaunchAdversarialTests.spelled(harness.log).filter { $0.hasSuffix(step.rawValue) }
    }
}
