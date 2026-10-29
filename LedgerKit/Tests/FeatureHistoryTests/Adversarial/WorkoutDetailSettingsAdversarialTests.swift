import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S2 adversarial (G2): a past workout's detail against its settings. Units changed back and forth live redraw it
/// each time. When the settings' observation ends (GRDB's ends at once, on every run, for a settings row this app
/// can't read, such as a later version's payload, and its documentation says the features then fall back to the
/// defaults), the detail instead says the workout can't be read (F13-S2-1), and then ignores the workout's own nil, so
/// a delete elsewhere no longer closes it (F13-S2-2).
@MainActor
@Suite("Adversarial F13 S2 · the detail when the settings end", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutDetailSettingsAdversarialTests {
    static let newest = HistoryFixtures.twelve()[11]

    static func isLoaded(_ store: WorkoutDetailStore) -> Bool {
        WorkoutDetailStoreAdversarialTests.isLoaded(store)
    }

    @Test("Units changed back and forth live: each model is the presentation's in those units")
    func unitsBackAndForth_redrawEachTime() async throws {
        let scene = DetailScene(Self.newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        for (settings, units) in [
            (Fixtures.settingsKg, Units.kg),
            (Fixtures.settingsLb, .lb),
            (Fixtures.settingsKg, .kg)
        ] {
            try await scene.memory.settings.save(settings)
            let wanted = try await scene.expected(Self.newest.id, units: units)
            await eventually { (try? scene.model) == wanted }
        }
        #expect(try scene.model.receipt.records == "2 new PRs this session", "units move no record")
    }

    /// F13-S2-1: a settings row this app can't read (a later version's payload) ends `observe()` at once, on every
    /// run, and `GRDBSettingsRepository` documents that features then fall back to the defaults. The detail instead
    /// says "This workout can't be read. It stays in your history. You can still delete it." of every workout,
    /// readable or not: it blames the workout and points at Delete, which can't be undone.
    @Test("F13-S2-1: settings that can't be read do not make a readable workout 'can't be read'")
    func settingsEndAtOnce_doesNotBlameTheWorkout() async {
        let scene = GatedDetailScene(Self.newest.id, settingsEnd: .atOnce)
        let run = Task { await scene.store.run() }
        defer { run.cancel() }
        _ = await settles { scene.store.state != .loading }
        let blamesTheWorkout = scene.store.state == .unreadable(WorkoutDetailPresentation.unreadable)
        #expect(blamesTheWorkout, "as built")
        let showsTheWorkout = Self.isLoaded(scene.store)
        withKnownIssue("F13-S2-1: a settings failure is drawn as the workout's damage, with Delete offered") {
            #expect(showsTheWorkout)
        }
    }

    @Test("F13-S2-1: settings that end after their first value turn a drawn workout into 'can't be read'")
    func settingsEndAfterFirstValue_doesNotBlameTheWorkout() async {
        let scene = GatedDetailScene(Self.newest.id, settingsEnd: .afterFirstValue)
        let run = Task { await scene.store.run() }
        defer { run.cancel() }
        _ = await settles { scene.store.state == .unreadable(WorkoutDetailPresentation.unreadable) }
        let showsTheWorkout = Self.isLoaded(scene.store)
        withKnownIssue("F13-S2-1: the receipt already drawn is replaced by the workout's 'can't be read'") {
            #expect(showsTheWorkout)
        }
    }

    /// F13-S2-2: once any source has ended, `rebuild()` returns before it looks at the workout, so a nil from the
    /// workout's own observation (deleted on another tab, or by the watch's sync) never closes the detail. It keeps
    /// saying the gone workout "stays in your history".
    @Test("F13-S2-2: after the settings end, a delete elsewhere still closes the detail")
    func settingsEnded_thenDeletedElsewhere_closes() async throws {
        let scene = GatedDetailScene(Self.newest.id, settingsEnd: .atOnce)
        let run = Task { await scene.store.run() }
        defer { run.cancel() }
        _ = await settles { scene.store.state != .loading }
        try await scene.memory.workouts.delete(id: Self.newest.id)
        let closes = await settles { scene.store.state == .gone }
        withKnownIssue("F13-S2-2: a nil from the workout's observation is ignored once another source has ended") {
            #expect(closes)
            #expect(scene.store.pendingRoute?.route == .closeWorkout(Self.newest.id))
        }
    }
}
