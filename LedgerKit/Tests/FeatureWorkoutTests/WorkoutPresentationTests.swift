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

    @Test("The current exercise is current whatever its sets; an exercise with no set is never done")
    func segments_currentWins_andAnEmptyExerciseIsUpcoming() throws {
        var state = try WorkoutPreview.logged(18, in: Fixtures.seedSession())
        #expect(state.doneSets == state.totalSets)
        let current = try #require(state.checkedCursor?.exerciseIndex)
        var expected = [ProgressSegment.State](repeating: .done, count: 5)
        expected[current] = .current
        #expect(Self.header(state).segments.map(\.state) == expected)

        state.exercises[0].sets = []
        #expect(Self.header(state).segments[0] == ProgressSegment(length: 0, state: .upcoming))
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

    @Test("The two dialogs read as the brief writes them")
    func dialogs_areTheBriefs() {
        #expect(WorkoutPresentation.conflictDialog == WorkoutConflictDialogModel(
            title: "You have a workout in progress",
            resume: "Resume it",
            replace: "Discard and start new",
            cancel: "Cancel"
        ))
        #expect(WorkoutPresentation.finishDialog == WorkoutFinishDialogModel(
            title: "End workout?",
            discard: "Discard",
            keepLifting: "Keep lifting"
        ))
        #expect(WorkoutPresentation.discardFailedAlert == WorkoutAlertModel(
            title: "Couldn't discard this workout",
            message: "It's still in progress. Try again.",
            dismiss: "OK"
        ))
    }

    @Test("Every failure of the launcher has its title and its line, and says what is live afterwards", arguments: [
        (WorkoutLaunchFailure.notStarted(.emptyDay), "Couldn't start this workout", "This day has no exercises yet."),
        (.notStarted(.dayNotInProgram), "Couldn't start this workout", "This day is no longer in your program."),
        (.notStarted(.blockEnded), "Couldn't start this workout", "Your program's block has ended."),
        (.notStarted(.other), "Couldn't start this workout", "Nothing was changed. Try again."),
        (.notReplaced(.liveKept), "Couldn't start the new workout", "Your workout in progress was kept."),
        (.notReplaced(.nothingLive), "Couldn't start the new workout", "Your workout in progress was discarded."),
        (.notReplaced(.unknown), "Couldn't start the new workout", "Try again."),
        (.notOpened, "Couldn't open this workout", "Try again.")
    ])
    func alert_saysWhatFailedAndWhatIsLeft(failure: WorkoutLaunchFailure, title: String, message: String) {
        #expect(
            WorkoutPresentation.alert(for: failure) == WorkoutAlertModel(title: title, message: message, dismiss: "OK")
        )
    }
}
