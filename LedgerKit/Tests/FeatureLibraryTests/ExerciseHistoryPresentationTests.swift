@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S2, criteria 4–8 and 11, N14 and Pete's questions 3 and 7, on the pure presentation of an exercise's
/// history.
@Suite("ExerciseHistoryPresentation", .tags(.feature))
struct ExerciseHistoryPresentationTests {
    static func model(_ input: ExerciseHistoryInput) -> ExerciseHistoryModel {
        ExerciseHistoryPresentation.make(input)
    }

    @Test("4. The fixture reads 219, 195×5 and 6 sessions; the weeks are its estimates; the change is +28 lb")
    func criterion4_statsWeeksAndChange() throws {
        let model = try Self.model(HistoryFixtures.input(HistoryFixtures.criterion4Sessions))
        #expect(model.eyebrow == "Barbell · Chest")
        #expect(model.title == "Barbell Bench Press")
        #expect(model.stats.map(\.value) == ["219", "195", "6"])
        #expect(model.stats.map(\.unit) == [nil, "×5", nil])
        #expect(model.stats.map(\.caption) == ["1RM est", "best set", "sessions"])
        #expect(model.numbers == [191, 197, nil, 205, 208, nil, 214, 219])
        #expect(model.chart.bars.map(\.week) == ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"])
        #expect(model.chart.title == "ESTIMATED 1RM · 8 WEEKS")
        #expect(model.chart.delta == "+28 lb")
        #expect(model.chart.empty == nil)
    }

    @Test("Q3. Orange is the estimate and the current week's bar; bars rise from a quarter to the full height")
    func orange_isTheEstimateAndTheLastBar() throws {
        let model = try Self.model(HistoryFixtures.input(HistoryFixtures.criterion4Sessions))
        #expect(model.stats.map(\.isAccented) == [true, false, false])
        #expect(model.chart.bars.map(\.isAccented) == [false, false, false, false, false, false, false, true])
        #expect(model.chart.bars.map(\.level) == [25, 41, 0, 62, 70, 0, 86, 100])
        let older = try Self.model(HistoryFixtures.input(Array(HistoryFixtures.criterion4Sessions.dropFirst())))
        #expect(older.chart.bars.allSatisfy { !$0.isAccented }, "no session this week: no bar is orange")
    }

    @Test("5. Empty weeks keep their labels; with no estimate the chart says so and the stats are dashes")
    func noData_saysSo() throws {
        let model = try Self.model(HistoryFixtures.input([]))
        #expect(model.chart.empty == "Log a session to start the chart.")
        #expect(model.chart.delta == nil && model.chart.bars.count == 8)
        #expect(model.stats.map(\.value) == ["—", "—", "0"])
        #expect(model.stats.map(\.isAccented) == [false, false, false])
        #expect(model.log.entries.isEmpty && model.log.empty == "No sessions yet." && model.log.title == "SESSION LOG")
    }

    @Test("5. One week with a value has no change")
    func oneWeek_hasNoChange() throws {
        let model = try Self.model(HistoryFixtures.input([HistoryFixtures.session(1, Fixtures.now, sets: 1, 200, 5)]))
        #expect(model.chart.delta == nil)
        #expect(model.chart.bars.last?.level == 100)
    }

    @Test("6. A best of 100 × 15: 1RM est is a dash, the best set 100×15, and the chart has nothing to draw")
    func repsOver12_haveNoEstimate() throws {
        let model = try Self.model(HistoryFixtures.input([HistoryFixtures.session(1, Fixtures.now, sets: 2, 100, 15)]))
        #expect(model.stats.map(\.value) == ["—", "100", "1"])
        #expect(model.stats[1].unit == "×15")
        #expect(model.chart.empty == "Log a session to start the chart.")
    }

