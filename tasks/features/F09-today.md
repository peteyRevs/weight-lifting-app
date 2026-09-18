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
