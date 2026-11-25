#if os(watchOS)
    import Foundation
    import HealthKit
    import LedgerDomain

    public extension LiveHealthStore {
        /// The watch's store, over `healthStore`, branded with the app's name from `bundle`.
        init(healthStore: HKHealthStore = HKHealthStore(), bundle: Bundle = .main) {
            self.init(
                provider: HealthKitSessionProvider(healthStore: healthStore),
                brandName: HealthMetadataKey.brandName(bundle.object(forInfoDictionaryKey:))
            )
        }
    }

    /// The watch's sessions, from HealthKit (F16 S2b).
    struct HealthKitSessionProvider: WorkoutSessionProvider {
        let healthStore: HKHealthStore

        func authorization() -> HealthAuthorization {
            HealthKitAuthorizer(healthStore: healthStore).authorization()
        }

        func requestAuthorization() async throws -> HealthAuthorization {
            try await HealthKitAuthorizer(healthStore: healthStore).requestAuthorization()
        }

        /// An indoor traditional-strength-training session (architecture §9), set up and not yet prepared.
        func makeSession() throws -> any WorkoutSessionDriver {
            do {
                let session = try HKWorkoutSession(
                    healthStore: healthStore,
                    configuration: HealthTypeSet.strengthTraining()
                )
                return HealthKitWorkoutSession(attaching: session, healthStore: healthStore)
            } catch {
                throw HealthError(error)
            }
        }

        func recoverSession() async throws -> (any WorkoutSessionDriver)? {
            let session = try await healthKitCall { try await healthStore.recoverActiveWorkoutSession() }
            return session.map { HealthKitWorkoutSession(attaching: $0, healthStore: healthStore) }
        }
    }

    /// One `HKWorkoutSession` and its `HKLiveWorkoutBuilder`. It is Sendable without `@unchecked`: HealthKit marks
    /// the session, the builder and the data source Sendable, and every property is a `let`.
    final class HealthKitWorkoutSession: WorkoutSessionDriver {
        let callbacks: AsyncStream<WorkoutSessionCallback>
        private let session: HKWorkoutSession
        private let builder: HKLiveWorkoutBuilder
        /// The session and the builder hold their delegate weakly.
        private let delegate: WorkoutSessionDelegate

        /// Attaches the builder, its live data source and the delegates to `session`, in that order: for a new
        /// session and for a recovered one alike (R1 §2.3, §3.1).
        init(attaching session: HKWorkoutSession, healthStore: HKHealthStore) {
            let (stream, sink) = AsyncStream<WorkoutSessionCallback>.makeStream(bufferingPolicy: .unbounded)
            let liveBuilder = session.associatedWorkoutBuilder()
            liveBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: session.workoutConfiguration
            )
            let both = WorkoutSessionDelegate(sink: sink)
            session.delegate = both
            liveBuilder.delegate = both
            callbacks = stream
            self.session = session
            builder = liveBuilder
            delegate = both
        }

        func prepare() {
            session.prepare()
        }

        func startMirroring() async throws {
            try await cancellableCompletion { session.startMirroringToCompanionDevice(completion: $0) }
        }

        func startActivity(at date: Date) {
            session.startActivity(with: date)
        }

        func beginCollection(at date: Date) async throws {
            try await healthKitCall { try await builder.beginCollection(at: date) }
        }

        func stopActivity(at date: Date) {
            session.stopActivity(with: date)
        }

        func endCollection(at date: Date) async throws {
            try await healthKitCall { try await builder.endCollection(at: date) }
        }

        func addMetadata(_ metadata: [String: HealthMetadataValue]) async throws {
            try await healthKitCall { try await builder.addMetadata(metadata.healthKitValues) }
        }

        /// Writes the workout; the record's statistics are the builder's (HR average and maximum, energy sum).
        func finishWorkout() async throws -> FinishedWorkout {
            guard let workout = try await healthKitCall({ try await builder.finishWorkout() }) else {
                throw HealthError.noActiveSession
            }
            let heartRate = builder.statistics(for: HealthTypeSet.heartRate)
            let perMinute = HKUnit.count().unitDivided(by: .minute())
            return FinishedWorkout(
                uuid: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                avgHeartRate: heartRate?.averageQuantity()?.rounded(in: perMinute),
                maxHeartRate: heartRate?.maximumQuantity()?.rounded(in: perMinute),
                activeEnergyKcal: builder.statistics(for: HealthTypeSet.activeEnergy)?.sumQuantity()?
                    .rounded(in: .kilocalorie())
            )
        }

        func end() {
            session.end()
        }

        func discardWorkout() {
            builder.discardWorkout()
        }

        func send(_ data: Data) async throws {
            try await healthKitCall { try await session.sendToRemoteWorkoutSession(data: data) }
        }
    }

    /// Both delegates, as values on one stream. Sendable without `@unchecked`: it is final and its one property is
    /// a `let` continuation, which is Sendable, so HealthKit may call it on any queue; it reads only what each call
    /// hands it, and the store reads the stream in its own isolation.
    final class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, Sendable {
        private let sink: AsyncStream<WorkoutSessionCallback>.Continuation

        init(sink: AsyncStream<WorkoutSessionCallback>.Continuation) {
            self.sink = sink
        }

        func workoutSession(
            _: HKWorkoutSession,
            didChangeTo toState: HKWorkoutSessionState,
            from _: HKWorkoutSessionState,
            date: Date
        ) {
            sink.yield(.state(WorkoutSessionState(toState), date))
        }

        func workoutSession(_: HKWorkoutSession, didFailWithError error: any Error) {
            sink.yield(.failed(HealthError(error)))
        }

        func workoutSession(_: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError _: (any Error)?) {
            sink.yield(.mirrorDisconnected)
        }

        func workoutSession(_: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
            sink.yield(.received(data))
        }

        /// The most recent heart rate, when the batch has one. Its value is never logged.
        func workoutBuilder(
            _ workoutBuilder: HKLiveWorkoutBuilder,
            didCollectDataOf collectedTypes: Set<HKSampleType>
        ) {
            guard collectedTypes.contains(HealthTypeSet.heartRate),
                  let statistics = workoutBuilder.statistics(for: HealthTypeSet.heartRate),
                  let bpm = statistics.mostRecentQuantity()?.rounded(in: .count().unitDivided(by: .minute())),
                  let interval = statistics.mostRecentQuantityDateInterval()
            else {
                return
            }
            sink.yield(.heartRate(HeartRateSample(bpm: bpm, date: interval.end)))
        }

        func workoutBuilderDidCollectEvent(_: HKLiveWorkoutBuilder) {}
    }

    extension WorkoutSessionState {
        init(_ state: HKWorkoutSessionState) {
            switch state {
            case .prepared: self = .prepared
            case .running: self = .running
            case .paused: self = .paused
            case .stopped: self = .stopped
            case .ended: self = .ended
            default: self = .notStarted
            }
        }
    }

    private extension HKQuantity {
        func rounded(in unit: HKUnit) -> Int {
            Int(doubleValue(for: unit).rounded())
        }
    }
#endif
