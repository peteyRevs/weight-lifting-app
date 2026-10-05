import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport

/// A host in the middle of a workout: `Seam.session(1)` live with its first two sets logged, over stores a
/// test can make fail (F10 S2 adversarial round 1).
struct SiegeScene {
    /// When the scene's workouts end.
    static let end = Seam.at(3600)

    let rig: SiegeRig
    let host: LocalWorkoutSessionActor
    /// The workout as it stands.
    let live: WorkoutState
    /// Streams opened once the workout stood as `live`, which is each one's first element. Reading what a
    /// stream holds ends it (`Seam.buffered`), so each look at the updates takes the next one: all of them
    /// were told the same.
    let streams: [AsyncStream<WorkoutSessionUpdate>]
    private let looks = SeamCounter()

    var siege: Siege {
        rig.siege
    }

    static func make(
        _ backing: SiegeRig.Backing = .memory,
        seed: InMemoryStores.Seed = .empty,
        session: WorkoutState = Seam.session(1)
    ) async throws -> SiegeScene {
        let stores = try await SiegeRig.make(backing, seed: seed)
        let client = await stores.host()
        try await client.start(session)
        var standing = session
        for (row, set) in session.exercises[0].sets.prefix(2).enumerated() {
            standing = try await client.apply(.setLogged(
                exerciseIndex: 0,
                setID: set.id,
                weight: set.weight,
                reps: set.reps,
                doneAt: Seam.at(60 + 180 * Double(row))
            ))
        }
        var opened: [AsyncStream<WorkoutSessionUpdate>] = []
        for _ in 0 ..< 8 {
            await opened.append(client.updates())
        }
        return SiegeScene(rig: stores, host: client, live: standing, streams: opened)
    }

    /// Row 2 of the first exercise logged: a change no scene has made.
    var nextLog: WorkoutEvent {
        let set = live.exercises[0].sets[2]
        return .setLogged(exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: Seam.at(420))
    }

    /// The update the engine gives for `event` on the workout as it stands.
    func update(after event: WorkoutEvent) -> WorkoutSessionUpdate? {
        Seam.update(after: event, on: live)
    }

    /// The finished workout the engine makes of the scene's workout ended at `SiegeScene.end`.
    var finished: WorkoutState? {
        update(after: .finished(endedAt: Self.end))?.state
    }

    /// What a subscriber from the scene's beginning has been told since, beyond its first element.
    func heard() async -> [WorkoutSessionUpdate] {
        await Array(Seam.buffered(streams[looks.next() - 1]).dropFirst())
    }

    /// The events of the stored log, in replay order.
    func storedEvents() async throws -> [WorkoutEvent] {
        try await rig.log(live.id).map(\.event)
    }

    /// How a call ended, with a store fault spelled by its call and kind.
    static func outcome(_ call: SeamCall, on host: LocalWorkoutSessionActor) async -> String {
        do {
            switch call {
            case let .start(snapshot): try await host.start(snapshot)
            case let .apply(event): try await host.apply(event)
            case let .finish(endedAt): _ = try await host.finish(endedAt: endedAt)
            case let .discard(endedAt): try await host.discard(endedAt: endedAt)
            }
            return "returned"
        } catch let error as SiegeError {
            return "\(error.call.rawValue) \(error.fault.rawValue)"
        } catch {
            return "\(error)"
        }
    }
}
