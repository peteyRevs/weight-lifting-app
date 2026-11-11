import Dependencies
@testable import FeatureOnboarding
@testable import FeatureSettings
import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import Testing

/// F14 S3, criterion 6.4 and C23, over the real launch: a composition on a database file in a temporary directory,
/// Settings' own store erasing through the keys the composition binds, and the gate the root's task runs. The app comes
/// back as a new install does after its first launch: onboarding, over the bundled catalog, the settings it was given
/// and this device's id; and finishing onboarding again shows a program and no history.
@MainActor
@Suite("Delete all data over the launch", .serialized, .timeLimit(.minutes(1)))
struct DeleteAllGateTests {
    /// This device's id, as the database at `harness`'s file gives it when it is opened again.
    static func deviceID(reopening harness: Harness) throws -> DeviceID {
        try LedgerStores.open(at: harness.databaseURL, kind: .phone, now: { Fixtures.now }, newID: { UUID() }).deviceID
    }

    @Test("Criterion 6.4. Confirmed in Settings, the erase turns the gate to onboarding; onboarding then starts afresh")
    func erase_showsOnboarding_andOnboardingStartsAfresh() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let (composition, gate) = try await harness.bootedWithAProgram()
        let stores = try #require(composition.stores)
        try await stores.exercises.save(DataResetContract.custom)
        try await stores.workouts.materialize(DataResetContract.workout(1), slotUpdates: [])
        let follow = Task { await gate.follow(composition, in: .active) }
        defer { follow.cancel() }
        #expect(await gate.answer() == .main)

        let store = withTestDependencies { composition.bind(&$0) } operation: {
            SettingsStore(about: AppAbout(name: nil, version: nil, build: nil))
        }
        let run = Task { await store.run() }
        defer { run.cancel() }
        await until { store.model != nil }
        store.send(.deleteAll)
        store.send(.continueDeleteAll)
        store.send(.setDeleteText("DELETE"))
        store.send(.confirmDeleteAll)

        #expect(await gate.change(from: .main) == .onboarding)
        await until { store.deleteAll == nil }
        #expect(try await stores.workouts.recent(limit: 10).isEmpty)
        #expect(try await stores.exercises.exercise(id: DataResetContract.custom.id) == nil)
        #expect(try await stores.exercises.all().count == ExerciseCatalog.seed().count)
        let regional = try await stores.settings.load()
            == Settings.regional(locale: Fixtures.locale, calendar: Fixtures.calendar)
        #expect(regional, "the settings a new US install starts from")
        #expect(try Self.deviceID(reopening: harness) == stores.deviceID, "this device keeps its id")

        await withTestDependencies { composition.bind(&$0) } operation: {
            let onboarding = OnboardingStore()
            onboarding.send(.skipSetup)
            await onboarding.save(prepareRetry: {})
        }
        #expect(await gate.change(from: .onboarding) == .main)
        #expect(try await stores.workouts.recent(limit: 10).isEmpty, "Today starts with no history")
    }
}
