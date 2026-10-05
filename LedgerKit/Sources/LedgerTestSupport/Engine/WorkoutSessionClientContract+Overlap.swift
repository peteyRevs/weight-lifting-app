import Foundation
import LedgerDomain

/// Calls that overlap. A host is an actor that awaits its store and its recovery, so two calls can be inside
/// it at once; the fake never suspends, so these clauses are the ones that hold a host to "one call at a
/// time". Each sends its calls from a task group and judges what came of them as a set, because which call
/// wins is the scheduler's choice.
///
/// The overlap must not depend on a second thread happening to run: a task that makes several calls in a row
/// never gives way between them on an uncontended client, because a hop to an idle actor does not suspend.
/// So either every call is a task of its own, or the task gives way after each call (`Task.yield()`).
extension WorkoutSessionClientContract {
    static let overlapClauses: [Clause] = [
        Clause(
            "callers at once: every event is applied once, and each update follows from the one before",
            callersAtOnce
        ),
        Clause("starts at once: one succeeds, the others throw workoutInProgress naming it", startsAtOnce),
        Clause(
            "ends at once: exactly one ends the workout, in one update; the others throw noLiveWorkout",
            endsAtOnce
        ),
        Clause(
            "an apply against an end lands before it or throws noLiveWorkout; the end is the last update",
            applyAgainstAnEnd
        ),
        Clause(
            "a stream opened while calls are in flight starts with a published state and misses no later update",
            joinsInFlight
        ),
        Clause(
            "a start against applies: the start is published first, then the applies that landed, as one history",
            startAgainstApplies
        ),
        Clause(
            "a subscriber acting on the start's update finds the workout current and its apply accepted",
            reactsToTheStart
        )
    ]

    /// `count` "+ Add set" events on `session`, each a set of its own, spread over its exercises: every one
    /// changes the workout, and they commute.
    static func adds(_ count: Int) -> [WorkoutEvent] {
        (0 ..< count).map { number in
            let id = SetID(EventBuilders.uuid(0xAD0000 + number))
            let set = LoggedSet(id: id, weight: .pounds(45), reps: .one, kind: .added)
            return .setAdded(exerciseIndex: number % session.exercises.count, set: set)
        }
    }

    /// `nil` when `updates`, a stream from its first element on, is one history of the engine: it starts
    /// with `start` and no haptics, and each later update is the engine's for the state before it and one of
    /// `events` not yet seen. Else the first update that does not follow.
    static func historyIssue(
        _ updates: [Update],
        from start: WorkoutState,
        events: [WorkoutEvent],
        _ what: String = "updates"
    ) -> String? {
        guard updates.first == Update(state: start) else {
            return "\(what): the first is \(brief(updates.first)), expected \(brief(Update(state: start)))"
        }
        var state = start
        var unseen = Set(events)
        for (index, update) in updates.enumerated().dropFirst() {
            let event = unseen.first { engineUpdate(state, $0, in: state.id) == update }
            guard let event, let next = update.state else {
                return "\(what): update \(index), \(brief(update)), does not follow from the one before it "
                    + "by any event not yet seen"
            }
            unseen.remove(event)
            state = next
        }
        return nil
    }

    /// One event per row of the session, all applied at once: the five rows of the first exercise are logged,
    /// which buzzes, and the others get a stepper edit. Whatever order the client takes them in, its updates
    /// must be one history of the engine, haptics included. A client that lets two calls start from one state
    /// loses an event; one that publishes in another order than it applied shows a state the workout never
    /// had; one that drops a haptic when calls overlap publishes an update the engine never made.
    static func callersAtOnce(_ client: Client) async throws -> String? {
        try await client.start(session)
        var one = await Subscriber(client)
        var two = await Subscriber(client)
        let rows = session.exercises.enumerated().flatMap { index, exercise in
            exercise.sets.indices.map { (exercise: index, set: $0) }
        }
        let events = rows.enumerated().map { number, row in
            row.exercise == 0 ? logged(0, row.set) : retargeted(row.exercise, row.set, pounds: Decimal(200 + number))
        }
        let returned = try await withThrowingTaskGroup(of: WorkoutState.self) { group in
            for event in events {
                group.addTask { try await client.apply(event) }
            }
            return try await group.reduce(into: Set<WorkoutState>()) { $0.insert($1) }
        }
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        let seen = await one.updates(before: mark)
        let published = Set(seen.dropFirst().compactMap(\.state))
        // The logs move the cursor and restart the rest, so the last state depends on the order the client
        // took: the walk says that every event is in it once, and `current()` must be where the walk ends.
        return await ContractCheck.first(
            ContractCheck.expect(seen.count, events.count + 1, "the number of updates"),
            historyIssue(seen, from: session, events: events),
            expectUpdates([Update(state: current)], [Update(state: seen.last?.state)], "current() after the calls"),
            ContractCheck.expect(published == returned, true, "the published states are the returned ones"),
            expectUpdates(two.updates(before: mark), seen, "the second subscriber's updates against the first's")
        )
    }

