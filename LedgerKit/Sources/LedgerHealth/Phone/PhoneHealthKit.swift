#if os(iOS)
    import Foundation
    import HealthKit
    import LedgerDomain

    public extension LiveHealthStore {
        /// The phone's store, over `healthStore` and the mirrored sessions `mirroring` keeps; see the designated
        /// initializer for `watchTookPart` and `onMirrorStart`.
        init(
            healthStore: HKHealthStore = HKHealthStore(),
            mirroring: MirroringStartRegistrar<HKWorkoutSession>,
            bundle: Bundle = .main,
            watchTookPart: @escaping @Sendable (WorkoutID) async -> Bool = { _ in false },
            onMirrorStart: @escaping @Sendable (WorkoutID?) async -> Void = { _ in }
        ) {
            let phone = PhoneHealthKit(healthStore: healthStore)
            self.init(
                provider: phone,
                brandName: HealthMetadataKey.brandName(bundle.object(forInfoDictionaryKey:)),
                mirror: mirroring,
                phone: phone,
                watchTookPart: watchTookPart,
                onMirrorStart: onMirrorStart
            )
        }
    }

    /// The phone's HealthKit calls (F16 S3), kept to the calls themselves: the rules they serve are
    /// `LiveHealthStore`'s, tested over a script. The phone never runs the primary session (ADR-005), so it makes
    /// none, and recovers its mirrored session through `MirroringStartRegistrar`.
    struct PhoneHealthKit: WorkoutSessionProvider, PhoneHealthServices {
        let healthStore: HKHealthStore

        func authorization() -> HealthAuthorization {
            HealthKitAuthorizer(healthStore: healthStore).authorization()
        }

        func requestAuthorization() async throws -> HealthAuthorization {
            try await HealthKitAuthorizer(healthStore: healthStore).requestAuthorization()
        }

        func makeSession() throws -> any WorkoutSessionDriver {
            throw HealthError.unavailable
        }

        func recoverSession() -> (any WorkoutSessionDriver)? {
            nil
        }

        func startWatchApp() async throws {
            try await cancellableCompletion {
                healthStore.startWatchApp(with: HealthTypeSet.strengthTraining(), completion: $0)
            }
        }

        func saveWorkout(
            _ metadata: [String: HealthMetadataValue],
            start: Date,
            end: Date
        ) async throws -> FinishedWorkout {
            let builder = HKWorkoutBuilder(
                healthStore: healthStore,
                configuration: HealthTypeSet.strengthTraining(),
                device: .local()
            )
            let workout = try await healthKitCall {
                try await builder.beginCollection(at: start)
                try await builder.endCollection(at: end)
                try await builder.addMetadata(metadata.healthKitValues)
                return try await builder.finishWorkout()
            }
            guard let workout else {
                throw HealthError.underlying(code: 0)
            }
            return FinishedWorkout(workout)
        }

        func workout(uuid: UUID) async throws -> FinishedWorkout? {
            let query = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                sortDescriptors: []
            )
            return try await healthKitCall { try await query.result(for: healthStore) }.first.map(FinishedWorkout.init)
        }
    }

    /// A mirrored session's delegate. Sendable without `@unchecked`, as the watch's is: final, and its one
    /// property is a `let` Sendable closure.
    final class MirroredSessionDelegate: NSObject, HKWorkoutSessionDelegate, Sendable {
        private let report: @Sendable (MirroringStartRegistrar<HKWorkoutSession>.Callback) -> Void

        init(report: @escaping @Sendable (MirroringStartRegistrar<HKWorkoutSession>.Callback) -> Void) {
            self.report = report
        }

        func workoutSession(
            _: HKWorkoutSession,
            didChangeTo _: HKWorkoutSessionState,
            from _: HKWorkoutSessionState,
            date _: Date
        ) {}

        func workoutSession(_: HKWorkoutSession, didFailWithError _: any Error) {}

        func workoutSession(_: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError _: (any Error)?) {
            report(.disconnected)
        }

        func workoutSession(_: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
            report(.received(data))
        }
    }

    private extension FinishedWorkout {
        /// `workout` with its own statistics (HR average and maximum, energy sum), rounded.
        init(_ workout: HKWorkout) {
            let heartRate = workout.statistics(for: HealthTypeSet.heartRate)
            let perMinute = HKUnit.count().unitDivided(by: .minute())
            let rounded = { (quantity: HKQuantity?, unit: HKUnit) in
                quantity.map { Int($0.doubleValue(for: unit).rounded()) }
            }
            self.init(
                uuid: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                avgHeartRate: rounded(heartRate?.averageQuantity(), perMinute),
                maxHeartRate: rounded(heartRate?.maximumQuantity(), perMinute),
                activeEnergyKcal: rounded(
                    workout.statistics(for: HealthTypeSet.activeEnergy)?.sumQuantity(),
                    .kilocalorie()
                )
            )
        }
    }
#endif
