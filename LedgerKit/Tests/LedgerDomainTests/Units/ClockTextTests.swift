import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 criterion 8: the one elapsed-time formatter of Today's Resume button, the workout header and the
/// receipt's TIME tile.
@Suite("ClockText", .tags(.domain))
struct ClockTextTests {
    struct Row: Sendable, CustomStringConvertible {
        let duration: Duration
        let text: String

        var description: String {
            "\(duration) → \(text)"
        }

        static let all: [Row] = [
            Row(duration: .zero, text: "0:00"),
            Row(duration: .seconds(5), text: "0:05"),
            Row(duration: .seconds(59), text: "0:59"),
            Row(duration: .seconds(60), text: "1:00"),
            Row(duration: .seconds(605), text: "10:05"),
            Row(duration: .seconds(24 * 60 + 22), text: "24:22"),
            Row(duration: .seconds(59 * 60 + 59), text: "59:59"),
            // From sixty minutes on, hours lead: the prototype's "61:05" reads "1:01:05".
            Row(duration: .seconds(60 * 60), text: "1:00:00"),
            Row(duration: .seconds(61 * 60 + 5), text: "1:01:05"),
            Row(duration: .seconds(10 * 3600 + 9 * 60 + 8), text: "10:09:08"),
            Row(duration: .seconds(100 * 3600), text: "100:00:00"),
            // Whole seconds, rounded down: the text changes when the second has passed.
            Row(duration: .milliseconds(999), text: "0:00"),
            Row(duration: .milliseconds(59999), text: "0:59"),
            Row(duration: .seconds(3599.9), text: "59:59"),
            // A negative duration reads zero, however small or large.
            Row(duration: .milliseconds(-1), text: "0:00"),
            Row(duration: .seconds(-75), text: "0:00"),
            Row(duration: .seconds(-7200), text: "0:00")
        ]
    }

    @Test("m:ss under an hour, h:mm:ss from sixty minutes, 0:00 for a negative duration", arguments: Row.all)
    func minutesSeconds_table(_ row: Row) {
        #expect(ClockText.minutesSeconds(row.duration) == row.text)
    }

    @Test("No duration traps: the longest, the shortest and elapsed time's saturated 2^63 s all print")
    func minutesSeconds_extremes_doNotTrap() {
        #expect(ClockText.minutesSeconds(Duration(attoseconds: .max)) == "47261439850130342:08:51")
        #expect(ClockText.minutesSeconds(Duration(attoseconds: .min)) == "0:00")
        // What `WorkoutState.elapsed(at:)` saturates at: 2^63 s = 2,562,047,788,015,215 h 30 min 8 s.
        #expect(ClockText.minutesSeconds(.seconds(Double(Int64.max))) == "2562047788015215:30:08")
    }

    @Test("A live workout's elapsed time reads as the header shows it")
    func minutesSeconds_ofElapsedTime() {
        let session = EventBuilders.seedSession()
        let now = EventBuilders.start.addingTimeInterval(24 * 60 + 22.4)
        #expect(ClockText.minutesSeconds(session.elapsed(at: now)) == "24:22")
        #expect(ClockText.minutesSeconds(session.elapsed(at: EventBuilders.start)) == "0:00")
        // A clock that stepped back behind the start: elapsed time is never negative, and neither is the text.
        #expect(ClockText.minutesSeconds(session.elapsed(at: EventBuilders.start.addingTimeInterval(-90))) == "0:00")
    }
}
