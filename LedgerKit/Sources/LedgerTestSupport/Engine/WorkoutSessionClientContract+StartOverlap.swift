import Foundation
import LedgerDomain

/// A start that overlaps other calls: the two clauses of `overlapClauses` about the moment a workout begins.
extension WorkoutSessionClientContract {
    /// One start races four tasks of twelve adds each, on a client with no workout. An add made before the
    /// start is refused; from the start on they land. The stream must tell it in that order: no workout, the
    /// start, then the adds that landed, as one history. A client that commits a start and publishes it
    /// after a suspension lets an add be published before the workout it belongs to.
    static func startAgainstApplies(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        let edits = adds(48)
        // The start leads the group, so that it is inside the client when the adds begin.
        let raced = await outcomes(ofApplying: edits, inTasksOf: 12, beside: .start(session), leading: true, on: client)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        let seen = await subscriber.updates(before: mark)
        let refused = Outcome.refused(.noLiveWorkout)
        let landed = Set(raced.applies.joined().compactMap(\.state))
        let published = Set(seen.dropFirst(2).compactMap(\.state))
        let strays = raced.applies.joined().count { $0.state == nil && $0 != refused }
        let refusedAfterLanding = raced.applies.contains { mine in
            mine.drop { $0 == refused }.contains(refused)
        }
        return ContractCheck.first(
            ContractCheck.expect(raced.step, .done, "the start"),
            expectUpdates(Array(seen.prefix(1)), [Update(state: nil)], "the update before the start"),
            historyIssue(Array(seen.dropFirst()), from: session, events: edits, "the updates from the start on"),
            ContractCheck.expect(strays, 0, "adds that neither landed nor threw noLiveWorkout"),
            ContractCheck.expect(landed == published, true, "the adds that returned a state are the ones published"),
            ContractCheck.expect(refusedAfterLanding, false, "adds of a task refused after an earlier one landed"),
            expectUpdates([Update(state: current)], [Update(state: seen.last?.state)], "current() after the calls")
        )
    }

    /// A subscriber acts on the update that tells it of the workout, as a screen does: it reads `current()`
    /// and applies an edit, while the `start` that published the update may still be inside the client. By
    /// the time a client says a workout is live, the workout must be there: a client that publishes a start
    /// and commits it after a suspension answers that subscriber with no workout.
    ///
    /// A client that never tells an open stream of the start keeps this clause waiting for the time limit,
    /// as one that never publishes a clause's last change does.
    static func reactsToTheStart(_ client: Client) async throws -> String? {
        let stream = await client.updates()
        var other = await Subscriber(client)
        let edit = retargeted(0, 0, pounds: 190)
        let reaction = try await withThrowingTaskGroup(of: (current: WorkoutState?, applied: Outcome)?.self) { group in
            group.addTask {
                for await update in stream where update.live != nil {
                    let current = try await client.current()
                    return await (current, outcome(of: .apply(edit), on: client))
                }
                return nil
            }
            try await client.start(session)
            return try await group.next() ?? nil
        }
        let mark = try await markEnd(of: client)
        guard let reaction, let edited = engineUpdate(session, edit, in: session.id) else {
            return "the subscriber's stream ended before it told of the workout"
        }
        return await ContractCheck.first(
            expectUpdates(
                [Update(state: reaction.current)],
                [Update(state: session)],
                "current() when the start's update arrived"
            ),
            ContractCheck.expect(reaction.applied, edited.state.map { .state($0) }, "an apply on the start's update"),
            expectUpdates(other.updates(before: mark), [Update(state: nil), Update(state: session), edited])
        )
    }
}
