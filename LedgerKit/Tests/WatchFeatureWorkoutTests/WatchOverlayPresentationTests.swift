import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The session list and the end overlay (spec §4.3, §5.1; F18 criteria 8 and 10, the pure halves).
@Suite("Watch list and end presentation", .tags(.watch))
struct WatchOverlayPresentationTests {
    static let locale = Fixtures.locale

    @Test("The list: a row per exercise with its number, name, first-set scheme, and the current one marked")
    func list_rows() throws {
        var state = try WatchSample.session()
        state.exercises[0].sets[0].weight = .pounds(185)
        let list = WatchPresentation.list(state, locale: Self.locale)
        #expect(list.header == "0 OF 5 DONE" && list.endWorkout == "End workout")
        #expect(list.rows.map(\.number) == ["1", "2", "3", "4", "5"])
        #expect(list.rows.map(\.exerciseIndex) == [0, 1, 2, 3, 4])
        let first = try #require(list.rows.first)
        #expect(first.name == "Barbell Bench Press" && first.scheme == "5 × 5 @ 185")
        #expect(first.isCurrent && !first.isDone)
        #expect(list.rows.dropFirst().allSatisfy { !$0.isCurrent && !$0.isDone })
    }

    @Test("A superset's rows are prefixed by their letter; a fully logged exercise is done and the current one moves")
    func list_supersetAndDone() throws {
        let state = try WatchSample.logging([(0, 0), (0, 1), (0, 2), (0, 3), (0, 4)], in: WatchSample.session())
        let list = WatchPresentation.list(state, locale: Self.locale)
        #expect(list.header == "1 OF 5 DONE")
        #expect(list.rows[3].name == "A · Lat Pulldown" && list.rows[4].name.hasPrefix("B · "))
        #expect(!list.rows[0].name.contains(" · "), "a solo exercise has no letter")
        #expect(list.rows[0].isDone && !list.rows[0].isCurrent && list.rows[1].isCurrent)
    }

    @Test("The scheme counts sets without the drop set, reads the workout's unit, and a row with no set is not done")
    func list_schemeDropSetAndUnits() throws {
        var state = try WatchSample.session(settings: Fixtures.settingsKg)
        state.exercises[0].sets[0].weight = .kilograms(Decimal(string: "82.5") ?? 0)
        state.exercises[0].sets[4].kind = .drop
        let list = WatchPresentation.list(state, locale: Self.locale)
        #expect(list.rows[0].scheme == "4 × 5 @ 82.5")
        state.exercises[1].sets = []
        let empty = WatchPresentation.list(state, locale: Self.locale).rows[1]
        #expect(!empty.isDone && empty.scheme.hasPrefix("0 × "), "the target's reps and load stand in")
    }

    @Test("End workout?: the sets logged of all, the volume, the three actions, and the facts the store decides by")
    func end_lineAndActions() throws {
        let fresh = try WatchPresentation.end(WatchSample.session(day: 1), locale: Self.locale)
        #expect(fresh.title == "End workout?")
        #expect(fresh.line == "0 of 15 sets logged · 0 lb moved")
        #expect(fresh.spokenLine == "0 of 15 sets logged, 0 lb moved")
        #expect(fresh.save == "Save workout" && fresh.discard == "Discard" && fresh.keepLifting == "Keep lifting")
        #expect(fresh.loggedSetCount == 0 && !fresh.canSave, "nothing to save yet, as on the phone")
        let logged = try WatchSample.loggedLowerA(.pounds(185), reps: 5, sets: 1)
        let one = WatchPresentation.end(logged, locale: Self.locale)
        #expect(one.line == "1 of 15 sets logged · 925 lb moved")
        #expect(one.loggedSetCount == 1 && one.canSave)
        var single = logged
        single.exercises = [single.exercises[0]]
        single.exercises[0].sets = [single.exercises[0].sets[0]]
        #expect(WatchPresentation.end(single, locale: Self.locale).line == "1 of 1 set logged · 925 lb moved")
    }
}
