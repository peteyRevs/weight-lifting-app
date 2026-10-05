import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// The keys as a store test meets them (architecture §13): a key the test did not configure fails the test by
/// name (F07 criterion 3); `withTestDependencies` fixes the time, ids, clock, calendar and locale; and
/// `inMemoryStores(seed:)` binds every store to one in-memory state.
@Suite("Dependency keys")
struct DependencyKeysTests {
    /// Each key with a test that fails when it is read unconfigured, and how to read it.
    struct Read: Sendable, CustomStringConvertible {
        let key: String
        let read: @Sendable () -> Void

        var description: String {
            key
        }
    }

    static let unconfigured: [Read] = [
        Read(key: "exerciseRepository") { @Dependency(\.exerciseRepository) var value; _ = value },
        Read(key: "programRepository") { @Dependency(\.programRepository) var value; _ = value },
        Read(key: "workoutRepository") { @Dependency(\.workoutRepository) var value; _ = value },
        Read(key: "workoutEventStore") { @Dependency(\.workoutEventStore) var value; _ = value },
        Read(key: "settingsRepository") { @Dependency(\.settingsRepository) var value; _ = value },
        Read(key: "statsQueries") { @Dependency(\.statsQueries) var value; _ = value },
        Read(key: "healthStore") { @Dependency(\.healthStore) var value; _ = value },
        Read(key: "liveWorkoutTransport") { @Dependency(\.liveWorkoutTransport) var value; _ = value },
        Read(key: "companionTransport") { @Dependency(\.companionTransport) var value; _ = value },
        Read(key: "haptics") { @Dependency(\.haptics) var value; _ = value },
        Read(key: "notifications") { @Dependency(\.notifications) var value; _ = value },
        Read(key: "liveActivities") { @Dependency(\.liveActivities) var value; _ = value },
        Read(key: "deviceID") { @Dependency(\.deviceID) var value; _ = value },
        Read(key: "workoutSession") { @Dependency(\.workoutSession) var value; _ = value }
    ]

    @Test("Criterion 3: a key the test did not configure fails it, naming the key", arguments: unconfigured)
    func test_unimplementedDependencyFailsLoudly(_ read: Read) {
        withKnownIssue {
            withTestDependencies {
                read.read()
            }
        } matching: { issue in
            issue.description.contains("@Dependency(\\.\(read.key))")
        }
    }

    @Test("The logger needs no configuring: its test value discards")
    func logger_testValue_discardsWithoutAnIssue() {
        withTestDependencies {
            @Dependency(\.logger) var logger
            logger.log.fault("discarded")
            #expect(!logger.isEnabled)
            #expect(!logger.category("other").isEnabled)
        }
    }

    @Test("withTestDependencies fixes the date, ids, clock, calendar and locale")
    func withTestDependencies_fixesTimeIDsAndPlace() async throws {
        try await withTestDependencies {
            @Dependency(\.date.now) var now
            @Dependency(\.uuid) var uuid
            @Dependency(\.calendar) var calendar
            @Dependency(\.locale) var locale
            @Dependency(\.continuousClock) var clock
            #expect(now == Fixtures.now)
            #expect(uuid() == UUID(0))
            #expect(uuid() == UUID(1))
            #expect(calendar == Fixtures.calendar)
            #expect(locale == Locale(identifier: "en_US"))
            #expect(clock is ImmediateClock<Duration>)
            try await clock.sleep(for: .seconds(3600)) // returns at once
        }
    }

    @Test("configure runs after the defaults, so a test can replace one")
    func withTestDependencies_configureOverridesTheDefaults() {
        let later = Fixtures.now.addingTimeInterval(60)
        withTestDependencies {
            $0.date = .constant(later)
        } operation: {
            @Dependency(\.date.now) var now
            #expect(now == later)
        }
    }

    @Test("A test binds the workout session to a fake, and what reads the key gets that fake", .timeLimit(.minutes(1)))
    func workoutSession_boundToAFake_isTheOneRead() async throws {
        let workout = try Fixtures.seedSession()
        let fake = FakeWorkoutSessionClient(live: workout)
        try await withTestDependencies {
            $0.workoutSession = fake
        } operation: {
            @Dependency(\.workoutSession) var session
            let current = try await session.current()
            #expect(session as? FakeWorkoutSessionClient === fake)
            #expect(current == workout)
        }
    }

    @Test("inMemoryStores binds the six stores to one state: a materialised workout reaches the stats")
    func inMemoryStores_linksEveryStore() async throws {
        let workout = try #require(Fixtures.history(weeks: 1).last)
        let catalog = try ExerciseCatalog.seed()
        try await withTestDependencies {
            try $0.inMemoryStores(seed: InMemoryStores.Seed(catalog: catalog, programs: [Fixtures.seedProgram()]))
        } operation: {
            @Dependency(\.workoutRepository) var workouts
            @Dependency(\.statsQueries) var stats
            @Dependency(\.programRepository) var programs
            @Dependency(\.exerciseRepository) var exercises
            @Dependency(\.settingsRepository) var settings
            @Dependency(\.workoutEventStore) var events
            var missed = try #require(try await programs.active()?.days.first?.slots.first)
            missed.misses = [4]
            try await workouts.materialize(workout, slotUpdates: [missed])
            #expect(workout.tag == "UA")
            #expect(try await stats.sessionCount(exerciseID: Fixtures.CatalogID.benchPress) == 1)
            #expect(try await stats.sessionsCompleted(in: .distantPast ..< .distantFuture) == 1)
            #expect(try await programs.active()?.days.first?.slots.first?.misses == [4])
            #expect(try await exercises.all().count == catalog.count)
            #expect(try await settings.load() == .default)
            #expect(try await events.uncompactedWorkoutIDs().isEmpty)
        }
    }

    @Test("Stores kept after the operation answer with the date configure ended with, set after binding too (F7-11)")
    func keptStores_answerWithTheConfiguredDate() async throws {
        let workout = try #require(Fixtures.history(weeks: 1).last)
        let later = Fixtures.now.addingTimeInterval(14 * 86400)
        var bound: InMemoryStores?
        try await withTestDependencies {
            bound = $0.inMemoryStores()
            $0.date = .constant(later)
        } operation: {
            @Dependency(\.workoutRepository) var workouts
            try await workouts.materialize(workout, slotUpdates: [])
        }
        let stores = try #require(bound)
        let calendar = try WeekCalendar(
            startDate: Fixtures.seedProgram().startDate,
            weekStart: .monday,
            calendar: Fixtures.calendar
        )
        // From `later`, the workout is two weeks back, outside the last week.
        let byWeek = try await stores.stats.e1RMByWeek(
            exerciseID: Fixtures.CatalogID.benchPress,
            lastWeeks: 1,
            calendar: calendar
        )
        #expect(byWeek.isEmpty)
    }
}
