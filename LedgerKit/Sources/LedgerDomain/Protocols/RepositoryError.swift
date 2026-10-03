import Foundation

/// Why a repository refused to store or read a value (engineering-standards §8): the errors the protocols in
/// `Repositories.swift` promise by name, so every implementation throws the same ones. LedgerPersistence's GRDB
/// repositories throw them as `LedgerPersistenceError`, a typealias kept for its call sites, and LedgerFakes'
/// in-memory stores throw them too (ADR-008: declared here, beside the protocols, so the fakes need no
/// LedgerPersistence).
///
/// Other errors reach callers unwrapped, and nothing is swallowed: an implementation's own (LedgerPersistence:
/// GRDB's `DatabaseError` from SQLite itself, e.g. a locked or full disk, or a foreign key: a slot naming an
/// exercise the database lacks), `EncodingError` (an envelope with a NaN `Weight`, which has no exact text),
/// `DecodingError` (a settings payload whose JSON holds an invalid value), `EngineError.conflictingEnvelope` from
/// `append`, `SlotValidationError` and `ProgramValidationError` (a program that fails its `init`s, when saved or
/// when read back), and `CancellationError`.
public enum RepositoryError: Error, Equatable, Sendable {
    /// ADR-007: a weight, or a volume in gram·reps, that is not a whole number of 10⁻⁷ g or lies beyond
    /// `Int64` (±922,337 t). The storage boundary rejects it rather than round it.
    case inexactWeight(Decimal)
    /// A date column holds a finite count of seconds; ±∞ and NaN have no column value.
    case nonFiniteDate
    /// A stored identifier that is not a UUID string.
    case malformedIdentifier(String)
    /// A stored JSON payload in a version this app version does not know: a later one wrote it.
    case unknownPayloadVersion(Int)
    /// A column that holds the wrong kind of value, e.g. a payload version stored as text or a payload
    /// that is not UTF-8 (`"table.column"`). Only damage or a foreign writer makes one.
    case malformedColumn(String)
    /// Two values to be saved in one table share an id (`"table id"`), e.g. a slot copied without a new id:
    /// both would land in one row, and one would be lost. Also a week, day or slot id that another program
    /// holds, live or deleted: saving it would move that row out of the other program. The same for a workout's
    /// exercise and set ids, and for a personal record that names another workout than the one it is stored
    /// with (`"personal_record of workout id"`): it would replace that workout's record.
    case duplicateIdentifier(String)
    /// A text value to be saved holds U+0000 (`"table.column"`). SQLite would keep the text only up to it, so
    /// it is refused rather than stored cut short.
    case nulInText(String)
    /// No live row has this id (`"table id"`): `setActive` named a program that is not saved, or deleted, or
    /// `updateSets` an exercise of no stored workout.
    case missingRow(String)
    /// `materialize` was given a workout that is not finished (`"workout id"`): its phase is not `.finished`, or
    /// it has no `endedAt`. History holds finished workouts only, so nothing is stored.
    case notFinished(String)
}
