import Foundation
import LedgerDomain
import Testing

/// F10 S1 adversarial round 1, criterion 8: `ClockText.elapsed(_:)`, the one elapsed-time formatter
/// for Today's Resume button, the workout header and the receipt. Expected texts are written out by hand
/// from the criterion (m:ss under an hour, h:mm:ss from sixty minutes, whole seconds rounded down, a negative
/// duration "0:00"); the property test's come from integer arithmetic done here.
@Suite("Adversarial F10 S1 · ClockText", .tags(.domain))
struct ClockTextAdversarialTests {
    /// A duration and the text criterion 8 gives it.
    struct Row: Sendable, CustomStringConvertible {
        let duration: Duration
        let text: String
        let description: String

        init(_ description: String, _ duration: Duration, _ text: String) {
            self.description = description
            self.duration = duration
            self.text = text
        }
    }

    static let attosecond = Duration(attoseconds: 1)
    /// U+0030 to U+003A: the ASCII digits and the colon, whatever the device's locale.
    static let digitsAndColon: ClosedRange<Unicode.Scalar> = "0" ... ":"

    static let boundaries: [Row] = [
        Row("zero", .zero, "0:00"),
        Row("one second", .seconds(1), "0:01"),
        Row("nine seconds", .seconds(9), "0:09"),
        Row("59 s", .seconds(59), "0:59"),
        Row("60 s", .seconds(60), "1:00"),
        Row("61 s", .seconds(61), "1:01"),
        Row("9:59", .seconds(599), "9:59"),
        Row("ten minutes", .seconds(600), "10:00"),
        Row("the brief's 24:22", .seconds(1462), "24:22"),
        Row("59:59", .seconds(3599), "59:59"),
        Row("exactly one hour", .seconds(3600), "1:00:00"),
        Row("an hour and a second", .seconds(3601), "1:00:01"),
        Row("an hour and 59 s", .seconds(3659), "1:00:59"),
        Row("the brief's 1:01:05", .seconds(3665), "1:01:05"),
        Row("an hour and nine minutes", .seconds(4140), "1:09:00"),
        Row("9:59:59", .seconds(35999), "9:59:59"),
        Row("ten hours", .seconds(36000), "10:00:00"),
        Row("a day less a second", .seconds(86399), "23:59:59"),
        Row("a day", .seconds(86400), "24:00:00"),
        Row("99:59:59", .seconds(359_999), "99:59:59"),
        Row("a hundred hours", .seconds(360_000), "100:00:00")
    ]

    static let fractions: [Row] = [
        Row("an attosecond", attosecond, "0:00"),
        Row("half a second", .milliseconds(500), "0:00"),
        Row("999 ms", .milliseconds(999), "0:00"),
        Row("a second less an attosecond", .seconds(1) - attosecond, "0:00"),
        Row("a second and an attosecond", .seconds(1) + attosecond, "0:01"),
        Row("1.999 s", .milliseconds(1999), "0:01"),
        Row("59.999 s", .milliseconds(59999), "0:59"),
        Row("a minute less an attosecond", .seconds(60) - attosecond, "0:59"),
        Row("an hour less an attosecond", .seconds(3600) - attosecond, "59:59"),
        Row("an hour and half a second", .seconds(3600) + .milliseconds(500), "1:00:00"),
        Row("a floating 0.9999999 s", .seconds(0.9999999), "0:00"),
        Row("a floating 3599.5 s", .seconds(3599.5), "59:59")
    ]

    static let negatives: [Row] = [
        Row("minus an attosecond", .zero - attosecond, "0:00"),
        Row("minus half a second", .milliseconds(-500), "0:00"),
        Row("minus a second", .seconds(-1), "0:00"),
        Row("minus 59 s", .seconds(-59), "0:00"),
        Row("minus an hour", .seconds(-3600), "0:00"),
        Row("minus a day and a bit", .seconds(-86461), "0:00"),
        Row("the most negative seconds", Duration(secondsComponent: .min, attosecondsComponent: 0), "0:00"),
        Row("the most negative duration", Duration(attoseconds: .min), "0:00")
    ]

