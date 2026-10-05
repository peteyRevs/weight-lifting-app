import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport

/// Logs as a host that died left them in its store (F10 S2 adversarial round 1, criterion 6).
enum SiegeLogs {
    /// `Seam.session(number)` started at `startedAt` and then `events`, as this device stored them: seq 1, 2, …
    /// with stamps a second apart from the start.
    static func log(
        _ number: Int,
        _ events: [WorkoutEvent] = [],
        startedAt: Date = EventBuilders.start
    ) -> [EventEnvelope] {
        var session = Seam.session(number)
        session.startedAt = startedAt
        return EventBuilders.log(
            from: [.started(session)] + events,
            startingAt: startedAt,
            spacing: 1,
            workoutID: Seam.workout(number)
        )
    }

    /// The first two sets of `Seam.session(number)` logged: with auto rest on, a rest is running afterwards and
    /// the cursor stands on the third.
    static func twoSets(in number: Int) -> [WorkoutEvent] {
        [Seam.logged(0, 0, in: number, at: 60), Seam.logged(0, 1, in: number, at: 240)]
    }

    static func finished(_ number: Int, startedAt: Date = EventBuilders.start) -> [EventEnvelope] {
        log(number, twoSets(in: number) + [.finished(endedAt: Seam.at(3600))], startedAt: startedAt)
    }

    static func discarded(_ number: Int) -> [EventEnvelope] {
        log(number, twoSets(in: number) + [.discarded(endedAt: Seam.at(3600))])
    }

    /// A rig whose store holds `logs` and whose host has not been built: the app was killed.
    static func rig(_ backing: SiegeRig.Backing, _ logs: [[EventEnvelope]], yields: Int = 0) async throws -> SiegeRig {
        let rig = try await SiegeRig.make(backing, yields: yields)
        for log in logs {
            _ = try await rig.events.append(log)
        }
        return rig
    }

    /// How the launch step ended: the workout it returned in a few words, or the store fault it threw.
    static func launch(_ host: LocalWorkoutSessionActor) async -> String {
        do {
            let live = try await host.resumeFromStore()
            return live.map { "resumed \($0.id.rawValue.uuidString.suffix(6))" } ?? "no workout"
        } catch let error as SiegeError {
            return "\(error.call.rawValue) \(error.fault.rawValue)"
        } catch {
            return "\(error)"
        }
    }

    static func name(_ number: Int) -> String {
        "resumed \(Seam.workout(number).rawValue.uuidString.suffix(6))"
    }

    static let writes: Set<SiegeCall> = [.append, .compact, .materialize]
}
