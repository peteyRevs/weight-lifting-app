#if DEBUG
    import Foundation
    import LedgerDomain

    /// Fixed values for tests and previews (testing-strategy §3): the clock, calendar and ids
    /// `withTestDependencies` injects, the catalog exercises the spec's seed program names, the program itself
    /// (spec §6.4), a session and a history built from it, and settings in each unit.
    ///
    /// Exercises keep their catalog ids, so a program or workout built here can be saved to a store seeded
    /// with `ExerciseCatalog.seed()`. Promoted from `LedgerDomainTests`' fixtures (F07), whose own copy keeps
    /// the prototype's `W0` exercises and ids for the F02 rule suites. What can fail validation throws; each
    /// fixture is checked by `FixturesTests`.
    public enum Fixtures {
        /// A fixture value that does not construct; `FixturesTests` keeps every fixture from it.
        public struct Invalid: Error, Equatable {
            public let fixture: String
        }

        public static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

        /// en_US: what the tests' plans run in (testing-strategy §8).
        public static let locale = Locale(identifier: "en_US")

        /// Gregorian, UTC, en_US, first weekday Sunday (testing-strategy §3 rule 4).
        public static let calendar: Calendar = {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = utc
            gregorian.locale = locale
            gregorian.firstWeekday = 1
            return gregorian
        }()

        /// Wednesday 2026-09-16, 05:20 UTC (testing-strategy §3 rule 1): in week 5 (index 4) of `seedProgram`.
        public static let now = date(2026, 9, 16, hour: 5, minute: 20)

        public static let deviceID = DeviceID(uuid(9002))
        public static let programID = ProgramID(uuid(9003))
        public static let sessionID = WorkoutID(uuid(9001))

        /// A fixed UUID whose last four bytes are `number`: 00000000-0000-0000-0000-0000000000NN.
        public static func uuid(_ number: Int) -> UUID {
            func byte(_ shift: Int) -> UInt8 {
                UInt8(truncatingIfNeeded: number >> shift)
            }
            return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte(24), byte(16), byte(8), byte(0)))
        }

        /// The instant `year-month-day hour:minute` in `timeZone` (UTC by default).
        public static func date(
            _ year: Int,
            _ month: Int,
            _ day: Int,
            hour: Int = 0,
            minute: Int = 0,
            in timeZone: TimeZone = utc
        ) -> Date {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = timeZone
            let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
            return gregorian.date(from: parts) ?? .distantPast
        }

        // MARK: Settings

        /// The defaults, in pounds, with the week starting on Monday as the seed schedule does.
        public static let settingsLb = Settings.default

        /// `settingsLb` in kilograms.
        public static let settingsKg: Settings = {
            var settings = Settings.default
            settings.units = .kg
            return settings
        }()
    }
#endif
