import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The set and rest screens' derivations (spec §4.3, §5.1; F18 criteria 2, 3 and 5, the pure halves), and the
/// connection line (F17 criterion 12, the watch's half).
@Suite("Watch set and rest presentation", .tags(.watch))
struct WatchSetPresentationTests {
    static let now = Fixtures.now

    static func ready(_ state: WorkoutState, _ input: WatchLiveInput = WatchSample.live()) throws -> WatchReadyModel {
        try #require(WatchPresentation.ready(state, at: now, input))
    }

    @Test("A fresh session shows its first set: label, name, weight in LB with a 5 lb step, reps, RPE, five dots")
    func ready_firstSet() throws {
        var state = try WatchSample.session()
        state.exercises[0].sets[0].weight = .pounds(185)
        let ready = try Self.ready(state, WatchSample.live(heartRate: 142))
        #expect(ready.setLabel == "SET 1 OF 5")
        #expect(ready.exerciseName == "Barbell Bench Press")
        #expect(ready.weight == "185" && ready.weightValue == 185 && ready.unit == "LB" && ready.step == 5)
        #expect(ready.reps == "× 5" && ready.repsValue == 5 && ready.target == "RPE 8")
        #expect(ready.dots == [false, false, false, false, false])
        #expect(ready.heartRate.value == "142" && ready.healthLine == nil && ready.connection == nil)
    }

    @Test("A superset's rows are labelled by their member's letter, in round order")
    func test_setLabel_supersetLetter() throws {
        // Upper A's pulldown (A, index 3) and lateral raise (B, index 4) are a superset of three rounds.
        let session = try WatchSample.session()
        var state = WatchSample.logging([(0, 0), (0, 1), (0, 2), (0, 3), (0, 4)], in: session)
        state.cursor = Cursor(exerciseIndex: 3, setIndex: 0)
        #expect(try Self.ready(state).setLabel == "A · SET 1 OF 3")
        state = WatchSample.logging([(3, 0)], in: state)
        state.cursor = Cursor(exerciseIndex: 4, setIndex: 0)
        #expect(try Self.ready(state).setLabel == "B · SET 1 OF 3")
        state = WatchSample.logging([(4, 0)], in: state)
        state.cursor = Cursor(exerciseIndex: 4, setIndex: 0)
        let second = try Self.ready(state)
        #expect(second.setLabel == "A · SET 2 OF 3", "the cursor's row is logged: the round's next open row")
        #expect(second.exerciseName == "Lat Pulldown")
        #expect(second.dots == [true, false, false])
    }

    @Test("A cursor on a finished exercise shows the first exercise with a set to log; every set logged shows the last")
    func ready_cursorOnALoggedRow() throws {
        let session = try WatchSample.session()
        var state = WatchSample.logging([(1, 0), (1, 1), (1, 2)], in: session)
        state.cursor = Cursor(exerciseIndex: 1, setIndex: 2)
        #expect(try Self.ready(state).exerciseName == "Barbell Bench Press")
        let rows = state.exercises.indices.flatMap { exercise in state.exercises[exercise].sets.indices.map { (
            exercise,
            $0
        ) } }
        state = WatchSample.logging(rows, in: state)
        let done = try Self.ready(state)
        #expect(done.exerciseName == "Incline DB Press" && done.setLabel == "SET 3 OF 3")
        #expect(WatchPresentation.nextLine(state, locale: Fixtures.locale) == "Next exercise")
        state.exercises = []
        state.cursor = nil
        #expect(WatchPresentation.ready(state, at: Self.now, WatchSample.live()) == nil)
    }

    @Test("In kilograms the unit reads KG, the weight is the kilogram value and a barbell steps by 2.5")
    func test_units_kgLabelsAndStep() throws {
        var state = try WatchSample.session(settings: Fixtures.settingsKg)
        state.exercises[0].sets[0].weight = .kilograms(Decimal(string: "82.5") ?? 0)
        let ready = try Self.ready(state)
        #expect(ready.unit == "KG" && ready.step == 2.5)
        #expect(ready.weight == "82.5" && ready.weightValue == Decimal(string: "82.5"))
        #expect(try Self.ready(WatchSample.session(settings: Fixtures.settingsKg)).step == 2.5)
        state.rest = RestTimer(endsAt: Self.now.addingTimeInterval(60), total: .seconds(90))
        #expect(WatchPresentation.nextLine(state, locale: Fixtures.locale) == "Next: 82.5 kg × 5")
    }