    /// Computed by hand (Python integers): 2^63 − 1 s is 2,562,047,788,015,215 h 30 min 7 s, and the
    /// largest `Duration`, 2^127 − 1 as, is 170,141,183,460,469,231,731 s = 47,261,439,850,130,342 h 8 min 51 s.
    static let extremes: [Row] = [
        Row(
            "the most seconds a component holds",
            Duration(secondsComponent: .max, attosecondsComponent: 0),
            "2562047788015215:30:07"
        ),
        Row(
            "the most seconds and all but an attosecond",
            Duration(secondsComponent: .max, attosecondsComponent: 999_999_999_999_999_999),
            "2562047788015215:30:07"
        ),
        Row("2^63 s, where elapsed(at:) saturates", .seconds(Double(Int64.max)), "2562047788015215:30:08"),
        Row("the largest duration", Duration(attoseconds: .max), "47261439850130342:08:51")
    ]

    @Test("Criterion 8: m:ss under an hour, h:mm:ss from sixty minutes", arguments: boundaries)
    func elapsed_atEachBoundary(_ row: Row) {
        #expect(ClockText.elapsed(row.duration) == row.text)
    }

    @Test("Criterion 8: whole seconds, rounded down, on both sides of a second", arguments: fractions)
    func elapsed_roundsDownToWholeSeconds(_ row: Row) {
        #expect(ClockText.elapsed(row.duration) == row.text)
    }

    @Test("Criterion 8: a negative duration reads 0:00, however small or large", arguments: negatives)
    func elapsed_negative_readsZero(_ row: Row) {
        #expect(ClockText.elapsed(row.duration) == row.text)
    }

    @Test("No duration traps: the extremes print like any other value", arguments: extremes)
    func elapsed_extremes_printWithoutTrapping(_ row: Row) {
        #expect(ClockText.elapsed(row.duration) == row.text)
    }

    @Test("Every whole second up to 30 hours formats as integer arithmetic says, in ASCII digits and colons")
    func elapsed_everySecondOfThirtyHours_matchesIntegerArithmetic() {
        var wrong: [String] = []
        for seconds in 0 ..< 30 * 3600 {
            let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
            let pad = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
            let expected = hours == 0 ? "\(minutes):\(pad(rest))" : "\(hours):\(pad(minutes)):\(pad(rest))"
            let text = ClockText.elapsed(.seconds(seconds) + .milliseconds(seconds % 1000))
            if text != expected || !text.unicodeScalars.allSatisfy(Self.digitsAndColon.contains) {
                wrong.append("\(seconds) s: \(text), expected \(expected)")
            }
        }
        #expect(wrong.isEmpty, "\(wrong.prefix(5))")
    }

    @Test(
        "Seeded durations anywhere in Int64 seconds: the text reads back to the whole seconds",
        arguments: PropertySeed.all
    )
    func elapsed_readsBackToTheWholeSeconds(seed: PropertySeed) throws {
        var generator = seed.generator
        let seconds = Int64.random(in: 0 ... .max, using: &generator) >> Int64.random(in: 0 ..< 63, using: &generator)
        let attoseconds = Int64.random(in: 0 ..< 1_000_000_000_000_000_000, using: &generator)
        let text = ClockText.elapsed(Duration(secondsComponent: seconds, attosecondsComponent: attoseconds))
        let fields: [Substring] = text.split(separator: ":", omittingEmptySubsequences: false)
        let parts = try fields.map { try #require(Int64($0)) }
        #expect(parts.count == (seconds < 3600 ? 2 : 3), "\(seed): \(text)")
        #expect(parts.dropFirst().allSatisfy { (0 ..< 60).contains($0) }, "\(seed): \(text)")
        #expect(parts.reduce(0) { $0 * 60 + $1 } == seconds, "\(seed): \(text) for \(seconds) s")
        #expect(fields.dropFirst().allSatisfy { $0.count == 2 }, "\(seed): \(text)")
    }
}
