#if os(iOS)
    import HealthKit
    import LedgerHealth
#endif
import LedgerDomain

extension AppComposition.Environment {
    /// The phone's mirroring handler and its HealthKit store, which reads the sessions the handler keeps (ADR-005;
    /// F16 S3a). Elsewhere (the package's host build), neither.
    static func liveHealth() -> (assignHandler: () -> Void, store: (any HealthStore)?) {
        #if os(iOS)
            let registrar = MirroringStartRegistrar<HKWorkoutSession>()
            return ({ registrar.register() }, LiveHealthStore(mirroring: registrar))
        #else
            return ({}, nil)
        #endif
    }
}
