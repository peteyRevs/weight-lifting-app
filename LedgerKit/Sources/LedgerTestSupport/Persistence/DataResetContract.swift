import Foundation
import LedgerDomain

/// The stores a `DataResetContract` clause runs against, all over one fresh, empty store, and the erase over them.
/// `makeReset` builds that erase seeding the catalog it is given, read when the erase begins; `reset` seeds the bundled
/// one.
public struct DataResetStores: Sendable {
    public let makeReset: @Sendable (@escaping @Sendable () throws -> [Exercise]) -> any DataReset
    public let exercises: any ExerciseRepository
    public let programs: any ProgramRepository
    public let workouts: any WorkoutRepository
    public let events: any WorkoutEventStore
    public let settings: any SettingsRepository

    public init(
        makeReset: @escaping @Sendable (@escaping @Sendable () throws -> [Exercise]) -> any DataReset,
        exercises: any ExerciseRepository,
        programs: any ProgramRepository,
        workouts: any WorkoutRepository,
        events: any WorkoutEventStore,
        settings: any SettingsRepository
    ) {
        self.makeReset = makeReset
        self.exercises = exercises
        self.programs = programs
        self.workouts = workouts
        self.events = events
        self.settings = settings
    }

    /// The erase seeding the bundled catalog, as the app's does.
    public var reset: any DataReset {
        makeReset { try ExerciseCatalog.seed() }
    }
}

/// `DataReset`'s contract as named clauses (F14 S3, criterion 6, N20): over a history holding everything the lifter can
/// make (the catalog, a custom exercise, the active program, finished workouts with their records, a deleted one, a
/// live workout's log and changed settings), an erase leaves the bundled catalog, the settings it is given and nothing
/// else; the observations open across it hear the empty state; a second is harmless; and one refused for any reason
/// erases nothing. `GRDBDataReset` and `InMemoryDataReset` run the same clauses (`DataResetTests`); what only a
/// database has (its row counts, this device's row, the bytes of its file) stays with the GRDB tests.
public enum DataResetContract {
    public typealias Clause = ContractClause<DataResetStores>

    public static let clauses: [Clause] = [
        Clause("eraseAll leaves the bundled catalog, the settings given, and nothing else", erases),
        Clause("every id is free again: the erased program and workout save anew", idsFreed),
        Clause("observations open across the erase hear the empty state", observed),
        Clause("a second erase leaves what the first did", eraseTwice),
        Clause(
            "a catalog that cannot be read, or that the store refuses, and unsavable settings erase nothing",
            refused
        )
    ]

    // MARK: Fixtures

    /// A custom exercise named as nothing else is, so a scan of a database file can look for it.
    public static let custom = ExerciseRepositoryContract.custom(
        0x5E, "Zygomorphic Quokka Press", "Quokka", .barbell, .chest
    )
    /// The settings the lifter changed before erasing: every field away from the defaults.
    public static let changedSettings = SettingsRepositoryContract.custom
    /// What the erase restores: a new install's settings, as the region gives them (decision #15).
    public static var restored: Settings {
        var settings = Settings.default
        settings.weekStart = .sunday
        return settings
    }

    /// The bundled catalog with one start load no column keeps exactly (⅛ lb): an entry the store refuses, so its seed
    /// throws `inexactWeight` once the erase has begun.
    public static func refusedCatalog() throws -> [Exercise] {
        var catalog = try ExerciseCatalog.seed()
        catalog[catalog.count - 1].defaultStartLoad = [.lb: Weight.pounds(Decimal(string: "0.125") ?? 0)]
        return catalog
    }

    /// A finished workout named as nothing else is, `number` days after `EventBuilders.start`, which also keeps two
    /// apart.
    public static func workout(_ number: Int) -> WorkoutState {
        var workout = WorkoutRepositoryContract.workout(
            number: number,
            endedAt: EventBuilders.start.addingTimeInterval(Double(number) * 86400)
        )
        workout.name = "Quokka Thursday Session \(number)"
        // Heavier from one workout to the next, so each after the first holds a personal record.
        workout.exercises[0].sets[0].weight = .pounds(Decimal(185 + 10 * number))
        return workout
    }

    /// The program the history follows: four days over the bundled catalog's first exercises, active.
    public static func program() throws -> Program {
        let catalog = try ExerciseCatalog.seed()
        return try Seeders.program(weeks: 4, days: 3, slotsPerDay: 3, exercises: catalog.prefix(6).map(\.id))
    }

