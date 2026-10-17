#if os(iOS)
    @testable import FeatureToday
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import LedgerTestSupport
    import Testing

    /// The states the F09 S4 adversarial suites draw (gate G2, round 1). The real ones are what
    /// `TodayPresentation.make` gives for the seed program begun on Monday 2026-09-14; the others are models
    /// made by hand to be inconsistent, which no presentation would give and a view must still only draw.
    nonisolated enum ViewsCases {
        typealias Support = TodayAdversarial

        struct Failure: Error {}

        /// Wednesday 2026-09-16 05:20 UTC: Lower A's day in week 1.
        static let wednesday = Fixtures.now
        /// Thursday 2026-09-17: nothing scheduled.
        static let thursday = Fixtures.date(2026, 9, 17, hour: 5, minute: 20)
        /// Monday 2026-09-21: week 2's first morning.
        static let monday = Fixtures.date(2026, 9, 21, hour: 5, minute: 20)
        /// Wednesday 2026-11-11: past the eighth week.
        static let afterTheBlock = Fixtures.date(2026, 11, 11, hour: 5, minute: 20)

        static func make(_ name: String, _ input: TodayInput) -> ViewsCase {
            ViewsCase(name: name, state: .loaded(TodayPresentation.make(input)), now: input.now)
        }

        /// Lower A of week 1, started `seconds` before `now`.
        static func live(_ program: Program, tag: String, now: Date, secondsAgo seconds: Int) throws -> WorkoutState {
            try Support.live(program, week: 0, tag: tag, number: 40, start: now.addingTimeInterval(-Double(seconds)))
        }

        /// Monday's Upper A and (when `withToday`) Wednesday's Lower A, finished.
        static func history(_ program: Program, withToday: Bool) throws -> [WorkoutState] {
            let upper = try Support.live(
                program, week: 0, tag: "UA", number: 41, start: Fixtures.date(2026, 9, 14, hour: 7)
            )
            let lower = try Support.live(
                program,
                week: 0,
                tag: "LA",
                number: 42,
                start: Fixtures.date(2026, 9, 16, hour: 3)
            )
            return [Support.finished(upper, after: 58 * 60)]
                + (withToday ? [Support.finished(lower, after: 24 * 60 + 22)] : [])
        }

        /// The eight states of criterion 3 (the sheet is a rest day's), and the two the review asked for.
        static func real() throws -> [ViewsCase] {
            let program = try Support.seed()
            let done = try history(program, withToday: false)
            let logged = try history(program, withToday: true)
            let volume = Volume(weight: .pounds(1000), reps: Reps(clamping: 7))
            return try [
                make("up next", Support.input(program, now: wednesday, week: done, recent: done)),
                make("up next, no history", Support.input(program, now: wednesday)),
                make(
                    "live workout",
                    Support.input(
                        program, now: wednesday, week: done, recent: done,
                        session: live(program, tag: "LA", now: wednesday, secondsAgo: 180)
                    )
                ),
                make("logged", Support.input(program, now: wednesday, week: logged, recent: logged.reversed())),
                make("rest day", Support.input(program, now: thursday, week: logged, recent: logged.reversed())),
                make("no program", Support.input(nil, now: wednesday)),
                make("block complete", Support.input(program, now: afterTheBlock, recent: logged.reversed())),
                ViewsCase(name: "loading", state: .loading),
                ViewsCase(name: "idle", state: .idle),
                ViewsCase(name: "failed", state: .failed(Failure())),
                make(
                    "live workout on a rest day",
                    Support.input(
                        program, now: thursday, week: logged, recent: logged.reversed(),
                        session: live(program, tag: "LB", now: thursday, secondsAgo: 754)
                    )
                ),
                make("Monday, nothing moved", Support.input(program, now: monday, previous: volume)),
                make("kilograms", Support.input(program, now: wednesday, settings: Support.settings(.kg), week: done))
            ]
        }

        /// Built once; empty when a fixture does not build, which `fixtures_build` reports.
        static let all: [ViewsCase] = (try? real()) ?? []
        static let odd: [ViewsCase] = (try? inconsistent()) ?? []
    }

    // MARK: - Models no presentation gives

    nonisolated extension ViewsCases {
        static let longName = String(repeating: "Romanian Deadlift With A Very Long Qualifier ", count: 4)
        static let arabic = "تمرين القرفصاء الخلفي بالبار"

        static func action(_ title: String, _ route: TodayRoute) -> TodayModel.Action {
            TodayModel.Action(title: title, route: route)
        }

        static func tile(_ value: String, _ unit: String, _ caption: String, delta: String? = nil) -> TodayModel.Tile {
            TodayModel.Tile(
                value: value, unit: unit, caption: caption, delta: delta,
                accessibilitySummary: "spoken [\(value)] [\(caption)]"
            )
        }

        static func cell(_ number: Int, _ mark: WeekStrip.Mark) -> WeekStrip.Day {
            WeekStrip.Day(weekday: "D", date: "\(number)", mark: mark, accessibilitySummary: "Day \(number)")
        }

        static func model(
            title: String = "Rest day",
            strip: [WeekStrip.Day] = (1 ... 7).map { cell($0, .rest) },
            card: TodayModel.Card,
            volume: TodayModel.Tile = tile("24.2", "k", "lb moved", delta: "+8%"),
            recent: [TodayModel.RecentRow] = []
        ) -> TodayModel {
            TodayModel(
                header: .init(date: "Someday, Month 1", title: title, settings: action("Gear", .settings)),
                weekStrip: strip,
                card: card,
                stats: .init(sessions: tile("5", "/4", "sessions this week"), volume: volume),
                recent: .init(eyebrow: "LATELY", rows: recent, emptyMessage: recent.isEmpty ? "Nothing yet." : nil)
            )
        }

        static func upNext(
            meta: String? = "Week 9 of 8",
            title: String = "Some day",
            rows: [TodayModel.PreviewRow] = [],
            action: TodayModel.PrimaryAction
        ) -> TodayModel.Card {
            .upNext(.init(eyebrow: "NEXT", meta: meta, title: title, rows: rows, action: action))
        }

        static func row(_ name: String, _ scheme: String) -> TodayModel.PreviewRow {
            TodayModel.PreviewRow(name: name, scheme: scheme, isHeld: true, isDeload: true)
        }

        static func offSchedule(days: [TodayModel.OffScheduleDay]) -> TodayModel.OffSchedule {
            TodayModel.OffSchedule(title: "Pick", subtitle: "From week 99.", days: days, cancel: "Never mind")
        }

        /// A start of a day no program holds.
        static let strayStart = TodayRoute.startWorkout(
            program: ProgramID(Fixtures.uuid(78)), weekIndex: 3, day: DayTemplateID(Fixtures.uuid(79))
        )

        static func inconsistent() throws -> [ViewsCase] {
            contradictions() + extremes()
        }

        /// Cards that say one thing and carry another.
        static func contradictions() -> [ViewsCase] {
            let workout = WorkoutID(Fixtures.uuid(77))
            let start = strayStart
            let twoEqualRows = [row("Back Squat", "5 × 5 @ 250"), row("Back Squat", "5 × 5 @ 250")]
            let recent = [
                TodayModel.RecentRow(name: "Same", meta: "Mon · 1 min · 1 lb", route: .openWorkout(workout)),
                TodayModel.RecentRow(name: "Same", meta: "Mon · 1 min · 1 lb", route: .openProgram)
            ]
            let logged = TodayModel.Logged(
                eyebrow: "DONE", elapsed: "99:59:59", title: "Other", stats: "0 of 0 sets",
                action: action("Start it again", start), next: nil
            )
            let rest = TodayModel.RestDay(
                eyebrow: "REST", title: "None", body: "Body.", editWeek: action("Edit", .setUpProgram),
                offSchedule: offSchedule(days: [])
            )
            let message = TodayModel.Message(title: "T", body: "B", action: action("Go", .resumeWorkout))
            let resume = TodayModel.PrimaryAction.resume(
                action("Spoken resume", .settings), startedAt: wednesday.addingTimeInterval(-3725)
            )
            return [
                ViewsCase(
                    name: "rest-day title over an up-next card that resumes with another route",
                    state: .loaded(model(card: upNext(rows: twoEqualRows, action: resume)))
                ),
                ViewsCase(name: "logged card that starts a workout", state: .loaded(model(card: .logged(logged)))),
                ViewsCase(
                    name: "empty strip, rest day with an empty list",
                    state: .loaded(model(strip: [], card: .restDay(rest)))
                ),
                ViewsCase(
                    name: "nine strip days, equal recent rows with different routes",
                    state: .loaded(model(
                        strip: (1 ... 9).map { cell($0, .done) },
                        card: .noProgram(message),
                        recent: recent
                    ))
                )
            ]
        }

        /// Empty, very long and right-to-left texts.
        static func extremes() -> [ViewsCase] {
            let long = upNext(
                meta: longName, title: longName, rows: [row(longName, "12 × 12 @ 1,234,567.5")],
                action: .start(action(longName, .openProgram))
            )
            return [
                ViewsCase(
                    name: "empty unit and caption, no meta, no rows",
                    state: .loaded(model(
                        card: upNext(meta: nil, action: .start(action("Go", strayStart))),
                        volume: tile("", "", "")
                    ))
                ),
                ViewsCase(name: "very long texts", state: .loaded(model(title: longName, card: long))),
                ViewsCase(
                    name: "right-to-left texts",
                    state: .loaded(model(title: arabic, card: .blockComplete(
                        .init(title: arabic, body: arabic, action: action(arabic, .openProgram))
                    )))
                )
            ]
        }
    }
#endif
