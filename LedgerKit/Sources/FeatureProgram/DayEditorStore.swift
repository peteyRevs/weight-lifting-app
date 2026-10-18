import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// The store of the Day editor (F11 S14, criteria 15 to 19): one day of the active program, fixed when the
/// app pushes the editor, with the week the builder had selected; the program as its own edit session shows
/// it; the open panel; the library sheet's store; the route waiting for the app.
///
/// **Intents are synchronous and decide nothing.** Each action is applied as `DayEditorAction` says. An edit
/// is queued on the session, which applies it to the program on screen before `send` returns, and the model
/// is made from that program whenever it is read: a stepper's edit carries the value the model was made
/// with, so two quick taps on "+" are two steps. `.open` sets the open panel, which needs no repair (a slot
/// the day no longer holds reads as none open). The name is applied as typed, as the builder's is.
///
/// **Leaving waits for the write.** "Done", "Program" and the day being gone (after "Delete", or deleted
/// elsewhere) hand the app `.closeDay` once, and only once no edit waits and no write runs, so nothing the
/// lifter did is cut off by the editor closing. The day is judged gone only once the store has said which
/// program is active. A write that fails drops every waiting edit and the close with them; the editor shows
/// the program as stored and says so in an alert (Pete's question 1, A: `showsSaveFailure`). The system's
/// swipe back pops at once: a write then in flight is cancelled whole and stores nothing (ruling R5).
///
/// **Making one does nothing** but keep its day, its week and its two parts: `@State` keeps the first.
@MainActor @Observable
final class DayEditorStore {
    /// What the root draws.
    enum State: Equatable {
        case loading
        case editing(DayEditorModel.Content)
        /// The program no longer holds the day: nothing is drawn while the editor closes.
        case dayIsGone
        /// A source ended.
        case failed
    }

    let day: DayTemplateID
    /// The week shown, as the builder had it selected.
    let weekIndex: Int
    let session = ProgramEditSession<DayEditorEdit>()
    /// The library sheet's store: it lives as long as the editor, so its chips are kept between openings.
    let library: ExercisePickerStore
    private(set) var openSlot: SlotID?
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: ProgramPendingRoute?
    /// "Done" or "Program" was tapped: the editor closes once nothing waits to be stored.
    private(set) var isClosing = false
    /// A write failed: the root's alert is up until its "OK" (Pete's question 1, A).
    var showsSaveFailure = false

    /// What the sources last said (`+Sources`); each nil until it has spoken, and kept across runs. These four
    /// are written by the sources' extension in its own file, so they are not `private(set)`; nothing outside
    /// the store writes them.
    /// The settings, whose units every load is shown and stepped in.
    var settings: Settings?
    /// The exercises as the store lists them, for the library, and by id, for the day.
    var exercises: [Exercise]?
    var exercisesByID: [ExerciseID: Exercise]?
    /// An observation ended in this run.
    var hasEnded = false

    @ObservationIgnored private var hasClosed = false
    @ObservationIgnored private var routeNumber = 0

    @ObservationIgnored @Dependency(\.programRepository) var programs
    @ObservationIgnored @Dependency(\.settingsRepository) var settingsRepository
    @ObservationIgnored @Dependency(\.exerciseRepository) var exerciseRepository
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8).
    var logger: LedgerLogger {
        injectedLogger.category("program")
    }

    init(day: DayTemplateID, weekIndex: Int) {
        self.day = day
        self.weekIndex = weekIndex
        library = ExercisePickerStore(day: day, session: session)
    }

    /// The model, made from what is known now: before any intent returns, it holds that intent's edit.
    var state: State {
        guard !hasEnded else {
            return .failed
        }
        guard session.hasHeard, let settings, let exercisesByID else {
            return .loading
        }
        guard let program = session.shown else {
            return .dayIsGone
        }
        let model = DayEditorPresentation.make(DayEditorInput(
            program: program,
            day: day,
            exercises: exercisesByID,
            settings: settings,
            weekIndex: weekIndex,
            openSlot: openSlot,
            locale: locale
        ))
        switch model {
        case let .editing(content):
            return .editing(content)
        case .dayIsGone:
            return .dayIsGone
        }
    }

    /// The library sheet's model, once the exercises are known.
    var libraryModel: ExercisePickerModel? {
        exercises.map { library.model(exercises: $0) }
    }

    // MARK: Intents

    func send(_ action: DayEditorAction) {
        switch action {
        case let .open(slot):
            openSlot = slot
        case let .edit(edit, closesPanel):
            session.enqueue(edit)
            if closesPanel {
                openSlot = nil
            }
        case .openLibrary:
            library.isShown = true
        case .route(.closeDay):
            isClosing = true
        case let .route(route):
            emit(route)
        }
        closeIfDone()
    }

    /// The library sheet's actions; "Add" queues its slots on this editor's session.
    func send(_ action: ExercisePickerAction) {
        guard let exercisesByID, let settings else {
            return
        }
        library.send(action, exercises: exercisesByID, settings: settings)
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (ProgramRoute) -> Void) {
        guard let pending = pendingRoute else {
            return
        }
        handler(pending.route)
        pendingRoute = nil
    }

    // MARK: Saving

    /// Runs the session's loop for as long as the root's task runs.
    func save() async {
        await session.run(finished: saved)
    }

    private func saved(_ outcome: ProgramEditSession<DayEditorEdit>.Outcome) {
        if case let .failed(error) = outcome {
            isClosing = false
            showsSaveFailure = true
            logger.log.error("A change to a day was not saved: \(String(describing: error), privacy: .public)")
        }
        closeIfDone()
    }

    // MARK: Closing

    /// Whether the program the editor shows no longer holds its day, once the store has said which is active.
    private var isDayGone: Bool {
        session.hasHeard && session.shown?.days.contains { $0.id == day } != true
    }

    /// Emits `.closeDay`, once, when the editor was asked to close or its day is gone, and nothing waits to
    /// be stored.
    func closeIfDone() {
        guard !hasClosed, isClosing || isDayGone, session.isIdle else {
            return
        }
        hasClosed = true
        emit(.closeDay)
    }

    /// One route waits at a time.
    private func emit(_ route: ProgramRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = ProgramPendingRoute(number: routeNumber, route: route)
    }
}
