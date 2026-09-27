import Foundation

/// Onboarding step 1 (spec §6.7): what the lifter is training for.
public enum TrainingGoal: String, Codable, Sendable, CaseIterable {
    case strength, hypertrophy, both, consistency
}

/// A training block (spec §6.1 "Program (block)", decision #18).
///
/// Validated at construction and on decoding: ≥ 2 weeks (rule 4), week indices exactly
/// 0…n − 1 (weeks are stored sorted by index), and every scheduled day exists in `days`.
public struct Program: Identifiable, Hashable, Codable, Sendable {
    public let id: ProgramID
    public var name: String
    /// Decision #18 / ADR-007: the calendar day week 0 starts on (normally the first day of the week
    /// the lifter started). A civil date, so the block's weeks do not move when the lifter travels.
    public var startDate: CivilDate
    public var weeks: [Week]
    public var days: [DayTemplate]
    public var goal: TrainingGoal?
    public var daysPerWeek: Int?
    public var isActive: Bool

    public init(
        id: ProgramID,
        name: String,
        startDate: CivilDate,
        weeks: [Week],
        days: [DayTemplate],
        goal: TrainingGoal? = nil,
        daysPerWeek: Int? = nil,
        isActive: Bool = false
    ) throws(ProgramValidationError) {
        let sortedWeeks = weeks.sorted { $0.index < $1.index }
        try Self.validate(weeks: sortedWeeks, days: days)
        self.id = id
        self.name = name
        self.startDate = startDate
        self.weeks = sortedWeeks
        self.days = days
        self.goal = goal
        self.daysPerWeek = daysPerWeek
        self.isActive = isActive
    }

    private static func validate(weeks: [Week], days: [DayTemplate]) throws(ProgramValidationError) {
        guard weeks.count >= 2 else {
            throw .tooFewWeeks(count: weeks.count)
        }
        let indices = weeks.map(\.index)
        guard indices == Array(0 ..< weeks.count) else {
            throw .nonContiguousWeeks(indices: indices)
        }
        let dayIDs = Set(days.map(\.id))
        for week in weeks {
            let scheduled = Weekday.allCases.compactMap { week.schedule[$0] }
            if let dangling = scheduled.first(where: { !dayIDs.contains($0) }) {
                throw .danglingSchedule(weekIndex: week.index, dayTemplateID: dangling)
            }
        }
    }

    /// The week with `index`, if the block has one.
    public func week(at index: Int) -> Week? {
        weeks.first { $0.index == index }
    }
}

// MARK: - Codable (re-validates)

extension Program {
    private enum CodingKeys: String, CodingKey {
        case id, name, startDate, weeks, days, goal, daysPerWeek, isActive
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(ProgramID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            startDate: container.decode(CivilDate.self, forKey: .startDate),
            weeks: container.decode([Week].self, forKey: .weeks),
            days: container.decode([DayTemplate].self, forKey: .days),
            goal: container.decodeIfPresent(TrainingGoal.self, forKey: .goal),
            daysPerWeek: container.decodeIfPresent(Int.self, forKey: .daysPerWeek),
            isActive: container.decode(Bool.self, forKey: .isActive)
        )
    }
}
