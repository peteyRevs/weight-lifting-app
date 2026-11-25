#if DEBUG
    import Foundation
    import LedgerDomain

    /// `HealthStore` for previews and tests (F16), held to `HealthStoreContractTests`: the initializer scripts what
    /// HealthKit answers, `simulate…` plays what it does unasked. It is its own `remoteChannel`, bound to the newest
    /// mirrored session. Saved workouts get `Fixtures.uuid(7001)`, `7002`, … in save order; a discarded session ends
    /// at `Fixtures.now`.
    public actor FakeHealthStore: HealthStore, RemoteSessionChannel {
        /// How `startSession`'s mirroring to the phone ends.
        public enum Mirroring: Sendable {
            case connects, timesOut
        }

        /// A session HealthKit holds.
        public struct Session: Equatable, Sendable {
            public let workoutID: WorkoutID
            public let start: Date

            public init(workoutID: WorkoutID, start: Date) {
                self.workoutID = workoutID
                self.start = start
            }
        }

        public nonisolated let events: AsyncStream<HealthSessionEvent>
        public nonisolated let connection: AsyncStream<Bool>
        public nonisolated let incoming: AsyncStream<[Data]>
        public nonisolated var remoteChannel: any RemoteSessionChannel {
            self
        }

        public private(set) var saved: [HealthWorkoutRecord] = []
        public private(set) var savedMetadata: [HealthWorkoutMetadata] = []
        public private(set) var activeSession: Session?
        public private(set) var discarded = false
        public private(set) var watchStartRequests = 0
        /// Mirrored sessions the phone was handed, every one retained (criterion 7).
        public private(set) var mirroredSessionCount = 0
        /// The mirrored session the channel is bound to (numbered from 1), nil when none is connected.
        public private(set) var boundSession: Int?
        /// Every send, with the mirrored session it went to.
        public private(set) var sent: [(session: Int, data: Data)] = []

        private var status: HealthAuthorization
        private let grant: HealthAuthorization
        private let mirroring: Mirroring
        private let watchAppInstalled: Bool
        private let activeEnergyKcal: Int?
        private var recoverable: Session?
        private let sink: AsyncStream<HealthSessionEvent>.Continuation
        private let connectionSink: AsyncStream<Bool>.Continuation
        private let incomingSink: AsyncStream<[Data]>.Continuation
        private var heartRateSubscribers: [AsyncStream<HeartRateSample>.Continuation] = []
        private var sessionSamples: [HeartRateSample] = []
        private var bindings = 0

        /// `grant` is the lifter's answer to the sheet, shown only while `.notDetermined`; `recoverable` is the
        /// session `recoverActiveSession()` finds, once; `activeEnergyKcal` is what an ended watch session reports.
        public init(
            authorization: HealthAuthorization = .notDetermined,
            grant: HealthAuthorization = .authorized,
            mirroring: Mirroring = .connects,
            watchAppInstalled: Bool = true,
            activeEnergyKcal: Int? = nil,
            recoverable: Session? = nil
        ) {
            status = authorization
            self.grant = grant
            self.mirroring = mirroring
            self.watchAppInstalled = watchAppInstalled
            self.activeEnergyKcal = activeEnergyKcal
            self.recoverable = recoverable
            (events, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            (connection, connectionSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
            (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        }

        public func authorization() -> HealthAuthorization {
            status
        }

        public func requestAuthorization() throws -> HealthAuthorization {
            if status == .unavailable {
                throw HealthError.unavailable
            }
            if status == .notDetermined {
                status = grant
            }
            return status
        }

        public func startSession(workoutID: WorkoutID, at start: Date) throws {
            try requireAuthorized()
            guard activeSession == nil else {
                throw HealthError.sessionAlreadyRunning
            }
            activeSession = Session(workoutID: workoutID, start: start)
            sessionSamples = []
            sink.yield(.prepared)
            switch mirroring {
            case .connects: bind()
            case .timesOut: sink.yield(.failed(.mirroringTimedOut))
            }
            sink.yield(.running(since: start))
        }

        public func heartRate() -> AsyncStream<HeartRateSample> {
            let (stream, continuation) = AsyncStream<HeartRateSample>.makeStream(bufferingPolicy: .unbounded)
            heartRateSubscribers.append(continuation)
            return stream
        }

        public func endSession(metadata: HealthWorkoutMetadata, at end: Date) throws -> HealthWorkoutRecord {
            guard let session = activeSession else {
                throw HealthError.noActiveSession
            }
            let beats = sessionSamples.map(\.bpm)
            let average = beats.isEmpty ? nil : Int((Double(beats.reduce(0, +)) / Double(beats.count)).rounded())
            activeSession = nil
            sink.yield(.ended(end))
            return save(metadata, session.start, end, heartRate: (average, beats.max()), energy: activeEnergyKcal)
        }

        public func discardSession() throws {
            guard activeSession != nil else {
                throw HealthError.noActiveSession
            }
            activeSession = nil
            discarded = true
            sink.yield(.ended(Fixtures.now))
        }

        public func recoverActiveSession() -> Bool {
            guard activeSession == nil, let session = recoverable else {
                return false
            }
            recoverable = nil
            activeSession = session
            sink.yield(.recovered)
            return true
        }

        public nonisolated func noteStartRequestedByPhone() {
            sink.yield(.startRequestedByPhone)
        }

        public func requestWatchStart() throws {
            watchStartRequests += 1
            guard watchAppInstalled else {
                throw HealthError.watchAppUnavailable
            }
        }

        public func saveWorkout(metadata: HealthWorkoutMetadata, start: Date, end: Date) throws -> HealthWorkoutRecord {
            try requireAuthorized()
            return save(metadata, start, end, heartRate: (nil, nil), energy: nil)
        }

        public func workoutRecord(healthKitUUID: UUID) -> HealthWorkoutRecord? {
            saved.first { $0.healthKitUUID == healthKitUUID }
        }

        /// Throws `noActiveSession` while no mirrored session is connected.
        public func send(_ data: Data) throws {
            guard let boundSession else {
                throw HealthError.noActiveSession
            }
            sent.append((boundSession, data))
        }
    }

    /// What HealthKit does unasked, and the helpers.
    public extension FakeHealthStore {
        /// The wrist's readings, to every `heartRate()` stream; a running session's statistics count them.
        func simulateHeartRate(_ samples: [HeartRateSample]) {
            if activeSession != nil {
                sessionSamples += samples
            }
            for sample in samples {
                for subscriber in heartRateSubscribers {
                    subscriber.yield(sample)
                }
            }
        }

        /// Another app's workout took over: HealthKit ends ours and nothing is written (criterion 9).
        func simulateAnotherWorkoutSessionStarted() {
            guard activeSession != nil else {
                return
            }
            activeSession = nil
            sink.yield(.anotherWorkoutSessionStarted)
        }

        /// The phone was handed a new mirrored session: it is retained and the channel rebinds to it.
        func simulateMirrorStarted() {
            mirroredSessionCount += 1
            bind()
        }

        /// The newest mirrored session disconnected.
        func simulateMirrorDisconnected() {
            boundSession = nil
            connectionSink.yield(false)
            sink.yield(.mirrorDisconnected)
        }

        /// A batch the other device sent.
        func simulateIncoming(_ batch: [Data]) {
            incomingSink.yield(batch)
        }

        private func bind() {
            bindings += 1
            boundSession = bindings
            connectionSink.yield(true)
            sink.yield(.mirrorConnected)
        }

        private func save(
            _ metadata: HealthWorkoutMetadata,
            _ start: Date,
            _ end: Date,
            heartRate: (average: Int?, max: Int?),
            energy: Int?
        ) -> HealthWorkoutRecord {
            let record = HealthWorkoutRecord(
                healthKitUUID: Fixtures.uuid(7001 + saved.count),
                start: start,
                end: end,
                avgHeartRate: heartRate.average,
                maxHeartRate: heartRate.max,
                activeEnergyKcal: energy
            )
            saved.append(record)
            savedMetadata.append(metadata)
            return record
        }

        private func requireAuthorized() throws {
            switch status {
            case .authorized: return
            case .unavailable: throw HealthError.unavailable
            case .notDetermined, .denied: throw HealthError.notAuthorized
            }
        }
    }
#endif