    /// Fills `stores` with everything the lifter can make, through the protocols, so both implementations hold the
    /// same: the bundled catalog, `custom`, `program()` (active), workouts 1 and 2 (records detected), workout 3
    /// deleted, a live workout's first envelope, and `changedSettings`.
    public static func seedHistory(_ stores: DataResetStores) async throws {
        try await stores.exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        try await stores.exercises.save(custom)
        try await stores.programs.save(program())
        for number in 1 ... 3 {
            try await stores.workouts.materialize(workout(number), slotUpdates: [])
        }
        try await stores.workouts.delete(id: workout(3).id)
        _ = try await stores.events.append(EventBuilders.log(from: [.started(EventBuilders.seedSession())]))
        try await stores.settings.save(changedSettings)
    }

    // MARK: Clauses

    static func erases(_ stores: DataResetStores) async throws -> String? {
        try await seedHistory(stores)
        try await stores.reset.eraseAll(restoring: restored)
        let after = try await Contents.read(stores)
        let customGone = try await stores.exercises.exercise(id: custom.id) == nil
        let logGone = try await stores.events.envelopes(for: EventBuilders.workoutID).isEmpty
        return try ContractCheck.first(
            after.difference(from: Contents.fresh(restored)).map { "after the erase: \($0)" },
            customGone ? nil : "the custom exercise is still stored",
            logGone ? nil : "the live workout's log is still stored"
        )
    }

    static func idsFreed(_ stores: DataResetStores) async throws -> String? {
        try await seedHistory(stores)
        try await stores.reset.eraseAll(restoring: restored)
        try await stores.programs.save(program())
        try await stores.workouts.materialize(workout(3), slotUpdates: [])
        let active = try await stores.programs.active()?.id
        let recent = try await stores.workouts.recent(limit: 100).map(\.id)
        return try ContractCheck.first(
            ContractCheck.expect(active, program().id, "the program saved again after the erase"),
            ContractCheck.expect(recent, [workout(3).id], "the workouts after materialising the deleted one again")
        )
    }

    static func observed(_ stores: DataResetStores) async throws -> String? {
        try await seedHistory(stores)
        var active = stores.programs.observeActive().makeAsyncIterator()
        var recent = stores.workouts.observeRecent(limit: 10).makeAsyncIterator()
        var settings = stores.settings.observe().makeAsyncIterator()
        let activeBefore = await active.next()
        let recentBefore = await recent.next()
        let settingsBefore = await settings.next()
        try await stores.reset.eraseAll(restoring: restored)
        let activeAfter = await active.next()
        let recentAfter = await recent.next()
        let settingsAfter = await settings.next()
        return ContractCheck.first(
            activeBefore??.id == nil ? "observeActive gave no program before the erase" : nil,
            recentBefore?.count == 2 ? nil : "observeRecent gave \(recentBefore?.count ?? -1) workouts beforehand",
            settingsBefore == changedSettings ? nil : "observe() did not give the changed settings before the erase",
            activeAfter.map { $0 == nil } == true ? nil : "observeActive did not emit nil after the erase",
            recentAfter.map(\.isEmpty) == true ? nil : "observeRecent did not emit [] after the erase",
            settingsAfter == restored ? nil : "observe() did not emit the restored settings after the erase"
        )
    }

    static func eraseTwice(_ stores: DataResetStores) async throws -> String? {
        try await seedHistory(stores)
        try await stores.reset.eraseAll(restoring: restored)
        try await stores.reset.eraseAll(restoring: restored)
        let after = try await Contents.read(stores)
        return try after.difference(from: Contents.fresh(restored)).map { "after a second erase: \($0)" }
    }

    static func refused(_ stores: DataResetStores) async throws -> String? {
        struct Unreadable: Error {}
        try await seedHistory(stores)
        let before = try await Contents.read(stores)
        var nan = restored
        nan.plateInventory[.kg] = PlateInventory(bar: Weight(grams: .nan), plates: [])
        let unreadable = await refusal {
            try await stores.makeReset { throw Unreadable() }.eraseAll(restoring: restored)
        }
        let refusedEntry = await refusal {
            try await stores.makeReset { try refusedCatalog() }.eraseAll(restoring: restored)
        }
        let unsavable = await refusal { try await stores.reset.eraseAll(restoring: nan) }
        let after = try await Contents.read(stores)
        return ContractCheck.first(
            unreadable.map { "an unreadable catalog: \($0)" },
            refusedEntry.map { "a catalog entry the store refuses: \($0)" },
            unsavable.map { "settings holding a NaN bar: \($0)" },
            after.difference(from: before).map { "after the refused erases: \($0)" }
        )
    }

    /// Nil when `erase` throws, else a line saying it did not.
    private static func refusal(_ erase: () async throws -> Void) async -> String? {
        do {
            try await erase()
            return "the erase did not throw"
        } catch {
            return nil
        }
    }
}
