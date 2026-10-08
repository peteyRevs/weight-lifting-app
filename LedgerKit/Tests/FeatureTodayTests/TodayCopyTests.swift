@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3 criterion 10: the wording of Today's copy, through its copy file. That the texts live in the catalog
/// and in no other file is not this suite's to test: `ModuleCopyTests` audits every module's sources and asks
/// each built bundle for its catalog's keys, and the gate compares each catalog with the compiler's keys.
@Suite("TodayCopy", .tags(.feature))
nonisolated struct TodayCopyTests {
    static let english = Fixtures.locale

    @Test("The plain texts are the brief's, word for word")
    func plainTexts_areTheBriefs() {
        #expect(TodayCopy.today == "Today")
        #expect(TodayCopy.restDay == "Rest day")
        #expect(TodayCopy.settings == "Settings")
        #expect(TodayCopy.upNext == "UP NEXT")
        #expect(TodayCopy.deload == "Deload")
        #expect(TodayCopy.startWorkout == "Start workout")
        #expect(TodayCopy.viewSession == "View session")
        #expect(TodayCopy.scheduledRest == "SCHEDULED REST")
        #expect(TodayCopy.noSessionToday == "No session today")
        #expect(TodayCopy.editThisWeek == "Edit this week")
        #expect(TodayCopy.trainOffSchedule == "Train off-schedule")
        #expect(TodayCopy.logged == "Logged")
        #expect(TodayCopy.cancel == "Cancel")
        #expect(TodayCopy.noProgramTitle == "No program yet")
        #expect(TodayCopy.noProgramBody == "Set up a program to see your next session here.")
        #expect(TodayCopy.setUpProgram == "Set up program")
        #expect(TodayCopy.blockCompleteTitle == "Block complete")
        #expect(TodayCopy.openProgram == "Open Program")
        #expect(TodayCopy.sessionsThisWeek == "sessions this week")
        #expect(TodayCopy.thousands == "k")
        #expect(TodayCopy.recent == "RECENT")
        #expect(TodayCopy.noSessionsYet == "No sessions yet. Your first workout lands here.")
        #expect(TodayCopy.failedTitle == "Can't show today right now")
        #expect(
            TodayCopy.failedBody == "Your workouts are still on this iPhone. Open the app again to try once more."
        )
    }

    @Test("The texts with values read as the brief writes them")
    func textsWithValues_areTheBriefs() {
        let locale = Self.english
        #expect(TodayCopy.week(3, of: 8, locale: locale) == "Week 3 of 8")
        #expect(TodayCopy.scheme(sets: 5, reps: 5, load: "185", locale: locale) == "5 × 5 @ 185")
        #expect(TodayCopy.resume("3:00", locale: locale) == "Resume · 3:00")
        #expect(TodayCopy.loggedWeek(1, locale: locale) == "LOGGED · WEEK 1")
        #expect(TodayCopy.next("Friday", tag: "UB", locale: locale) == "Next: Friday · UB")
        #expect(TodayCopy.nextWeek(2, locale: locale) == "Next: week 2")
        #expect(TodayCopy.pickADay(week: 1, locale: locale) == "Pick a day from week 1.")
        #expect(TodayCopy.todaySummary("Wednesday, September 16", locale: locale) == "Today, Wednesday, September 16")
        #expect(TodayCopy.sessionsPlanned(4, locale: locale) == "/4")
        #expect(
            TodayCopy.restNextUp("Wednesday", week: 1, next: "Friday", locale: locale)
                == "Nothing scheduled for Wednesday in week 1. Next up is Friday."
        )
        #expect(
            TodayCopy.restNextUpLater("Saturday", week: 1, next: "Monday", locale: locale)
                == "Nothing scheduled for Saturday in week 1. Next up is next Monday."
        )
        #expect(
            TodayCopy.restLastWeek("Saturday", week: 8, locale: locale)
                == "Nothing scheduled for Saturday in week 8. This is the last week of the block."
        )
        #expect(
            TodayCopy.restNoneLeft("Sunday", week: 2, locale: locale)
                == "Nothing scheduled for Sunday in week 2. No sessions are left in this block."
        )
        #expect(TodayCopy
            .blockStarts(on: "Monday, September 28", locale: locale) == "Your block starts on Monday, September 28.")
    }

    @Test("Each unit has its own words")
    func unitTexts_readPoundsAndKilograms() {
        let locale = Self.english
        #expect(TodayCopy.movedCaption(.lb) == "lb moved")
        #expect(TodayCopy.movedCaption(.kg) == "kg moved")
        #expect(TodayCopy.moved("24,180", units: .lb, locale: locale) == "24,180 lb moved")
        #expect(TodayCopy.moved("10,968", units: .kg, locale: locale) == "10,968 kg moved")
        #expect(TodayCopy.movedThisWeek("24,180", units: .lb, locale: locale) == "24,180 lb moved this week")
        #expect(TodayCopy.movedThisWeek("10,968", units: .kg, locale: locale) == "10,968 kg moved this week")
        #expect(
            TodayCopy.movedThisWeek("24,180", change: "+8%", units: .lb, locale: locale)
                == "24,180 lb moved this week, +8% from last week"
        )
        #expect(
            TodayCopy.movedThisWeek("10,968", change: "\u{2212}3%", units: .kg, locale: locale)
                == "10,968 kg moved this week, \u{2212}3% from last week"
        )
        #expect(TodayCopy.volume("24,180", units: .lb, locale: locale) == "24,180 lb")
        #expect(TodayCopy.volume("10,968", units: .kg, locale: locale) == "10,968 kg")
    }

    @Test("The change keeps its percent sign, and a fall is written with a real minus sign")
    func change_readsSignNumberAndPercent() {
        let locale = Self.english
        #expect(TodayCopy.increase(8, locale: locale) == "+8%")
        #expect(TodayCopy.decrease(3, locale: locale) == "\u{2212}3%")
        #expect(TodayCopy.unchanged(0, locale: locale) == "0%")
    }

    @Test("A counted text has its singular and its plural: one and several")
    func countedTexts_haveOneAndSeveral() {
        let locale = Self.english
        #expect(TodayCopy.estimate(minutes: 1, locale: locale) == "~1 min")
        #expect(TodayCopy.estimate(minutes: 38, locale: locale) == "~38 min")
        #expect(TodayCopy.duration(minutes: 1, locale: locale) == "1 min")
        #expect(TodayCopy.duration(minutes: 58, locale: locale) == "58 min")
        #expect(TodayCopy.sets(done: "1", of: 1, locale: locale) == "1 of 1 set")
        #expect(TodayCopy.sets(done: "15", of: 16, locale: locale) == "15 of 16 sets")
        #expect(TodayCopy.exercises(1, locale: locale) == "1 exercise")
        #expect(TodayCopy.exercises(4, locale: locale) == "4 exercises")
        #expect(TodayCopy.exercises(0, locale: locale) == "0 exercises")
        #expect(
            TodayCopy.blockCompleteBody(weeks: 1, locale: locale) == "1 week done. Start the next block from Program."
        )
        #expect(
            TodayCopy.blockCompleteBody(weeks: 8, locale: locale) == "8 weeks done. Start the next block from Program."
        )
        #expect(TodayCopy.sessionsSummary(done: "0", planned: 1, locale: locale) == "0 of 1 session this week")
        #expect(TodayCopy.sessionsSummary(done: "2", planned: 4, locale: locale) == "2 of 4 sessions this week")
    }

    @Test("In a counted text it is the counted number that picks the form, not the number passed as text")
    func countedTexts_formFollowsTheCountedNumber() {
        let locale = Self.english
        #expect(TodayCopy.sets(done: "1", of: 15, locale: locale) == "1 of 15 sets")
        #expect(TodayCopy.sets(done: "0", of: 1, locale: locale) == "0 of 1 set")
        #expect(TodayCopy.sessionsSummary(done: "1", planned: 4, locale: locale) == "1 of 4 sessions this week")
        #expect(TodayCopy.sessionsSummary(done: "5", planned: 1, locale: locale) == "5 of 1 session this week")
    }

    @Test("A number in a text is grouped by the locale it is given")
    func numbers_followTheGivenLocale() {
        let german = Locale(identifier: "de_DE")
        #expect(TodayCopy.exercises(1234, locale: Self.english) == "1,234 exercises")
        #expect(TodayCopy.exercises(1234, locale: german) == "1.234 exercises")
        #expect(TodayCopy.increase(1234, locale: german) == "+1.234%")
    }

    @Test("No text of Today names the product")
    func catalog_neverNamesTheProduct() throws {
        let catalog = try StringCatalog(module: "FeatureToday")
        // S3's 55 and the two texts of the failed state (S4).
        #expect(catalog.keys.count == 57)
        #expect(catalog.problems == [])
    }
}
