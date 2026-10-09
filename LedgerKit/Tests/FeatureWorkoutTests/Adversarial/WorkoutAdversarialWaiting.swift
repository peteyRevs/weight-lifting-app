import Foundation
import LedgerDomain
import Testing

/// Waits for `condition` by giving way on the main actor, never by the clock. It records an issue and
/// answers false when the condition does not come, so a test that waits for something that never happens
/// fails with what it waited for.
@MainActor
@discardableResult
func eventually(
    _ what: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    for _ in 0 ..< 200_000 {
        if condition() {
            return true
        }
        await Task.yield()
    }
    Issue.record("never came: \(what)", sourceLocation: sourceLocation)
    return false
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
