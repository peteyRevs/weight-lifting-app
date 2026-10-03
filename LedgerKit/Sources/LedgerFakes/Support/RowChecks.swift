#if DEBUG
    import Foundation
    import LedgerDomain

    /// The row checks every in-memory store makes before it keeps a value, with the GRDB stores' errors and
    /// payloads (`"table id"`, `"table.column"`). Weights and dates go through `StorageBoundary`, the rule the
    /// database's columns share.
    enum RowChecks {
        /// Throws `duplicateIdentifier` for the first id used twice.
        static func refuseRepeats(_ ids: [some TypedIdentifier], _ table: String) throws(RepositoryError) {
            var seen = Set<UUID>()
            if let repeated = ids.first(where: { !seen.insert($0.rawValue).inserted }) {
                throw .duplicateIdentifier("\(table) \(repeated.rawValue.uuidString)")
            }
        }

        /// Throws `nulInText` when `text` holds U+0000, which SQLite would cut the text short at.
        static func refuseNul(_ text: String, _ column: String) throws(RepositoryError) {
            if text.unicodeScalars.contains("\0") {
                throw .nulInText(column)
            }
        }
    }
#endif
