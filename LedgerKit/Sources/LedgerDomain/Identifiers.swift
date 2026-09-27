import Foundation

/// A typed identity (engineering-standards §5): never pass a bare `UUID` as an ID.
///
/// Encodes as the bare UUID string, so persisted and transmitted payloads stay flat.
/// There is deliberately no `init()` that calls `UUID()`: new IDs come from the injected
/// `@Dependency(\.uuid)` (standards §4) or, inside a built session, from `derived(from:index:)`.
public protocol TypedIdentifier: Hashable, Codable, Sendable {
    var rawValue: UUID { get }
    init(_ rawValue: UUID)
}

public extension TypedIdentifier {
    init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(UUID.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ExerciseID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct ProgramID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WeekID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct DayTemplateID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct SlotID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WorkoutID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WorkoutExerciseID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct SetID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct DeviceID: TypedIdentifier {
    public let rawValue: UUID
    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

// MARK: - Deterministic child identifiers

public extension WorkoutExerciseID {
    /// The ID of the exercise at `index` in a session built for `workout` (spec §7.3).
    /// Deterministic, so `SessionBuilder.build` needs no UUID source and replays are stable.
    static func derived(from workout: WorkoutID, index: Int) -> WorkoutExerciseID {
        WorkoutExerciseID(UUID(derivedFrom: workout.rawValue, tag: 1, index: index))
    }
}

public extension SetID {
    /// The ID of the set row at `index` of `exercise` in a built session (spec §7.3).
    static func derived(from exercise: WorkoutExerciseID, index: Int) -> SetID {
        SetID(UUID(derivedFrom: exercise.rawValue, tag: 2, index: index))
    }
}

extension UUID {
    /// A UUIDv8 (RFC 9562 §5.8, "custom") mixed from `base`, a namespace `tag` and an `index` with
    /// SplitMix64. Distinct inputs give distinct IDs with overwhelming probability, and the
    /// version nibble (8) can never equal a random v4 ID from `@Dependency(\.uuid)`.
    init(derivedFrom base: UUID, tag: UInt8, index: Int) {
        let bytes = base.uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let key = UInt64(tag) << 56 ^ UInt64(bitPattern: Int64(index))
        let first = Self.mix(high ^ Self.mix(key ^ low))
        let second = Self.mix(low ^ Self.mix(first ^ key))
        // Version 8 in the high nibble of byte 6; RFC variant (0b10) in the top bits of byte 8.
        let versioned = first & 0xFFFF_FFFF_FFFF_0FFF | 0x0000_0000_0000_8000
        let varianted = second & 0x3FFF_FFFF_FFFF_FFFF | 0x8000_0000_0000_0000
        self.init(uuid: Self.tuple(versioned, varianted))
    }

    /// SplitMix64 finaliser (Steele, Lea, Flood 2014).
    private static func mix(_ value: UInt64) -> UInt64 {
        var mixed = value &+ 0x9E37_79B9_7F4A_7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    private static func tuple(_ high: UInt64, _ low: UInt64) -> uuid_t {
        func byte(_ word: UInt64, _ index: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: word >> UInt64(56 - 8 * index))
        }
        return (
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        )
    }
}
