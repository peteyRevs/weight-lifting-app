import Foundation
@testable import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// The live values the composition root has not bound yet: each store stub throws
/// `LedgerDependencyError.unimplemented` naming its key from every method, and its `observe…()` ends at once.
@Suite("Unimplemented stubs")
struct UnimplementedStubTests {
    /// Every call `calls` makes throws `unimplemented(key:)`.
    static func expectUnimplemented(
        _ key: String,
        _ calls: [@Sendable () async throws -> Void],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for call in calls {
            await #expect(throws: LedgerDependencyError.unimplemented(key: key), sourceLocation: sourceLocation) {
                try await call()
            }
        }
    }

    static func isEmpty(_ stream: AsyncStream<some Any>) async -> Bool {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() == nil
    }

    static let workout = WorkoutID(Fixtures.uuid(1))

    @Test("The exercise repository's stub throws from every method; observeAll ends at once")
    func exerciseRepository() async {
        let stub = ExerciseRepositoryKey.liveValue
        await Self.expectUnimplemented("exerciseRepository", [
            { _ = try await stub.all() },
            { _ = try await stub.exercise(id: Fixtures.CatalogID.benchPress) },
            { _ = try await stub.search("", equipment: nil, muscle: nil) },
            { try await stub.save(Fixtures.benchPress) },
            { try await stub.seedIfNeeded([], version: 1) }
        ])
        #expect(await Self.isEmpty(stub.observeAll()))
    }

    @Test("The program repository's stub throws from every method; observeActive ends at once")
    func programRepository() async {
        let stub = ProgramRepositoryKey.liveValue
        await Self.expectUnimplemented("programRepository", [
            { _ = try await stub.active() },
            { try await stub.save(Fixtures.seedProgram()) },
            { _ = try await stub.update(Fixtures.programID) { $0 } },
            { try await stub.setActive(Fixtures.programID) },
            { try await stub.delete(Fixtures.programID) }
        ])
        #expect(await Self.isEmpty(stub.observeActive()))
    }

    @Test("The workout repository's stub throws from every method; observeRecent ends at once")
    func workoutRepository() async throws {
        let stub = WorkoutRepositoryKey.liveValue
        let session = try Fixtures.seedSession()
        await Self.expectUnimplemented("workoutRepository", [
            { try await stub.materialize(session, slotUpdates: []) },
            { _ = try await stub.workout(id: Self.workout) },
            { _ = try await stub.recent(limit: 1) },
            { _ = try await stub.workouts(in: .distantPast ..< .distantFuture) },
            { try await stub.updateSets(workoutExerciseID: session.exercises[0].id, sets: []) },
            { try await stub.delete(id: Self.workout) }
        ])
        #expect(await Self.isEmpty(stub.observeRecent(limit: 1)))
    }

    @Test("The settings repository's stub throws from every method; observe ends at once")
    func settingsRepository() async {
        let stub = SettingsRepositoryKey.liveValue
        await Self.expectUnimplemented("settingsRepository", [
            { _ = try await stub.load() },
            { try await stub.save(.default) }
        ])
        #expect(await Self.isEmpty(stub.observe()))
    }

    @Test("The event store's stub throws from every method")
    func workoutEventStore() async {
        let stub = WorkoutEventStoreKey.liveValue
        await Self.expectUnimplemented("workoutEventStore", [
            { _ = try await stub.append([]) },
            { _ = try await stub.envelopes(for: Self.workout) },
            { _ = try await stub.unreadableCount(for: Self.workout) },
            { _ = try await stub.highestSeq(for: Self.workout, device: Fixtures.deviceID) },
            { _ = try await stub.uncompactedWorkoutIDs() },
            { _ = try await stub.newestWallClock() },
            { try await stub.compact(workout: Self.workout) }
        ])
    }

    @Test("The stats queries' stub throws from every query; its two observations end at once")
    func statsQueries() async throws {
        let stub = StatsQueriesKey.liveValue
        let bench = Fixtures.CatalogID.benchPress
        let program = try Fixtures.seedProgram()
        let calendar = WeekCalendar(startDate: program.startDate, weekStart: .monday, calendar: Fixtures.calendar)
        let session = try Fixtures.seedSession()
        let all = Date.distantPast ..< Date.distantFuture
        await Self.expectUnimplemented("statsQueries", [
            { _ = try await stub.lastPerformance(exerciseID: bench) },
            { _ = try await stub.bestSet(exerciseID: bench) },
            { _ = try await stub.bestSets() },
            { _ = try await stub.exerciseSessions(exerciseID: bench) },
            { _ = try await stub.bestE1RM(exerciseID: bench) },
            { _ = try await stub.e1RMByWeek(exerciseID: bench, lastWeeks: 8, calendar: calendar) },
            { _ = try await stub.weeklyVolume(in: all) },
            { _ = try await stub.sessionsCompleted(in: all) },
            { _ = try await stub.sessionCount(exerciseID: bench) },
            { _ = try await stub.personalRecords(exerciseID: bench) },
            { _ = try await stub.bests(before: session, for: [bench]) },
            { _ = try await stub.recentlyLogged(limit: 3) }
        ])
        #expect(await Self.isEmpty(stub.observeExerciseSessions(exerciseID: bench)))
        #expect(await Self.isEmpty(stub.observeLibraryStats(recentLimit: 5)))
    }

    @Test(
        "The workout session's stub throws from every method; updates ends at once (F10 S1 criterion 6)",
        .timeLimit(.minutes(1))
    )
    func workoutSession() async throws {
        let stub = WorkoutSessionKey.liveValue
        let session = try Fixtures.seedSession()
        #expect(stub is UnimplementedWorkoutSession)
        await Self.expectUnimplemented("workoutSession", [
            { _ = try await stub.current() },
            { try await stub.start(session) },
            { try await stub.apply(.restSkipped) },
            { _ = try await stub.finish(endedAt: Fixtures.now) },
            { try await stub.discard(endedAt: Fixtures.now) }
        ])
        #expect(await Self.isEmpty(stub.updates()))
    }

    @Test("Until the composition root binds it, the live device id is the nil UUID, which no device row holds")
    func deviceID_liveValue_isTheNilUUID() {
        #expect(DeviceIDKey.liveValue.rawValue == UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    @Test("The device keys' live values are their stubs, and the logger's logs under the app's subsystem")
    func deviceKeys_liveValues() {
        #expect(HealthStoreKey.liveValue is UnimplementedHealthStore)
        #expect(LiveWorkoutTransportKey.liveValue is UnimplementedLiveWorkoutTransport)
        #expect(CompanionTransportKey.liveValue is UnimplementedCompanionTransport)
        #expect(HapticsKey.liveValue is UnimplementedHaptics)
        #expect(NotificationsKey.liveValue is UnimplementedNotifications)
        #expect(LiveActivitiesKey.liveValue is UnimplementedLiveActivities)
        #expect(LoggerKey.liveValue.isEnabled)
        #expect(LedgerLogger.subsystem == "com.petearevalo.Ledger")
    }
}
