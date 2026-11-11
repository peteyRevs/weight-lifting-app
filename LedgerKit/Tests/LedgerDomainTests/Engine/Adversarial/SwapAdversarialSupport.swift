import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

// F10 S8a adversarial round 1 (G2): the swap event with its optional replacement. Every expected value is
// derived from the S8 plan ("The swap event's payload", criteria 3–8) and its rulings, never from the engine.

/// Builders for the swap suites: a session with drop sets, swaps, and the plan's re-target rule.
enum SwapAdv {
    /// Bench 5 × 5 @ 185 lb with a drop row, Incline DB 3 × 10 @ 55, Row 4 × 8 @ 70 with a drop row.
    static let specs: [EventBuilders.ExerciseSpec] = [
        .init("Barbell Bench Press", .barbell, sets: 5, reps: 5, pounds: 185, restSeconds: 150, dropSet: true),
        .init("Incline DB Press", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90),
        .init(
            "Chest-Supported Row",
            .machine,
            sets: 4,
            reps: 8,
            pounds: 70,
            restSeconds: 90,
            superset: true,
            dropSet: true
        )
    ]

    static func session() -> WorkoutState {
        EventBuilders.session(specs)
    }

    static func replacement(
        _ equipment: Equipment = .dumbbell,
        step: Weight = .pounds(2.5),
        load: Weight = .pounds(60),
        last: LastPerformance? = nil
    ) -> SwappedExercise {
        SwappedExercise(equipment: equipment, step: step, load: load, lastPerformance: last)
    }

    static func swap(
        _ index: Int,
        to number: Int = 0xA1,
        name: String = "Dumbbell Bench Press",
        program: Bool = false,
        _ replacement: SwappedExercise? = nil
    ) -> WorkoutEvent {
        .exerciseSwapped(
            exerciseIndex: index,
            exerciseID: ExerciseID(EventBuilders.uuid(0xEE00 + number)),
            name: name,
            alsoUpdateProgram: program,
            replacement: replacement
        )
    }

    /// The plan's rule, written from the payload section: the exercise takes id, name, equipment, step, last
    /// performance; target load becomes `load`; every undone set takes `load`, an undone drop set
    /// `load × 0.85` rounded to the step (ties away from zero); nothing else changes.
    static func expected(
        _ before: WorkoutExercise,
        id: ExerciseID,
        name: String,
        _ swap: SwappedExercise?
    ) -> WorkoutExercise {
        var after = before
        after.exerciseID = id
        after.name = name
        guard let swap else {
            return after
        }
        after.equipment = swap.equipment
        after.step = swap.step
        after.lastPerformance = swap.lastPerformance
        after.targetLoad = swap.load
        let count = (swap.load.grams * SwapAdv.dec("0.85") / swap.step.grams)
            .rounded(scale: 0, .toNearestOrAwayFromZero)
        let drop = Weight(grams: count * swap.step.grams)
        for index in after.sets.indices where after.sets[index].doneAt == nil {
            after.sets[index].weight = after.sets[index].kind == .drop ? drop : swap.load
        }
        return after
    }

    /// `state` after `events`, each reduced in turn on a log that begins with `started(state)`.
    static func fold(_ state: WorkoutState, _ events: [WorkoutEvent]) -> WorkoutState? {
        let log = EventBuilders.log(from: [.started(state)] + events)
        var current: WorkoutState?
        for envelope in log {
            current = WorkoutEngine.reduce(current, envelope).0
        }
        return current
    }

    static func weights(_ state: WorkoutState?) -> [Weight] {
        state?.exercises.flatMap { $0.sets.map(\.weight) + [$0.targetLoad, $0.step] } ?? []
    }

    /// `text` as an exact decimal (NaN when it is not one).
    static func dec(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    static func isWholeE7g(_ weight: Weight) -> Bool {
        guard weight.grams.isFinite else {
            return false
        }
        let units = weight.grams * 10_000_000
        return units.rounded(scale: 0, .toNearestOrEven) == units && abs(units) <= Decimal(Int64.max)
    }
}
