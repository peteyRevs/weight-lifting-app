@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: the words (S3 criterion 10). Singular and plural forms for 0, 1 and 2, the marks the brief's
/// "Copy (exact)" writes (a real minus, " · ", "×", "~"), no placeholder or product name in anything drawn or
/// spoken, and a locale that changes how numbers are grouped and nothing else.
@Suite("Adversarial F09 S3 · the words", .tags(.feature))
nonisolated struct TodayCopyAdversarialTests {
    typealias Support = TodayAdversarial

    /// The seed whose Lower A holds only its first `count` slots, each cut to `sets` sets and 30 s of rest when
    /// `sets` is given: a day of 0, 1 or 2 exercises, and of a minute or two.
    static func lowerA(slots count: Int, sets: Int? = nil) throws -> Program {
        var program = try Support.seed()
        var slots = Array(program.days[1].slots.prefix(count))
        if let sets {
            slots = try slots.map { slot in
                try Slot(
                    id: slot.id,
                    exerciseID: slot.exerciseID,
                    sets: sets,
                    reps: slot.reps,
                    repsHi: slot.repsHi,
                    rpe: slot.rpe.value,
                    restSeconds: 30,
                    progression: slot.progression,
                    startLoad: slot.startLoad
                )
            }
        }
        program.days[1].slots = slots
        return program
    }

    /// Slots, sets per slot (nil keeps the seed's), and the texts of the day in week 1.
    struct Count: Sendable, CustomStringConvertible {
        let slots: Int
        let sets: Int?
        let detail: String
        let meta: String

        init(_ slots: Int, _ sets: Int?, _ detail: String, _ meta: String) {
            self.slots = slots
            self.sets = sets
            self.detail = detail
            self.meta = meta
        }

        var description: String {
            detail
        }
    }

    static let counts = [
        Count(0, nil, "0 exercises · ~0 min", "Week 1 of 8 · ~0 min"),
        // One set of 42 s and 30 s of rest is 72 s → 1 minute; two are 144 s = 2.4 → 2.
        Count(1, 1, "1 exercise · ~1 min", "Week 1 of 8 · ~1 min"),
        Count(1, 2, "1 exercise · ~2 min", "Week 1 of 8 · ~2 min"),
        // Squat 5×(42+180) = 1110 s → 19; with the RDL's 3×(42+120) = 1596 s → 27.
        Count(1, nil, "1 exercise · ~19 min", "Week 1 of 8 · ~19 min"),
        Count(2, nil, "2 exercises · ~27 min", "Week 1 of 8 · ~27 min")
    ]

    @Test("Exercises and minutes are counted in the singular and the plural", arguments: counts)
    func exercisesAndMinutes_areCounted(_ row: Count) throws {
        let program = try Self.lowerA(slots: row.slots, sets: row.sets)
        let wednesday = try Support.input(program, now: Support.moment(Support.civil(2026, 9, 16)))
        let card = try Support.upNext(TodayPresentation.make(wednesday))
        #expect(card.meta == row.meta)
        #expect(card.rows.count == row.slots)
        let tuesday = try Support.input(program, now: Support.moment(Support.civil(2026, 9, 15)))
        let sheet = try Support.rest(TodayPresentation.make(tuesday)).offSchedule
        #expect(sheet.days.map(\.detail)[1] == row.detail)
    }

    @Test("Weeks done are counted in the singular and the plural", arguments: [1, 2, 8])
    func weeksDone_areCounted(_ count: Int) throws {
        var program = try Support.seed()
        program.weeks = Array(program.weeks.prefix(count))
        let after = try Support.moment(#require(program.startDate.adding(days: 7 * count)))
        let card = try Support.blockComplete(TodayPresentation.make(Support.input(program, now: after)))
        let noun = count == 1 ? "week" : "weeks"
        #expect(card.body == "\(count) \(noun) done. Start the next block from Program.")
    }

    @Test("The marks are the brief's: a real minus, a middle dot between spaces, a multiplication sign, a tilde")
    func marks_areTheBriefs() throws {
        let program = try Support.seed()
        let start = try Support.moment(Support.civil(2026, 9, 14), 7)
        let workout = try Support.lifted(number: 600, start: start, lifts: [.pounds(97, 100)])
        let previous = Volume(weight: .pounds(100), reps: Reps(clamping: 100))
        let input = try Support.input(
            program,
            now: Support.moment(Support.civil(2026, 9, 16)),
            week: [workout],
            recent: [workout],
            previous: previous
        )
        let model = TodayPresentation.make(input)
        #expect(model.stats.volume.delta.map { Array($0.unicodeScalars).map(\.value) } == [0x2212, 0x33, 0x25])
        let card = try Support.upNext(model)
        #expect(card.meta?.unicodeScalars.contains("\u{00B7}") == true)
        #expect(card.meta?.contains(" \u{00B7} ~38 min") == true)
        #expect(card.rows.first?.scheme.unicodeScalars.map(\.value) == Array("5 \u{00D7} 5 @ 250".unicodeScalars)
            .map(\.value))
        #expect(card.title.unicodeScalars.contains("\u{2014}"))
        #expect(model.recent.rows.first?.meta == "Mon \u{00B7} 60 min \u{00B7} 9,700 lb")
    }
}
