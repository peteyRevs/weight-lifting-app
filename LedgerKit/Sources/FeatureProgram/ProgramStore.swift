import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// A route on its way to the app: `ProgramRoot`'s `.task(id:)` hands it on. The number tells one tap from
/// the next when both ask for the same route.
nonisolated struct ProgramPendingRoute: Hashable, Sendable {
    let number: Int
    let route: ProgramRoute
}

/// The store of the Program builder (F11 S13; the M1 store convention): the program as the edit session shows
/// it, the selected week, the notice and the route waiting for the app.
///
/// **Intents are synchronous and decide nothing.** Each action is applied as `ProgramBuilderAction` says:
/// an edit is queued on the session, which applies it to the program on screen before `send` returns, so the
/// next tap is taken from a model that holds it (two quick "+" add two weeks). Ids are drawn from `\.uuid`
/// once, at the tap. No clamp and no rule of the block is here: the presentation and `ProgramEditing` decide.
///
/// **The name** is applied as it is typed: the field's draft is the view's, and each keystroke sends the
/// whole text. A name changed elsewhere while the field is being edited is therefore overwritten by the next
/// keystroke; the lifter's text wins.
///
/// **Work** runs from `ProgramRoot`'s tasks: `run()` follows the sources (`+Sources`), `save()` runs the
/// session's loop. A write that fails says so in the notice's line and is logged; one that leaves out the
/// last week because a workout was finished in it since the tap says that instead (the whole write is
/// dropped: the lifter sees the stored program).
///
/// **Making one does nothing.** `ProgramRoot` makes a store each time SwiftUI makes the root and `@State`
/// keeps the first, so the initializer stays empty.
@MainActor @Observable
final class ProgramStore {
    /// What the root draws.
    enum State: Equatable {
        case loading
        case loaded(ProgramBuilderModel)
        /// No program is active.
        case noProgram
        /// A source ended or could not be read.
        case failed
    }

    let session = ProgramEditSession<ProgramBuilderEdit>()
    private(set) var notice: ProgramBuilderNotice?
    /// The selected week's place, raw: the presentation reads a place outside the block as the nearest week.
    /// Nil until the program first arrives, unless a week was asked for.
    private(set) var selectedWeek: Int?
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: ProgramPendingRoute?
    /// The Day editor's route for a day just added, until the write that holds the day has returned.
    private(set) var routeAfterSave: ProgramRoute?

    // What the sources last said (`+Sources`); each nil until it has spoken, and kept across runs.
    var settings: Settings?
    var exercises: [ExerciseID: Exercise]?
    var loggedWeeks: Set<Int>?
    /// A source ended or a read failed in this run.
    var hasFailed = false

    @ObservationIgnored private var routeNumber = 0

    @ObservationIgnored @Dependency(\.programRepository) var programs
    @ObservationIgnored @Dependency(\.settingsRepository) var settingsRepository
    @ObservationIgnored @Dependency(\.exerciseRepository) var exerciseRepository
    @ObservationIgnored @Dependency(\.workoutRepository) var workouts
    @ObservationIgnored @Dependency(\.date) var date
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.calendar) var calendar
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8).
    var logger: LedgerLogger {
        injectedLogger.category("program")
    }

    /// The model, made from what is known now: before any intent returns, it holds that intent's edit.
    var state: State {
        guard !hasFailed else {
            return .failed
        }
        guard session.hasHeard, let settings, let exercises, let loggedWeeks else {
            return .loading
        }
        guard let program = session.shown else {
            return .noProgram
        }
        return .loaded(ProgramPresentation.make(ProgramBuilderInput(
            program: program,
            exercises: exercises,
            settings: settings,
            selectedWeek: selectedWeek ?? 0,
            loggedWeeks: loggedWeeks,
            notice: notice,
            calendar: calendar,
            locale: locale
        )))
    }

    // MARK: Intents

    func send(_ action: ProgramBuilderAction) {
        switch action {
        case let .selectWeek(place):
            selectedWeek = place
            notice = nil
        case let .edit(edit, notice):
            session.enqueue(edit)
            self.notice = notice
        case .addWeek:
            addWeek()
        case let .addDay(name, weekIndex):
            addDay(named: name, weekIndex: weekIndex)
        case let .notice(notice):
            self.notice = notice
        case let .route(route):
            emit(route)
        }
    }

    /// Selects the week at `place`, as asked for by Today's "Edit week" or, on the first program, the week
    /// that holds today.
    func select(week place: Int) {
        selectedWeek = place
        notice = nil
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (ProgramRoute) -> Void) {
        guard let pending = pendingRoute else {
            return
        }
        handler(pending.route)
        pendingRoute = nil
    }

    /// "+": the new week is selected, found by its id in the program the edit was applied to.
    private func addWeek() {
        let id = WeekID(uuid())
        notice = nil
        guard session.enqueue(.addWeek(id)), let place = session.shown?.weeks.firstIndex(where: { $0.id == id })
        else {
            return
        }
        selectedWeek = place
    }

    /// "+ Add training day": the day is queued now and the Day editor's route waits for the write that holds
    /// it, so the editor never opens on a day that is not stored. While a route waits, a tap adds nothing.
    private func addDay(named name: String, weekIndex: Int) {
        guard pendingRoute == nil, routeAfterSave == nil else {
            return
        }
        let id = DayTemplateID(uuid())
        notice = nil
        if session.enqueue(.addDay(id, name: name)) {
            routeAfterSave = .day(id, weekIndex: weekIndex)
        }
    }

    /// One route waits at a time: a tap that comes before the app was handed the one before is dropped.
    private func emit(_ route: ProgramRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = ProgramPendingRoute(number: routeNumber, route: route)
    }

    // MARK: Saving

    /// Runs the session's loop for as long as the root's task runs.
    func save() async {
        await session.run(prepare: prepared, finished: saved)
    }

    /// A write that removes the last week checks it against the workouts as they are now, read just before
    /// the write, not as they were when "−" was tapped.
    private func prepared(_ edits: [ProgramBuilderEdit]) async throws -> [ProgramBuilderEdit] {
        guard let program = session.stored, edits.contains(where: \.removesTheLastWeek) else {
            return edits
        }
        let fresh = try await readLoggedWeeks(of: program)
        loggedWeeks = fresh
        return edits.map { $0.removesTheLastWeek ? .removeLastWeek(loggedWeeks: fresh) : $0 }
    }

    private func saved(_ outcome: ProgramEditSession<ProgramBuilderEdit>.Outcome) {
        switch outcome {
        case .stored:
            // The new day may still wait behind this write, if it was added while the write ran.
            guard let route = routeAfterSave, case let .day(id, _) = route,
                  session.stored?.days.contains(where: { $0.id == id }) == true
            else {
                return
            }
            routeAfterSave = nil
            emit(route)
        case let .failed(error as ProgramEditError):
            routeAfterSave = nil
            notice = ProgramBuilderNotice(error)
        case let .failed(error):
            routeAfterSave = nil
            notice = .saveFailed
            logger.log.error("A change to the program was not saved: \(String(describing: error), privacy: .public)")
        }
    }
}

private nonisolated extension ProgramBuilderEdit {
    var removesTheLastWeek: Bool {
        if case .removeLastWeek = self {
            return true
        }
        return false
    }
}
