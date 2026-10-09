@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criteria 1, 6 and 8 (the brief's criterion 13): the header's model word for word, the progress
/// segments, and the words of the dialogs and the failures. The presentation is pure: every input is an
/// argument.
@Suite("WorkoutPresentation", .tags(.feature))
struct WorkoutPresentationTests {
    static let locale = Fixtures.locale

    static func header(_ state: WorkoutState, isBusy: Bool = false) -> WorkoutHeaderModel {
        WorkoutPresentation.header(state, isBusy: isBusy, locale: locale)
    }

    static func segments(_ lengths: [Int], _ states: [ProgressSegment.State]) -> [ProgressSegment] {
        zip(lengths, states).map { ProgressSegment(length: $0, state: $1) }
    }

    /// Upper A's set counts: bench 5, incline 3, row 4, pulldown 3, lateral raise 3.
    static let upperA = [5, 3, 4, 3, 3]

    @Test("A workout just started: its name, its start, every word of the header, and no segment done")
    func header_justStarted_isWordForWord() throws {
        let state = try Fixtures.seedSession()
        #expect(Self.header(state) == WorkoutHeaderModel(
            minimize: "Minimize",
            finish: "Finish",
            isEnabled: true,
            startedAt: Fixtures.now,
            elapsedLabel: "Elapsed time",
            title: "Upper A — Push focus",
            segments: Self.segments(Self.upperA, [.current, .upcoming, .upcoming, .upcoming, .upcoming]),
            progressLabel: "Workout progress",
            progressValue: "Exercise 1 of 5"
        ))
    }

    @Test("After the first exercise: its segment is done, the second is current, and the words say so")
    func header_secondExercise_marksTheFirstDone() throws {
        let state = try WorkoutPreview.minutes.workout()
        let header = Self.header(state)
        #expect(state.doneSets == 6)
        #expect(header.segments == Self.segments(Self.upperA, [.done, .current, .upcoming, .upcoming, .upcoming]))
        #expect(header.progressValue == "Exercise 2 of 5")
        #expect(header.startedAt == Fixtures.now, "the elapsed time counts from the start, whatever was logged")
    }

    @Test("In the closing superset an exercise with sets left is not done, and the current one is the cursor's")
    func header_inTheSuperset_followsTheCursor() throws {
        let state = try WorkoutPreview.hour.workout()
        let header = Self.header(state)
        #expect(state.doneSets == 15)
        #expect(state.checkedCursor == Cursor(exerciseIndex: 4, setIndex: 1))
        #expect(header.segments == Self.segments(Self.upperA, [.done, .done, .done, .upcoming, .current]))
        #expect(header.progressValue == "Exercise 5 of 5")
    }

    @Test("Segments are as long as each exercise's set count, an added set included (rule 36)")
    func segments_areAsLongAsTheSetCounts() throws {
        var state = try Fixtures.seedSession()
        state.exercises[1].sets.append(state.exercises[1].sets[0])
        #expect(Self.header(state).segments.map(\.length) == [5, 4, 4, 3, 3])
        #expect(Self.header(state).segments.map(\.length).reduce(0, +) == state.totalSets)
    }

    @Test("With every set logged every segment is done and none is current, though the cursor rests on a row")
    func segments_everySetLogged_areAllDone() throws {
        let state = try WorkoutPreview.logged(18, in: Fixtures.seedSession())
        #expect(state.doneSets == state.totalSets)
        #expect(state.checkedCursor != nil)
        #expect(Self.header(state).segments.map(\.state) == [.done, .done, .done, .done, .done])
        #expect(Self.header(state).progressValue.hasPrefix("Exercise "), "the words still name the cursor's exercise")
    }

    @Test("The cursor on a finished exercise while others are not: the first unfinished is current, and is named")
    func header_cursorOnAFinishedExercise_marksTheFirstUnfinished() throws {
        var state = try WorkoutPreview.minutes.workout()
        state.cursor = Cursor(exerciseIndex: 0, setIndex: 0)
        let header = Self.header(state)
        #expect(header.segments.map(\.state) == [.done, .current, .upcoming, .upcoming, .upcoming])
        #expect(header.progressValue == "Exercise 2 of 5")
        #expect(WorkoutPresentation.currentExercise(of: state.exercises, cursor: 3) == 3)
        #expect(WorkoutPresentation.currentExercise(of: state.exercises, cursor: nil) == nil)
        #expect(WorkoutPresentation.currentExercise(of: state.exercises, cursor: 9) == nil)
    }

    @Test("A finished exercise is done also when it is the current one; an exercise with no set is never done")
    func segments_doneWinsOverCurrent_andAnEmptyExerciseIsNeverDone() throws {
        var state = try WorkoutPreview.minutes.workout()
        #expect(WorkoutPresentation.segments(of: state.exercises, current: 0).map(\.state)
            == [.done, .upcoming, .upcoming, .upcoming, .upcoming])
        state.exercises[0].sets = []
        #expect(Self.header(state).segments[0] == ProgressSegment(length: 0, state: .upcoming))
        #expect(WorkoutPresentation.segments(of: state.exercises, current: 0)[0].state == .current)
        #expect(WorkoutPresentation.segments(of: [], current: nil).isEmpty)
    }

    @Test(
        "A cursor that names no row marks no segment and gives the progress no value",
        arguments: [nil, Cursor(exerciseIndex: 9, setIndex: 0), Cursor(exerciseIndex: 0, setIndex: 9)]
    )
    func header_cursorNamesNoRow_hasNoCurrentExercise(cursor: Cursor?) throws {
        var state = try WorkoutPreview.minutes.workout()
        state.cursor = cursor
        let header = Self.header(state)
        #expect(header.segments.map(\.state) == [.done, .upcoming, .upcoming, .upcoming, .upcoming])
        #expect(header.progressValue.isEmpty)
        #expect(header.progressLabel == "Workout progress")
    }

    @Test("Busy disables the header's buttons and changes nothing else")
    func header_busy_isDisabled() throws {
        let state = try Fixtures.seedSession()
        var expected = Self.header(state)
        #expect(expected.isEnabled)
        expected = WorkoutHeaderModel(
            minimize: expected.minimize, finish: expected.finish, isEnabled: false, startedAt: expected.startedAt,
            elapsedLabel: expected.elapsedLabel, title: expected.title, segments: expected.segments,
            progressLabel: expected.progressLabel, progressValue: expected.progressValue
        )
        #expect(Self.header(state, isBusy: true) == expected)
    }

    @Test("The screen is loading until a workout arrives, shows its header, and says when it cannot")
    func screen_followsTheLoadState() throws {
        struct Broken: Error {}
        let state = try Fixtures.seedSession()
        #expect(WorkoutPresentation.screen(.idle, isBusy: false, locale: Self.locale) == .loading)
        #expect(WorkoutPresentation.screen(.loading, isBusy: false, locale: Self.locale) == .loading)
        #expect(
            WorkoutPresentation.screen(.loaded(state), isBusy: false, locale: Self.locale)
                == .workout(WorkoutModel(header: Self.header(state)))
        )
        #expect(
            WorkoutPresentation.screen(.failed(Broken()), isBusy: false, locale: Self.locale)
                == .failed(WorkoutFailedModel(
                    title: "Couldn't open this workout",
                    message: "Close this screen and try again.",
                    close: "Close"
                ))
        )
    }
}
