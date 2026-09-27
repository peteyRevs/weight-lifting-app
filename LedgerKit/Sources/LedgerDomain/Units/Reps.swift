import Foundation

/// A repetition count, always ≥ 1 (rule 2: reps step 1, minimum 1).
///
/// Encodes as a bare integer; decoding re-validates, so a stored `0` fails loudly.
public struct Reps: Hashable, Codable, Sendable, Comparable {
    public let value: Int

    /// Rule 2: `nil` when `value < 1`.
    public init?(_ value: Int) {
        guard value >= 1 else {
            return nil
        }
        self.value = value
    }

    /// Rule 2 stepper semantics: values below 1 become 1.
    public init(clamping value: Int) {
        self.value = max(1, value)
    }

    public static let one = Reps(clamping: 1)

    public static func < (lhs: Reps, rhs: Reps) -> Bool {
        lhs.value < rhs.value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        guard let reps = Reps(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Reps must be ≥ 1, got \(raw)")
        }
        self = reps
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
