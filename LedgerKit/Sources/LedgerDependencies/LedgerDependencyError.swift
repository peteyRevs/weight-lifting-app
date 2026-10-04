/// Why a dependency could not do what was asked.
public enum LedgerDependencyError: Error, Equatable, Sendable {
    /// The key's live value is an `Unimplemented*` stub: the composition root has not bound a real one yet
    /// (F07 binds the stores in S2; HealthKit, the transports and the clients come with F16–F23).
    case unimplemented(key: String)
}
