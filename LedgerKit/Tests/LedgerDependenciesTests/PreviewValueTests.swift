import Dependencies
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// What a `#Preview` reads (F07 criterion 8's data half): every key's `previewValue` is a fake, the stores seeded
/// with the bundled catalog, the spec's seed program and its history up to `Fixtures.now`.
@Suite("Preview values")
struct PreviewValueTests {
    @Test("In a preview the stores hold the catalog, the seed program, its history and the default settings")
    func previewStores_areSeeded() async throws {
        try await withDependencies {
            $0.context = .preview
        } operation: {
            @Dependency(\.exerciseRepository) var exercises
            @Dependency(\.programRepository) var programs
            @Dependency(\.workoutRepository) var workouts
            @Dependency(\.statsQueries) var stats
            @Dependency(\.settingsRepository) var settings
            @Dependency(\.workoutEventStore) var events
            let (catalog, program, history) = try (
                ExerciseCatalog.seed(),
                Fixtures.seedProgram(),
                Fixtures.history(weeks: 8)
            )
            #expect(try await exercises.all().count == catalog.count)
            #expect(try await programs.active() == program)
            #expect(try await workouts.recent(limit: 100) == history.reversed())
            #expect(try await stats.sessionCount(exerciseID: Fixtures.CatalogID.benchPress) == 8)
            #expect(try await settings.load() == Fixtures.settingsLb)
            #expect(try await events.uncompactedWorkoutIDs().isEmpty)
        }
    }

    @Test("In a preview the device keys are fakes and the device id is the fixtures'")
    func previewDevices_areFakes() {
        withDependencies {
            $0.context = .preview
        } operation: {
            @Dependency(\.healthStore) var health
            @Dependency(\.liveWorkoutTransport) var live
            @Dependency(\.companionTransport) var companion
            @Dependency(\.haptics) var haptics
            @Dependency(\.notifications) var notifications
            @Dependency(\.liveActivities) var activities
            @Dependency(\.deviceID) var deviceID
            #expect(health is FakeHealthStore)
            #expect(live is FakeLiveWorkoutTransport)
            #expect(companion is FakeCompanionTransport)
            #expect(haptics is FakeHaptics)
            #expect(notifications is FakeNotifications)
            #expect(activities is FakeLiveActivities)
            #expect(deviceID == Fixtures.deviceID)
        }
    }
}
