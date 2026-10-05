import Foundation
import LedgerDomain

/// Starting and ending a workout: what `start`, `finish` and `discard` return, throw and publish, and what
/// `current()` and a new stream say afterwards.
extension WorkoutSessionClientContract {
    static let lifecycleClauses: [Clause] = [
        Clause("a new client has no workout: current() is nil and a stream starts with a nil state", startsEmpty),
        Clause("start makes a live snapshot current and publishes it, with no effects", startMakesCurrent),
        Clause("a second start throws workoutInProgress, changes nothing and publishes nothing", secondStart),
        Clause("a snapshot the engine would not start throws notStartable, live workout or not", notStartable),
        Clause("apply, finish and discard with nothing live throw noLiveWorkout and publish nothing", nothingLive),
        Clause("finish returns the finished state, publishes it once, then there is no workout", finishEnds),
        Clause("discard publishes the discarded state once, then there is no workout", discardEnds),
        Clause("a terminal event through apply ends the workout as finish and discard do", terminalByApply),
        Clause("after a workout ends another can start, and earlier subscribers see it", startsAgain)
    ]

    static func startsEmpty(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            ContractCheck.expect(current, nil, "current()"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: nil)])
        )
    }

    static func startMakesCurrent(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        try await client.start(session)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            ContractCheck.expect(current, session, "current()"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: nil), Update(state: session)])
        )
    }

    static func secondStart(_ client: Client) async throws -> String? {
        try await client.start(session)
        var subscriber = await Subscriber(client)
        let again = await ContractCheck.expectError(WorkoutSessionError.workoutInProgress(session.id)) {
            try await client.start(session)
        }
        let another = await ContractCheck.expectError(WorkoutSessionError.workoutInProgress(session.id)) {
            try await client.start(other)
        }
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            again,
            another,
            ContractCheck.expect(current, session, "current() after the refused starts"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: session)])
        )
    }

    /// Snapshots the engine ignores a `started` for: ended ones, and a live one holding a date that is not
    /// finite (`EventEnvelope.isWellFormed`).
    static var unstartable: [WorkoutState] {
        var finished = other
        finished.phase = .finished
        finished.endedAt = at(600)
        var discarded = other
        discarded.phase = .discarded
        discarded.endedAt = at(600)
        var malformed = other
        malformed.startedAt = never
        return [finished, discarded, malformed]
    }

    static func notStartable(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        var issues: [String?] = []
        for snapshot in unstartable {
            await issues.append(ContractCheck.expectError(WorkoutSessionError.notStartable(snapshot.id)) {
                try await client.start(snapshot)
            })
        }
        let current = try await client.current()
        issues.append(ContractCheck.expect(current, nil, "current() after the refused starts"))
        try await client.start(session)
        // The snapshot is judged first: with a workout live it is still `notStartable`.
        for snapshot in unstartable {
            await issues.append(ContractCheck.expectError(WorkoutSessionError.notStartable(snapshot.id)) {
                try await client.start(snapshot)
            })
        }
        let mark = try await markEnd(of: client)
        let seen = await subscriber.updates(before: mark)
        issues.append(expectUpdates(seen, [Update(state: nil), Update(state: session)]))
        return issues.lazy.compactMap(\.self).first
    }

    static func nothingLive(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        let refused = WorkoutSessionError.noLiveWorkout
        let apply = await ContractCheck.expectError(refused) { _ = try await client.apply(.restSkipped) }
        // `apply` never starts a workout: only `start` does.
        let started = await ContractCheck.expectError(refused) { _ = try await client.apply(.started(session)) }
        let finish = await ContractCheck.expectError(refused) { _ = try await client.finish(endedAt: at(600)) }
        let discard = await ContractCheck.expectError(refused) { try await client.discard(endedAt: at(600)) }
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            apply,
            started,
            finish,
            discard,
            ContractCheck.expect(current, nil, "current() after the refused calls"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: nil)])
        )
    }

    static func finishEnds(_ client: Client) async throws -> String? {
        try await client.start(session)
        let live = try await client.apply(logged(0, 0))
        var subscriber = await Subscriber(client)
        let finished = try await client.finish(endedAt: at(600))
        let current = try await client.current()
        var late = await Subscriber(client)
        let mark = try await markEnd(of: client)
        let published = Update(state: finished, effects: [.haptic(.workoutFinished)])
        return await ContractCheck.first(
            ContractCheck.expect(finished.phase, .finished, "the returned state's phase"),
            ContractCheck.expect(finished.endedAt, at(600), "the returned state's endedAt"),
            ContractCheck.expect(
                finished,
                engineUpdate(live, .finished(endedAt: at(600)), in: session.id)?.state,
                "the returned state"
            ),
            ContractCheck.expect(current, nil, "current() after finish"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: live), published]),
            expectUpdates(late.updates(before: mark), [Update(state: nil)], "a stream opened after finish")
        )
    }

    static func discardEnds(_ client: Client) async throws -> String? {
        try await client.start(session)
        let live = try await client.apply(logged(0, 0))
        var subscriber = await Subscriber(client)
        try await client.discard(endedAt: at(600))
        let current = try await client.current()
        var late = await Subscriber(client)
        let mark = try await markEnd(of: client)
        // `discard` returns nothing, so the discarded state is the engine's: the live one, ended, with no haptic.
        guard let published = engineUpdate(live, .discarded(endedAt: at(600)), in: session.id) else {
            return "the engine ignored the discard"
        }
        return await ContractCheck.first(
            ContractCheck.expect(published.state?.phase, .discarded, "the discarded state's phase"),
            ContractCheck.expect(published.state?.endedAt, at(600), "the discarded state's endedAt"),
            ContractCheck.expect(published.effects, [], "the discarding update's effects"),
            ContractCheck.expect(current, nil, "current() after discard"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: live), published]),
            expectUpdates(late.updates(before: mark), [Update(state: nil)], "a stream opened after discard")
        )
    }

    static func terminalByApply(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        try await client.start(session)
        let finished = try await client.apply(.finished(endedAt: at(600)))
        let afterFinish = try await client.current()
        try await client.start(other)
        let discarded = try await client.apply(.discarded(endedAt: at(900)))
        let afterDiscard = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            ContractCheck.expect(finished.phase, .finished, "apply(.finished) returns a state in phase"),
            ContractCheck.expect(afterFinish, nil, "current() after apply(.finished)"),
            ContractCheck.expect(discarded.phase, .discarded, "apply(.discarded) returns a state in phase"),
            ContractCheck.expect(afterDiscard, nil, "current() after apply(.discarded)"),
            expectUpdates(
                subscriber.updates(before: mark),
                [
                    Update(state: nil),
                    Update(state: session),
                    Update(state: finished, effects: [.haptic(.workoutFinished)]),
                    Update(state: other),
                    Update(state: discarded)
                ]
            )
        )
    }

    static func startsAgain(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        try await client.start(session)
        let finished = try await client.finish(endedAt: at(600))
        // The ended workout is gone: nothing is live to finish or discard a second time.
        let refused = WorkoutSessionError.noLiveWorkout
        let again = await ContractCheck.expectError(refused) { _ = try await client.finish(endedAt: at(700)) }
        let discard = await ContractCheck.expectError(refused) { try await client.discard(endedAt: at(700)) }
        try await client.start(other)
        let current = try await client.current()
        let repeated = try await client.apply(
            .allSetsRepeated(exerciseIndex: 0, weight: .pounds(60), reps: Reps(clamping: 12))
        )
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            again,
            discard,
            ContractCheck.expect(current, other, "current() after the second start"),
            expectUpdates(
                subscriber.updates(before: mark),
                [
                    Update(state: nil),
                    Update(state: session),
                    Update(state: finished, effects: [.haptic(.workoutFinished)]),
                    Update(state: other),
                    Update(state: repeated)
                ]
            )
        )
    }
}
