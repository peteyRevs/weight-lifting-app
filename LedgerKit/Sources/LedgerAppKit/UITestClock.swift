import Foundation

/// A UI test's own date for the app (F09 S5): `-LEDGER_UITEST_NOW <instant>` beside `-LEDGER_UITEST` moves
/// the app's clock so that the launch happens at that instant, written as ISO 8601 ("2026-09-17T12:00:00Z").
/// Time then runs as it does: the clock is the device's plus a fixed offset. The calendar, the time zone and
/// the locale stay the device's.
///
/// It exists because Today depends on the date: which card a program shows today is otherwise the day the
/// test happens to run on. Without `-LEDGER_UITEST` the argument is ignored, so no launch but a UI test's
/// can be moved in time.
///
/// What it does not move: a time the system counts by itself. The workout cover's elapsed time is drawn by
/// SwiftUI's timer from the device's clock, so under an offset it reads the offset too; a test that reads
/// that time launches without the argument.
nonisolated enum UITestClock {
    static let argument = "-LEDGER_UITEST_NOW"

    /// The argument is there and its value is missing or is no ISO 8601 instant.
    struct InvalidInstant: Error, Equatable {
        let value: String?
    }

    /// The seconds to add to the device's clock so that `launch` reads as the instant the arguments name; nil
    /// when they name none, or are not a UI test's.
    static func offset(arguments: [String], launch: Date) throws -> TimeInterval? {
        guard arguments.contains("-LEDGER_UITEST"), let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        guard let value, let instant = instant(written: value) else {
            throw InvalidInstant(value: value)
        }
        return instant.timeIntervalSince(launch)
    }

    /// The instant `text` writes, when it writes exactly one: a date and a time that exist, to the second, and
    /// then "Z" or an offset of hours and minutes, with nothing before or after
    /// ("2026-09-17T12:00:00Z", "2026-09-17T14:00:00+02:00", "…+0200"). Foundation's reader alone takes
    /// more: it moves 30 February to 2 March, hour 25 to the next day and second 60 to the next minute, and
    /// ignores what follows the instant. So what it read is written out again, in the offset the text gave,
    /// and must be the text.
    static func instant(written text: String) -> Date? {
        let wallClock = text.prefix(19)
        // `try?`: a text Foundation cannot read is no instant, which is all the caller asks.
        guard let instant = try? Date(text, strategy: .iso8601),
              let readAsUTC = try? Date(wallClock + "Z", strategy: .iso8601),
              let zone = TimeZone(secondsFromGMT: Int(readAsUTC.timeIntervalSince(instant)))
        else {
            return nil
        }
        let exact = Date.ISO8601FormatStyle(timeZone: zone)
            .year().month().day().dateSeparator(.dash).dateTimeSeparator(.standard)
            .time(includingFractionalSeconds: false).timeSeparator(.colon)
        var spellings = [exact.timeZone(separator: .colon), exact.timeZone(separator: .omitted)].map(instant.formatted)
        if zone.secondsFromGMT() == 0 {
            // Written out, no offset is "Z"; written as an offset it is the same instant.
            spellings += ["+00:00", "+0000"].map { wallClock + $0 }
        }
        return spellings.contains(text) ? instant : nil
    }

    /// `offset(arguments:launch:)` for the launch that is happening now. A value that cannot be read stops the
    /// launch: a UI test set up wrongly must not run on the real date and pass or fail by the weekday.
    ///
    /// **Debug builds only.** A UI test runs a Debug build (it reaches a program through the Debug menu), so
    /// a Release build reads no argument here, moves no clock and holds no `fatalError`.
    static func liveOffset(arguments: [String]) -> TimeInterval? {
        #if DEBUG
            do {
                return try offset(arguments: arguments, launch: Date())
            } catch {
                fatalError("\(argument) needs an ISO 8601 instant such as 2026-09-17T12:00:00Z: \(error)")
            }
        #else
            return nil
        #endif
    }
}
