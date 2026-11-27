import Foundation
import LedgerDomain
#if DEBUG
    import LedgerFakes
#endif

/// A UI test's watch (F18 S7), read from the launch's arguments beside `-LEDGER_UITEST` as the iPhone reads its own
/// (`LedgerAppKit`'s `UITestProgram` and `UITestClock`), with the same names, and **in Debug builds only**: a Release
/// build reads no argument here, moves no clock, seeds nothing and keeps the live Health store.
///
/// - `-LEDGER_UITEST_PROGRAM seed` saves the spec's seed program (`Fixtures.seedProgram()`) as the active one
///   when there is none, so the screen before a workout shows a day: a fresh watch database has no program until
///   the phone sends one (F19).
/// - `-LEDGER_UITEST_NOW <instant>` moves the app's clock so that the launch happens at that instant, then time runs as
///   it does: the seed program's weeks are in the past. The watch takes the instant in UTC alone,
///   "2026-09-14T12:00:00Z".
/// - Any UI test's launch gets a `FakeHealthStore`, authorized, in place of HealthKit: no sheet asks for Health, and
///   the running session's heart rate is the script's (`heartRate`).
///
/// A value that cannot be read stops the launch: a UI test set up wrongly must not run on the real date.
nonisolated enum WatchUITest {
    static let flag = "-LEDGER_UITEST"
    static let programArgument = "-LEDGER_UITEST_PROGRAM"
    static let nowArgument = "-LEDGER_UITEST_NOW"
    /// The one value `-LEDGER_UITEST_PROGRAM` takes.
    static let seed = "seed"
    /// The heart rate the script reads to a running session, and how often.
    static let heartRate = 128
    static let heartRateEvery = Duration.seconds(2)

    /// An argument is there and its value is missing or is not one it takes.
    struct InvalidValue: Error, Equatable {
        let argument: String
        let value: String?
    }

    /// Whether the arguments ask for the seed program; false when they do not, or are not a UI test's.
    static func seedsProgram(arguments: [String]) throws -> Bool {
        guard let value = try value(of: programArgument, in: arguments) else {
            return false
        }
        guard value == seed else {
            throw InvalidValue(argument: programArgument, value: value)
        }
        return true
    }

    /// The seconds to add to the device's clock so that `launch` reads as the instant the arguments name; nil when
    /// they name none, or are not a UI test's.
    static func clockOffset(arguments: [String], launch: Date) throws -> TimeInterval? {
        guard let value = try value(of: nowArgument, in: arguments) else {
            return nil
        }
        guard let instant = instant(written: value) else {
            throw InvalidValue(argument: nowArgument, value: value)
        }
        return instant.timeIntervalSince(launch)
    }

    /// The instant `text` writes in UTC to the second ("2026-09-14T12:00:00Z"), when Foundation writes it back the
    /// same: a date or a time that does not exist (30 February, hour 25), an offset or anything after it is none.
    static func instant(written text: String) -> Date? {
        // `try?`: a text Foundation cannot read is no instant, which is all the caller asks.
        guard let instant = try? Date(text, strategy: .iso8601), instant.formatted(.iso8601) == text else {
            return nil
        }
        return instant
    }

    /// The value after `argument`: nil when it is absent or the launch is not a UI test's; it throws when the argument
    /// is the last.
    private static func value(of argument: String, in arguments: [String]) throws -> String? {
        guard arguments.contains(flag), let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        guard arguments.indices.contains(index + 1) else {
            throw InvalidValue(argument: argument, value: nil)
        }
        return arguments[index + 1]
    }
}

extension WatchUITest {
    /// What this launch's arguments ask for, read once by `WatchComposition.Environment.live(arguments:)`.
    struct Launch {
        var clockOffset: TimeInterval?
        var seedsProgram = false
        /// The UI test's Health store, scripted; nil in an app no UI test launched.
        var healthStore: (any HealthStore)?
    }

    static func live(arguments: [String]) -> Launch {
        #if DEBUG
            guard arguments.contains(flag) else {
                return Launch()
            }
            do {
                return try Launch(
                    clockOffset: clockOffset(arguments: arguments, launch: Date()),
                    seedsProgram: seedsProgram(arguments: arguments),
                    healthStore: FakeHealthStore(authorization: .authorized)
                )
            } catch {
                fatalError("\(nowArgument) takes 2026-09-14T12:00:00Z, \(programArgument) takes \(seed): \(error)")
            }
        #else
            return Launch()
        #endif
    }

    /// The seed program, saved as the active one when there is none.
    static func saveSeedProgramIfNone(in programs: any ProgramRepository) async throws {
        #if DEBUG
            if try await programs.active() == nil {
                try await programs.save(Fixtures.seedProgram())
            }
        #endif
    }

    /// The script's heart rate: every `heartRateEvery`, one reading of `heartRate`, which a running session shows and
    /// none other does, until the caller's task is cancelled. Nothing for a store that is not the UI test's.
    static func scriptHeartRate(
        of store: any HealthStore, clock: any Clock<Duration>, now: @escaping @Sendable () -> Date
    ) async {
        #if DEBUG
            guard let fake = store as? FakeHealthStore else {
                return
            }
            while await (try? clock.sleep(for: heartRateEvery)) != nil {
                await fake.simulateHeartRate([HeartRateSample(bpm: heartRate, date: now())])
            }
        #endif
    }
}
