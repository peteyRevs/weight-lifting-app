import Foundation
import LedgerDesign

/// Everything Today draws, as `TodayPresentation.make(_:)` builds it. Every string is final: the views draw the
/// model and decide nothing, and every action carries the `TodayRoute` its tap emits.
nonisolated struct TodayModel: Equatable, Sendable {
    let header: Header
    /// The week at a glance, from the settings' week start: seven days.
    let weekStrip: [WeekStrip.Day]
    let card: Card
    let stats: Stats
    let recent: Recent

    /// The one card under the week strip.
    enum Card: Equatable, Sendable {
        case upNext(UpNext)
        case logged(Logged)
        case restDay(RestDay)
        case noProgram(Message)
        case blockComplete(Message)
    }

    /// A control's title and the route its tap emits.
    struct Action: Equatable, Sendable {
        let title: String
        let route: TodayRoute
    }

    struct Header: Equatable, Sendable {
        /// "Wednesday, September 16".
        let date: String
        /// "Lower A", "Rest day", or "Today" when there is no program or the block is complete.
        let title: String
        /// The gear: its spoken label, "Settings", and `.settings`.
        let settings: Action
    }
}

// MARK: - The cards

nonisolated extension TodayModel {
    /// Today's session, not yet logged; or the live workout, whichever day it was started for.
    struct UpNext: Equatable, Sendable {
        /// "UP NEXT".
        let eyebrow: String
        /// "Week 1 of 8 · ~38 min", with "Deload" between the two in a deload week. Nil for a live workout that
        /// is not a session of the active program.
        let meta: String?
        /// "Lower A — Squat focus".
        let title: String
        let rows: [PreviewRow]
        let action: PrimaryAction
    }

    /// One exercise of the card.
    struct PreviewRow: Equatable, Sendable {
        /// "Back Squat".
        let name: String
        /// "5 × 5 @ 250": sets, reps and the load in the lifter's units, with no unit after it.
        let scheme: String
        /// The load holds because last week was missed (spec §7.2). Not drawn yet: F24 adds "HELD".
        let isHeld: Bool
        /// A deload week's prescription. Not drawn yet: F24 styles it.
        let isDeload: Bool
    }

    /// The card's one orange button.
    enum PrimaryAction: Equatable, Sendable {
        /// "Start workout", carrying `.startWorkout`.
        case start(Action)
        /// "Resume · 3:00" as it reads at the model's moment, carrying `.resumeWorkout`. The view counts on from
        /// `startedAt` by the wall clock, so the model is not rebuilt each second.
        case resume(Action, startedAt: Date)

        var action: Action {
            switch self {
            case let .start(action), let .resume(action, _): action
            }
        }
    }

    /// Today's session, finished today.
    struct Logged: Equatable, Sendable {
        /// "LOGGED · WEEK 1".
        let eyebrow: String
        /// "24:22": how long the workout took.
        let elapsed: String
        /// "Lower A — Squat focus".
        let title: String
        /// "15 of 15 sets · 30,370 lb moved".
        let stats: String
        /// "View session", carrying `.openWorkout`.
        let action: Action
        /// "Next: Friday · UB", "Next: week 2", or nil when the block has no later session.
        let next: String?
    }

    /// A day with no session: a rest day, or a day before the block begins.
    struct RestDay: Equatable, Sendable {
        /// "SCHEDULED REST".
        let eyebrow: String
        /// "No session today".
        let title: String
        /// "Nothing scheduled for Saturday in week 1. Next up is next Monday."
        let body: String
        /// "Edit this week", carrying `.editWeek`.
        let editWeek: Action
        let offSchedule: OffSchedule
    }

    /// "Train off-schedule": the rest-day card's second button and the sheet it opens (decision #18).
    struct OffSchedule: Equatable, Sendable {
        /// "Train off-schedule": the button's title and the sheet's.
        let title: String
        /// "Pick a day from week 1."
        let subtitle: String
        let days: [OffScheduleDay]
        /// "Cancel".
        let cancel: String
    }

    /// One day of the program, to train today.
    struct OffScheduleDay: Equatable, Sendable {
        /// "Lower B — Hinge focus".
        let name: String
        /// "3 exercises · ~29 min".
        let detail: String
        /// "Logged" when the day is already done this program week, else nil.
        let logged: String?
        /// `.startWorkout` for this day in the card's week.
        let route: TodayRoute
    }

    /// The No-program and Block-complete cards: a title, a sentence and one button.
    struct Message: Equatable, Sendable {
        let title: String
        let body: String
        let action: Action
    }
}

// MARK: - The tiles and the recent list

nonisolated extension TodayModel {
    /// The two tiles under the card.
    struct Stats: Equatable, Sendable {
        /// "2" "/4" "sessions this week".
        let sessions: Tile
        /// "24.2" "k" "lb moved", and "+8%" against the previous week.
        let volume: Tile
    }

    /// One tile, as `StatTile` takes it.
    struct Tile: Equatable, Sendable {
        let value: String
        /// Drawn light after the value: "/4", "k".
        let unit: String
        let caption: String
        /// "+8%", "−3%" or "0%"; nil when there is nothing to compare with.
        let delta: String?
        /// What VoiceOver reads for the tile: "2 of 4 sessions this week".
        let accessibilitySummary: String
    }

    struct Recent: Equatable, Sendable {
        /// "RECENT".
        let eyebrow: String
        /// The five finished workouts that started last, newest first.
        let rows: [RecentRow]
        /// "No sessions yet. Your first workout lands here." when there are no rows, else nil.
        let emptyMessage: String?
    }

    struct RecentRow: Equatable, Sendable {
        /// "Lower A — Squat focus".
        let name: String
        /// "Mon · 58 min · 24,180 lb"; "Today · 24:22 · 8,120 lb" for one that started today.
        let meta: String
        /// `.openWorkout` for this workout.
        let route: TodayRoute
    }
}
