import FeatureProgram
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S14, criterion 22: where each of the Program screens' routes goes (`Routes+Program.swift`), and Today's
/// "Edit this week" handed to the builder (criterion 23, ruling R10, Pete's question 2).
@MainActor
@Suite("Program routes")
struct ProgramRouteMappingTests {
    private static let dayA = DayTemplateID(Fixtures.uuid(441))
    private static let dayB = DayTemplateID(Fixtures.uuid(442))

    @Test("A day's route pushes its Day editor on the Program tab's stack, one screen per route, from any tab")
    func day_pushesTheDayEditor() {
        let router = AppRouter()
        router.selectedTab = .history
        router.resolve(ProgramRoute.day(Self.dayA, weekIndex: 3))
        #expect(router.selectedTab == .program)
        #expect(router[path: .program] == [.day(Self.dayA, weekIndex: 3)])
        router.resolve(ProgramRoute.day(Self.dayB, weekIndex: 3))
        #expect(router[path: .program] == [.day(Self.dayA, weekIndex: 3), .day(Self.dayB, weekIndex: 3)])
        #expect(AppTab.allCases.map { router[path: $0].count } == [0, 2, 0, 0])
    }

    @Test("Closing pops the Day editor on top; a second close, or one with no Day editor on top, pops nothing")
    func closeDay_popsOnlyADayOnTop() {
        let router = AppRouter()
        router.resolve(ProgramRoute.day(Self.dayA, weekIndex: 0))
        router.resolve(ProgramRoute.closeDay)
        #expect(router[path: .program] == [])
        router.resolve(ProgramRoute.closeDay)
        #expect(router[path: .program] == [])
        router.open(.settings, in: .program)
        router.resolve(ProgramRoute.closeDay)
        #expect(router[path: .program] == [.settings])
    }

    @Test("Edit this week selects the Program tab, pops it to the builder and asks for the week, numbered anew")
    func editWeek_popsToTheBuilder_andRequestsTheWeek() {
        let router = AppRouter()
        router.resolve(ProgramRoute.day(Self.dayA, weekIndex: 0))
        router.selectedTab = .today
        #expect(router.programWeek == nil)
        router.editProgramWeek(4)
        #expect(router.selectedTab == .program && router[path: .program] == [])
        #expect(router.programWeek == ProgramWeekRequest(number: 1, weekIndex: 4))
        router.editProgramWeek(4)
        #expect(router.programWeek == ProgramWeekRequest(number: 2, weekIndex: 4), "the same week asked again")
    }
}
