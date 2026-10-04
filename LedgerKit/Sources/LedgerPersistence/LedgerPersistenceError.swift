import LedgerDomain

/// Why LedgerPersistence refused to store or read a value: `RepositoryError`, which moved to LedgerDomain beside
/// the repository protocols so LedgerFakes' in-memory stores throw the same errors without this module (ADR-008).
/// The name stays for the call sites and suites written against it.
public typealias LedgerPersistenceError = RepositoryError
