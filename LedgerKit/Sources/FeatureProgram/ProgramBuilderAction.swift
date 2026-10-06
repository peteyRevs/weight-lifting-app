import LedgerDomain

/// What a tap on the builder means, as a value: the store applies it and decides nothing.
nonisolated enum ProgramBuilderAction: Hashable, Sendable {
    /// Select the week at this place in the block and drop the notice. Nothing is stored.
    case selectWeek(Int)
    /// Queue `edit`, then show `notice`; nil drops the one that is showing.
    case edit(ProgramBuilderEdit, notice: ProgramBuilderNotice? = nil)
    /// "+": draw a `WeekID`, queue `.addWeek` with it, select the week at `selecting` (the new one) and drop
    /// the notice.
    case addWeek(selecting: Int)
    /// "+ Add training day": draw a `DayTemplateID`, queue `.addDay` with it and `name`, drop the notice and
    /// emit `ProgramRoute.day` for the new day with `weekIndex`.
    case addDay(name: String, weekIndex: Int)
    /// Change nothing and show `notice`: a "−" the block refuses.
    case notice(ProgramBuilderNotice)
    /// Emit the route.
    case route(ProgramRoute)
}

/// One edit of the block, complete with its ids: exactly one `ProgramEditing` call. The store queues these
/// values and applies them to the stored program inside `ProgramRepository.update`.
///
/// `removeLastWeek`, `toggleDeload` and `cycleSchedule` are relative: applied twice they do not give what one
/// application gives, so each queued edit reaches the stored program exactly once. Every `week` is a place in
/// the block, 0 for the first.
nonisolated enum ProgramBuilderEdit: Hashable, Sendable {
    /// The name as typed; a blank one changes nothing.
    case renameProgram(String)
    case addWeek(WeekID)
    case removeLastWeek(loggedWeeks: Set<Int>)
    case toggleDeload(week: Int)
    case cycleSchedule(week: Int, weekday: Weekday)
    case copyPreviousWeek(week: Int)
    case applyToLaterWeeks(week: Int)
    case addDay(DayTemplateID, name: String)

    /// `program` after this edit. Only `removeLastWeek` throws; an edit that names a week or an id the
    /// program does not hold returns it unchanged, as `ProgramEditing` does.
    func applied(to program: Program) throws(ProgramEditError) -> Program {
        switch self {
        case let .renameProgram(name):
            ProgramEditing.renameProgram(program, to: name)
        case let .addWeek(id):
            ProgramEditing.addWeek(program, id: id)
        case let .removeLastWeek(loggedWeeks):
            try ProgramEditing.removeLastWeek(program, loggedWeeks: loggedWeeks)
        case let .toggleDeload(week):
            ProgramEditing.toggleDeload(program, week: week)
        case let .cycleSchedule(week, weekday):
            ProgramEditing.cycleSchedule(program, week: week, weekday: weekday)
        case let .copyPreviousWeek(week):
            ProgramEditing.copyPreviousWeek(program, week: week)
        case let .applyToLaterWeeks(week):
            ProgramEditing.applyToLaterWeeks(program, week: week)
        case let .addDay(id, name):
            ProgramEditing.addDay(program, id: id, name: name)
        }
    }
}

/// A line the builder shows under the block when an edit was refused or needs a word. The presentation turns
/// it into its text.
nonisolated enum ProgramBuilderNotice: Hashable, Sendable {
    /// "−" on a block of two weeks.
    case minimumTwoWeeks
    /// "−" on a last week that holds a finished workout; `weekNumber` counts from 1.
    case weekHasLoggedSessions(weekNumber: Int)
    /// A weekday was just assigned a day that has no exercise yet.
    case dayHasNoExercises

    /// The notice for an edit the Domain refused.
    init(_ error: ProgramEditError) {
        switch error {
        case .minimumTwoWeeks: self = .minimumTwoWeeks
        case let .weekHasLoggedSessions(weekNumber): self = .weekHasLoggedSessions(weekNumber: weekNumber)
        }
    }
}
