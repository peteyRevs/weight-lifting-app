#if DEBUG
    import Foundation
    import LedgerDomain

    /// `DataReset` over `InMemoryStores`, keeping `DataResetContract` (LedgerTestSupport) as `GRDBDataReset` does:
    /// every store emptied, soft-deleted entries and the event log included, the catalog seeded afresh and the settings
    /// stored.
    ///
    /// **All or nothing**, as the database's one transaction: everything that can refuse is checked first, the catalog
    /// read, the settings round-tripped through `SettingsCodec` as a save is, and every catalog entry checked at the
    /// exercise store's boundary as part of its own reset, which runs first and changes nothing when it throws. The
    /// resets after it cannot fail. Unlike the database, the stores are reset one after another, each under its own
    /// lock, so an observer may hear one store emptied before the next; a test reads the state once the call returns.
    public struct InMemoryDataReset: DataReset {
        private let stores: InMemoryStores
        private let catalog: @Sendable () throws -> [Exercise]
        private let catalogVersion: Int

        /// - Parameters:
        ///   - catalog: the exercises seeded after the erase; the bundled catalog by default.
        ///   - catalogVersion: the version `catalog` is seeded at.
        public init(
            _ stores: InMemoryStores,
            catalog: @escaping @Sendable () throws -> [Exercise] = { try ExerciseCatalog.seed() },
            catalogVersion: Int = ExerciseCatalog.version
        ) {
            self.stores = stores
            self.catalog = catalog
            self.catalogVersion = catalogVersion
        }

        public func eraseAll(restoring settings: Settings) async throws {
            let exercises = try catalog()
            let restored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
            try stores.exercises.reset(catalog: exercises, version: catalogVersion)
            stores.workouts.reset()
            stores.programs.reset()
            stores.events.reset()
            stores.settings.reset(to: restored)
        }
    }
#endif
