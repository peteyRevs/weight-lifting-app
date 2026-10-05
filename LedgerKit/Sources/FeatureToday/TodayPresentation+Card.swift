import Foundation
import LedgerDomain

/// Which card Today shows, and what each card says.
///
/// The first of these that holds decides: a live workout (Up next, with Resume); no program; the block is
/// complete; today's session was finished today (Logged); a session is scheduled today (Up next, with Start);
/// otherwise a rest day, which a day before the block begins is too. `day(_:)` reads the calendar's part, and
/// the two rules below are the two product questions still open: each is one function, so the other answer is a
/// change in one place.
nonisolated extension TodayPresentation {
    static func card(_ day: Day, _ context: Context) -> TodayModel.Card {
        if let live = workoutTakingOver(context) {
            return .upNext(upNext(resuming: live, context))
        }
        switch day {
        case .noProgram:
            return .noProgram(noProgram())
        case let .blockComplete(block):
            return .blockComplete(blockComplete(block.program, context.input.locale))
        case let .session(block, session):
            if let workout = loggedWorkout(for: session, context) {
                return .logged(logged(workout, session, block, context))
            }
            return .upNext(upNext(session, context.input))
        case let .rest(block):
            return .restDay(restDay(block, context))
        }
    }

    /// The workout that takes over the card: the session's workout while it is live, whichever day it was
    /// started for, also on a rest day, after the block and without a program, so that Today never offers
    /// "Start workout" while a workout runs and always leads back to it (Pete's decision 1, default A).
    ///
    /// The other answer, the prototype's, keeps the calendar's card and resumes only today's own session: it
    /// would return the workout only on a `.session` day whose session `SessionBuilder.resumable` accepts.
    static func workoutTakingOver(_ context: Context) -> WorkoutState? {
        context.input.session?.phase == .live ? context.input.session : nil
    }

    /// The finished workout that makes today's session "Logged": one of the same program, week and day that
    /// started today, the newest if there are several. A session done on another day of the week is offered
    /// again (the brief's rule; Pete's decision 2, default A).
    ///
    /// The other answer, "this week's session is done whichever day it was done", drops `startedToday`.
    static func loggedWorkout(for session: Session, _ context: Context) -> WorkoutState? {
        context.finished.first { $0.source == session.source && context.startedToday($0) }
    }
}

// MARK: - Up next

nonisolated extension TodayPresentation {
    /// One slot of a session with what it asks for that week.
    struct PlannedSlot {
        let slotID: SlotID
        let name: String
        let prescription: Prescription
    }

    /// What each slot of `session` asks for, in slot order. A slot whose exercise is no longer stored has no
    /// prescription and so no row (specification, criterion 12).
    static func plannedSlots(of session: Session, _ input: TodayInput) -> [PlannedSlot] {
        session.day.slots.compactMap { slot in
            input.exercises[slot.exerciseID].map { exercise in
                PlannedSlot(slotID: slot.id, name: exercise.name, prescription: ProgressionRules.prescribe(
                    week: session.week,
                    weekIndex: session.weekIndex,
                    slot: slot,
                    exercise: exercise,
                    units: input.settings.units
                ))
            }
        }
    }

    /// Decision #14's estimate for the session, from that week's prescriptions (a deload week has fewer sets).
    static func minutes(of session: Session, _ planned: [PlannedSlot]) -> Int {
        let prescriptions = Dictionary(planned.map { ($0.slotID, $0.prescription) }) { first, _ in first }
        return TimeEstimate.minutes(day: session.day, prescriptions: prescriptions)
    }

    /// "Week 1 of 8 · ~38 min", and "Week 8 of 8 · Deload · ~31 min" in a deload week.
    static func meta(of session: Session, _ planned: [PlannedSlot], _ locale: Locale) -> String {
        let fragments = [
            TodayCopy.week(session.weekIndex + 1, of: session.program.weeks.count, locale: locale),
            session.week.isDeload ? TodayCopy.deload : nil,
            TodayCopy.estimate(minutes: minutes(of: session, planned), locale: locale)
        ]
        return fragments.compactMap(\.self).joined(separator: separator)
    }

    /// The card for today's session, not yet logged.
    static func upNext(_ session: Session, _ input: TodayInput) -> TodayModel.UpNext {
        let planned = plannedSlots(of: session, input)
        let route = TodayRoute.startWorkout(
            program: session.program.id,
            weekIndex: session.weekIndex,
            day: session.day.id
        )
        return TodayModel.UpNext(
            eyebrow: TodayCopy.upNext,
            meta: meta(of: session, planned, input.locale),
            title: session.day.name,
            rows: planned.map { slot in
                TodayModel.PreviewRow(
                    name: slot.name,
                    scheme: TodayCopy.scheme(
                        sets: slot.prescription.sets,
                        reps: slot.prescription.reps,
                        load: slot.prescription.load.formatted(in: input.settings.units),
                        locale: input.locale
                    ),
                    isHeld: slot.prescription.isHeld,
                    isDeload: slot.prescription.isDeload
                )
            },
            action: .start(TodayModel.Action(title: TodayCopy.startWorkout, route: route))
        )
    }

    /// The card for a live workout: its own name and its own exercises with their targets, as the workout
    /// holds them (a swapped exercise shows as swapped). The week and the estimate are those of the session it
    /// was built for; a workout that is not a session of the active program has neither.
    static func upNext(resuming workout: WorkoutState, _ context: Context) -> TodayModel.UpNext {
        let input = context.input
        let session = workout.source.flatMap { source in
            context.block.flatMap { block in
                source.programID == block.program.id
                    ? session(of: block.program, weekIndex: source.weekIndex, day: source.dayTemplateID) : nil
            }
        }
        let elapsed = ClockText.elapsed(workout.elapsed(at: input.now))
        return TodayModel.UpNext(
            eyebrow: TodayCopy.upNext,
            meta: session.map { meta(of: $0, plannedSlots(of: $0, input), input.locale) },
            title: workout.name,
            rows: workout.exercises.map { exercise in
                TodayModel.PreviewRow(
                    name: exercise.name,
                    scheme: TodayCopy.scheme(
                        sets: exercise.targetSets,
                        reps: exercise.targetReps,
                        load: exercise.targetLoad.formatted(in: input.settings.units),
                        locale: input.locale
                    ),
                    isHeld: false,
                    isDeload: workout.isDeload
                )
            },
            action: .resume(
                TodayModel.Action(title: TodayCopy.resume(elapsed, locale: input.locale), route: .resumeWorkout),
                startedAt: workout.startedAt
            )
        )
    }
}

