import Foundation
import LedgerDomain
import LedgerTestSupport

/// Calls that race for the same workout, as checks any client can be put through: each returns `nil` when
/// the client told one story, else what was wrong. Which task wins is the scheduler's choice, so outcomes
/// are judged as sets. Streams are read with `buffered`, so a missing update is a difference, not a wait.
extension Seam {
    /// Fifty starts at once on `client`, which holds no workout: one wins, the rest are refused naming the
    /// winner, and one update is published.
    static func startRaceFault(on client: any WorkoutSessionClient) async throws -> String? {
        let stream = await client.updates()
        let outcomes = await withTaskGroup(of: (Int, SeamOutcome).self) { group in
            for number in 1 ... 50 {
                group.addTask {
                    await (number, outcome(of: .start(session(number)), on: client))
                }
            }
            return await group.reduce(into: [Int: SeamOutcome]()) { $0[$1.0] = $1.1 }
        }
        let winners = outcomes.filter { $0.value == .returned }.map(\.key)
        guard winners.count == 1, let winner = winners.first else {
            return "\(winners.count) of 50 starts returned"
        }
        let refused = outcomes.values.count { $0 == .refused(.workoutInProgress(workout(winner))) }
        guard refused == 49 else {
            return "\(refused) of the 49 other starts were refused naming the winner"
        }
        guard try await client.current() == session(winner) else {
            return "current() is not the winner's workout"
        }
        return await difference(buffered(stream), [Update(state: nil), Update(state: session(winner))], "the stream")
    }

    /// Twenty finishes and twenty discards at once on `client`, which holds a workout: exactly one ends it,
    /// in one update, and returns what was published.
    static func endRaceFault(on client: any WorkoutSessionClient) async throws -> String? {
        let live = try await client.current()
        let stream = await client.updates()
        let outcomes = await withTaskGroup(of: SeamOutcome.self) { group in
            for number in 0 ..< 40 {
                group.addTask {
                    let endedAt = at(Double(100 + number))
                    return await outcome(of: number % 2 == 0 ? .finish(endedAt) : .discard(endedAt), on: client)
                }
            }
            return await group.reduce(into: [SeamOutcome]()) { $0.append($1) }
        }
        let refused = outcomes.count { $0 == .refused(.noLiveWorkout) }
        guard refused == 39 else {
            return "\(40 - refused) of 40 ends were not refused"
        }
        let heard = await buffered(stream)
        guard heard.count == 2, heard.first == Update(state: live), let ended = heard.last?.state, ended.phase != .live
        else {
            return "the stream holds \(heard.count) updates, not the workout and its one end"
        }
        guard outcomes.contains(ended.phase == .finished ? .state(ended) : .returned) else {
            return "the call that ended the workout did not return what was published"
        }
        return try await client.current() == nil ? nil : "a workout is still current after the end"
    }

    /// A finish racing eight tasks of forty adds each on `client`, which holds a workout: every add lands
    /// before the end or is refused after it, and the end is the stream's last word.
    static func applyVersusEndFault(on client: any WorkoutSessionClient) async throws -> String? {
        let stream = await client.updates()
        let outcomes = await withTaskGroup(of: [SeamOutcome].self) { group in
            for task in 0 ..< 8 {
                group.addTask {
                    var mine: [SeamOutcome] = []
                    for number in 0 ..< 40 {
                        let add = WorkoutEvent.setAdded(exerciseIndex: 0, set: freshSet(task * 100 + number))
                        await mine.append(outcome(of: .apply(add), on: client))
                    }
                    return mine
                }
            }
            group.addTask {
                await [outcome(of: .finish(at(500)), on: client)]
            }
            return await group.reduce(into: [[SeamOutcome]]()) { $0.append($1) }
        }
        let heard = await buffered(stream)
        let applies = outcomes.filter { $0.count == 40 }
        let landed = applies.flatMap(\.self).filter { $0 != .refused(.noLiveWorkout) }
        guard let finished = heard.last?.state, finished.phase == .finished,
              outcomes.contains([.state(finished)])
        else {
            return "the stream's last update is not the finished state that finish returned"
        }
        guard heard.dropLast().allSatisfy({ $0.state?.phase == .live }), landed.count == heard.count - 2 else {
            return "\(landed.count) adds returned a state; \(heard.count - 2) live updates came before the end"
        }
        let published = Set(heard.compactMap(\.state))
        guard Set(landed.compactMap(\.state)).isSubset(of: published) else {
            return "an add returned a state that was never published"
        }
        // Within a task, once the workout has ended every later add is refused.
        let late = applies.contains { mine in
            mine.drop { $0 != .refused(.noLiveWorkout) }.contains { $0 != .refused(.noLiveWorkout) }
        }
        return late ? "an add landed after an earlier one of its task was refused" : nil
    }

    /// Forty streams opened while another task adds four hundred sets to `client`, which holds a workout:
    /// each starts at some update, without effects, and then misses none.
    static func lateJoinFault(on client: any WorkoutSessionClient) async throws -> String? {
        let whole = await client.updates()
        let events = adds(0 ..< 400)
        let streams = try await withThrowingTaskGroup(of: AsyncStream<Update>?.self) { group in
            group.addTask {
                for add in events.values {
                    try await client.apply(add)
                }
                return nil
            }
            for _ in 0 ..< 40 {
                group.addTask {
                    await client.updates()
                }
            }
            return try await group.reduce(into: [AsyncStream<Update>]()) { $0 += [$1].compactMap(\.self) }
        }
        let history = await buffered(whole)
        let first = SeamHistory(history, adds: events).fault ?? (history.count == 401 ? nil : "updates are missing")
        if let first {
            return "the stream opened first: \(first)"
        }
        for stream in streams {
            let heard = await buffered(stream)
            let joinedAt = history.firstIndex { $0.state == heard.first?.state } ?? history.count
            guard heard.first?.haptics == [], Array(heard.dropFirst()) == Array(history.dropFirst(joinedAt + 1)) else {
                return "a stream that joined at update \(joinedAt) of 400 then held \(heard.count - 1) more"
            }
        }
        return nil
    }
}
