import Foundation

/// "Delete all data" (F14 S3, criterion 6; ruling A1): the lifter's whole log erased in place, leaving this install as
/// a new one finds itself after its first launch. `DataResetContract` in LedgerTestSupport holds every implementation
/// to what follows; `GRDBDataReset` is the database's, `InMemoryDataReset` LedgerFakes'.
///
/// The database stays open and every store over it stays bound: an erase is not a new file (C22; product decision #29
/// forbids the launch to delete one). Every observation open over the stores hears the empty state.
public protocol DataReset: Sendable {
    /// Deletes every workout and its sets, records and health values, every program, every custom exercise, the live
    /// workout's event log and the settings, soft-deleted rows included; seeds the bundled exercise catalog
    /// (`ExerciseCatalog.seed()`) afresh; and stores `settings`, the values a new install starts from (decision #15).
    /// This device's own row (`deviceID`) stays: it holds nothing of the lifter's.
    ///
    /// All of it or nothing, in one write: the catalog is read before anything is deleted, and whatever throws
    /// afterwards, a catalog entry the store refuses among it, leaves every row as it was. A task cancelled during the
    /// call ends with all of it done or none. Apple Health is never touched: workouts saved there stay there.
    ///
    /// What follows the erase to wipe the deleted rows from the disk is the implementation's, and never undoes it.
    func eraseAll(restoring settings: Settings) async throws
}