    @Test("7. The log reads PR, —, +5 lb, —, — from Aug 12 down, with every set and its date")
    func criterion7_tagsAndDates() throws {
        let sessions = HistoryFixtures.criterion7Sessions
        let now = Fixtures.date(2026, 8, 13)
        let model = try Self.model(HistoryFixtures.input(sessions, records: [sessions[0].workoutID], now: now))
        #expect(model.log.entries.map(\.tag) == ["PR", "—", "+5 lb", "—", "—"])
        #expect(model.log.entries.map(\.isRecord) == [true, false, false, false, false])
        #expect(model.log.entries.map(\.date) == ["Aug 12", "Aug 5", "Jul 29", "Jul 22", "Jun 24"])
        #expect(model.log.entries[1].sets == "175×5   175×5   175×5   175×5   175×4")
        #expect(model.log.entries[0].spokenValue == "PR, 180×5, 180×5, 180×5, 180×5, 180×5")
        #expect(model.log.empty == nil)
    }

    @Test("11. A log entry's tap opens its workout")
    func entry_routesToItsWorkout() throws {
        let sessions = HistoryFixtures.criterion7Sessions
        let model = try Self.model(HistoryFixtures.input(sessions))
        #expect(model.log.entries.map(\.route) == sessions.map { .openWorkout($0.workoutID) })
        #expect(model.log.entries.map(\.id) == sessions.map(\.workoutID))
    }

    @Test("N14. A date of another year carries its year")
    func date_ofAnotherYear_carriesItsYear() throws {
        let old = HistoryFixtures.session(1, Fixtures.date(2025, 8, 12, hour: 7), sets: 1, 100, 5)
        #expect(try Self.model(HistoryFixtures.input([old])).log.entries.map(\.date) == ["Aug 12, 2025"])
    }

    @Test("8, Q7. In kilograms: whole estimates, the change of the shown values, a step's tag to one decimal")
    func kilograms_convertEverything() throws {
        let model = try Self.model(HistoryFixtures.input(HistoryFixtures.criterion4Sessions, units: .kg))
        #expect(model.stats.map(\.value) == ["100", "88.5", "6"])
        #expect(model.numbers.first == 87 && model.numbers.last == 100)
        #expect(model.chart.delta == "+13 kg")
        let sessions = HistoryFixtures.criterion7Sessions
        let tags = try Self.model(HistoryFixtures.input(sessions, units: .kg)).log.entries.map(\.tag)
        #expect(tags == ["+2.3 kg", "—", "+2.3 kg", "—", "—"])
        #expect(try Self.model(HistoryFixtures.input(sessions, units: .kg)).log.entries[0].sets.hasPrefix("81.6×5"))
    }

    @Test("Q7. A fall reads −, no change 0")
    func change_fallAndNone() throws {
        let falling = [
            HistoryFixtures.session(2, Fixtures.now, sets: 1, 180, 5),
            HistoryFixtures.session(1, Fixtures.now.addingTimeInterval(-7 * 86400), sets: 1, 200, 5)
        ]
        #expect(try Self.model(HistoryFixtures.input(falling)).chart.delta == "−23 lb")
        let flat = [
            HistoryFixtures.session(2, Fixtures.now, sets: 1, 200, 5),
            HistoryFixtures.session(1, Fixtures.now.addingTimeInterval(-7 * 86400), sets: 1, 200, 5)
        ]
        let model = try Self.model(HistoryFixtures.input(flat))
        #expect(model.chart.delta == "0 lb")
        #expect(model.chart.bars.compactMap(\.number).count == 2 && model.chart.bars.last?.level == 100)
        #expect(try Self.model(HistoryFixtures.input(falling, units: .kg)).chart.delta == "−10 kg")
        #expect(try Self.model(HistoryFixtures.input(flat, units: .kg)).chart.delta == "0 kg")
    }

    @Test("12. The chart's spoken names, in pounds and in kilograms")
    func chart_spokenNames() throws {
        let pounds = try Self.model(HistoryFixtures.input([])).chart
        #expect([pounds.spokenTitle, pounds.weekAxis, pounds.valueAxis] == ["Estimated 1RM by week", "Week", "Pounds"])
        #expect(try Self.model(HistoryFixtures.input([], units: .kg)).chart.valueAxis == "Kilograms")
    }
}
