import Foundation

/// Rest between sets: 30…300 s in 15 s steps (rule 3).
///
/// Encodes as a bare number of seconds; decoding re-validates.
public struct RestDuration: Hashable, Codable, Sendable, Comparable {
    public let seconds: Int

    /// Rule 3: `nil` unless `seconds` is in 30…300 and a multiple of 15.
    public init?(seconds: Int) {
        guard (30 ... 300).contains(seconds), seconds.isMultiple(of: 15) else {
            return nil
        }
        self.seconds = seconds
    }

    private init(validSeconds: Int) {
        seconds = validSeconds
    }

    /// Rule 3: the default rest for new slots and for Settings (90 s).
    public static let defaultRest = RestDuration(validSeconds: 90)

    /// Rule 39 (`restLbl`): "{s}s" under 60 s, "{m} min" on whole minutes, "m:ss" otherwise.
    /// 45 → "45s", 120 → "2 min", 90 → "1:30", 150 → "2:30".
    public var label: String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "\(minutes) min"
        }
        // 15 s steps leave a remainder of 15, 30 or 45: always two digits.
        return "\(minutes):\(remainder)"
    }

    /// The rest as a `Duration`, for `RestTimer`.
    public var duration: Duration {
        .seconds(seconds)
    }

    public static func < (lhs: RestDuration, rhs: RestDuration) -> Bool {
        lhs.seconds < rhs.seconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        guard let rest = RestDuration(seconds: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Rest must be 30…300 s by 15, got \(raw)"
            )
        }
        self = rest
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }
}
