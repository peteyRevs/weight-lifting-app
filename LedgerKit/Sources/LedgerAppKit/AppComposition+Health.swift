#if os(iOS)
    import HealthKit
    import LedgerHealth
#endif
import LedgerDomain
import LedgerSync

/// What the phone's health store asks the live workout's host (F17 S7b): whether a watch took part in a workout
/// (the watch saves that one to Health, F16 S3b) and what runs at each mirrored start.
struct HealthHooks: Sendable {
    let watchTookPart: @Sendable (WorkoutID) async -> Bool
    let onMirrorStart: @Sendable (WorkoutID?) async -> Void
}

extension AppComposition.Environment {
    /// The phone's mirroring handler, and how to make its HealthKit store, which reads the sessions the handler
    /// keeps (ADR-005; F16 S3a). Elsewhere (the package's host build), neither.
    static func liveHealth() -> (assignHandler: () -> Void, makeStore: (HealthHooks) -> (any HealthStore)?) {
        #if os(iOS)
            let registrar = MirroringStartRegistrar<HKWorkoutSession>()
            return ({ registrar.register() }, { hooks in
                LiveHealthStore(
                    mirroring: registrar,
                    watchTookPart: hooks.watchTookPart,
                    onMirrorStart: hooks.onMirrorStart
                )
            })
        #else
            return ({}, { _ in nil })
        #endif
    }
}
