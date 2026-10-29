@testable import FeatureHistory
@testable import FeatureProgram
@testable import FeatureSettings
@testable import FeatureToday
import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S1b, G2: the app's side of the Settings screen, on the host.
/// - `AppAbout(bundle:)` read from real bundles on disk whose Info.plist lacks keys, holds blank ones or holds a
///   number where a string belongs (N6).
/// - Settings' routes beside F13's History tab: the Debug menu's route moves no stack, and no tab.
/// - A burst of changes made in Settings while its saves run reaches Today, the Program builder and History, all
///   three running at once over one set of stores, without navigating (criteria 1 and 7).
@MainActor
@Suite("Settings screen wiring, adversarial", .serialized, .timeLimit(.minutes(1)))
struct SettingsScreenWiringAdversarialTests {
    // MARK: AppAbout(bundle:)

    /// A bundle on disk whose Info.plist is `info`, read afresh (a new directory each time, so `Bundle`'s cache
    /// never hands back another test's).
    static func bundle(_ info: [String: Any]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("F14-S1b-about-\(UUID().uuidString).bundle", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist = info
        plist["CFBundleIdentifier"] = "com.example.f14-s1b.\(UUID().uuidString)"
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
    }

    static func line(_ about: AppAbout) -> String {
        SettingsPresentation.about(about, locale: Locale(identifier: "en_US"))
    }

    @Test("N6. Every key present: the display name, not the bundle name; the line reads all three")
    func about_everyKey() throws {
        let bundle = try Self.bundle([
            "CFBundleDisplayName": "Shown", "CFBundleName": "Internal",
            "CFBundleShortVersionString": "0.15.0", "CFBundleVersion": "1"
        ])
        let about = AppAbout(bundle: bundle)
        #expect(about == AppAbout(name: "Shown", version: "0.15.0", build: "1"))
        #expect(Self.line(about) == "Shown 0.15.0 · build 1")
    }

    @Test("N6. No display name: the bundle name; no keys at all: \"Version unknown\"")
    func about_missingKeys() throws {
        let named = try AppAbout(bundle: Self.bundle(["CFBundleName": "Internal", "CFBundleVersion": "7"]))
        #expect(named == AppAbout(name: "Internal", version: nil, build: "7"))
        #expect(Self.line(named) == "Internal · build 7")
        let bare = try AppAbout(bundle: Self.bundle([:]))
        #expect(bare.version == nil && bare.build == nil)
        #expect(Self.line(bare).hasSuffix("Version unknown"))
    }

    @Test("N6. A number where Info.plist should hold a string is no value, never a crash or \"74\" typed as text")
    func about_nonStringValues() throws {
        let about = try AppAbout(bundle: Self.bundle([
            "CFBundleName": "Internal", "CFBundleShortVersionString": 15, "CFBundleVersion": 74
        ]))
        #expect(about == AppAbout(name: "Internal", version: nil, build: nil))
        #expect(Self.line(about) == "Internal · Version unknown")
    }

    /// F14-S1b-1. `value("CFBundleDisplayName") ?? value("CFBundleName")` takes a blank display name as the name,
    /// so the bundle name is never read; the presentation then trims the blank away and the About line loses the
    /// app's name ("Version 0.15.0 · build 1"). The app's Info.plist sets `CFBundleDisplayName` from
    /// `$(PRODUCT_DISPLAY_NAME)` (Config/Ledger.xcconfig), which is blank in any configuration that does not define
    /// it.
    @Test(
        "F14-S1b-1. A blank or spaces-only display name falls back to the bundle name",
        arguments: ["", "   ", "\n"]
    )
    func about_blankDisplayName_fallsBackToTheBundleName(_ blank: String) throws {
        let about = try AppAbout(bundle: Self.bundle([
            "CFBundleDisplayName": blank, "CFBundleName": "Internal",
            "CFBundleShortVersionString": "0.15.0", "CFBundleVersion": "1"
        ]))
        #expect(about.name == "Internal")
        #expect(Self.line(about) == "Internal 0.15.0 · build 1")
    }

    // MARK: Routes beside History

    @Test("N7. Diagnostics from Settings on Today leaves History's stack, its workout and the selected tab alone")
    func debugMenu_leavesHistoryAlone() {
        let router = AppRouter()
        let workout = WorkoutID(Fixtures.uuid(4242))
        router.selectedTab = .history
        router.resolve(HistoryRoute.workout(workout))
        let history = router[path: .history]
        #expect(history == [.workout(workout)])
        router.selectedTab = .today
        router.open(.settings, in: .today)
        var raised = 0
        router.resolve(SettingsRoute.debugMenu) { raised += 1 }
        router.resolve(SettingsRoute.debugMenu) { raised += 1 }
        #expect(raised == 2, "each route the store hands on raises the sheet; the store drops a double tap")
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.settings])
        #expect(router[path: .history] == history)
    }

    // MARK: Reach (the scene and its readers are in the extension below)

    @Test("Criteria 1, 7. A burst made while saves run reaches Today, Program and History, all up at once")
    func burst_reachesEveryScreen_live() async throws {
        let scene = try Scene()
        let tasks = [
            Task { await scene.settings.run() },
            Task { await scene.today.run() },
            Task { await scene.program.run() },
            Task { await scene.program.save() },
            Task { await scene.history.run() }
        ]
        defer { tasks.forEach { $0.cancel() } }
        await until {
            scene.settings.model != nil && Self.todayCaption(scene.today) != nil
                && Self.programFirstWeekday(scene.program) != nil && Self.historyMeta(scene.history) != nil
        }
        #expect(Self.historyMeta(scene.history)?.hasSuffix(" lb") == true)
        // Each change lands while the one before is being saved: the saves fold, the last value wins.
        scene.settings.send(.setUnits(.kg))
        scene.settings.send(.setWeekStart(.sunday))
        await Task.yield()
        scene.settings.send(.setUnits(.lb))
        scene.settings.send(.setWeekStart(.wednesday))
        await Task.yield()
        scene.settings.send(.setUnits(.kg))
        await until { scene.settings.pending == nil }
        let stored = try await scene.memory.settings.load()
        #expect(stored.units == .kg && stored.weekStart == .wednesday)
        await until { Self.todayCaption(scene.today) == "kg moved" }
        await until { Self.programFirstWeekday(scene.program) == .wednesday }
        await until { Self.historyMeta(scene.history)?.hasSuffix(" kg") == true }
        // Wednesday 2026-09-16 (`Fixtures.now`) starts its own week from Wednesday.
        await until { Self.todayFirstDate(scene.today) == "16" }
        #expect(scene.settings.shown == stored, "Settings shows what the others were handed")
    }
}