// MARK: - Logged, rest day, no program, block complete

nonisolated extension TodayPresentation {
    static func logged(
        _ workout: WorkoutState,
        _ session: Session,
        _ block: Block,
        _ context: Context
    ) -> TodayModel.Logged {
        let input = context.input
        let stats = [
            TodayCopy.sets(done: context.number(workout.doneSets), of: workout.totalSets, locale: input.locale),
            TodayCopy.moved(
                workout.volume.formatted(in: input.settings.units),
                units: input.settings.units,
                locale: input.locale
            )
        ]
        return TodayModel.Logged(
            eyebrow: TodayCopy.loggedWeek(session.weekIndex + 1, locale: input.locale),
            elapsed: ClockText.elapsed(workout.elapsed(at: input.now)),
            title: session.day.name,
            stats: stats.joined(separator: separator),
            action: TodayModel.Action(title: TodayCopy.viewSession, route: .openWorkout(workout.id)),
            next: nextLine(block, context)
        )
    }

    /// "Next: Friday · UB" while the next session is in today's program week, "Next: week 2" when it is in a
    /// later one, and nil when the block has no later session. That is what `nextScheduledDay` says, not the
    /// week's number: a block whose later weeks are empty has none left before its last week.
    static func nextLine(_ block: Block, _ context: Context) -> String? {
        let locale = context.input.locale
        guard let next = block.weeks.nextScheduledDay(after: context.input.now, in: block.program) else {
            return nil
        }
        guard next.weekIndex == block.weekIndex else {
            return TodayCopy.nextWeek(next.weekIndex + 1, locale: locale)
        }
        let weekday = context.weekdayName(context.start(of: next.date))
        return block.program.days.first { $0.id == next.dayTemplateID }
            .map { TodayCopy.next(weekday, tag: $0.tag, locale: locale) }
    }

    /// The card for a day with no session. A day before the block begins speaks of the block's first week:
    /// that is the week to edit and to pick a day from.
    static func restDay(_ block: Block, _ context: Context) -> TodayModel.RestDay {
        let weekIndex = max(0, block.weekIndex)
        return TodayModel.RestDay(
            eyebrow: TodayCopy.scheduledRest,
            title: TodayCopy.noSessionToday,
            body: restBody(block, weekIndex: weekIndex, context),
            editWeek: TodayModel.Action(
                title: TodayCopy.editThisWeek,
                route: .editWeek(program: block.program.id, weekIndex: weekIndex)
            ),
            offSchedule: offSchedule(block.program, weekIndex: weekIndex, context)
        )
    }

    /// The copy's three bodies, by where the next session is: later in the card's program week, in a later
    /// week ("next Monday", also when an empty week lies between), or nowhere in the block.
    static func restBody(_ block: Block, weekIndex: Int, _ context: Context) -> String {
        let input = context.input
        let today = context.weekdayName(input.now)
        guard let next = block.weeks.nextScheduledDay(after: input.now, in: block.program) else {
            return TodayCopy.restNothingLeft(today, week: weekIndex + 1, locale: input.locale)
        }
        let weekday = context.weekdayName(context.start(of: next.date))
        return next.weekIndex == weekIndex
            ? TodayCopy.restNextUp(today, week: weekIndex + 1, next: weekday, locale: input.locale)
            : TodayCopy.restNextUpLater(today, week: weekIndex + 1, next: weekday, locale: input.locale)
    }

    static func noProgram() -> TodayModel.Message {
        TodayModel.Message(
            title: TodayCopy.noProgramTitle,
            body: TodayCopy.noProgramBody,
            action: TodayModel.Action(title: TodayCopy.setUpProgram, route: .setUpProgram)
        )
    }

    static func blockComplete(_ program: Program, _ locale: Locale) -> TodayModel.Message {
        TodayModel.Message(
            title: TodayCopy.blockCompleteTitle,
            body: TodayCopy.blockCompleteBody(weeks: program.weeks.count, locale: locale),
            action: TodayModel.Action(title: TodayCopy.openProgram, route: .openProgram)
        )
    }
}
