import Foundation
import LedgerDomain
import LedgerTestSupport

/// Round 2's overlap checks, for the pairs of calls round 1's did not race: a start against applies, a
/// subscriber that acts on the update it was just given, and ends at dates the engine ignores against one
/// that succeeds. Each returns `nil` when the client told one story, else what was wrong; none asserts
/// which task won.
extension Seam {
    /// One start races four tasks that each apply ten adds, retrying while nothing is live, on `client`,
    /// which holds no workout. The stream must read: no workout, the start, then one history of the adds.
    static func startVersusApplyFault(on client: any WorkoutSessionClient) async throws -> String? {
        let stream = await client.updates()
        let events = adds(0 ..< 40)
        let landed = await withTaskGroup(of: Int.self) { group in
            group.addTask {
                _ = await outcome(of: .start(session(1)), on: client)
                return 0
            }
            for task in 0 ..< 4 {
                group.addTask {
                    var count = 0
                    for number in task * 10 ..< task * 10 + 10 {
                        guard let add = events[freshSet(number).id] else {
                            continue
                        }
                        count += await appliedOnceLive(add, on: client) ? 1 : 0
                    }
                    return count
                }
            }
            return await group.reduce(0, +)
        }
        let heard = await buffered(stream)
        guard heard.first == Update(state: nil), heard.dropFirst().first == Update(state: session(1)) else {
            return "the stream does not read no workout, then the start: its second update is "
                + (heard.dropFirst().first.map(brief) ?? "missing")
        }
        let fault = SeamHistory(Array(heard.dropFirst()), adds: events).fault
        return fault ?? (heard.count == 2 + landed ? nil : "\(landed) adds returned, \(heard.count - 2) were published")
    }

    /// Applies `event` as soon as a workout is live, giving up after many refusals. Whether it landed.
    private static func appliedOnceLive(_ event: WorkoutEvent, on client: any WorkoutSessionClient) async -> Bool {
        for _ in 0 ..< 200_000 {
            if await outcome(of: .apply(event), on: client) != .refused(.noLiveWorkout) {
                return true
            }
            await Task.yield()
        }
        return false
    }

    /// A subscriber of `client`, which holds no workout, acts on the update that says a workout is live: by
    /// then `current()` must hold a workout and an `apply` must not be refused for want of one.
    static func reactionFault(on client: any WorkoutSessionClient) async throws -> String? {
        let stream = await client.updates()
        let reacting = Task { () -> String? in
            for await update in stream where update.live != nil {
                guard let current = try? await client.current(), current.phase == .live else {
                    return "current() held no workout when the update that started one had arrived"
                }
                let applied = await outcome(of: .apply(.restSkipped), on: client)
                return applied == .refused(.noLiveWorkout) ? "an apply made on the start's update found no workout" :
                    nil
            }
            return "the stream ended before it told of a workout"
        }
        do {
            try await client.start(session(1))
        } catch {
            reacting.cancel()
            throw error
        }
        return await reacting.value
    }

    /// Twelve finishes and discards at dates the engine ignores race one finish at 500 s on `client`, which
    /// holds a workout. Only that finish may return, with the finished state the one update carries; each of
    /// the others throws `invalidEndDate` (it came first) or `noLiveWorkout` (it came after).
    static func invalidEndRaceFault(on client: any WorkoutSessionClient) async throws -> String? {
        guard let live = try await client.current(),
              let finished = engine(live, .finished(endedAt: at(500)), in: live.id).0
        else {
            return "no workout to end"
        }
        let stream = await client.updates()
        let outcomes = await withTaskGroup(of: (Bool, SeamOutcome).self) { group in
            for number in 0 ..< 12 {
                group.addTask {
                    let never = nonFinite[number % 3]
                    return await (false, outcome(of: number < 6 ? .finish(never) : .discard(never), on: client))
                }
            }
            group.addTask {
                await (true, outcome(of: .finish(at(500)), on: client))
            }
            return await group.reduce(into: [(Bool, SeamOutcome)]()) { $0.append($1) }
        }
        let allowed: [SeamOutcome] = [.refused(.invalidEndDate), .refused(.noLiveWorkout)]
        if let stray = outcomes.first(where: { !$0.0 && !allowed.contains($0.1) }) {
            return "an end at a date the engine ignores \(stray.1)"
        }
        guard outcomes.contains(where: { $0.0 && $0.1 == .state(finished) }) else {
            return "the finish at 500 s did not return the finished state"
        }
        let expected = [Update(state: live), Update(state: finished, haptics: [.workoutFinished])]
        return await difference(buffered(stream), expected, "the stream")
    }
}
