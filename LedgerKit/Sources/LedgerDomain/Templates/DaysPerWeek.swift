import Foundation

/// Onboarding step 2 (spec §6.7): how many days a week the lifter trains, which picks the split
/// `ProgramTemplates` writes. It types the generator's input only: `Program.daysPerWeek` stays an `Int?`
/// holding the raw value, because the builder can later give a block any number of days.
public enum DaysPerWeek: Int, Codable, Sendable, CaseIterable {
    case three = 3, four, five, six
}
