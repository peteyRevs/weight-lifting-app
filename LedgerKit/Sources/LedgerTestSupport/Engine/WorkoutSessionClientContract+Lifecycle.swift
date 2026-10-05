import Foundation
import LedgerDomain

/// Starting and ending a workout: what `start`, `finish` and `discard` return, throw and publish, and what
/// `current()` and a new stream say afterwards.
extension WorkoutSessionClientContract {
    static let lifecycleClauses: [Clause] = [
        Clause("a new client has no workout: current() is nil and a stream starts with a nil state", startsEmpty),
        Clause("start makes a live snapshot current and publishes it, with no haptics", startMakesCurrent),
        Clause("a second start throws workoutInProgress, changes nothing and publishes nothing", secondStart),
        Clause("a snapshot the engine would not start throws notStartable, live workout or not", notStartable),
        Clause("apply, finish and discard with nothing live throw noLiveWorkout and publish nothing", nothingLive),
        Clause("finish returns the finished state, publishes it once, then there is no workout", finishEnds),
        Clause("discard publishes the discarded state once, then there is no workout", discardEnds),
        Clause(
            "finish and discard at a date the engine ignores throw invalidEndDate, end nothing and publish nothing",
            invalidEnd
        ),
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

    /// Snapshots the engine ignores a `started` for (`EventEnvelope.isWellFormed`): ended ones, and live ones
    /// that hold a start date that is not finite, a rest longer than `WorkoutEngine.longestRest`, or a set
    /// done at a date that is not finite. A client must ask the engine: the phase and the start date alone do
    /// not tell.
    static var unstartable: [WorkoutState] {
        var finished = other
        finished.phase = .finished
        finished.endedAt = at(600)
        var discarded = other
        discarded.phase = .discarded
        discarded.endedAt = at(600)
        var startedNever = other
        startedNever.startedAt = never
        var restingTooLong = other
        restingTooLong.rest = RestTimer(endsAt: at(60), total: WorkoutEngine.longestRest + .seconds(1))
        var doneNever = other
        doneNever.exercises[0].sets[0].doneAt = never
        return [finished, discarded, startedNever, restingTooLong, doneNever]
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
        // With nothing live there is no end to ignore: a date that is not finite is `noLiveWorkout` too.
        let finishNever = await ContractCheck.expectError(refused) { _ = try await client.finish(endedAt: never) }
        let discardNever = await ContractCheck.expectError(refused) { try await client.discard(endedAt: never) }
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            apply,
            started,
            finish,
            discard,
            finishNever,
            discardNever,
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
        let published = Update(state: finished, haptics: [.workoutFinished])
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
            ContractCheck.expect(published.haptics, [], "the discarding update's haptics"),
            ContractCheck.expect(current, nil, "current() after discard"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: live), published]),
            expectUpdates(late.updates(before: mark), [Update(state: nil)], "a stream opened after discard")
        )
    }

    /// `finish` and `discard` promise an ended workout, so an end the engine ignores is refused: the caller
    /// of `discard`, which returns nothing, could not tell otherwise. The same event through `apply` stays an
    /// ignored event (the clause "an event the engine ignores…").
    ///
    /// A refused end leaves the workout as it was, so one the engine takes still ends it afterwards. That
    /// finish is made at once with eight more ends the engine ignores, listed before it so that they are
    /// inside the client when it wins: each of them may only throw, `invalidEndDate` when it came first and
    /// `noLiveWorkout` when it came after. A client that looks again after a suspension, finds the workout
    /// gone and returns as if its own end had been taken fails here.
    static func invalidEnd(_ client: Client) async throws -> String? {
        guard engineUpdates(from: session, [.finished(endedAt: never), .discarded(endedAt: never)]).isEmpty,
              let finishing = engineUpdate(session, .finished(endedAt: at(600)), in: session.id)
        else {
            return "the engine no longer ignores an end at a date that is not finite, or ignored one that is"
        }
        try await client.start(session)
        var subscriber = await Subscriber(client)
        let refused = WorkoutSessionError.invalidEndDate
        let finish = await ContractCheck.expectError(refused) { _ = try await client.finish(endedAt: never) }
        let discard = await ContractCheck.expectError(refused) { try await client.discard(endedAt: never) }
        let current = try await client.current()
        let ignoredEnds: [Step] = (0 ..< 8).map { number in
            number.isMultiple(of: 2) ? .finish(endedAt: never) : .discard(endedAt: never)
        }
        let outcomes = await outcomesAtOnce(of: ignoredEnds + [.finish(endedAt: at(600))], on: client)
        let allowed: [Outcome] = [.refused(.invalidEndDate), .refused(.noLiveWorkout)]
        let stray = outcomes.dropLast().first { !allowed.contains($0) }
        let afterwards = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            finish,
            discard,
            ContractCheck.expect(current, session, "current() after the refused ends"),
            stray.map { "an end at a date the engine ignores \($0), beside a finish the engine takes" },
            ContractCheck.expect(outcomes.last, finishing.state.map { .state($0) }, "the finish the engine takes"),
            ContractCheck.expect(afterwards, nil, "current() once that finish has returned"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: session), finishing])
        )
    }

    static func terminalByApply(_ client: Client) async throws -> String? {
        // The ended states are the engine's, not what the client hands back: each end is at the event's date.
        guard let finishing = engineUpdate(session, .finished(endedAt: at(600)), in: session.id),
              let discarding = engineUpdate(other, .discarded(endedAt: at(900)), in: other.id)
        else {
            return "the engine ignored a terminal event"
        }
        var subscriber = await Subscriber(client)
        try await client.start(session)
        let finished = try await client.apply(.finished(endedAt: at(600)))
        let afterFinish = try await client.current()
        try await client.start(other)
        let discarded = try await client.apply(.discarded(endedAt: at(900)))
        let afterDiscard = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates([Update(state: finished)], [Update(state: finishing.state)], "apply(.finished) returned"),
            ContractCheck.expect(afterFinish, nil, "current() after apply(.finished)"),
            expectUpdates([Update(state: discarded)], [Update(state: discarding.state)], "apply(.discarded) returned"),
            ContractCheck.expect(afterDiscard, nil, "current() after apply(.discarded)"),
            expectUpdates(
                subscriber.updates(before: mark),
                [Update(state: nil), Update(state: session), finishing, Update(state: other), discarding]
            )
        )
    }

    static func startsAgain(_ client: Client) async throws -> String? {
        // The engine's answers for the end of the first workout and for the edit of the second.
        let repeatAll = WorkoutEvent.allSetsRepeated(exerciseIndex: 0, weight: .pounds(60), reps: Reps(clamping: 12))
        guard let finishing = engineUpdate(session, .finished(endedAt: at(600)), in: session.id),
              let repeating = engineUpdate(other, repeatAll, in: other.id)
        else {
            return "the engine ignored the finish or the edit"
        }
        var subscriber = await Subscriber(client)
        try await client.start(session)
        let finished = try await client.finish(endedAt: at(600))
        // The ended workout is gone: nothing is live to finish or discard a second time.
        let refused = WorkoutSessionError.noLiveWorkout
        let again = await ContractCheck.expectError(refused) { _ = try await client.finish(endedAt: at(700)) }
        let discard = await ContractCheck.expectError(refused) { try await client.discard(endedAt: at(700)) }
        try await client.start(other)
        let current = try await client.current()
        try await client.apply(repeatAll)
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates([Update(state: finished)], [Update(state: finishing.state)], "finish returned"),
            again,
            discard,
            ContractCheck.expect(current, other, "current() after the second start"),
            expectUpdates(
                subscriber.updates(before: mark),
                [Update(state: nil), Update(state: session), finishing, Update(state: other), repeating]
            )
        )
    }
}
