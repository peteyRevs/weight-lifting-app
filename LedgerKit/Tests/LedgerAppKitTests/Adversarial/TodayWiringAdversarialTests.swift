import Dependencies
@testable import FeatureToday
@testable import FeatureWorkout
import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// F09 S5 adversarial round 1 (G2), criteria 7, 9 and 10: Today's store, the app's route mapping and the
/// workout's launcher together, over one set of in-memory stores and the fake session, with no view. What a
/// button of Today's model asks for is taken from the model the store made, handed on as `TodayRoot` hands
/// it, resolved as `MainRoot` resolves it, and answered as the cover's task answers it.
@MainActor
@Suite("Adversarial F09 S5 · Today wired to the launcher", .timeLimit(.minutes(1)))
struct TodayWiringAdversarialTests {
    // MARK: Criterion 9: every route mapped, no button dead

    @Test(
        "In every state, every control of Today's model does something: a tab, a screen or a workout",
        arguments: states
    )
    func everyControl_ofEveryState_doesSomething(_ state: String) async throws {
        let shown = try Self.app(showing: state)
        let first = await shown.running()
        let model = try #require(shown.model)
        first.cancel()
        #expect(Self.kind(model.card) == state)
        let controls = Self.routes(of: model)
        #expect(controls.count >= 2, "the gear and the card's button at least")
        for (name, route) in controls {
            // A fresh app for each control, in the same state: what one tap does, alone.
            let app = try Self.app(showing: state)
            await app.tap(route)
            let moved = app.router.selectedTab != .today || !app.router[path: .today].isEmpty
            let live = try await app.fake.current()
            switch route {
            case let .startWorkout(program, weekIndex, day):
                let source = WorkoutSource(programID: program, weekIndex: weekIndex, dayTemplateID: day)
                #expect(app.launcher.phase == .cover, "\(state), \(name): \(app.launcher.phase)")
                #expect(live?.source == source, "\(state), \(name): the workout is the control's day")
                #expect(!moved, "\(state), \(name): the cover goes over Today")
            case .resumeWorkout:
                Issue.record("\(state), \(name): Resume offered with nothing live")
            case .openWorkout, .editWeek, .openProgram, .settings, .setUpProgram:
                #expect(moved, "\(state), \(name): a dead button")
                #expect(live == nil && app.launcher.request == nil, "\(state), \(name): starts nothing")
            }
            #expect(app.today.pendingRoute == nil)
        }
    }

    // MARK: The mapping, exhaustively

    @Test("From any tab and any stack, a route changes only what its mapping names", arguments: AppTab.allCases)
    func routes_changeOnlyWhatTheyName(from tab: AppTab) {
        let day = DayTemplateID(Fixtures.uuid(5))
        let all: [TodayRoute] = [
            .startWorkout(program: Fixtures.programID, weekIndex: 0, day: day), .resumeWorkout,
            .openWorkout(Fixtures.sessionID), .editWeek(program: Fixtures.programID, weekIndex: 7), .openProgram,
            .settings, .setUpProgram
        ]
        for route in all {
            let router = AppRouter()
            let launcher = WorkoutLauncher()
            router.open(.settings, in: .history)
            router.open(.settings, in: .program)
            router.selectedTab = tab
            router.resolve(route, workout: launcher)
            let depths = AppTab.allCases.map { router[path: $0].count }
            switch route {
            case .startWorkout, .resumeWorkout:
                #expect(router.selectedTab == tab && depths == [0, 1, 0, 1], "\(route)")
                #expect(launcher.request?.number == 1, "\(route)")
            case .openWorkout:
                #expect(router.selectedTab == .history && depths == [0, 1, 0, 1], "\(route)")
                #expect(launcher.request == nil)
            case .editWeek:
                // Sanctioned edit (F11 S14, criterion 23 and Pete's question 2, A): "Edit this week" lands on
                // the builder, so the Program tab's stack is emptied.
                #expect(router.selectedTab == .program && depths == [0, 0, 0, 1], "\(route)")
                #expect(launcher.request == nil)
            case .openProgram, .setUpProgram:
                #expect(router.selectedTab == .program && depths == [0, 1, 0, 1], "\(route)")
                #expect(launcher.request == nil)
            case .settings:
                #expect(router.selectedTab == .today && depths == [1, 1, 0, 1], "\(route)")
                #expect(launcher.request == nil)
            }
        }
    }
}
