#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureToday, one case each: the eight states of the screen, the off-schedule sheet, and
    /// two states that carry an open product question. Each is drawn from the model the presentation makes of a
    /// fixed input, so a preview shows the words the app would. `PreviewTests` render every case and fail on a
    /// `#Preview` that is not a case here; `TodaySnapshotTests` and `TodayAccessibilityTests` draw the same
    /// states' pages. None runs a task: the screen only draws.
    ///
    /// The program is spec §6.4's (`Fixtures.seedProgram()`), begun on Monday 2026-09-14, so that the tests' own
    /// moment, Wednesday 2026-09-16, is Lower A's day in week 1 (the brief's criterion 1).
    enum TodayPreview: String, CaseIterable {
        case upNext = "Up next"
        case resume = "Live workout"
        case logged = "Logged"
        case restDay = "Rest day"
        case offSchedule = "Off-schedule sheet"
        case noProgram = "No program"
        case blockComplete = "Block complete"
        case loading = "Loading"
        case failed = "Failed"
        /// Pete's decision 1: the title follows the calendar ("Rest day") over the card of the running workout.
        case resumeOnRestDay = "Live workout on a rest day"
        /// The first morning of a week: nothing moved yet, against a week that moved something ("−100%").
        case mondayVolume = "Monday, nothing moved yet"

        /// The moment the case shows, at 05:20 UTC like the tests' own.
        var now: Date {
            switch self {
            case .upNext, .resume, .logged, .noProgram, .loading, .failed: Fixtures.now
            case .restDay, .offSchedule, .resumeOnRestDay: Fixtures.date(2026, 9, 17, hour: 5, minute: 20)
            case .mondayVolume: Fixtures.date(2026, 9, 21, hour: 5, minute: 20)
            case .blockComplete: Fixtures.date(2026, 11, 11, hour: 5, minute: 20)
            }
        }

        /// What the screen is handed. A fixture that does not build shows as the failed state, and fails
        /// `PreviewTests`, which asks each case for its model.
        var state: Loadable<TodayModel> {
            switch self {
            case .loading: .loading
            case .failed: .failed(TodayPreviewData.Unreadable())
            // `try?`: the fixture's own error is of no use to a preview; the failed state shows that it broke.
            default: (try? model()).map(Loadable.loaded) ?? .failed(TodayPreviewData.Unreadable())
            }
        }

        /// The model of a loaded case.
        func model() throws -> TodayModel {
            try TodayPresentation.make(TodayPreviewData(now: now).input(for: self))
        }

        /// The screen in this state, its resume time standing still at the case's moment. The sheet's case
        /// draws the sheet alone, as it stands over the screen.
        @ViewBuilder var content: some View {
            // `try?`: a fixture that does not build falls through to the screen, which then shows "failed".
            if self == .offSchedule, case let .restDay(card)? = try? model().card {
                OffScheduleSheet(model: card.offSchedule, onPick: { _ in }, onCancel: {})
            } else {
                TodayScreen(state: state) { _ in }
                    .environment(\.todayTimerPause, now)
            }
        }
    }

    /// The fixed inputs of the previews: the program, the catalog's exercises and a few workouts around `now`.
    nonisolated struct TodayPreviewData {
        /// Stands for whatever kept Today's data from being read.
        struct Unreadable: Error {}

        /// The four days of the seed program, by their place in `Program.days`.
        enum Day: Int {
            case upperA, lowerA, upperB, lowerB
        }

        let now: Date
        let program: Program
        let exercises: [ExerciseID: Exercise]

        init(now: Date) throws {
            self.now = now
            var seed = try Fixtures.seedProgram()
            seed.startDate = try Self.blockStart()
            program = seed
            exercises = try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
        }

        static func blockStart() throws -> CivilDate {
            guard let start = CivilDate(year: 2026, month: 9, day: 14) else {
                throw Unreadable()
            }
            return start
        }

        /// The input of `preview` at `now`: this week's finished workouts, the recent ones, last week's volume
        /// and the session, as the store would have read them.
        func input(for preview: TodayPreview) throws -> TodayInput {
            var input = TodayInput(
                program: preview == .noProgram ? nil : program,
                exercises: exercises,
                settings: Fixtures.settingsLb,
                now: now,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale
            )
            let monday = try finished(1, .upperA, on: 14, minutes: 58)
            let wednesday = try finished(2, .lowerA, on: 16, minutes: 52)
            let friday = try finished(3, .upperB, on: 18, minutes: 61)
            switch preview {
            case .noProgram, .loading, .failed:
                break
            case .upNext, .resume, .logged:
                input.weekWorkouts = [monday]
                input.previousWeekVolume = Self.pounds(preview == .logged ? 39500 : 11340)
                if preview == .resume {
                    input.session = try live(4, .lowerA, secondsAgo: 180)
                }
                if preview == .logged {
                    // Today's Lower A, started two hours ago and finished in 24:22.
                    let today = try finishing(live(4, .lowerA, secondsAgo: 7200), after: 24 * 60 + 22)
                    input.weekWorkouts.append(today)
                }
            case .restDay, .offSchedule, .resumeOnRestDay:
                input.weekWorkouts = [wednesday, monday]
                input.previousWeekVolume = Self.pounds(41600)
                if preview == .resumeOnRestDay {
                    input.session = try live(4, .lowerB, secondsAgo: 12 * 60 + 40)
                }
            case .mondayVolume:
                input.recentWorkouts = [friday, wednesday, monday]
                input.previousWeekVolume = [friday, wednesday, monday].map(\.volume).reduce(.zero, +)
            case .blockComplete:
                // One more session in the week after the block's last: sessions done over none planned.
                input.weekWorkouts = try [finished(5, .lowerA, week: 7, month: 11, on: 9, minutes: 47)]
            }
            if preview != .mondayVolume {
                input.recentWorkouts = input.weekWorkouts.sorted { $0.startedAt > $1.startedAt }
            }
            return input
        }

        private static func pounds(_ pounds: Decimal) -> Volume {
            Volume(weight: .pounds(pounds), reps: .one)
        }

        /// The workout `SessionBuilder` builds for `day` in program week `week`, started at `start`.
        private func workout(_ number: Int, _ day: Day, week: Int, startedAt start: Date) throws -> WorkoutState {
            try SessionBuilder.build(
                program: program,
                weekIndex: week,
                day: program.days[day.rawValue],
                exercises: exercises,
                history: [:],
                settings: Fixtures.settingsLb,
                id: WorkoutID(Fixtures.uuid(number)),
                device: Fixtures.deviceID,
                now: start
            )
        }

        /// A workout of week 1 that started `secondsAgo` and is still running.
        private func live(_ number: Int, _ day: Day, secondsAgo: Int) throws -> WorkoutState {
            try workout(number, day, week: 0, startedAt: moment(-secondsAgo, from: now))
        }

        /// The moment `seconds` after `date`, counted by the fixtures' calendar.
        private func moment(_ seconds: Int, from date: Date) throws -> Date {
            guard let moment = Fixtures.calendar.date(byAdding: .second, value: seconds, to: date) else {
                throw Unreadable()
            }
            return moment
        }

        /// A workout that started at 07:00 UTC on a day of 2026 and was finished, every set done, in `minutes`.
        private func finished(
            _ number: Int,
            _ day: Day,
            week: Int = 0,
            month: Int = 9,
            on dayOfMonth: Int,
            minutes: Int
        ) throws -> WorkoutState {
            let start = Fixtures.date(2026, month, dayOfMonth, hour: 7)
            return try finishing(workout(number, day, week: week, startedAt: start), after: minutes * 60)
        }

        /// `workout` with every set done as prescribed, finished `seconds` after it started.
        private func finishing(_ workout: WorkoutState, after seconds: Int) throws -> WorkoutState {
            var done = workout
            for exercise in done.exercises.indices {
                for set in done.exercises[exercise].sets.indices {
                    done.exercises[exercise].sets[set].doneAt = workout.startedAt
                }
            }
            done.cursor = nil
            done.phase = .finished
            done.endedAt = try moment(seconds, from: workout.startedAt)
            return done
        }
    }

    #Preview("Up next") {
        TodayPreview.upNext.content
    }

    #Preview("Live workout") {
        TodayPreview.resume.content
    }

    #Preview("Logged") {
        TodayPreview.logged.content
    }

    #Preview("Rest day") {
        TodayPreview.restDay.content
    }

    #Preview("Off-schedule sheet") {
        TodayPreview.offSchedule.content
    }

    #Preview("No program") {
        TodayPreview.noProgram.content
    }

    #Preview("Block complete") {
        TodayPreview.blockComplete.content
    }

    #Preview("Loading") {
        TodayPreview.loading.content
    }

    #Preview("Failed") {
        TodayPreview.failed.content
    }

    #Preview("Live workout on a rest day") {
        TodayPreview.resumeOnRestDay.content
    }

    #Preview("Monday, nothing moved yet") {
        TodayPreview.mondayVolume.content
    }

#endif
