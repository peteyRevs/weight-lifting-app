import Foundation
import LedgerDomain
import LedgerTestSupport

/// The check the suites share for calls that overlap.
extension Seam {
    static let overlapTasks = 16
    static let setsPerTask = 20

    /// Sixteen tasks each add and log twenty sets on `client`, which holds `Seam.session(1)`, while two
    /// subscribers listen. `nil` when the updates are one engine history, the same for both subscribers,
    /// and each apply returned the update of its own event; else what was wrong.
    static func overlapFault(on client: any WorkoutSessionClient) async throws -> String? {
        let (one, two) = await (client.updates(), client.updates())
        let events = adds(0 ..< overlapTasks * setsPerTask)
        let returned = try await withThrowingTaskGroup(of: [WorkoutEvent: WorkoutState].self) { group in
            for task in 0 ..< overlapTasks {
                group.addTask {
                    var mine: [WorkoutEvent: WorkoutState] = [:]
                    for number in 0 ..< setsPerTask {
                        guard let add = events[freshSet(task * setsPerTask + number).id] else {
                            continue
                        }
                        mine[add] = try await client.apply(add)
                        mine[logging(add)] = try await client.apply(logging(add))
                    }
                    return mine
                }
            }
            return try await group.reduce(into: [WorkoutEvent: WorkoutState]()) { $0.merge($1) { $1 } }
        }
        let heard = await buffered(one)
        let history = SeamHistory(heard, adds: events)
        if let fault = history.fault {
            return fault
        }
        guard heard.count == 1 + 2 * events.count else {
            return "\(heard.count - 1) updates for \(2 * events.count) applies"
        }
        guard history.published == returned else {
            return "an apply returned a state that is not its own event's update"
        }
        return await buffered(two) == heard ? nil : "the two subscribers disagree"
    }
}
