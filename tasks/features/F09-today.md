# F09 — Today

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F02, F05, F06, F07, F10 (Domain `WorkoutSessionClient` protocol only) |
| Branch | `feat/F09-today` |
| Design refs | `design/prototype/Ledger v2.dc.html` → screen labels: `Today`; `design/prototype/Ledger.dc.html` → `Today` (rest-day, logged, up-next variants, behaviour) |
| Spec refs | `docs/product-spec.md` §3.5, §3.10 (Today v2), §6.5, §6.6, §7.7 rules 34–35, 42–43, 45–46; `docs/product-decisions.md` #1, #8, #14, #15, #17, #18, #19 |

## Goal
The lifter opens the app and sees, without tapping, what they are lifting today, how the week is going, and what they did last — and can start (or resume) today's session in one tap. Today is data-driven from the active program, the calendar, and finished history; nothing is hard-coded.

## User stories
- As a lifter, I can see today's scheduled day with every exercise's prescription so that I know the session before I start it.
- As a lifter, I can resume a minimised or interrupted workout from Today so that a phone call or an app kill never loses my session.
- As a lifter on a rest day, I can train off-schedule or edit the week so that a shifted schedule doesn't strand me.
- As a lifter, I can see sessions done / planned and volume moved this week with the change vs last week so that I know whether I am on track.