    @Test("Elapsed runs from the start while live and is frozen at the end once finished")
    func test_elapsed_frozenOnSummary() throws {
        var state = try WatchSample.session()
        #expect(WatchPresentation.elapsed(state, at: Self.now.addingTimeInterval(125)) == "2:05")
        #expect(try Self.ready(state).elapsed == "0:00")
        state.phase = .finished
        state.endedAt = Self.now.addingTimeInterval(1462)
        #expect(WatchPresentation.elapsed(state, at: Self.now.addingTimeInterval(7200)) == "24:22")
    }

    @Test("Heart rate: the sample's number; a dash with none yet, and with Health denied, which also asks once")
    func ready_heartRate() throws {
        let state = try WatchSample.session()
        #expect(try Self.ready(state).heartRate.value == "—")
        let denied = try Self.ready(state, WatchSample.live(heartRate: 150, health: .denied))
        #expect(denied.heartRate.value == "—" && denied.healthLine == "Allow Health in iPhone Settings")
        #expect(try Self.ready(state, WatchSample.live(heartRate: 98, health: .notDetermined)).heartRate.value == "98")
    }

    @Test("Rest: m:ss left, the ring 553 − 553 × remaining/total, the next set; GO at zero; +30s rescales the ring")
    func rest_clockRingAndNext() throws {
        var state = try WatchSample.session()
        state.exercises[0].sets[0].weight = .pounds(185)
        state.rest = RestTimer(endsAt: Self.now.addingTimeInterval(45), total: .seconds(90))
        let rest = try #require(state.rest)
        let input = WatchSample.live(heartRate: 131)
        let resting = try #require(WatchPresentation.rest(state, mode: .rest(rest), at: Self.now, input))
        #expect(resting.title == "REST" && resting.clock == "0:45" && resting.endsAt == rest.endsAt)
        #expect(resting.ringOffset == 276.5 && resting.heartRate == "131")
        #expect(resting.next == "Next: 185 lb × 5")
        let over = try #require(WatchPresentation.rest(state, mode: .restOver(rest), at: rest.endsAt, input))
        #expect(over.title == "GO" && over.clock == "0:00" && over.ringOffset == 553)
        let extended = RestTimer(endsAt: rest.endsAt.addingTimeInterval(30), total: .seconds(120))
        let longer = try #require(WatchPresentation.rest(state, mode: .rest(extended), at: Self.now, input))
        #expect(longer.ringOffset == 553 - 553 * 75 / 120 && longer.clock == "1:15")
        #expect(WatchPresentation.rest(state, mode: .ready, at: Self.now, input) == nil)
    }

    @Test("The iPhone line shows while reconnecting, and in solo once the phone was heard, on both live screens")
    func connectionLine_cases() throws {
        let line = "iPhone not connected — logging continues"
        let away: [(LiveConnectionState?, Bool)] = [(.reconnecting, false), (.reconnecting, true), (.solo, true)]
        let quiet: [(LiveConnectionState?, Bool)] = [
            (.solo, false), (.connected(.mirroring), true), (.degraded(.mirroring), true), (nil, false)
        ]
        let cases = away.map { ($0, line) } + quiet.map { ($0, String?.none) }
        var state = try WatchSample.session()
        state.rest = RestTimer(endsAt: Self.now.addingTimeInterval(45), total: .seconds(90))
        let rest = try #require(state.rest)
        for ((connection, heard), expected) in cases {
            let input = WatchSample.live(connection: connection, hasHeardPhone: heard)
            let label = "\(String(describing: connection)), heard \(heard)"
            #expect(WatchPresentation.connectionLine(connection, hasHeardPhone: heard) == expected, "\(label)")
            #expect(try Self.ready(state, input).connection == expected, "\(label)")
            #expect(WatchPresentation.rest(state, mode: .rest(rest), at: Self.now, input)?.connection == expected)
        }
    }
}
