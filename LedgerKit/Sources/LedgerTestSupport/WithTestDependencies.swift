#if DEBUG
    import Dependencies
    import Foundation
    import LedgerDependencies
    import LedgerFakes

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
        try withDependencies {
            $0.useTestDefaults()
            try configure(&$0)
        } operation: {
            try operation()
        }
    }

    /// `withTestDependencies(_:operation:)` with nothing to configure.
    public func withTestDependencies<Result>(operation: () throws -> Result) rethrows -> Result {
        try withTestDependencies({ _ in }, operation: operation)
    }

    /// `withTestDependencies(_:operation:)` for an async operation, on the caller's isolation.
    public func withTestDependencies<Result>(
        isolation _: isolated (any Actor)? = #isolation,
        _ configure: (inout DependencyValues) throws -> Void,
        operation: () async throws -> Result
    ) async rethrows -> Result {
        try await withDependencies {
            $0.useTestDefaults()
            try configure(&$0)
        } operation: {
            try await operation()
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
        /// inside. Its stats read the `date` dependency each time they need the current time, as the composition
        /// root's GRDB stats will, so a `date` the test sets after this line is the one they use (finding F7-6).
        @discardableResult
        mutating func inMemoryStores(seed: InMemoryStores.Seed = .empty) -> InMemoryStores {
            let stores = InMemoryStores(seed: seed, now: {
                @Dependency(\.date.now) var now
                return now
            })
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
#endif
