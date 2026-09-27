import Foundation

/// What a set row is (spec §6.1 "Logged set"; decision #5 counts only `.working` toward misses).
public enum SetKind: String, Codable, Sendable, CaseIterable {
    /// A prescribed set.
    case working
    /// Rule 15: the extra set at −15 % after the last working set.
    case drop
    /// Rule 26: "+ Add set".
    case added
    /// A warm-up set (never counts toward misses or PRs).
    case warmup
}

/// One set row in a live or finished workout (spec §6.1 "Logged set").
public struct LoggedSet: Identifiable, Hashable, Codable, Sendable {
    public let id: SetID
    public var weight: Weight
    public var reps: Reps
    public var kind: SetKind
    /// When the set was ticked done (rule 18); `nil` while undone.
    public var doneAt: Date?

    public init(id: SetID, weight: Weight, reps: Reps, kind: SetKind, doneAt: Date? = nil) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.kind = kind
        self.doneAt = doneAt
    }

    public var isDone: Bool {
        doneAt != nil
    }
}
