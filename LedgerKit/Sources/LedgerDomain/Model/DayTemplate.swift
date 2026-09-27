import Foundation

/// A training-day template shared by every week of a block (spec §6.1 "Training day").
public struct DayTemplate: Identifiable, Hashable, Codable, Sendable {
    public let id: DayTemplateID
    /// "Upper A — Push focus".
    public var name: String
    /// "UA", or "D{n}" for added days (rule 8).
    public var tag: String
    public var slots: [Slot]

    public init(id: DayTemplateID, name: String, tag: String, slots: [Slot] = []) {
        self.id = id
        self.name = name
        self.tag = tag
        self.slots = slots
    }

    /// Rule 45: the part of `name` before " — " ("Upper A"); the whole name when there is none.
    public var shortTitle: String {
        guard let separator = name.range(of: " — ") else {
            return name
        }
        return String(name[..<separator.lowerBound])
    }
}
