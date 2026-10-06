@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: inputs no screen should hand over, and some a damaged store or a peer's envelope could.
/// `make` must return a model for each: an edited-away program, names that look like format strings, weights
/// and volumes at the ends of `Decimal`, and workouts whose dates make no sense.
@Suite("Adversarial F09 S3 · inputs that must not trap", .tags(.feature))
nonisolated struct TodayRobustnessAdversarialTests {
    typealias Support = TodayAdversarial

    static func wednesday() throws -> Date {
        try Support.moment(Support.civil(2026, 9, 16))
    }

    /// A short word for the card, so a test can say which one an odd input gave.
    static func kind(_ model: TodayModel) -> String {
        String(TodayOracle.name(of: model.card).prefix { $0 != "(" })
    }

    @Test("A program with no weeks and no days gives a card on every day", arguments: [-3, 0, 3, 400])
    func programWithNothingInIt_givesACard(_ offset: Int) throws {
        var program = try Support.seed()
        program.weeks = []
        program.days = []
        let today = try #require(program.startDate.adding(days: offset))
        let model = try TodayPresentation.make(Support.input(program, now: Support.moment(today)))
        #expect(model.weekStrip.count == 7)
        #expect(model.weekStrip.allSatisfy { $0.mark == .rest || $0.mark == .today })
        #expect(model.stats.sessions.unit == "/0")
        print(
            "TodayRobustnessAdversarialTests empty program, day \(offset): \(Self.kind(model)), \(model.header.title)"
        )
    }

    @Test("A schedule that names a day the program no longer holds gives a card, and no session to start")
    func scheduleNamingAMissingDay_givesACard() throws {
        var program = try Support.seed()
        let lowerA = program.days.remove(at: 1)
        let model = try TodayPresentation.make(Support.input(program, now: Self.wednesday()))
        let offered = Support.texts(in: model.card)
        #expect(!offered.contains(lowerA.name))
        if case let .upNext(card) = model.card {
            #expect(card.action.action.route != .startWorkout(program: program.id, weekIndex: 0, day: lowerA.id))
        }
        print("TodayRobustnessAdversarialTests missing day: \(Self.kind(model)), \(model.header.title), "
            + "\(model.weekStrip.map(\.mark)), \(model.stats.sessions.unit)")
    }

    @Test("Weeks whose indices are not their places give a card on every day of the block", arguments: 0 ..< 21)
    func weeksOutOfPlace_giveACard(_ offset: Int) throws {
        var program = try Support.seed()
        program.weeks = [program.weeks[5], program.weeks[0], program.weeks[0], program.weeks[7]]
        let today = try #require(program.startDate.adding(days: offset * 3 - 3))
        let model = try TodayPresentation.make(Support.input(program, now: Support.moment(today)))
        #expect(model.weekStrip.count == 7)
        #expect(!Self.kind(model).isEmpty)
    }

    static let names = [
        "%@ %lld %d %s %n %1$@ 100%", "", " — ", "— ", "A — B — C", "\u{202E}tfel-ot-thgir", "עברית — יום", "🏋️ — 💪",
        String(repeating: "Long name ", count: 40), "line\nbreak — tab\there", "\\(interpolation)"
    ]

    /// Lower A of week 1 of `program`, finished on Wednesday 2026-09-16, with the exercises' names as `stored`.
    static func lowerADone(_ program: Program, _ stored: [ExerciseID: Exercise]) throws -> WorkoutState {
        try Support.finished(SessionBuilder.build(
            program: program,
            weekIndex: 0,
            day: program.days[1],
            exercises: stored,
            history: [:],
            settings: .default,
            id: WorkoutID(Fixtures.uuid(800)),
            device: Fixtures.deviceID,
            now: Support.moment(Support.civil(2026, 9, 16), 6)
        ))
    }

    /// `text` without the isolates Foundation puts around a right-to-left value in a left-to-right line
    /// (U+2068 … U+2069): they keep the line's order and are not part of the name.
    static func plain(_ text: String?) -> String? {
        text.map { String($0.unicodeScalars.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }) }
    }

    @Test("A day, a tag, an exercise and a workout named like a format string are shown as they are", arguments: names)
    func namesLikeFormatStrings_areShownAsTheyAre(_ name: String) throws {
        var program = try Support.seed()
        for index in program.days.indices {
            program.days[index].name = name
            program.days[index].tag = name
        }
        var input = try Support.input(program, now: Self.wednesday())
        for id in input.exercises.keys {
            input.exercises[id]?.name = name
        }
        let offered = try Support.upNext(TodayPresentation.make(input))
        var wrong: [String] = []
        if TodayPresentation.make(input).header.title != (name.components(separatedBy: " — ").first ?? name) {
            wrong.append("the header's title")
        }
        if offered.title != name || offered.rows.map(\.name) != [name, name, name, name] {
            wrong.append("the Up-next card")
        }
        let done = try Self.lowerADone(program, input.exercises)
        input.weekWorkouts = [done]
        input.recentWorkouts = [done]
        let logged = TodayPresentation.make(input)
        let card = try Support.logged(logged)
        if [card.title, Self.plain(card.next)] != [name, "Next: Friday · \(name)"] {
            wrong.append("the Logged card")
        }
        if logged.recent.rows.map(\.name) != [name] {
            wrong.append("the recent row")
        }
        input.now = try Support.moment(Support.civil(2026, 9, 15))
        if try Support.rest(TodayPresentation.make(input)).offSchedule.days.map(\.name) != [name, name, name, name] {
            wrong.append("the off-schedule list")
        }
        #expect(wrong == [])
    }
}
