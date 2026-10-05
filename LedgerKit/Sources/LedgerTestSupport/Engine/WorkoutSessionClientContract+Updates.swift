import Foundation
import LedgerDomain

/// The update stream: what a subscriber is told, in what order, and when nothing is published.
extension WorkoutSessionClientContract {
    static let updateClauses: [Clause] = [
        Clause("apply returns the state after the event; the next update carries it and the engine's haptics", applies),
        Clause("a stream opened on a live workout starts with it, without the last event's effects", joinsLive),
        Clause("two subscribers, one from before the start, each get every update in order", twoSubscribers),
        Clause("updates under rapid apply calls arrive in order, none dropped or merged", rapidApplies),
        Clause("callers at once: every event is applied once, in one order every subscriber sees", callersAtOnce),
        Clause("an event the engine accepts is published once even when it changes nothing here", unchanged),
        Clause("an event the engine ignores returns the workout unchanged and publishes nothing", ignored),
        Clause("a subscriber whose task is cancelled stops; the others keep getting every update", cancelled)
    ]

    /// One event of each kind `apply` takes on a live workout, each of which changes `session` where it
    /// stands in this order.
    static let events: [WorkoutEvent] = [
        .exerciseSelected(exerciseIndex: 1, setIndex: 0),
        logged(1, 0, at: 30),
        .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: at(40)),
        .restSkipped,
        retargeted(0, 1, pounds: 190),
        .setAdded(
            exerciseIndex: 0,
            set: LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(185), reps: .one, kind: .added)
        ),
        .allSetsRepeated(exerciseIndex: 2, weight: .pounds(75), reps: Reps(clamping: 8)),
        .exerciseSwapped(
            exerciseIndex: 3,
            exerciseID: ExerciseID(EventBuilders.uuid(0xE0FF)),
            name: "Pull-Up",
            alsoUpdateProgram: true
        ),
        .restStarted(endsAt: at(200), total: .seconds(90)),
        .setUnlogged(exerciseIndex: 1, setID: EventBuilders.setID(1, 0))
    ]

    static func applies(_ client: Client) async throws -> String? {
        try await client.start(session)
        var subscriber = await Subscriber(client)
        let expected = engineUpdates(from: session, events)
        guard expected.count == events.count, Set(expected).count == events.count else {
            return "the engine no longer accepts every fixture event with a change of its own"
        }
        for (event, update) in zip(events, expected) {
            let returned = try await client.apply(event)
            if let issue = expectUpdates([Update(state: returned)], [Update(state: update.state)], "apply returned") {
                return "\(event): \(issue)"
            }
        }
        let mark = try await markEnd(of: client)
        return await expectUpdates(subscriber.updates(before: mark), [Update(state: session)] + expected)
    }

    static func joinsLive(_ client: Client) async throws -> String? {
        try await client.start(session)
        // The stream is opened right after a haptic: its first element still carries no effects.
        let live = try await client.apply(logged(0, 0))
        var subscriber = await Subscriber(client)
        let next = try await client.apply(retargeted(0, 1, pounds: 190))
        let mark = try await markEnd(of: client)
        return await expectUpdates(subscriber.updates(before: mark), [Update(state: live), Update(state: next)])
    }

    static func twoSubscribers(_ client: Client) async throws -> String? {
        let script = [logged(0, 0), retargeted(0, 1, pounds: 190), .finished(endedAt: at(600))]
        let expected = engineUpdates(from: session, script)
        var early = await Subscriber(client)
        try await client.start(session)
        let first = try await client.apply(script[0])
        var late = await Subscriber(client)
        try await client.apply(script[1])
        _ = try await client.finish(endedAt: at(600))
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates(
                early.updates(before: mark),
                [Update(state: nil), Update(state: session)] + expected,
                "the earlier subscriber's updates"
            ),
            expectUpdates(
                late.updates(before: mark),
                [Update(state: first)] + expected.dropFirst(),
                "the later subscriber's updates"
            )
        )
    }

    /// Sixty stepper edits with no read in between: the stream must hold every one (it is unbounded), in the
    /// order they were applied.
    static func rapidApplies(_ client: Client) async throws -> String? {
        try await client.start(session)
        var subscriber = await Subscriber(client)
        let edits = (0 ..< 60).map { retargeted(0, $0 % 5, pounds: Decimal(100 + $0)) }
        var returned: [Update] = []
        for edit in edits {
            try await returned.append(Update(state: client.apply(edit)))
        }
        let expected = engineUpdates(from: session, edits)
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates(returned, expected, "the states apply returned"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: session)] + expected)
        )
    }

    /// One edit per row of the session, all applied at once. The edits commute, so whatever order the client
    /// takes them in, the workout ends the same; a client that lets two calls start from one state loses an
    /// edit.
    static func callersAtOnce(_ client: Client) async throws -> String? {
        try await client.start(session)
        var one = await Subscriber(client)
        var two = await Subscriber(client)
        let rows = session.exercises.enumerated().flatMap { index, exercise in
            exercise.sets.indices.map { (exercise: index, set: $0) }
        }
        let edits = rows.enumerated().map { number, row in
            retargeted(row.exercise, row.set, pounds: Decimal(200 + number))
        }
        let returned = try await withThrowingTaskGroup(of: WorkoutState.self) { group in
            for edit in edits {
                group.addTask { try await client.apply(edit) }
            }
            return try await group.reduce(into: Set<WorkoutState>()) { $0.insert($1) }
        }
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        let seen = await one.updates(before: mark)
        let published = Set(seen.dropFirst().compactMap(\.state))
        let final = engineUpdates(from: session, edits).last?.state
        return await ContractCheck.first(
            ContractCheck.expect(current, final, "current() once every caller has returned"),
            ContractCheck.expect(seen.count, edits.count + 1, "the number of updates"),
            ContractCheck.expect(seen.first, Update(state: session), "the first update"),
            ContractCheck.expect(seen.last?.state, final, "the last update's state"),
            ContractCheck.expect(published == returned, true, "the published states are the returned ones"),
            expectUpdates(two.updates(before: mark), seen, "the second subscriber's updates against the first's")
        )
    }

    static func unchanged(_ client: Client) async throws -> String? {
        try await client.start(session)
        let done = try await client.apply(logged(0, 0))
        var subscriber = await Subscriber(client)
        // No row 99 to select (rule 11), and a done set logged again with the same values: neither changes the
        // state, yet the engine accepts both. Each belongs in the log, and the second one buzzes.
        let pointless: [WorkoutEvent] = [.exerciseSelected(exerciseIndex: 99, setIndex: 0), logged(0, 0)]
        let expected = [Update(state: done), Update(state: done, effects: [.haptic(.setLogged)])]
        guard engineUpdates(from: done, pointless) == expected else {
            return "the engine no longer accepts these events without changing the state"
        }
        var returned: [Update] = []
        for event in pointless {
            try await returned.append(Update(state: client.apply(event)))
        }
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates(returned, [Update(state: done), Update(state: done)], "the states apply returned"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: done)] + expected)
        )
    }

    /// What ADR-004 has the engine ignore on a live workout: a second `started`, a date that is not finite, a
    /// rest longer than `WorkoutEngine.longestRest`.
    static let ignoredEvents: [WorkoutEvent] = [
        .started(other),
        logged(0, 0, at: .infinity),
        .restStarted(endsAt: at(10), total: WorkoutEngine.longestRest + .seconds(1)),
        .finished(endedAt: never),
        .discarded(endedAt: never)
    ]

    static func ignored(_ client: Client) async throws -> String? {
        guard engineUpdates(from: session, ignoredEvents).isEmpty else {
            return "the engine no longer ignores every fixture event"
        }
        try await client.start(session)
        var subscriber = await Subscriber(client)
        var returned: [Update] = []
        for event in ignoredEvents {
            try await returned.append(Update(state: client.apply(event)))
        }
        try await returned.append(Update(state: client.finish(endedAt: never)))
        try await client.discard(endedAt: never)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates(
                returned,
                Array(repeating: Update(state: session), count: ignoredEvents.count + 1),
                "the states apply and finish returned"
            ),
            ContractCheck.expect(current, session, "current() after the ignored calls"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: session)])
        )
    }

    static func cancelled(_ client: Client) async throws -> String? {
        var kept = await Subscriber(client)
        let stream = await client.updates()
        let (listening, signal) = AsyncStream<Void>.makeStream()
        let heard = await withTaskGroup(of: [Update].self) { group in
            group.addTask {
                var heard: [Update] = []
                for await update in stream {
                    heard.append(update)
                    signal.yield()
                }
                return heard
            }
            // Cancelled only once it is listening: it has read its first update.
            var reading = listening.makeAsyncIterator()
            _ = await reading.next()
            group.cancelAll()
            return await group.next() ?? []
        }
        try await client.start(session)
        let next = try await client.apply(logged(0, 0))
        var late = await Subscriber(client)
        let mark = try await markEnd(of: client)
        return await ContractCheck.first(
            expectUpdates(heard, [Update(state: nil)], "the cancelled subscriber's updates"),
            expectUpdates(
                kept.updates(before: mark),
                [Update(state: nil), Update(state: session)] + engineUpdates(from: session, [logged(0, 0)]),
                "the other subscriber's updates"
            ),
            expectUpdates(late.updates(before: mark), [Update(state: next)], "a stream opened afterwards")
        )
    }
}
