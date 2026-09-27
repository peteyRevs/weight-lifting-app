import Foundation
@testable import LedgerDomain
import Testing

// Fixtures for LedgerDomainTests (testing-strategy §3). Kept in the test target rather than
// LedgerTestSupport for the same reason as Tags.swift (F02 implementation notes).

/// An exact decimal from its text; float literals are only exact for dyadic values like 52.5.
func dec(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
}

enum Fixtures {
    static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    /// Gregorian, UTC, en_US, first weekday Sunday (testing-strategy §3 rule 4).
    static let calendar: Calendar = {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = utc
        gregorian.locale = Locale(identifier: "en_US")
        gregorian.firstWeekday = 1
        return gregorian
    }()

    /// 2026-09-16T05:20:00Z (testing-strategy §3 rule 1).
    static let now = date(2026, 9, 16, hour: 5, minute: 20)

    static let workoutID = WorkoutID(uuid(9001))
    static let deviceID = DeviceID(uuid(9002))
    static let programID = ProgramID(uuid(9003))

    /// A fixed UUID whose last four bytes are `number`: 00000000-0000-0000-0000-0000000000NN.
    static func uuid(_ number: Int) -> UUID {
        func byte(_ shift: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: number >> shift)
        }
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte(24), byte(16), byte(8), byte(0)))
    }

    static func date(
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

    /// The civil date `year-month-day` (a Program start, ADR-007).
    static func civil(_ year: Int, _ month: Int, _ day: Int) -> CivilDate {
        guard let civil = CivilDate(year: year, month: month, day: day) else {
            Issue.record("\(year)-\(month)-\(day) is not a valid fixture date")
            return .unixEpoch
        }
        return civil
    }

    /// `value` encoded as JSON text.
    static func json(_ value: some Encodable) throws -> String {
        try #require(String(bytes: JSONEncoder().encode(value), encoding: .utf8))
    }

    static func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    static func rpe(_ value: Decimal) throws -> RPE {
        try #require(RPE(value))
    }

    static func rest(_ seconds: Int) throws -> RestDuration {
        try #require(RestDuration(seconds: seconds))
    }

    static func reps(_ value: Int) throws -> Reps {
        try #require(Reps(value))
    }
}

// MARK: - Exercises (spec §6.2 W0 loads)

extension Fixtures {
    static let bench = exercise(1, "Barbell Bench Press", .barbell, pounds: 180, kilograms: 80)
    static let inclineDB = exercise(2, "Incline DB Press", .dumbbell, pounds: 50, kilograms: 22.5)
    static let chestSupportedRow = exercise(5, "Chest-Supported Row", .machine, pounds: 65, kilograms: 30)
    static let latPulldown = exercise(6, "Lat Pulldown", .cable, pounds: 100, kilograms: 45)
    static let lateralRaise = exercise(9, "Cable Lateral Raise", .cable, pounds: 12.5, kilograms: 5)
    static let backSquat = exercise(11, "Back Squat", .barbell, pounds: 250, kilograms: 110)
    static let barbellCurl = exercise(18, "Barbell Curl", .barbell, pounds: 75, kilograms: 35)

    static let catalog: [ExerciseID: Exercise] = Dictionary(
        uniqueKeysWithValues: [bench, inclineDB, chestSupportedRow, latPulldown, lateralRaise, backSquat, barbellCurl]
            .map { ($0.id, $0) }
    )

    /// Taxonomy fields that no rule reads get fixed placeholder values.
    static func exercise(
        _ number: Int,
        _ name: String,
        _ equipment: Equipment,
        pounds: Decimal,
        kilograms: Decimal
    ) -> Exercise {
        Exercise(
            id: ExerciseID(uuid(number)),
            name: name,
            shortName: name.uppercased(),
            equipment: equipment,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(pounds), .kg: .kilograms(kilograms)]
        )
    }
}
