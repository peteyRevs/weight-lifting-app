import Dependencies
@testable import FeatureToday
@testable import FeatureWorkout
import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

// F09 S5 adversarial round 1 (G2): the app `TodayWiringAdversarialTests` drives, and what it reads of Today's
// model.

extension TodayWiringAdversarialTests {
    /// Today, the router and the launcher of one app, over the seed program (8 weeks from Monday 2026-08-17).
    @MainActor
    struct App {
        let stores: InMemoryStores
        let fake: FakeWorkoutSessionClient
        let today: TodayStore
        let router: AppRouter
        let launcher: WorkoutLauncher

        init(now: Date = Fixtures.now, hasProgram: Bool = true, finished: [WorkoutState] = []) throws {
            let memory = try InMemoryStores(seed: InMemoryStores.Seed(
                catalog: ExerciseCatalog.seed(),
                programs: hasProgram ? [Fixtures.seedProgram()] : [],
                workouts: finished,
                settings: Fixtures.settingsLb
            ))
            let session = FakeWorkoutSessionClient()
            stores = memory
            fake = session
            (today, router, launcher) = withTestDependencies {
                $0.exerciseRepository = memory.exercises
                $0.programRepository = memory.programs
                $0.workoutRepository = memory.workouts
                $0.workoutEventStore = memory.events
                $0.settingsRepository = memory.settings
                $0.statsQueries = memory.stats
                $0.workoutSession = session
                $0.deviceID = Fixtures.deviceID
                $0.date = .constant(now)
            } operation: {
                (TodayStore(), AppRouter(), WorkoutLauncher())
            }
        }

        var model: TodayModel? {
            if case let .loaded(model) = today.state {
                return model
            }
            return nil
        }

        /// The store running, once it shows a model for which `holds`.
        func running() async -> Task<Void, Never> {
            let task = Task { await today.run() }
            for await isThere in Observations({ model != nil }) where isThere {
                break
            }
            return task
        }

        /// A tap on a control that carries `route`: the store keeps it, the root hands it on, the app
        /// resolves it, and the cover's task answers the launcher's request.
        func tap(_ route: TodayRoute) async {
            today.send(route)
            today.deliverRoute { router.resolve($0, workout: launcher) }
            await launcher.run()
        }

        /// How many workouts the session was asked to start.
        func starts() async -> Int {
            await fake.applied.count { event in
                if case .started = event {
                    return true
                }
                return false
            }
        }
    }

    /// Every route the model's controls carry, with the control's name.
    static func routes(of model: TodayModel) -> [(String, TodayRoute)] {
        var found = [("the gear", model.header.settings.route)]
        switch model.card {
        case let .upNext(card):
            found.append(("the card's button", card.action.action.route))
        case let .logged(card):
            found.append(("the card's button", card.action.route))
        case let .restDay(card):
            found.append(("Edit week", card.editWeek.route))
            found += card.offSchedule.days.map { ("the sheet's \($0.name)", $0.route) }
        case let .noProgram(card), let .blockComplete(card):
            found.append(("the card's button", card.action.route))
        }
        return found + model.recent.rows.map { ("a recent row", $0.route) }
    }

    /// A finished Lower A of week 5, started today.
    static func finishedToday() throws -> WorkoutState {
        let program = try Fixtures.seedProgram()
        var workout = try SessionBuilder.build(
            program: program,
            weekIndex: 4,
            day: program.days[1],
            exercises: Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first },
            history: [:],
            settings: Fixtures.settingsLb,
            id: WorkoutID(Fixtures.uuid(77)),
            device: Fixtures.deviceID,
            now: Fixtures.now.addingTimeInterval(-7200)
        )
        for exercise in workout.exercises.indices {
            for set in workout.exercises[exercise].sets.indices {
                workout.exercises[exercise].sets[set].doneAt = workout.startedAt
            }
        }
        workout.cursor = nil
        workout.phase = .finished
        workout.endedAt = workout.startedAt.addingTimeInterval(3000)
        return workout
    }

    /// The states a test can make from the stores and the clock, by the card each shows.
    nonisolated static let states = ["noProgram", "upNext", "restDay", "logged", "blockComplete"]

    static func app(showing state: String) throws -> App {
        switch state {
        case "noProgram": try App(hasProgram: false)
        case "restDay": try App(now: Fixtures.date(2026, 9, 17, hour: 12))
        case "logged": try App(finished: [finishedToday()])
        case "blockComplete": try App(now: Fixtures.date(2026, 10, 20, hour: 12))
        default: try App()
        }
    }

    static func kind(_ card: TodayModel.Card) -> String {
        switch card {
        case .upNext: "upNext"
        case .logged: "logged"
        case .restDay: "restDay"
        case .noProgram: "noProgram"
        case .blockComplete: "blockComplete"
        }
    }
}

extension TodayModel.Card {
    /// The button of the up-next card, start or resume.
    var upNextAction: TodayModel.Action? {
        if case let .upNext(card) = self {
            return card.action.action
        }
        return nil
    }
}

extension TodayModel {
    var restDayCard: TodayModel.RestDay? {
        if case let .restDay(card) = card {
            return card
        }
        return nil
    }
}
