@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4 criterion 8 and the brief's criterion 13 (rule 36): the header's model. One segment per
/// exercise, as long as its set count, done / current / remaining; the words that go with it.
@MainActor
@Suite("Workout header (adversarial)", .tags(.feature))
struct WorkoutHeaderAdversarialTests {
    typealias Spec = EventBuilders.ExerciseSpec

    func specs(_ sets: [Int]) -> [Spec] {
        sets.enumerated().map { Spec(
            "Exercise \($0.offset)",
            .barbell,
            sets: $0.element,
            reps: 5,
            pounds: 100,
            restSeconds: 60
        ) }
    }

    /// The workout after logging the first `count` rows in order, as the engine leaves it.
    func logged(_ count: Int, of sets: [Int]) async throws -> WorkoutState {
        var state = EventBuilders.session(specs(sets))
        let session = FakeWorkoutSessionClient(live: state)
        var left = count
        for (exercise, rows) in sets.enumerated() {
            for row in 0 ..< rows where left > 0 {
                let set = state.exercises[exercise].sets[row]
                state = try await session.apply(
                    .setLogged(
                        exerciseIndex: exercise,
                        setID: set.id,
                        weight: set.weight,
                        reps: set.reps,
                        doneAt: EventBuilders.start
                    )
                )
                left -= 1
            }
        }
        return state
    }

    func picture(_ state: WorkoutState) -> String {
        WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale).segments
            .map { "\($0.length)\($0.state == .done ? "d" : $0.state == .current ? "c" : "u")" }
            .joined(separator: " ")
    }

    @Test("None done: the first exercise is current, the rest remain, each as long as its set count")
    func segments_noneDone() async throws {
        let state = try await logged(0, of: [5, 3, 4, 2])
        #expect(picture(state) == "5c 3u 4u 2u")
        let header = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale)
        #expect(header.progressValue == "Exercise 1 of 4")
        #expect(header.progressLabel == "Workout progress")
    }

    @Test("Some done: finished exercises are done, the cursor's is current")
    func segments_someDone() async throws {
        let early = try await logged(2, of: [5, 3, 4, 2])
        #expect(picture(early) == "5c 3u 4u 2u")
        let state = try await logged(6, of: [5, 3, 4, 2])
        #expect(state.checkedCursor?.exerciseIndex == 1, "the engine's cursor: \(String(describing: state.cursor))")
        #expect(picture(state) == "5d 3c 4u 2u")
        #expect(WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale)
            .progressValue == "Exercise 2 of 4")
    }

    @Test("All done: every segment is done (the planner's rule: \"done when every set is done\")")
    func segments_allDone() async throws {
        let state = try await logged(14, of: [5, 3, 4, 2])
        #expect(state.exercises.flatMap(\.sets).allSatisfy { $0.doneAt != nil })
        #expect(picture(state) == "5d 3d 4d 2d", "the cursor rests on \(String(describing: state.cursor))")
    }

    @Test("A finished exercise after the cursor is done; an unfinished one before it remains")
    func segments_outOfOrder() async throws {
        var state = EventBuilders.session(specs([2, 2, 2]))
        let session = FakeWorkoutSessionClient(live: state)
        for row in 0 ..< 2 {
            let set = state.exercises[2].sets[row]
            state = try await session.apply(
                .setLogged(
                    exerciseIndex: 2,
                    setID: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    doneAt: EventBuilders.start
                )
            )
        }
        state = try await session.apply(.exerciseSelected(exerciseIndex: 1, setIndex: 0))
        #expect(state.checkedCursor?.exerciseIndex == 1)
        #expect(picture(state) == "2u 2c 2d")
    }

    @Test("No exercises: no segment, and nothing to speak")
    func segments_noExercises() {
        let state = EventBuilders.session([])
        let header = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale)
        #expect(header.segments.isEmpty)
        #expect(header.progressValue.isEmpty)
        #expect(header.title == state.name)
    }

    @Test("Many exercises: one segment each, lengths the set counts, exactly one current")
    func segments_manyExercises() async throws {
        let sets = (0 ..< 120).map { $0 % 7 + 1 }
        let state = try await logged(0, of: sets)
        let segments = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale).segments
        #expect(segments.map(\.length) == sets)
        #expect(segments.count { $0.state == .current } == 1)
        #expect(WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale)
            .progressValue == "Exercise 1 of 120")
    }

    @Test("A cursor that names no row marks nothing current and speaks no value", arguments: [
        Cursor(exerciseIndex: 9, setIndex: 0), Cursor(exerciseIndex: 0, setIndex: 99), Cursor(
            exerciseIndex: -1,
            setIndex: 0
        )
    ])
    func segments_cursorOutOfRange(cursor: Cursor) {
        var state = EventBuilders.session(specs([3, 3]))
        state.cursor = cursor
        let header = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale)
        #expect(header.segments.count { $0.state == .current } == 0)
        #expect(header.progressValue.isEmpty)
    }
}
