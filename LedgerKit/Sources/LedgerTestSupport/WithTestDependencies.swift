#if DEBUG
    import Dependencies
    import Foundation
    import LedgerDependencies
    import LedgerFakes
    import Synchronization

    /// Runs `operation` with the dependencies every store test shares, then those `configure` sets (testing-strategy
    /// §2.6): the date fixed at `Fixtures.now`, incrementing UUIDs, an immediate clock, and `Fixtures`' calendar and
    /// locale (Gregorian, UTC, en_US).
    ///
    /// It starts from each key's `testValue`, not its `previewValue`: a store that reads a key the test did not
    /// configure fails the test with a message naming the key (F07 criterion 3), so no store runs on data the test
    /// never chose. `configure` binds what the test needs, for example
    /// `$0.inMemoryStores(seed: .empty)`. Built on `withDependencies`, so it is safe in parallel tests; it never
    /// calls `prepareDependencies`.
    public func withTestDependencies<Result>(
        _ configure: (inout DependencyValues) throws -> Void,
        operation: () throws -> Result
    ) rethrows -> Result {
        let scope = TestScope()
        return try TestScope.$current.withValue(scope) {
            try withDependencies {
                $0.useTestDefaults()
                try configure(&$0)
                scope.configured($0.date)
            } operation: {
                try operation()
            }
        }
    }

    /// `withTestDependencies(_:operation:)` with nothing to configure.
    public func withTestDependencies<Result>(operation: () throws -> Result) rethrows -> Result {
        try withTestDependencies({ _ in }, operation: operation)
    }

    /// `withTestDependencies(_:operation:)` for an async operation, on the caller's isolation.
    public func withTestDependencies<Result>(
        isolation: isolated (any Actor)? = #isolation,
        _ configure: (inout DependencyValues) throws -> Void,
        operation: () async throws -> Result
    ) async rethrows -> Result {
        let scope = TestScope()
        return try await TestScope.$current.withValue(scope) {
            try await withDependencies(isolation: isolation) {
                $0.useTestDefaults()
                try configure(&$0)
                scope.configured($0.date)
            } operation: {
                try await operation()
            }
        }
    }

    /// `withTestDependencies(_:operation:)` for an async operation with nothing to configure.
    public func withTestDependencies<Result>(
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> Result
    ) async rethrows -> Result {
        try await withTestDependencies(isolation: isolation, { _ in }, operation: operation)
    }

    public extension DependencyValues {
        /// Binds the six store keys to one `InMemoryStores` built from `seed`, and returns it so the test can look
        /// inside. Its stats answer with the date the test configured (findings F7-6, F7-11):
        /// - inside `withTestDependencies`' operation, the `date` dependency, read on each query, so a `date` set
        ///   after this line in `configure`, or by a nested `withDependencies`, is the one they use;
        /// - after the operation (stores the test kept), the `date` its `configure` ended with, so they need no
        ///   dependency there. Bound outside `withTestDependencies`, the `date` as it stands when this runs.
        @discardableResult
        mutating func inMemoryStores(seed: InMemoryStores.Seed = .empty) -> InMemoryStores {
            let clock = StatsClock(date)
            TestScope.current?.register(clock)
            let stores = InMemoryStores(seed: seed, now: { clock.now })
            exerciseRepository = stores.exercises
            programRepository = stores.programs
            workoutRepository = stores.workouts
            statsQueries = stores.stats
            settingsRepository = stores.settings
            workoutEventStore = stores.events
            return stores
        }

        /// The fixed date, UUIDs, clock, calendar and locale of `withTestDependencies`.
        fileprivate mutating func useTestDefaults() {
            date = .constant(Fixtures.now)
            uuid = .incrementing
            continuousClock = ImmediateClock()
            calendar = Fixtures.calendar
            locale = Fixtures.locale
        }
    }

    /// One `withTestDependencies` call, as a task-local: set while its `configure` and its operation run, so the
    /// stats clocks `inMemoryStores` makes can be bound to the date `configure` ends with, and can tell whether
    /// they are queried inside the operation.
    final class TestScope: Sendable {
        @TaskLocal static var current: TestScope?

        private let clocks = Mutex<[StatsClock]>([])

        func register(_ clock: StatsClock) {
            clocks.withLock { $0.append(clock) }
        }

        /// `configure` has returned: every clock it made keeps `date` for queries after the operation.
        func configured(_ date: DateGenerator) {
            for clock in clocks.withLock({ $0 }) {
                clock.configure(date)
            }
        }
    }

    /// The current time of one `InMemoryStores`' stats.
    final class StatsClock: Sendable {
        private let configured: Mutex<DateGenerator>

        init(_ date: DateGenerator) {
            configured = Mutex(date)
        }

        func configure(_ date: DateGenerator) {
            configured.withLock { $0 = date }
        }

        /// Inside a `withTestDependencies` operation, the `date` dependency; otherwise the configured date.
        var now: Date {
            guard TestScope.current != nil else {
                return configured.withLock { $0.now }
            }
            @Dependency(\.date.now) var current
            return current
        }
    }
#endif
