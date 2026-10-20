import Foundation
import LedgerDomain
import Testing

/// Waits until `condition` holds, for at most `limit` of the wall clock. It records an issue and answers
/// false when the condition has not come by then, so a test that waits for something that never happens
/// fails with what it waited for.
///
/// What it waits for is work already under way on other tasks: a store's actor, a fake clock's sleepers, a
/// double's counter. Many of those are not observable, so the condition is polled: first by giving way on
/// the main actor, which is enough when the work is the main actor's own; then, if it has not come, every
/// millisecond, which leaves the cores to the tasks that are late. The bound is time, not a number of turns:
/// a busy machine (another build, a runner with three cores) runs the other tasks later, never fewer of
/// them, and a count of 200,000 yields once ran out before such a task did (seed 1021568 of
/// `WorkoutAnnouncementAdversarialTests.walk_saysEachRestOnce`, 2026-10-19).
@MainActor
@discardableResult
func eventually(
    _ what: String,
    limit: Duration = .seconds(10),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: limit)
    var turns = 0
    while !condition() {
        guard clock.now < deadline, !Task.isCancelled else {
            Issue.record("never came in \(limit): \(what)", sourceLocation: sourceLocation)
            return false
        }
        turns += 1
        if turns < 1000 {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
    return true
}

/// Gives way often enough for anything already under way to land: for "nothing happened" only.
@MainActor
func giveWay() async {
    for _ in 0 ..< 2000 {
        await Task.yield()
    }
}

/// Whether two workouts are the same in every field, as a `Bool`: a whole state is never printed by an
/// expectation. What differs is printed here, by field name.
nonisolated func unchanged(_ now: WorkoutState?, _ before: WorkoutState?) -> Bool {
    guard now != before else {
        return true
    }
    var fields: [String] = []
    if now?.id != before?.id {
        fields.append("id")
    }
    if now?.phase != before?.phase {
        fields.append("phase")
    }
    if now?.cursor != before?.cursor {
        fields.append("cursor")
    }
    if now?.exercises != before?.exercises {
        fields.append("exercises")
    }
    if now?.rest != before?.rest {
        fields.append("rest")
    }
    if now?.startedAt != before?.startedAt {
        fields.append("startedAt")
    }
    print("workouts differ in: \(fields.isEmpty ? "another field" : fields.joined(separator: ", "))")
    return false
}
