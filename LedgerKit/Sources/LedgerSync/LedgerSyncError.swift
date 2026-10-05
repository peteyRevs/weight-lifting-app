/// What LedgerSync refuses on its own account (engineering-standards §8): no caller got anything wrong.
public enum LedgerSyncError: Error, Equatable, Sendable {
    /// The session host could not stamp an envelope with a finite time: its clock reads a time that is not
    /// finite (`HybridLogicalClock.stamp(now:)`). The engine would ignore such an envelope, so the call is
    /// refused before anything is stored or changed.
    case noFiniteStamp
}
