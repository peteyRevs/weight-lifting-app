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
        guard let value, let instant = try? Date(value, strategy: .iso8601) else {
            throw InvalidInstant(value: value)
        }
        return instant.timeIntervalSince(launch)
    }

    /// `offset(arguments:launch:)` for the launch that is happening now. A value that cannot be read stops the
    /// launch: a UI test set up wrongly must not run on the real date and pass or fail by the weekday.
    static func liveOffset(arguments: [String]) -> TimeInterval? {
        do {
            return try offset(arguments: arguments, launch: Date())
        } catch {
            fatalError("\(argument) needs an ISO 8601 instant such as 2026-09-17T12:00:00Z: \(error)")
        }
    }
}
