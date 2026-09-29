import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · finished and discarded (rules 2, 10)", .tags(.domain))
struct ReduceTerminalTests {
    /// One of every event kind, as a late envelope would carry it.
    static let lateEvents: [WorkoutEvent] = [
        .started(EventBuilders.seedSession()),
        .exerciseSelected(exerciseIndex: 1, setIndex: 0),
        Engine.logged(0, 1, at: 500),
        .setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0)),
        .setTargetChanged(exerciseIndex: 0, setID: Engine.set(0, 1), weight: .pounds(200), reps: nil),
        .setAdded(
            exerciseIndex: 0,
            set: LoggedSet(id: SetID(EventBuilders.uuid(501)), weight: .zero, reps: .one, kind: .added)
        ),
        .allSetsRepeated(exerciseIndex: 0, weight: .pounds(100), reps: .one),
        .exerciseSwapped(
            exerciseIndex: 0,
            exerciseID: ExerciseID(EventBuilders.uuid(502)),
            name: "Dip",
            alsoUpdateProgram: true
        ),
        .restStarted(endsAt: Engine.at(600), total: .seconds(90)),
        .restExtended(amount: .seconds(30)),
        .restSkipped,
        .finished(endedAt: Engine.at(700)),
        .discarded(endedAt: Engine.at(700))
    ]

    @Test(
        "Criterion 6: after finished, every later envelope leaves the state unchanged with no effects",
        arguments: lateEvents
    )
    func criterion6_afterFinished_everythingIsIgnored(event: WorkoutEvent) throws {
        let (finished, _) = try Engine.run([Engine.logged(0, 0, at: 10), .finished(endedAt: Engine.at(300))])
        let (state, effects) = WorkoutEngine.reduce(finished, Engine.envelope(event, 500, from: Engine.watch, seq: 9))
        #expect(state == finished)
        #expect(effects.isEmpty)
    }

    @Test("Rule 2: after discarded, every later envelope is ignored too", arguments: lateEvents)
    func afterDiscarded_everythingIsIgnored(event: WorkoutEvent) throws {
        let (discarded, _) = try Engine.run([.discarded(endedAt: Engine.at(30))])
        let (state, effects) = WorkoutEngine.reduce(discarded, Engine.envelope(event, 500, seq: 9))
        #expect(state == discarded)
        #expect(effects.isEmpty)
    }

    @Test("Rule 10: finished ends the workout, stops the rest and materialises its final state")
    func finished_endsAndMaterializes() throws {
        let (state, effects) = try Engine.run([Engine.logged(0, 0, at: 10), .finished(endedAt: Engine.at(1800))])
        #expect(state.phase == .finished)
        #expect(state.endedAt == Engine.at(1800))
        #expect(state.rest == nil)
        #expect(effects.contains(.materialize(state)))
        #expect(effects.contains(.haptic(.workoutFinished)))
        #expect(effects.contains(.cancelRestNotification))
    }

    @Test("Rule 10: discarded ends the workout and drops its log")
    func discarded_endsAndDropsLog() throws {
        let (state, effects) = try Engine.run([Engine.logged(0, 0, at: 10), .discarded(endedAt: Engine.at(60))])
        #expect(state.phase == .discarded)
        #expect(state.endedAt == Engine.at(60))
        #expect(state.rest == nil)
        #expect(effects.contains(.discardLog))
        #expect(effects.contains(.cancelRestNotification))
        #expect(!effects.contains {
            if case .materialize = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test("The first terminal event wins: a finish after a discard is ignored")
    func firstTerminalWins() throws {
        let (state, _) = try Engine.run([.discarded(endedAt: Engine.at(10)), .finished(endedAt: Engine.at(20))])
        #expect(state.phase == .discarded)
        #expect(state.endedAt == Engine.at(10))
    }

    @Test("Rule 31: the summary freezes elapsed at the end and counts sets, volume and receipt rows")
    func summary_ofFinishedWorkout() throws {
        let (state, _) = try Engine.run([
            Engine.logged(0, 0, at: 10),
            Engine.logged(0, 1, pounds: 185, reps: 4, at: 20),
            .finished(endedAt: Engine.at(3480))
        ])
        let record = PersonalRecord(
            exerciseID: state.exercises[0].exerciseID,
            kind: .weightAtReps(.pounds(185), Reps(clamping: 5)),
            previous: nil,
            achievedAt: Engine.at(3480),
            workoutID: state.id
        )
        let summary = WorkoutEngine.summary(state, prs: [record])
        #expect(summary.workoutID == state.id)
        #expect(summary.elapsed == .seconds(3480))
        #expect(summary.doneSets == 2)
        #expect(summary.totalSets == 18)
        #expect(summary.volume == Volume(gramReps: Weight.pounds(185).grams * 9))
        #expect(summary.prs == [record])
        #expect(summary.rows.first == ReceiptRow(
            name: "Barbell Bench Press",
            target: "5 × 5 @ 185 lb",
            actual: ["185×5", "185×4"]
        ))
        #expect(summary.rows.count == 5)
    }

    @Test("A workout that has not ended has zero elapsed in its summary")
    func summary_ofLiveWorkout_hasZeroElapsed() throws {
        #expect(try WorkoutEngine.summary(Engine.live(), prs: []).elapsed == .zero)
    }

    @Test(
        "A decodable finish at an absurd or infinite time saturates the summary's elapsed instead of trapping",
        arguments: [1e21, .infinity, .nan]
    )
    func summary_ofCorruptEndedAt_saturatesElapsed(seconds: Double) throws {
        let (state, _) = try Engine.run([.finished(endedAt: Date(timeIntervalSinceReferenceDate: seconds))])
        let expected: Duration = seconds.isNaN ? .zero : .seconds(Double(Int64.max))
        #expect(WorkoutEngine.summary(state, prs: []).elapsed == expected)
    }

    @Test("Receipt rows use the units SessionBuilder snapshotted from Settings")
    func summary_usesSnapshottedUnits() throws {
        var settings = Settings.default
        settings.units = .kg
        let day = try Fixtures.upperB()
        let session = try SessionBuilder.build(
            program: Fixtures.program(days: [day]),
            weekIndex: 0,
            day: day,
            exercises: Fixtures.catalog,
            history: [:],
            settings: settings,
            id: EventBuilders.workoutID,
            device: Engine.phone,
            now: Engine.at(0)
        )
        #expect(session.units == .kg)
        let (state, _) = try Engine.run([.finished(endedAt: Engine.at(60))], on: session)
        #expect(WorkoutEngine.summary(state, prs: []).rows == [
            ReceiptRow(name: "Barbell Curl", target: "3 × 12 @ 35 kg", actual: ["—"])
        ])
    }
}