    /// Twelve starts at once, each with a workout of its own. A client that suspends between "nothing is
    /// live" and its commit lets several succeed, and leaves as many logs behind.
    static func startsAtOnce(_ client: Client) async throws -> String? {
        var subscriber = await Subscriber(client)
        let snapshots = (0 ..< 12).map { number in
            EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(0xF300 + number)))
        }
        let outcomes = await outcomesAtOnce(of: snapshots.map { .start($0) }, on: client)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        let winners = outcomes.indices.filter { outcomes[$0] == .done }
        guard winners.count == 1, let winner = winners.first.map({ snapshots[$0] }) else {
            return "\(winners.count) of \(snapshots.count) starts returned, expected one"
        }
        let refused = outcomes.count { $0 == .refused(.workoutInProgress(winner.id)) }
        return await ContractCheck.first(
            ContractCheck.expect(refused, snapshots.count - 1, "starts refused naming the workout that won"),
            ContractCheck.expect(current, winner, "current() once every start has returned"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: nil), Update(state: winner)])
        )
    }

    /// Six finishes and six discards at once, each at a time of its own. A client that suspends before it
    /// commits an end lets several end the workout, and publishes as many endings.
    static func endsAtOnce(_ client: Client) async throws -> String? {
        try await client.start(session)
        var subscriber = await Subscriber(client)
        let ends: [Step] = (0 ..< 12).map { number in
            let endedAt = at(Double(600 + number))
            return number.isMultiple(of: 2) ? .finish(endedAt: endedAt) : .discard(endedAt: endedAt)
        }
        let outcomes = await outcomesAtOnce(of: ends, on: client)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        let winners = outcomes.indices.filter { outcomes[$0] != .refused(.noLiveWorkout) }
        guard winners.count == 1, let winner = winners.first else {
            return "\(winners.count) of \(ends.count) ends were not refused with noLiveWorkout, expected one"
        }
        // What the rules make of the end that won: what its call returned, and the one update it published.
        var model = Model()
        _ = model.perform(.start(session))
        let (ruled, ending) = model.perform(ends[winner])
        return await ContractCheck.first(
            ContractCheck.expect(outcomes[winner], ruled, "the end that won (\(ends[winner]) \(winner))"),
            ContractCheck.expect(current, nil, "current() once every end has returned"),
            expectUpdates(subscriber.updates(before: mark), [Update(state: session)] + [ending].compactMap(\.self))
        )
    }

    /// How each of `steps` ended on `client` when all were called at once, in the steps' order.
    static func outcomesAtOnce(of steps: [Step], on client: Client) async -> [Outcome] {
        await withTaskGroup(of: (Int, Outcome).self) { group in
            for (number, step) in steps.enumerated() {
                group.addTask { await (number, outcome(of: step, on: client)) }
            }
            let ended = await group.reduce(into: [Int: Outcome]()) { $0[$1.0] = $1.1 }
            return steps.indices.compactMap { ended[$0] }
        }
    }

    /// How `edits` and `step` ended when they raced on `client`: the edits are applied by tasks of `each`
    /// that make their calls one after another and give way after each one, and `step` is one more call,
    /// the first task of the group when `leading` and the last otherwise.
    static func outcomes(
        ofApplying edits: [WorkoutEvent],
        inTasksOf each: Int,
        beside step: Step,
        leading: Bool,
        on client: Client
    ) async -> (applies: [[Outcome]], step: Outcome?) {
        await withTaskGroup(of: (applies: [Outcome], step: Outcome?).self) { group in
            if leading {
                group.addTask { await ([], outcome(of: step, on: client)) }
            }
            for first in stride(from: 0, to: edits.count, by: each) {
                group.addTask {
                    var mine: [Outcome] = []
                    for edit in edits[first ..< min(first + each, edits.count)] {
                        await mine.append(outcome(of: .apply(edit), on: client))
                        await Task.yield()
                    }
                    return (mine, nil)
                }
            }
            if !leading {
                group.addTask { await ([], outcome(of: step, on: client)) }
            }
            return await group.reduce(into: (applies: [[Outcome]](), step: Outcome?.none)) { all, one in
                if let ended = one.step {
                    all.step = ended
                } else {
                    all.applies.append(one.applies)
                }
            }
        }
    }

    /// Six tasks of twelve adds each race one finish. Every add lands before the end or is refused after it:
    /// a client that publishes the end before it lets go of the workout lets an add land after it.
    static func applyAgainstAnEnd(_ client: Client) async throws -> String? {
        try await client.start(session)
        var subscriber = await Subscriber(client)
        let edits = adds(72)
        let finish = Step.finish(endedAt: at(600))
        let raced = await outcomes(ofApplying: edits, inTasksOf: 12, beside: finish, leading: false, on: client)
        let current = try await client.current()
        let mark = try await markEnd(of: client)
        let seen = await subscriber.updates(before: mark)
        return ContractCheck.first(
            ContractCheck.expect(current, nil, "current() once every call has returned"),
            endIssue(seen, edits, applies: raced.applies, finish: raced.step)
        )
    }

    /// What is wrong with a stream on which `edits` raced a finish at 600 s, given how each task's applies
    /// and the finish ended. The updates before the last must be one history of the engine, and the last the
    /// finish of the state before it, which `finish` returned. Every add either landed (it returned a state,
    /// and that state was published) or threw `noLiveWorkout`, and none of a task landed after one was refused.
    static func endIssue(
        _ seen: [Update],
        _ edits: [WorkoutEvent],
        applies: [[Outcome]],
        finish: Outcome?
    ) -> String? {
        let live = Array(seen.dropLast())
        let ending = live.last?.state.flatMap { engineUpdate($0, .finished(endedAt: at(600)), in: $0.id) }
        let refused = Outcome.refused(.noLiveWorkout)
        let landed = Set(applies.joined().compactMap(\.state))
        let published = Set(live.dropFirst().compactMap(\.state))
        let strays = applies.joined().count { $0.state == nil && $0 != refused }
        let landedAfterARefusal = applies.contains { mine in
            mine.drop { $0 != refused }.contains { $0 != refused }
        }
        return ContractCheck.first(
            historyIssue(live, from: session, events: edits, "the updates before the last"),
            expectUpdates(Array(seen.suffix(1)), [ending].compactMap(\.self), "the last update, which must be the end"),
            ContractCheck.expect(finish, ending?.state.map { .state($0) }, "what finish returned"),
            ContractCheck.expect(strays, 0, "adds that neither landed nor threw noLiveWorkout"),
            ContractCheck.expect(landed == published, true, "the adds that returned a state are the ones published"),
            ContractCheck.expect(landedAfterARefusal, false, "an add of a task landed after an earlier one was refused")
        )
    }

    /// Eight streams are opened while another task adds sixty sets. Each must start with a state the first
    /// subscriber was told, without haptics, and then carry every update after it: a client that reads the
    /// state, suspends and only then registers the stream leaves a gap.
    static func joinsInFlight(_ client: Client) async throws -> String? {
        try await client.start(session)
        var first = await Subscriber(client)
        let edits = adds(60)
        let streams = try await withThrowingTaskGroup(of: AsyncStream<Update>?.self) { group in
            group.addTask {
                for edit in edits {
                    try await client.apply(edit)
                    await Task.yield()
                }
                return nil
            }
            for _ in 0 ..< 8 {
                group.addTask { await client.updates() }
            }
            return try await group.reduce(into: [AsyncStream<Update>]()) { $0 += [$1].compactMap(\.self) }
        }
        let mark = try await markEnd(of: client)
        let history = await first.updates(before: mark)
        var issues = [
            ContractCheck.expect(history.count, edits.count + 1, "the number of updates on the stream opened first"),
            historyIssue(history, from: session, events: edits, "the stream opened first")
        ]
        for stream in streams {
            var late = Subscriber(stream)
            let heard = await late.updates(before: mark)
            guard let joined = history.firstIndex(where: { $0.state == heard.first?.state }) else {
                issues.append("a stream opened in flight starts with \(brief(heard.first)), which was never published")
                continue
            }
            let expected = [Update(state: history[joined].state)] + history[(joined + 1)...]
            issues.append(expectUpdates(heard, expected, "a stream opened in flight, at update \(joined)"))
        }
        return issues.lazy.compactMap(\.self).first
    }
}
