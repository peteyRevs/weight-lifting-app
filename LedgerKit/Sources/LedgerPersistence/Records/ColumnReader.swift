import Foundation
import GRDB
import LedgerDomain
import os

/// Reads a row's columns strictly, for the records' `init(row:)`. A `NULL` in a required column, a value of
/// another kind, an unknown enum case or a malformed id throws `LedgerPersistenceError`, where GRDB's
/// accessors trap on `NULL`, truncate a `REAL` read as an integer (an `_e7g` weight of 1.5 would read as 1)
/// or read text as 0. Only damage or a later writer makes such a row (S1 fix round 2, finding 4).
struct ColumnReader {
    let row: Row
    let table: String

    /// Text: a `TEXT` value, or a `BLOB` holding UTF-8.
    func text(_ column: String) throws(LedgerPersistenceError) -> String {
        guard let text = String.fromDatabaseValue(row[column]) else {
            throw malformed(column)
        }
        return text
    }

    /// An integer: only an `INTEGER` value that `Value` holds (on arm64_32, `Int` is 32 bits).
    func integer<Value: FixedWidthInteger>(_ column: String) throws(LedgerPersistenceError) -> Value {
        let stored: DatabaseValue = row[column]
        guard case let .int64(integer) = stored.storage, let value = Value(exactly: integer) else {
            throw malformed(column)
        }
        return value
    }

    func optionalInteger<Value: FixedWidthInteger>(_ column: String) throws(LedgerPersistenceError) -> Value? {
        isNull(column) ? nil : try integer(column)
    }

    /// A 0-or-1 flag stored as an `INTEGER`; any integer but 0 reads as true, as SQLite reads it.
    func flag(_ column: String) throws(LedgerPersistenceError) -> Bool {
        try integer(column) as Int64 != 0
    }

    func identifier<ID: TypedIdentifier>(_ column: String) throws(LedgerPersistenceError) -> ID {
        try ColumnCodec.identifier(text(column))
    }

    func optionalIdentifier<ID: TypedIdentifier>(_ column: String) throws(LedgerPersistenceError) -> ID? {
        isNull(column) ? nil : try identifier(column)
    }

    /// A case stored as its raw value, e.g. `slot.progression`.
    func enumeration<Value: RawRepresentable<String>>(_ column: String) throws(LedgerPersistenceError) -> Value {
        guard let value = try Value(rawValue: text(column)) else {
            throw malformed(column)
        }
        return value
    }

    func optionalEnumeration<Value: RawRepresentable<String>>(
        _ column: String
    ) throws(LedgerPersistenceError) -> Value? {
        isNull(column) ? nil : try enumeration(column)
    }

    /// An exact weight from a nullable `_e7g` column (ADR-007).
    func weight(_ column: String) throws(LedgerPersistenceError) -> Weight? {
        try optionalInteger(column).map(Weight.init(e7g:))
    }

    /// A repetition count: an integer of at least 1.
    func reps(_ column: String) throws(LedgerPersistenceError) -> Reps {
        guard let reps = try Reps(integer(column)) else {
            throw malformed(column)
        }
        return reps
    }

    /// A history date: only a finite `REAL`, seconds since 2001 (`ColumnCodec.seconds`).
    func date(_ column: String) throws(LedgerPersistenceError) -> Date {
        let stored: DatabaseValue = row[column]
        guard case let .double(seconds) = stored.storage, seconds.isFinite else {
            throw malformed(column)
        }
        return ColumnCodec.date(seconds: seconds)
    }

    func optionalDate(_ column: String) throws(LedgerPersistenceError) -> Date? {
        isNull(column) ? nil : try date(column)
    }

    /// The elements of a JSON array column (`JSONArray`).
    func array<Element: Codable & Sendable>(_ column: String) throws(LedgerPersistenceError) -> [Element] {
        guard let array = JSONArray<Element>.fromDatabaseValue(row[column]) else {
            throw malformed(column)
        }
        return array.elements
    }

    func isNull(_ column: String) -> Bool {
        (row[column] as DatabaseValue).isNull
    }

    private func malformed(_ column: String) -> LedgerPersistenceError {
        .malformedColumn("\(table).\(column)")
    }
}

/// A JSON array column (`exercise.secondary_muscles`, `exercise.curated_alternatives`). GRDB stores a
/// `Codable` value that needs JSON as JSON text, and reads it back as `nil` when the column holds anything
/// else, e.g. a muscle group a later version added (`ColumnReader.array` then throws `malformedColumn`).
struct JSONArray<Element: Codable & Sendable>: Codable, DatabaseValueConvertible, Sendable {
    let elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    init(from decoder: any Decoder) throws {
        elements = try [Element](from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try elements.encode(to: encoder)
    }
}

extension Row {
    /// What `read` makes of this row, or `nil` when this app cannot read it (a case a later version added, or
    /// damage). For lists: the row is logged by its id, left out, and stays stored, so one bad row never
    /// hides the rest (S1's event rows, S2's exercises).
    ///
    /// The row must have an `id` column, which names it in the log.
    func readable<Value>(as table: String, _ read: (Row) throws -> Value) -> Value? {
        do {
            return try read(self)
        } catch {
            let id = String.fromDatabaseValue(self["id"]) ?? "?"
            Logger.persistence.error(
                "Left out \(table, privacy: .public) row \(id, privacy: .public), which is unreadable: \(error)"
            )
            return nil
        }
    }
}