extension SettingsScreenWiringAdversarialTests {
    /// The seed program, the catalog, one finished workout this week and the settings in pounds, behind Settings,
    /// Today, the Program builder and History.
    struct Scene {
        let memory: InMemoryStores
        let settings: SettingsStore
        let today: TodayStore
        let program: ProgramStore
        let history: HistoryStore

        init() throws {
            let seed = try Fixtures.seedProgram()
            let bench = WorkoutRepositoryContract.exercises[0]
            let workout = Seeders.workout(
                number: 1,
                endedAt: Fixtures.date(2026, 9, 15, hour: 8),
                minutes: 58,
                [.straight(bench, sets: 3, reps: 5, pounds: 185)]
            )
            var stores: InMemoryStores?
            let made = try withTestDependencies {
                stores = try $0.inMemoryStores(seed: InMemoryStores.Seed(
                    catalog: ExerciseCatalog.seed(),
                    programs: [seed],
                    workouts: [workout],
                    settings: Fixtures.settingsLb
                ))
                $0.workoutSession = FakeWorkoutSessionClient()
                $0.uuid = .incrementing
            } operation: {
                (
                    SettingsStore(about: AppAbout(name: nil, version: nil, build: nil)),
                    TodayStore(),
                    ProgramStore(),
                    HistoryStore()
                )
            }
            memory = try #require(stores)
            (settings, today, program, history) = made
        }
    }

    static func todayCaption(_ store: TodayStore) -> String? {
        guard case let .loaded(model) = store.state else {
            return nil
        }
        return model.stats.volume.caption
    }

    static func todayFirstDate(_ store: TodayStore) -> String? {
        guard case let .loaded(model) = store.state else {
            return nil
        }
        return model.weekStrip.first?.date
    }

    static func programFirstWeekday(_ store: ProgramStore) -> Weekday? {
        guard case let .loaded(model) = store.state else {
            return nil
        }
        return model.week.cells.first?.weekday
    }

    static func historyMeta(_ store: HistoryStore) -> String? {
        guard case let .loaded(model) = store.state, case let .weeks(weeks) = model.content else {
            return nil
        }
        return weeks.first?.rows.first?.meta
    }
}
