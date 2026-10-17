import Foundation

// Locale-independent number handling shared by every domain string.
//
// Domain strings follow the spec's own formats (§7.7: "185", "52.5", "24,180", "41.2k",
// "5 × 5 @ 185 lb · RPE 8"): '.' decimal point, ',' thousands separator, no `Locale`,
// no `NumberFormatter`. Output is byte-identical on every host regardless of its region.

extension Decimal {
    /// Rounds to `scale` fractional digits using a Swift rounding rule (via `NSDecimalRound`).
    func rounded(scale: Int, _ rule: FloatingPointRoundingRule) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, Self.decimalMode(for: rule, isNegative: self < 0))
        return result
    }

    /// Rounds to a whole number and returns it as an `Int`. A value that is not a number rounds to 0.
    ///
    /// `Decimal` gives NaN, not zero, for a quotient too small for it to hold (10⁻⁸⁸ g in thousands
    /// of a unit), and `NSDecimalNumber.intValue` of a NaN is undefined: it read as an arbitrary
    /// number that changed from launch to launch (F09 S2, finding F9-S2-1).
    func roundedToInt(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        isNaN ? 0 : NSDecimalNumber(decimal: rounded(scale: 0, rule)).intValue
    }

    /// `NSDecimalNumber.RoundingMode` only has plain / bankers / up (toward +∞) / down (toward −∞);
    /// the sign decides which of those implements `towardZero` and `awayFromZero`.
    private static func decimalMode(
        for rule: FloatingPointRoundingRule,
        isNegative: Bool
    ) -> NSDecimalNumber.RoundingMode {
        switch rule {
        case .toNearestOrAwayFromZero: .plain
        case .toNearestOrEven: .bankers
        case .up: .up
        case .down: .down
        case .towardZero: isNegative ? .up : .down
        case .awayFromZero: isNegative ? .down : .up
        @unknown default: .plain
        }
    }
}

enum NumberText {
    /// Renders `scaled / 10^fractionDigits` with a '.' decimal point. Trailing fractional zeros
    /// (and a bare '.') are dropped when `trimZeros` is true: `fixed(18500, fractionDigits: 2)`
    /// → "185", `fixed(5250, fractionDigits: 2)` → "52.5", `fixed(242, fractionDigits: 1,
    /// trimZeros: false)` → "24.2".
    static func fixed(_ scaled: Int, fractionDigits: Int, trimZeros: Bool = true, grouped: Bool = false) -> String {
        let divisor = (0 ..< fractionDigits).reduce(UInt(1)) { product, _ in product * 10 }
        let whole = Int(scaled.magnitude / divisor)
        var text = grouped ? thousands(whole) : String(whole)
        let digits = String(scaled.magnitude % divisor)
        var fraction = String(repeating: "0", count: max(0, fractionDigits - digits.count)) + digits
        if trimZeros || fractionDigits == 0 {
            while fraction.hasSuffix("0") {
                fraction.removeLast()
            }
        }
        if !fraction.isEmpty {
            text += "." + fraction
        }
        return scaled < 0 ? "-" + text : text
    }

    /// "24180" → "24,180". Negative values keep their sign in front.
    static func thousands(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start ..< end], at: 0)
            end = start
        }
        let text = groups.joined(separator: ",")
        return value < 0 ? "-" + text : text
    }
}

/// Exact decimal text for `Codable` (ADR-007): "-12.5", "83914.58845". Always '.', never an
/// exponent, never localised. Decoding accepts exactly that shape and rejects anything else
/// (NaN, "1e3", "1,5", "12abc"), so a stored value reads back bit-for-bit.
enum DecimalText {
    static func encode(_ value: Decimal) -> String {
        value.description
    }

    /// Encodes `value` as exact text; a NaN has no exact text and throws `EncodingError.invalidValue`.
    static func encode<Key: CodingKey>(
        _ value: Decimal,
        into container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        guard value.isFinite else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: container.codingPath + [key],
                debugDescription: "A non-finite decimal has no exact text"
            ))
        }
        try container.encode(encode(value), forKey: key)
    }

    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Decimal {
        let text = try container.decode(String.self, forKey: key)
        guard let value = parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected an exact decimal like \"-12.5\", got \"\(text)\""
            )
        }
        return value
    }

    /// `text` as a `Decimal` when it is an optional '-', digits, and an optional '.' plus digits,
    /// and `Decimal` holds it exactly (at most 38 significant digits): anything that would not
    /// read back digit for digit is rejected rather than silently truncated.
    static func parse(_ text: String) -> Decimal? {
        let unsigned = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let isDigits = { (part: Substring) in !part.isEmpty && part.allSatisfy { ("0" ... "9").contains($0) } }
        guard (1 ... 2).contains(parts.count), parts.allSatisfy(isDigits),
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              canonical(text) == canonical(value.description)
        else {
            return nil
        }
        return value
    }

    /// `text` without leading integer zeros or trailing fraction zeros ("-007.50" → "-7.5", "-0" → "0").
    private static func canonical(_ text: String) -> String {
        let isNegative = text.hasPrefix("-")
        let parts = (isNegative ? text.dropFirst() : Substring(text)).split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        let whole = parts.first?.drop { $0 == "0" } ?? ""
        var fraction = parts.count > 1 ? parts[1] : ""
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        let digits = (whole.isEmpty ? "0" : String(whole)) + (fraction.isEmpty ? "" : "." + fraction)
        return isNegative && digits != "0" ? "-" + digits : digits
    }
}