## Scope
**In:** `TodayRoot` + `TodayStore`; header (date, title, Settings gear in the avatar spot — decision #19); `WeekStrip` (done / today / planned dots); one of five cards (Up-next, Logged, Rest-day, No-program, Block-complete); "Train off-schedule" day picker (decision #18); two stat tiles; RECENT list (last 5 finished workouts); live "Resume · m:ss" by observing `WorkoutSessionClient`; empty/first-run states; routes to Workout, History detail, Program builder, Settings, Onboarding.
**Out (explicitly):** the workout itself and the start/resume use case (F10), receipt/detail screens (F13), Settings screen (F14), "Still lifting?" 4-hour prompt (F23), block-end "Start next block" flow (F24 — this brief ships a placeholder card), widgets (F22).

## Touches
- `LedgerKit/Sources/FeatureToday/TodayRoot.swift`, `TodayStore.swift`, `TodayRoute.swift`, `TodayPresentation.swift` (pure value builders)
- `LedgerKit/Sources/FeatureToday/Views/TodayHeader.swift`, `UpNextCard.swift`, `LoggedCard.swift`, `RestDayCard.swift`, `NoProgramCard.swift`, `BlockCompleteCard.swift`, `OffScheduleSheet.swift`, `StatsRow.swift`, `RecentList.swift`
- `LedgerKit/Sources/FeatureToday/Resources/Localizable.xcstrings`
- `LedgerKit/Sources/LedgerDomain/Calendar/WeekCalendar.swift` (F02; add `nextScheduledDay(after weekday:in week:)` and `firstScheduledDay(in week:)` if absent)
- `LedgerKit/Tests/FeatureTodayTests/TodayStoreTests.swift`, `TodayPresentationTests.swift`, `TodaySnapshotTests.swift`
- `Apps/Ledger/Sources/Navigation/TodayDestinations.swift` (F07-owned route mapping; add cases)

## Domain changes
No new persisted types. Consumes F02 `WeekCalendar`, `TimeEstimate.minutes(day:prescriptions:)` (decision #14), `ProgressionRules.prescribe`, F05 `StatsQueries` (`sessionsThisWeek`, `weeklyVolume(week:)` + previous complete week, `recentWorkouts(limit:)`, `workoutsOn(dates:)`), `ProgramRepository.activeProgram()` (live `AsyncSequence`), `SettingsRepository.settings()` (live), and F10's `WorkoutSessionClient.updates` (live phase + `startedAt`).
```swift
public enum TodayRoute: Hashable, Sendable {
    case startWorkout(program: ProgramID, weekIndex: Int, day: DayTemplateID)   // app → F10 use case + cover
    case resumeWorkout                                                          // app → F10 cover
    case openWorkout(WorkoutID)                                                 // app → F13 detail (receipt layout)
    case editWeek(program: ProgramID, weekIndex: Int)                           // app → F11 builder, week selected
    case settings                                                               // app → F14
    case setUpProgram                                                           // app → F08
}
```
Presentation model (pure, tested): `TodayPresentation.make(program:settings:today:workouts:live:stats:) -> TodayModel` with `card: .upNext | .logged | .restDay | .noProgram | .blockComplete`, `weekStrip: [DayCell]`, `stats`, `recent`.
Rules: current week = `WeekCalendar.currentWeekIndex(startDate:today:weekStart)`; `>= weeks.count` → `.blockComplete`. Today's day = `week.schedule[weekday]`. Logged = a finished workout exists with `source == (program, week, day)` today. Done dot = any finished workout on that date. Planned dot = schedule has a day. "Sessions this week" = finished workouts in the current week (off-schedule included) / scheduled days in the week (decision #15). Volume = Σ weight×reps of done sets this week; delta = `(this − previousCompleteWeek) / previousCompleteWeek`, hidden when no previous complete week or it is 0.

**Copy (exact):** date `Date.FormatStyle` weekday(.wide) month(.wide) day() e.g. "Wednesday, September 16"; title = day name before " — " or "Rest day"; gear button label "Settings". Up-next: eyebrow "UP NEXT", meta "Week %lld of %lld · ~%lld min" / deload "Week %lld of %lld · Deload · ~%lld min", preview rows "%@" · "%lld × %lld @ %@" (load in user units, no unit suffix), CTA "Start workout" / "Resume · %@" (m:ss). Logged: eyebrow "LOGGED · WEEK %lld", right elapsed m:ss, title day name, stats "%lld of %lld sets · %@ lb moved" ("kg moved" for kg), "View session", footer "Next: %@ · %@" (weekday · tag) / "Next: week %lld" (n+1). Rest day: eyebrow "SCHEDULED REST", "No session today", body "Nothing scheduled for %@ in week %lld. Next up is %@." (later this week) / "Nothing scheduled for %@ in week %lld. Next up is next %@." (first day of next week) / last week: "Nothing scheduled for %@ in week %lld. This is the last week of the block."; buttons "Edit this week", "Train off-schedule". Off-schedule sheet: "Train off-schedule", "Pick a day from week %lld.", rows day name · "%lld exercises · ~%lld min", trailing "Logged" when already done this week, "Cancel". No program: "No program yet", "Set up a program to see your next session here.", "Set up program". Block complete: "Block complete", "%lld weeks done. Start the next block from Program.", "Open Program". Stats: "%lld/%lld" + "sessions this week"; "%@k" + "lb moved · %@" (delta "+8%"/"−3%") or "lb moved" ("kg moved"). "RECENT"; rows "%@" · "%@ · %lld min · %@ lb" (weekday abbreviated; "Today" for today); empty "No sessions yet. Your first workout lands here."

## Acceptance criteria
1. Given the F08 default program started 2026-09-14 and today 2026-09-16 (Wed), when Today loads, then the header reads "Wednesday, September 16" / "Lower A", the strip shows M14 (done if logged) · T15 · W16 (today, orange) · T17 · F18 (planned) · S19 (planned) · S20, and the Up-next card shows "Week 1 of 8 · ~{TimeEstimate} min", "Lower A — Squat focus", five preview rows with prescriptions from `ProgressionRules`.
2. Given the Up-next card, when I tap "Start workout", then `TodayRoute.startWorkout(program:weekIndex:0, day: LA)` is emitted exactly once (no duplicate on double-tap).
3. Given a live workout (`phase == .live`, `startedAt` 3 min ago), when Today renders, then the CTA reads "Resume · 3:00" and counts up each second without the store ticking (wall-clock `Text(timerInterval:)`), and tapping emits `.resumeWorkout`. Given the workout finishes elsewhere, then the card flips to Logged within one stream update.
4. Given today's day was finished today, when Today renders, then the Logged card shows "LOGGED · WEEK 1", the elapsed m:ss, "{done} of {total} sets · {volume} lb moved", "View session" → `.openWorkout(id)`, and footer "Next: Friday · UB".
5. Given a Saturday whose schedule is empty and next week's first day is Monday, when Today renders, then the Rest-day card body reads "Nothing scheduled for Saturday in week 1. Next up is next Monday." with "Edit this week" → `.editWeek(program, 0)` and "Train off-schedule" opening the sheet listing all four days with "{n} exercises · ~{m} min"; picking a day emits `.startWorkout` for that day.
6. Given week 8 is deload, when Today renders on a scheduled day, then the meta reads "Week 8 of 8 · Deload · ~{m} min" and preview loads are the deload prescription.
7. Given `currentWeekIndex >= weeks.count`, when Today renders, then the Block-complete card is shown and stats/recent still render.
8. Given no active program, when Today renders, then the No-program card is shown, the strip has no planned dots, stats read "0/0" and "0k", and "Set up program" emits `.setUpProgram`.
9. Given 2 finished workouts this week, 4 scheduled, 24 180 lb this week and 22 400 lb last complete week, when Today renders, then tiles read "2/4 sessions this week" and "24.2k lb moved · +8%"; with no previous complete week the delta is absent; with units kg the tile says "kg moved" and values convert.
10. Given 7 finished workouts in history, when Today renders, then RECENT lists the 5 most recent, newest first, with meta "Mon · 58 min · 24,180 lb" style (today's → "Today · 24:22 · 8,120 lb"), and tapping a row emits `.openWorkout(id)`; with none, the empty copy is shown.
11. Given Settings.weekStart = Sunday, when Today renders, then the strip starts on Sunday and "sessions this week" counts Sun–Sat.
12. Given the screen, when audited, then orange appears only on the CTA, the today dot, the "UP NEXT" eyebrow and the delta (decision #17), and there are ≤ 6 all-caps eyebrows.
13. Given the gear button, when tapped, then `.settings` is emitted; VoiceOver reads "Settings, button" (no "JD" avatar exists).

## Test plan
- Unit (FeatureTodayTests): `test_presentation_upNext_weekOneWednesday_LowerA`, `test_presentation_weekStrip_doneTodayPlannedStates`, `test_presentation_loggedCard_nextLine_laterThisWeek`, `test_presentation_loggedCard_nextLine_nextWeek`, `test_presentation_restDay_nextUpLaterThisWeek`, `test_presentation_restDay_nextUpNextWeek`, `test_presentation_restDay_lastWeekOfBlock`, `test_presentation_deloadMeta`, `test_presentation_blockComplete_whenIndexPastWeeks`, `test_presentation_noProgram`, `test_presentation_stats_deltaPositiveNegativeHidden`, `test_presentation_stats_kgConversion`, `test_presentation_recent_fiveNewestFirst_todayLabel`, `test_presentation_timeEstimate_usesDecision14Formula`, `test_presentation_weekStartSunday`, `test_store_startWorkout_emitsRouteOnce`, `test_store_liveWorkout_showsResumeAndFlipsToLoggedOnFinish`, `test_store_offSchedule_pickEmitsStartForThatDay`, `test_store_settingsChange_rerenders`.
- Integration (LedgerPersistenceTests): `test_statsQueries_sessionsThisWeek_offScheduleCounted`, `test_statsQueries_weeklyVolumeDelta_previousCompleteWeek` (if not already in F05).
- Snapshot (FeatureTodayTests): `TodayRoot` × {upNext, upNextDeload, resumeLive, logged, restDay, noProgram, blockComplete, recentEmpty} × {light, dark} × {default, XL type}; `OffScheduleSheet` × {light, dark} × {default, XL}.
- UI (LedgerUITests): F15 flows `onboard_start_log_finish_history` (Today start/Logged), `program_edit_reflects_on_today`.

## Non-functional
- Performance budget: first frame of Today (cold launch, seeded 20 k sets) < 600 ms total (architecture §15); every query it runs < 50 ms; no work in `body` — all values come from `TodayModel`.
- Accessibility: cards are grouped containers with a heading; week strip cells read "Wednesday 16, today, planned"; stat tiles read "2 of 4 sessions this week"; hit targets ≥ 44 pt; Dynamic Type to AX5 with preview rows wrapping; Reduce Motion disables the resume-timer pulse.
- Offline behaviour: fully local.

## Risks / unknowns
- Off-schedule sessions can make "sessions this week" exceed planned (e.g. 5/4); accepted per decision #15.
- `WorkoutSessionClient` is declared by F10; if F09 lands first it ships the protocol under the F10-specified signature and F10 adopts it.
- "Resume · m:ss" (v1 copy) is chosen over v2's "Resume workout · m:ss"; flagged for copy review.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `TodayPresentation` at 100 % line coverage; no `Date()`/`Calendar.current` in feature code.
- [ ] All eight card/list states have previews and snapshots (light/dark, default/XL).
- [ ] Every string above present in the String Catalog with plural rules for sets/exercises/min.
- [ ] Manual check: minimise a live workout, kill the app, relaunch → Today shows "Resume · m:ss" (with F10).

---
_Filled in by agents during delivery:_
- `F09-today/implementation-notes.md`
- `F09-today/test-findings.md`
- `F09-today/review.md`

## Plan amendments (orchestrator, 2026-10-04)

The body above was written before M0 existed. Where it disagrees with this section, this section wins. The slice
plan and its evidence are in `F09-today/implementation-notes.md`.

**Delivery.** Six slices: S1 the tab shell, route mapping and the first String Catalog; S2 Domain additions; S3
the pure presentation; S4 the views; S5 the store and wiring; S6 the live session (after F10's first slice).

**Slice S1 — tab shell (product decision #1; nothing built it in M0)**
1. Given the database is open, the root shows four tabs in this order: Today, Program, Library, History. Today is
   selected on launch. Each tab has its own navigation stack, and a tab keeps its stack when the lifter switches
   away and back.
2. The Today tab shows the existing Today placeholder unchanged until S5: its title keeps the identifier
   `today.title`, and a long press on it still opens the Debug menu in Debug builds. The other three tabs show a
   placeholder that names the tab.
3. Routes are mapped in `LedgerAppKit/Routes.swift` (`AppTab`, `AppDestination`, `AppRouter`), not in
   `Apps/Ledger/Sources/Navigation/`. Every tab's stack is keyed by the one `AppDestination`. `AppRouter.open(_:in:)`
   selects the tab and pushes the destination on that tab's stack.
4. Every string the shell shows comes from `LedgerAppKit`'s String Catalog, including the two strings of the
   can't-open-your-data screen (product decision #29). (Revised after G2 round 1:) its second sentence drops the
   product's name, as the Naming rule requires of all shipped copy, and reads "Your workouts are still on this
   iPhone. The app tries again when you come back to it."; nothing else in its wording changes. The catalog and the
   code agree in both directions: the gate compares each catalog with the keys the compiler extracted from the
   code, and a source audit fails a user-facing literal or a lookup outside a module's copy file.
5. The selected tab's icon and label use the accent colour that meets AA contrast in both themes
   (`LedgerColor.accentText`; revised after G3: the plain accent measured 2.70:1 on the light theme's selection
   capsule), and the tint does not reach the tabs' content. VoiceOver reads each tab as its title with the system's
   tab traits. Tab icons are Apple's stock symbols (put to Pete; custom icons can replace them later).
6. The database-unavailable and idle states of the root are unchanged, apart from criterion 4's sentence.

**Later slices (corrections known today)**
- Criterion 1: Lower A has four exercises, so the Up-next card shows **four** preview rows (Upper A has five).
- `WeekCalendar` is `LedgerDomain/Rules/WeekCalendar.swift`; S2 adds one date-based `nextScheduledDay(after:in:)`
  in place of the two weekday-based helpers.
- The stats and repository names in "Domain changes" were guesses; the calls on `main` are listed in the notes'
  "Brief vs main".
- Week strip cells speak as F06's `WeekStrip` does (its pinned VoiceOver tree), not the phrase in "Non-functional".
- There is no resume-timer pulse to disable. `TodayRoute` gains `.openProgram`; `onRoute` is synchronous.
- Test names follow `docs/testing-strategy.md` §6, not the `test_…` names above.

## Plan amendments — slice S2, Domain additions (orchestrator, 2026-10-05)

S1 (the tab shell) is in review as #28; S2 is built on its tip and its PR opens after #28 merges. This section is
S2's specification; where it and the body above disagree, this section wins. Signatures on `main` are in
`F09-today/implementation-notes.md`, "Inputs the implementer needs › S2".

S2 adds three small things to `LedgerDomain` that the Today presentation (S3) needs. Everything is additive: no
existing declaration changes, and nothing the app shows changes.

1. **`WeekCalendar.nextScheduledDay(after:in:)`** returns the first day after the given moment's calendar day, in
   the calendar's time zone, on which the program schedules a session, as a `ScheduledDay`: its `CivilDate`, the
   program week's index, its `Weekday` and the `DayTemplateID`. It looks no further than the block's last week and
   returns `nil` when no session is left. A moment before the block begins gives the block's first session. Each
   candidate day is judged by its own program week, as `scheduledDay(on:in:)` judges it, so the answer does not
   depend on which weekday the block began or on a stats week that straddles two program weeks. Days are calendar
   dates (ADR-007): a date a time zone once skipped is still a day of the block and may be the answer.
   With the 4-day program of spec §6.4 begun on Monday 2026-09-14: after Wednesday 09-16 it is Friday 09-18 (Upper
   B, week index 0); after Saturday 09-19 it is Monday 09-21 (Upper A, week index 1); week 8 schedules three
   sessions, so after its Friday it is `nil`.
2. **`Volume.percentChange(from:)`** is the change from a previous volume in whole percent, rounded half away from
   zero, computed exactly (no `Double`): 24,180 lb against 22,400 lb is 8; 21,728 against 22,400 is −3; equal volumes
   give 0. It is `nil` when the previous volume is zero, and when the change cannot be computed as a number (a
   volume that is not a number, or a result too large for `Decimal`); a change beyond `Int` is clamped. It never
   traps, whatever the two volumes. (Revised after G2 round 1.)
3. **`Volume.thousands(in:)`** is the number `compact(in:)` prints, without its "k": "24.2" for 24,180 lb, and the
   same conversion to kilograms as `compact`. Zero reads "0"; every other volume keeps one decimal, and a volume too
   small to show reads "0.0" (and "0.0k" through `compact`), never an arbitrary number. (Revised after G2 round 1.)
4. **`Loadable<T>`** is the type `docs/engineering-standards.md` §5 names for a screen's load state, written as §5
   writes it: `idle`, `loading`, `loaded(T)`, `failed(any Error)`, `Sendable` when its value is.
5. `LedgerDomain` still imports Foundation only; the new code is covered line for line; no existing test changes.

## Plan amendments — slice S3, the presentation (orchestrator, 2026-10-05)

S1 (the tab shell) is in review as #28 and S2 (the Domain additions) is done; S3 is built on S2's tip and its PR
opens after both are on `main`. This section is S3's specification; where it and the body above disagree, this
section wins. The body's acceptance criteria 1 and 3–11 and its "Copy (exact)" paragraph still describe what Today
shows; S3 delivers their logic as a pure function, with no view and no store. Calls on `main` and line references
are in `F09-today/implementation-notes.md` ("Brief vs main", "Presentation purity and cost", "Inputs the
implementer needs › S3").

`TodayPresentation.make(_ input: TodayInput) -> TodayModel` turns the active program, the exercises, the settings,
this week's finished workouts, the five most recent, the previous complete week's volume, the session's workout
(live, or just finished), the moment, a calendar and a locale into everything Today draws, every string final.

1. **Header.** The date reads as the body says ("Wednesday, September 16") from the injected moment, locale,
   calendar and time zone. The title is today's day name before " — ", "Rest day" on a day with no session, and
   "Today" when there is no program or the block is complete.
2. **Week strip.** Seven days from the settings' week start. Each day's mark is the first that applies of: done (a
   finished workout that started that day), today, planned (the program schedules a session that day, judged by
   that day's own program week), rest. Each cell carries the text VoiceOver reads for it.
3. **Up next** (the body's criteria 1, 2, 6). On a day with a session not yet logged: the eyebrow, the meta line
   with the week and the time estimate (the deload wording in a deload week), the day's name, and one preview row
   per slot whose exercise is stored, "sets × reps @ load" from `ProgressionRules`, the load in the lifter's units
   with no unit suffix. Lower A has four rows. The action is "Start workout" carrying
   `TodayRoute.startWorkout(program:weekIndex:day:)`.
4. **A live workout** (criterion 3's model half). When the input holds a live workout, the card's action is
   "Resume" with the workout's start, and the card shows that workout: its name and its exercises, whichever day
   it was started for, also on a rest day. Today never offers "Start workout" while a workout is live. (This is
   the default of an open product question.)
5. **Logged** (criteria 3, 4). When today's session was finished today (a finished workout of the same program,
   week and day that started today, or the session's own workout the moment it is finished), the card shows the
   eyebrow with the week, the elapsed time, "{done} of {total} sets · {volume} lb moved" ("kg moved"), "View
   session" carrying `.openWorkout(id)`, and the "Next:" line: the next session's weekday and tag, "Next: week
   {n+1}" when it is in a later week, nothing when the block has no later session. A session done on another day
   of the week does not make today's "Logged": today's session is offered again (the body's rule; the default of
   an open product question, kept in one place so that the other answer is a small change).
6. **Rest day** (criterion 5). The three bodies of the copy, by where the next session is (later this week, in a
   later week, none left); a day before the block begins is a rest day whose next session is the block's first.
   "Edit this week" carries `.editWeek(program:weekIndex:)`. The off-schedule list holds every day of the week
   with "{n} exercises · ~{m} min" and "Logged" on a day already done this week; picking one carries
   `.startWorkout` for that day.
7. **Block complete and no program** (criteria 7, 8). Past the last week: the block-complete card, "Open
   Program" carrying `.openProgram`, with the strip, the tiles and the recent list still filled. With no program:
   the no-program card, "Set up program" carrying `.setUpProgram`, a strip with no planned marks, and tiles that
   read "0/0" and "0" with "k".
8. **Tiles** (criteria 9, 11). Sessions: finished workouts that started in the strip's seven days, off-schedule
   ones included, over the days of those seven with a session. Volume: this week's, as `Volume.thousands` and the
   unit's words, with the change against the previous complete week ("+8%", "−3%") or without it when there is no
   such week or it was zero. Kilograms when the settings say so. Each tile carries its spoken text.
9. **Recent** (criterion 10). The five most recent finished workouts, newest first: the name, and "Mon · 58 min ·
   24,180 lb"; one that started today reads "Today · 24:22 · 8,120 lb". Each carries `.openWorkout(id)`. With none,
   the empty copy.
10. **Copy.** Every text is the body's "Copy (exact)", resolved in `TodayCopy` from `FeatureToday`'s String Catalog
    as `docs/engineering-standards.md` §7 requires (a counted value per key, fragments joined with " · ", a second
    number passed as text), and spoken texts are copy too. Weights, volumes and clock times are shown as the
    Domain formats them. No text names the product.
11. **Purity.** `FeatureToday` reads no clock, calendar, locale or time zone of its own (a source test), no weight
    or volume passes through `Double`, and `TodayPresentation` is covered line for line.
12. **What the body leaves open, as decided in the plan:** a slot whose exercise is no longer stored has no
    preview row; an empty week between today and the next session still says "next {weekday}"; sessions can read
    "5/4"; a workout belongs to the day and week it started (decision #26).

## Plan amendments — slice S3 after round 1 (orchestrator, 2026-10-05)

Rulings on the tester's findings F9-S3-1 to F9-S3-7 and the reviewer's R1 to R4. They add to the twelve criteria
of S3 and replace them where they differ.

13. **The order of the input is not assumed** (F9-S3-1, F9-S3-7, review n1). `make` gives the same model for
    `weekWorkouts` handed in any order: of several finished workouts of today's session the Logged card shows the
    one that started last, and two that started at the same instant are told apart the same way every time.
14. **The volume tile's spoken line is copy** (F9-S3-2, R1): one key per unit for the line with a change and one
    for the line without, naming the week and what the change is against: "24,180 lb moved this week, +8% from
    last week" and "24,180 lb moved this week" (kilograms alike). No string literal other than the empty one and
    " · " is left in the module outside the copy files.
15. **"Next" in the rest-day body follows the seven days on screen** (F9-S3-3, review n2). "Next up is
    {weekday}." when the next session's date is one of the strip's seven days, "Next up is next {weekday}." when
    it is not, whichever program week it falls in. The first sentence still names the program week, and the
    Logged card's "Next:" line still follows the program week ("Next: week n" must never name the week the
    lifter is in).
16. **Before the block begins** (F9-S3-4, R4a) the rest-day body is one sentence of its own: "Your block starts
    on {date}." with the block's first day written as the header writes a date ("Monday, September 28"). The
    card is otherwise as criterion 6 says (the title "Rest day", "Edit this week" for week 1, the list).
17. **No session left** (F9-S3-5, R4b). In the block's last week the body ends "This is the last week of the
    block." as the brief has it. In any earlier week it ends "No sessions are left in this block."
18. **Unchanged, and recorded for later slices** (F9-S3-6): a slot whose exercise is not stored has no preview
    row and still counts in the estimate, and the card still offers "Start workout". No program can hold such a
    slot today (a program is refused on save when a slot's exercise has no row). F12 decides what deleting a
    custom exercise does to the slots that use it; F10 shows a start that fails.

The two sentences of 16 and 17, and the wording of 14, are texts the brief did not give: they are listed for
Pete with the slice's other new texts.
19. **Recorded for S5** (F9-S3-8, round 2): `make` counts a workout once for each time it is handed in. The store
    hands each finished workout of the week once (one read over the union of the stats week and the program
    week, or a merge by id), and its test pins that; the comment on `TodayInput.weekWorkouts` says so in S5.

## Plan amendments — slice S4, the views (orchestrator, 2026-10-08)

Cut from `main`, which holds the presentation (S3) and the scrolling-screens convention
(`docs/testing-strategy.md` §2.5–§2.6). The Today screen drawn from a `TodayModel` and nothing else: no store,
not yet in the app (the placeholder stays until S5). The plan's S4 row lists the files; "Inputs the implementer
needs › S4 — views", S3's "Inputs for S4" and the review's "What S4 must be told" give what each view is
handed. About 610 product lines planned. The slice is accepted when:

1. **Drawn from the model only.** Every view takes its part of `TodayModel` (or `Loadable` of it) and closures;
   no view decides which card, formats a number or a date, or reads a clock, calendar or locale. Every text on
   screen is a string of the model or a `TodayCopy` lookup the model does not carry (none is expected).
2. **The screen scrolls as the convention says:** `TodayScreen` is its pinned parts plus a `ScrollView` around
   one page view (`TodayPage(model:)`); snapshots and VoiceOver trees are taken from the page; the screen has
   its one nightly UI test listed for S5, when it is in the app.
3. **All eight states have a preview and snapshots** (the registry `TodayPreview`): up next, a live workout
   with Resume, logged, rest day with the off-schedule sheet's list, no program, block complete, loading and
   failed, in light and dark at the sizes `docs/testing-strategy.md` gives for a screen, and one at the
   largest accessibility size without clipped or overlapping text.
4. **The header, the week strip, the card, the tiles and the recent list** match the dark design
   (`design/prototype/Ledger v2.dc.html`, the regions the notes cite) with `LedgerDesign` tokens and
   components only: no literal colour, font or spacing in the feature.
5. **The resume button's time ticks** from the model's start instant with `Text(timerInterval:)` and is frozen
   in previews and tests; nothing else on the screen animates on its own.
6. **Actions.** Every button and row calls its closure with the model's `TodayRoute` or action value; the
   off-schedule sheet is presented by the screen from a value the model gives; a tap is at least 44 points.
7. **VoiceOver.** One intended tree for the page, written in the notes and pinned by a test, for each of the
   eight states: order, labels from the model's spoken texts, traits (headings, buttons), the strip's cells
   read as the model says, the tiles as one element each; nothing decorative is read.
8. **The two additions to `LedgerDesign`** the plan names (`IconPillButton`, `PrimaryButton` taking a `Text`)
   are components with gallery cases, snapshots and tree rows, usable by other features; existing references
   change only where the plan says they do, and each changed reference is listed.
9. **Wiring of the test targets** as the plan's row says (`snapshotTestTargets`, `PreviewScan`); the gate's
   preview and string-catalog steps pass; `FeatureToday` stays at or above its coverage threshold.

## Plan amendments — slice S4 after round 1 (orchestrator, 2026-10-08)

The tester found no bug (53 tests; its trees, written first, matched the page in all thirteen states) and the
reviewer approved with four should-fix items. Rulings, which add to S4's nine criteria:

10. **The resume button speaks without a time** (F9-S4-1, review S1): VoiceOver reads "Resume workout", one new
    text in the catalog; the drawn label keeps its ticking time. `PrimaryButton`'s spoken label is optional.
    (Default until Pete answers; the other answer is to read the live time.)
11. **At the accessibility sizes the recent list reads cleanly** (F9-S4-4): no row ends in a line that holds
    only the chevron, and the "RECENT" label clears its rule.
12. **Kept as built, for Pete to see:** the exercise rows of the up-next card use the design system's standard
    row, heavier and brighter than the dark design draws them (review S2; a quieter row style is the other
    answer). Each card has one heading and is not an accessibility container (F9-S4-3).
13. **The purity scans** (the tester's ruling): the catalog holds 57 texts; preview files are skipped by the
    S3 scans, and the tester's new scans read `Views/` and check previews another way. The implementer's edit
    to the S3 tester's file stands as audited.

**For S5** (review S3, S4; F9-S4-2): the nightly UI test of Today opens the off-schedule sheet, picks a day and
cancels, and checks the route; the store never returns to loading once it has loaded, since the sheet closes
when the state passes through it. **For F15** (F9-S4-5): how VoiceOver pronounces "24:22" and "~38 min" is
checked on a device.
14. **A blank spoken label is no label** (F9-S4-6, round 2): `PrimaryButton` given an empty or white-space-only
    spoken label speaks its drawn label.
