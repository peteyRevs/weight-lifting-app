# F10 — Active workout (phone)

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F02, F04, F05, F06, F07 |
| Branch | `feat/F10-active-workout` |
| Design refs | `design/prototype/Ledger v2.dc.html` → screen labels: `Active workout` (rest card, swap sheet, set rows); `design/prototype/Ledger.dc.html` → `Active workout` (supersets, drop sets, TARGET pill, REMAINING, behaviour), `Session receipt` |
| Spec refs | `docs/product-spec.md` §3.6, §3.7, §3.10 (Active workout v2), §7.3–7.7 (rules 14–36, 39, 44); `docs/adr/ADR-004-event-sourced-workout-engine.md`; `docs/product-decisions.md` #3, #5, #6, #7, #8, #9, #13, #17 |

## Goal
A lifter can run an entire session on the phone: every set arrives pre-filled, one tap logs it, rest runs on a wall-clock timer, supersets log round by round, exercises can be swapped, and Finish produces a receipt and a persisted workout. Everything goes through `WorkoutEngine` via `WorkoutSessionClient`, so when F17 adds the watch channel no UI changes.

## User stories
- As a lifter, I can tick a set and have the rest timer start and the cursor move to the next set so that logging is one tap per set.
- As a lifter, I can adjust weight/reps with steppers in my unit's step so that I never type numbers.
- As a lifter, I can swap an exercise when the rack is taken, optionally updating my program, so that the session continues.
- As a lifter, I can minimise, take a call, or have the app killed, and resume with nothing lost.
- As a lifter, I can finish and see a receipt of what I did vs what was prescribed.

## Scope
**In:** `WorkoutSessionClient` protocol (Domain) + `LocalWorkoutSessionActor` (LedgerSync, no transport); `StartWorkoutUseCase` (build/resume/replace); `WorkoutRoot` presented as a full-screen cover; header, exercise card (solo + superset block), set rows with steppers, drop rows, TARGET pill, LAST + Repeat, + Add set, REMAINING, rest panel, swap sheet, Finish confirmation, Session receipt, Minimize, Discard; effect execution (haptics, rest notification scheduling); state restoration after kill.
**Out (explicitly):** watch UI and transport (F17, F18), Live Activity (F21), rest-over notification content/permission UX and "Still lifting?" prompt (F23), plate-math line (F25), failed-set/held UI (F24), HealthKit save (F16; the engine emits no Health effect), workout detail editing (F13).

## Touches
- `LedgerKit/Sources/LedgerDomain/Workout/WorkoutSessionClient.swift` (new protocol + `WorkoutSessionUpdate`)
- `LedgerKit/Sources/LedgerDomain/Workout/StartWorkoutUseCase.swift` (new, pure decision + repository calls)
- `LedgerKit/Sources/LedgerSync/LocalWorkoutSessionActor.swift` (new; F17 extends with transport)
- `LedgerKit/Sources/LedgerDesign/Components/ReceiptLayout.swift` (new, string-only model; reused by F13)
- `LedgerKit/Sources/FeatureWorkout/WorkoutRoot.swift`, `WorkoutStore.swift`, `WorkoutRoute.swift`, `WorkoutPresentation.swift`
- `LedgerKit/Sources/FeatureWorkout/Views/WorkoutHeader.swift`, `ExerciseCard.swift`, `SupersetBlock.swift`, `SetRowList.swift`, `RemainingList.swift`, `RestPanel.swift`, `SwapSheet.swift`, `FinishDialog.swift`, `ReceiptView.swift`
- `LedgerKit/Sources/FeatureWorkout/Resources/Localizable.xcstrings`
- `LedgerKit/Sources/LedgerTestSupport/Fakes/FakeWorkoutSessionClient.swift`, `Fixtures/WorkoutStateFixtures.swift`
- `LedgerKit/Tests/LedgerDomainTests/StartWorkoutUseCaseTests.swift`; `LedgerKit/Tests/LedgerSyncTests/LocalWorkoutSessionActorTests.swift`
- `LedgerKit/Tests/FeatureWorkoutTests/WorkoutStoreTests.swift`, `WorkoutPresentationTests.swift`, `WorkoutSnapshotTests.swift`
- `Apps/Ledger/Sources/LedgerApp.swift` (F07-owned: register `workoutSession` key; call `resumeFromStore()` at launch), `Apps/Ledger/Sources/RootView.swift` (`fullScreenCover` binding)

## Domain changes
```swift
public struct WorkoutSessionUpdate: Sendable { public let state: WorkoutState; public let effects: [Effect]; public let origin: DeviceID }
public protocol WorkoutSessionClient: Sendable {
    var updates: AsyncStream<WorkoutSessionUpdate> { get }        // yields current state first, then every change
    func current() async -> WorkoutState?
    func start(_ initial: WorkoutState) async throws              // persists .started; fails if a live workout exists
    func apply(_ event: WorkoutEvent) async throws                // local intent → EventEnvelope(device, seq, HLC wallClock) → reduce → effects (.persist first)
    func resumeFromStore() async throws -> WorkoutState?          // launch step over WorkoutEventStore.uncompactedWorkoutIDs() (ADR-004 amendment)
    func finishAndMaterialise() async throws -> WorkoutSummary    // apply .finished, run its .materialize(WorkoutState) (F05), compact log
    func discard() async throws                                   // apply .discarded, drop log
}
```
DI key `workoutSession` (F07 list gains it). `LocalWorkoutSessionActor` executes `.persist`, `.materialize` and `.discardLog` itself, ignores `.transmit`/`.updateLiveActivity` in M1, and forwards `.haptic`, `.scheduleRestNotification`, `.cancelRestNotification` in `effects`. The store plays every `.haptic` it is forwarded (which changes buzz is the engine's: ADR-004 "The host loop"), and notification effects always (`@Dependency(\.notifications)`; live value may be a no-op until F23 grants authorization).
`StartWorkoutUseCase.start(program:weekIndex:day:) -> Outcome` — `.resumed` (live workout with same source, rule 17), `.conflict(existing)` (live workout with a different source → dialog), `.started` (builds via `SessionBuilder.build(program:week:day:history:)` with `StatsQueries.lastPerformance` per exercise, then `start`). `WorkoutRoute`: `.live`, `.receipt(WorkoutSummary)`. Cursor: `exerciseSelected(exerciseIndex:setIndex:)` sets the engine cursor; the selected set inside a slot is store-local `selectedSetID` defaulting to the engine cursor's set (see Risks). Swap: `exerciseSwapped(exerciseIndex:exerciseID:name:alsoUpdateProgram:)` then, for every undone set, `setTargetChanged(weight: replacementLastLoad ?? unchanged)` (decision #13); store keeps `[ExerciseID: Exercise]` for names/steps. Adds `ProgramRepository.replaceSlotExercise(slot: SlotID, with: ExerciseID)` if F05 lacks it. Step per unit from `Exercise.equipment` + `Settings.units` (`Equipment.defaultStep(in:)`: lb 5 / 2.5, kg 2.5 / 1.25; kettlebell 5 lb / 2 kg, decision #22).

**Copy (exact):** header "Minimize", elapsed m:ss, "Finish"; eyebrow "Exercise %lld of %lld" / "Superset · block %lld of %lld"; superset title "Round %lld of %lld"; swap button label "Swap exercise"; TARGET pill "TARGET" + "%lld × %lld @ %@ lb · RPE %@"; "Last" + "%@ · %lld×%lld @ %@ lb" (e.g. "Aug 12 · 5×5 @ 180 lb") or "No history yet" (Repeat hidden); "Repeat"; legend rest "Rest %@ after %@" ("Rest 1:15 after B"); columns "#", "lb"/"kg", "reps"; row labels "1"…, "D", "A1", "B1", "AD"; stepper labels "%@ LB"/"%@ KG" and "1 REP"; "+ Add set"; "REMAINING" rows "%lld × %lld"; rest card "Resting · watch buzzes at zero", next "Set %lld · %@ lb × %lld" / "Set %lld · next exercise", at zero "Rest over", buttons "+30s", "Skip rest"; swap sheet "Swap exercise", "Cancel", "Same movement pattern, equipment you have.", row sub "%@ · %@ lb" (equipment · last-known or default load), "Use", toggle "Also update program"; conflict dialog "You have a workout in progress", "Resume it", "Discard and start new"; finish dialog "End workout?", "%lld of %lld sets logged · %@ lb moved", "Save workout", "Discard", "Keep lifting"; receipt: date "Wednesday, September 16", day name, "Done", tiles "TIME" / "SETS" / "LB MOVED" ("KG MOVED"), "1 new PR this session" / "%lld new PRs this session", "LOGGED", "Prescribed on the right", target "%lld × %lld @ %@ lb", chips "%lld × %@×%lld" / "%@×%lld" / "—".

## Acceptance criteria
1. Given Today emits `.startWorkout` with no live workout, when the use case runs, then a `WorkoutState` is built by `SessionBuilder` (drop rows at −15 % rounded to step, `lastPerformance` filled), `start` persists `.started`, and the cover presents with exercise 1 / set 1 selected and elapsed at 0:00.
2. Given a live workout for a different day, when `.startWorkout` runs, then the conflict dialog appears; "Resume it" opens the existing one; "Discard and start new" calls `discard()` then starts.
3. Given set 2 of a solo exercise selected, when I tap its check, then `setLogged` is applied, the row dims with an orange check, the engine starts rest for `exercise.rest` (autoRest on) and the cursor advances per rule 20; the store sends no rest-related events itself. Given autoRest off, no rest panel appears.
4. Given a superset A/B with 3 sets, when I log A1, then no rest starts and the cursor moves to B1; when I log B1, then rest = max(rest A, rest B) starts and the cursor moves to A2; the title reads "Round 2 of 3" and the legend marks B current after A2. Drop rows AD/BD form a final round.
5. Given the active row, when I tap "+" on weight, then `setTargetChanged` with +step (5 lb barbell or kettlebell / 2.5 lb other; 2.5 kg barbell / 2 kg kettlebell / 1.25 kg other) is applied to that set only, minimum 0; reps "−" floors at 1; tapping a stepper on a non-selected row selects it first.
6. Given rest is running, when the app is backgrounded and returns 40 s later, then the ring and m:ss reflect wall-clock remaining (no drift); at zero the phone plays `.restOver`, the card shows "0:00" / "Rest over" and stays until "+30s" (restarts 30 s, decision #7), "Skip rest", or the next logged set.
7. Given "+30s" during rest, when tapped, then `restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: now)` is applied (`false` when the card shows "Rest over") and the ring rescales; un-ticking a set never cancels rest (rule 22).
8. Given the swap sheet for Bench Press, when it opens, then curated alternatives come first, then same movement pattern + primary muscle, then same primary muscle, deduped, ≤ 8 rows, each with "{Equipment} · {load} lb"; choosing "Use" with the toggle off renames only this workout's slot and undone sets take the replacement's last-known load if any; with the toggle on, `ProgramRepository.replaceSlotExercise` is also called. Swap is available inside a superset (decision #13).
9. Given "Repeat", when tapped, then every set of the current exercise receives the LAST weight/reps via `setTargetChanged` (done flags unchanged); "+ Add set" appends a copy of the last row via `setAdded` (no drop flag) and the header segment for that exercise widens.
10. Given "Finish", when tapped, then the dialog shows "{done} of {total} sets logged · {volume} lb moved"; "Save workout" (disabled at 0 sets) calls `finishAndMaterialise()`, PRs/misses are computed (decisions #3, #5), the receipt shows TIME/SETS/LB MOVED, the PR line only when > 0, and rows with run-length chips ("5 × 185×5", "—"); "Done" dismisses the cover and Today shows the Logged card. "Discard" calls `discard()` and returns to Today with nothing persisted.
11. Given "Minimize", when tapped, then the cover dismisses, the workout stays live, elapsed keeps counting (decision #8), and Today's "Resume · m:ss" reopens it at the same cursor.
12. Given the app is killed mid-workout with rest running, when relaunched, then `resumeFromStore()` replays the log, Today shows Resume, and reopening shows the same sets/cursor and the correct remaining rest (or "Rest over" if elapsed). Given it was killed after `.finished` but before materialisation, then the launch step over `uncompactedWorkoutIDs()` materialises the replayed state, compacts the log, and no cover appears.
13. Given the screen, when audited, then progress segments are proportional to set counts and coloured done/current/remaining, orange is used once for the primary action per surface (check on the active row / "Skip rest" on the rest card / "Use" in the sheet), and every icon-only control has a label.

## Test plan
- Unit (LedgerDomainTests): `test_startUseCase_noLive_buildsAndStarts`, `test_startUseCase_sameSource_resumes`, `test_startUseCase_differentSource_conflict`, `test_startUseCase_lastPerformanceInjected`.
- Unit (LedgerSyncTests): `test_actor_apply_assignsMonotonicSeqAndPersists`, `test_actor_updates_yieldsCurrentStateFirst`, `test_actor_resumeFromStore_replaysUnfinishedLog`, `test_actor_resume_finishedButNotMaterialised_completes`, `test_actor_finish_materialisesThenCompacts`, `test_actor_start_whenLiveExists_throws`, `test_actor_effects_forwardHapticAndNotificationOnly`.
- Unit (FeatureWorkoutTests): `test_store_check_appliesSetLogged`, `test_store_playsForwardedHaptics`, `test_store_weightStep_lbBarbell5_other2_5`, `test_store_weightStep_kg2_5_1_25`, `test_store_stepperOnOtherRow_selectsFirst`, `test_store_repeat_writesAllSets`, `test_store_addSet_copiesLastRow`, `test_store_swap_oneOff_keepsProgram`, `test_store_swap_updateProgram_callsRepository`, `test_store_swap_undoneSetsTakeReplacementLoad`, `test_store_swapAlternatives_orderCuratedPatternMuscle`, `test_store_restZero_playsRestOverOnce`, `test_store_finish_zeroSets_saveDisabled`, `test_store_finish_showsReceiptAndRoutes`, `test_store_discard_routesToday`, `test_store_scheduleRestNotification_onRestStarted`, `test_presentation_rowLabels_soloDropSuperset`, `test_presentation_progressSegments_proportional`, `test_presentation_receiptChips_runLength`, `test_presentation_remaining_onlyLaterExercises`, `test_presentation_supersetRoundTitle`.
- Integration (LedgerPersistenceTests): `test_eventStore_replayAfterKill_matchesLastState` (write log, new store, replay).
- Snapshot (FeatureWorkoutTests): `WorkoutRoot` × {soloActive, soloWithDrop, supersetRound2, resting, restOver, remainingEmpty, noHistory} × {light, dark} × {default, XL}; `SwapSheet`, `FinishDialog`, `ReceiptView` × {withPRs, noPRs, kg} × {light, dark} × {default, XL}.
- UI (LedgerUITests): F15 flow `onboard_start_log_finish_history` (log 3 sets incl. a superset round, rest, swap, finish, receipt).

## Non-functional
- Performance budget: tap → row state change < 16 ms (one frame); `apply` round-trip incl. persist < 30 ms; rest ring animates via `TimelineView(.animation)` with no per-second store updates; cover presentation < 200 ms.
- Accessibility: set rows read "Set 2, 185 pounds, 5 reps, not done"; check button label "Log set 2" / "Unlog set 2"; steppers are `.adjustable` with the step in the value; rest card announces "Rest, 1:30 remaining" on appear and "Rest over" at zero; Reduce Motion disables ring animation; Dynamic Type to AX5 (numbers wrap to two lines, never truncate).
- Offline behaviour: fully local; no transport in M1.

## Risks / unknowns
- F04's `exerciseSelected(exerciseIndex:setIndex:)` moves the engine cursor only onto an undone row (rule 11); this brief keeps any other set selection store-local. If the watch needs the phone's selected set (F18), F04 adds `setSelected` and this store adopts it.
- F04's `exerciseSwapped` carries the replacement's `name` and replaces only the exercise's identity (rule 8); equipment and steps are still resolved by the store via `ExerciseRepository`.
- Swapping onto a kettlebell or other stepped equipment (F03 fix round 2; decision #22): F04 rule 27 keeps the original targets, so the swap sheet re-targets the undone sets to the replacement's step and sizes (its last-known load if any, else its own start load, rounded to its step), and the stepper uses the replacement's equipment step.
- Rest card persisting at zero (for "+30s" per decision #7) deviates from the prototype, which hides it at zero.
- `WorkoutRepository.finish(_:) -> WorkoutSummary` is assumed from F05; if named differently, adapt and note.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] No rest arithmetic or cursor logic in FeatureWorkout — only events in, state out (reviewer greps for `Date()`/`Timer`).
- [ ] Kill-and-relaunch test passes on simulator with rest running (screenshot before/after).
- [ ] All copy above in the String Catalog with plurals (sets, PRs, exercises).
- [ ] `FakeWorkoutSessionClient` in LedgerTestSupport used by F09 tests.

---
_Filled in by agents during delivery:_
- `F10-active-workout/implementation-notes.md`
- `F10-active-workout/test-findings.md`
- `F10-active-workout/review.md`

## Inputs from F04 (2026-09-29)

F04 shipped the engine this brief drives. **F10 is its first host** (ADR-004 names F10/F17, and F10 ships in
M1, before F17), so ADR-004's amendment binds F10 too; F17 "Inputs from F04" holds the shared rules. Where
these contradict the brief above, they win.

1. **Stamp with the hybrid logical clock.** `LocalWorkoutSessionActor` stamps every envelope it creates
   `wallClock = max(now, newest wallClock seen or sent + 1 ms)`, takes its next `seq` from
   `WorkoutEventStore.highestSeq` + 1, and recovers `newest` at launch under F17 item 3's two rules. Even
   with no peer, raw clocks lose an un-log after an NTP step-back or a relaunch (F04 findings 6 and 12).
2. **Follow ADR-004's host loop.** Own actions: `reduce`, then run its effects in order (`.persist` before
   `.transmit`). Received envelopes (none until F17): append, then rebuild with `WorkoutEngine.replay` and
   run `WorkoutEngine.effects(from:to:)`; never `reduce` them. The store needs no origin filter for haptics.
3. **Effects** are `.persist`, `.transmit`, `.haptic`, `.scheduleRestNotification(endsAt:)`,
   `.cancelRestNotification`, `.updateLiveActivity`, `.materialize(WorkoutState)` (F05 computes the receipt
   through `WorkoutEngine.summary(_:prs:)`) and `.discardLog`. There is no `.persistEnvelope`,
   `.transmitEnvelope` or `.saveToHealth`.
4. **"+30s" is `restExtended(amount:extendsShownRest:tappedAt:)`.** The UI sets `extendsShownRest` when its
   rest had time left (`RestTimer.remaining(at: now) > .zero`), and `tappedAt` is the tap's time. The other
   renamed labels (`setLogged(…, doneAt:)`, `finished(endedAt:)`, …) are in F17 item 7.
5. **The launch step** (`resumeFromStore()`, criterion 12) runs over `WorkoutEventStore.uncompactedWorkoutIDs()`
   and classifies each log by `replay`: live → resume; finished → materialise, then compact; discarded →
   drop, then compact; `nil` → keep. It plays no haptic and does not run `effects(from: nil, to:)`.
6. **No validation windows.** The engine ignores only envelopes with a non-finite date or a rest length
   outside `0 ... WorkoutEngine.longestRest`; F10 adds no time checks of its own.
7. **Swap with "Also update program"** sends `alsoUpdateProgram: true`; the finished state carries it in
   `WorkoutState.programUpdates` to F05's materialisation (F04 criterion 12). Decide whether criterion 8's
   `replaceSlotExercise` runs at the swap or from `.materialize`.
8. **Bounds-check `WorkoutState.cursor`** before indexing `exercises`: a `started` snapshot's cursor is not
   validated, and the engine keeps whatever cursor it has (F04 review N7). F18 and F21 read it too.

## Inputs from F05 (2026-10-01, slice S3)

`GRDBWorkoutRepository` and `GRDBStatsQueries` shipped. What the finish path must know:

1. **`materialize(_:slotUpdates:)` takes only a finished workout.** A state that is not `.finished`, or has no
   `endedAt`, throws `LedgerPersistenceError.notFinished` and stores nothing. It is an upsert by `WorkoutID`, in
   one transaction, so the launch step and a rebuild may call it again. (The F05 records follow-up removed its
   `summary` and `prs` arguments: `WorkoutEngine.summary(state, prs:)` is for the finish screen only.)
2. **F05 detects and stores the records; F10 never passes them** (product decision #27, F05 records follow-up).
   Every write keeps `personal_record` and `pr_count` equal to `PersonalRecords.detect` replayed over history in
   order (by start, then id), each workout judged against the bests before it, `achievedAt` its start. So a
   rebuild, a late workout stored before others, and an edit are all safe; F10 has nothing to keep between
   materialisations.
3. **The live "PR!" moment** (haptic `.personalRecord`, the finish screen's list): call
   `StatsQueries.bests(before: state, for: Set(state.exercises.map(\.exerciseID)))` once the workout starts (and
   again after a swap adds an exercise), then `PersonalRecords.detect(workout: state, against: bests, now:
   state.startedAt)` as sets are logged. Pass the **start** as `now`: the store stamps a record's `achievedAt`
   with its workout's start, so only then are the finish screen's records equal to the stored ones (review
   R-N1; with another `now`, only the kinds and values agree). Those are the bests the store will judge the
   workout against: the stored workouts that started before it (or with it and a smaller id), working and added
   sets only (decision #25). The workout itself is never counted, stored or not, not even a stored copy of it
   that started earlier (a rebuild whose start moved later; review R-SF1, fixed). A workout the store cannot read
   is left out, as the store's replay leaves it out.
4. **Records name only their own workout.** The S3 refusal of a record naming another workout went with the
   `prs` argument.
5. **`programUpdates` is not applied by F05.** `materialize` writes no slot's exercise. Item 7 of "Inputs from
   F04" stands: if a swap is to land with the workout, it must run inside `materialize`'s transaction (an F05
   change, about 15 lines); a separate `replaceSlotExercise` call beside it is not atomic with the workout.
6. **`slotUpdates` replace each slot's whole miss set.** Only `misses` is written, over the stored ones. Apply
   `MissTracking.update` to the program **as stored at that moment**, never to a copy taken when the workout
   started, and never re-send the slots of an older workout on a rebuild: either would clear misses recorded
   since. A slot that is no longer stored (the program was edited or deleted during the workout) is logged and
   skipped, and the workout is still stored.
7. **`lastPerformance`** (for `SessionBuilder` and the swap's "last-known load") is the most recent workout with
   a done **working** set of the exercise: the count of those sets, and the heaviest one's load and reps. A
   workout's date is when it started (product decision #26).
8. **Refusals to surface:** `nulInText` (a workout or exercise name holding U+0000), `inexactWeight` (a weight
   that is not a whole number of 10⁻⁷ g, e.g. an eighth of a pound) and `nonFiniteDate`. Each stores nothing.
   A damaged workout elsewhere in the history never fails a `materialize` (orchestrator decision on R-Q1, F05
   records fix round 1): the replay leaves out a workout it cannot read, logs it, and keeps its stored records
   until a write repairs it.

## Plan amendments (orchestrator, 2026-10-04)

The body above was written before M0 existed. Where it disagrees with this section, this section wins (as do the
two "Inputs" sections). The slice plan and its evidence are in `F10-active-workout/implementation-notes.md`.

**Delivery.** Nine slices: S1 the session seam, S2 the host and the start use case, S3 the persistence follow-up,
S4 the cover and header, S5 solo logging, S6 rest and effects, S7 finish and receipt, S8 swap, S9 supersets.

**Slice S1 — session seam** (what F09 and, later, the watch code against; it replaces the draft under "Domain
changes")
```swift
public struct WorkoutSessionUpdate: Hashable, Sendable {
    public let state: WorkoutState?          // live; finished or discarded in the one update that ends it; nil = no workout
    public let haptics: [Haptic]             // feedback to play, in order; empty in a stream's first element
    public var live: WorkoutState? { get }   // `state` when its phase is `.live`
    public static func haptics(from effects: [Effect]) -> [Haptic]    // the one forwarding rule: the engine's haptics, in order
}
public enum WorkoutSessionError: Error, Equatable, Sendable {
    case workoutInProgress(WorkoutID), notStartable(WorkoutID), noLiveWorkout, incompleteLog(WorkoutID), invalidEndDate
}
public protocol WorkoutSessionClient: Sendable {
    func updates() async -> AsyncStream<WorkoutSessionUpdate>   // current state first (no haptics), then every change; a new stream per call
    func current() async throws -> WorkoutState?
    func start(_ initial: WorkoutState) async throws
    @discardableResult func apply(_ event: WorkoutEvent) async throws -> WorkoutState
    func finish(endedAt: Date) async throws -> WorkoutState
    func discard(endedAt: Date) async throws
}
```
(Revised 2026-10-04 after G2 and G3 round 1: `haptics: [Haptic]` replaced `effects: [Effect]`, `invalidEndDate` was
added, and criteria 1, 3, 4 and 8 below were tightened.)
1. Given a subscriber, when it calls `updates()`, then the first element is the workout as it stands with no
   haptics, and every later change arrives in the order it was applied; two subscribers each get every update. This
   holds when calls overlap: a stream opened while other calls are in flight starts with a state the client
   published and misses no later update, and each update follows from the one before it.
2. Given no live workout, `start` with a live snapshot makes it current; a second `start` throws
   `workoutInProgress`; a snapshot that is not live throws `notStartable`; `apply`, `finish` and `discard` with
   nothing live throw `noLiveWorkout`.
   Of several `start` calls made at once exactly one succeeds and the others throw `workoutInProgress`.
3. Given a live workout, `apply` returns the state after the event, equal to the next update's state, and that
   update's haptics are exactly `haptics(from:)` of the engine's effects for it. An event the engine ignores (ADR-004,
   "Malformed envelopes") changes nothing: `apply` returns the workout as it stands and nothing is published.
4. Given a live workout, `finish(endedAt:)` returns the finished state, publishes it in one update, and afterwards
   `current()` is nil and a new stream starts with a nil state; `discard(endedAt:)` likewise. The ending update is
   published once the workout is stored (or its log dropped), so a subscriber may read history when it arrives. Of
   several overlapping `finish` / `discard` calls exactly one ends the workout, and an `apply` that loses to it
   throws `noLiveWorkout`. If the workout is still live after the call (the engine ignored the end, as it does for a
   date that is not finite), `finish` and `discard` throw `invalidEndDate`, end nothing and publish nothing.
5. `resumeFromStore()` is not on the protocol: it is the host's launch step (S2), and every protocol method waits
   for recovery.
6. The dependency key is `workoutSession`; its unimplemented stub's `updates()` ends at once and its other methods
   throw; its preview value is a fake with no workout.
7. The fake, `FakeWorkoutSessionClient`, is in `LedgerFakes` (ADR-008), runs the real engine, records what it was
   asked (`applied`), and passes the shared `WorkoutSessionClientContract` in `LedgerTestSupport` that S2's host
   must pass too. It is absent from Release builds, as all of `LedgerFakes` is.
8. `ClockText.elapsed(_:)` in `LedgerDomain` is the one elapsed-time formatter for Today, the workout header
   and the receipt: m:ss under an hour ("0:00", "24:22"), h:mm:ss from sixty minutes ("1:01:05"); a negative
   duration reads "0:00". (The format past an hour is put to Pete; the prototype prints "61:05".)

**Later slices (corrections known today)**
- The host runs the rest-notification effects; a screen plays only the haptics an update forwards.
- Files live in `LedgerDomain/Protocols`, `UseCases`, `Engine`; fakes and fixtures in `LedgerFakes`; the app's
  wiring in `LedgerAppKit` (`AppComposition`, `MainRoot`), not under `Apps/Ledger/Sources/`.
- The check's label on a logged row is "Undo set 2".
- Test names follow `docs/testing-strategy.md` §6, not the `test_…` names above.

## Plan amendments — slice S2, host and start use case (orchestrator, 2026-10-05)

S1 (the session seam) is on `main` (#27). This section is the specification of S2; where it and anything above
disagree, this section wins. Evidence and signatures are in `F10-active-workout/implementation-notes.md` ("Inputs
the implementer needs › S2", "Inputs for S2", the orchestrator's rulings).

**What S2 delivers.** `LocalWorkoutSessionActor` in `LedgerSync` (the real `WorkoutSessionClient`),
`HybridLogicalClock` and `StartWorkoutUseCase` in `LedgerDomain`, the launch step `LaunchStep.resumeWorkout`, and
the iPhone app's wiring in `AppComposition`. No screen: nothing the lifter sees changes, but a live workout now
survives a relaunch.

1. **The contract.** The host keeps every clause and every seeded script of `WorkoutSessionClientContract`: over
   in-memory stores, over the GRDB stores, and over stores that suspend inside every call; and also when its
   recovery has not been started (the first protocol call starts it, and every call waits for it).
2. **Own actions follow ADR-004's host loop.** An event is stamped with `seq` = the highest stored for this
   workout and device + 1 and with the hybrid logical clock, reduced, and its effects run in order, `.persist`
   first. If the store refuses the append, the call throws and nothing changes: no state, no clock, no `seq`, no
   update. An event the engine ignores stores nothing and takes no `seq`.
3. **The clock.** A stamp is `max(now, newest stamp seen or sent + 1 ms)`. After a relaunch the clock continues
   from the store's newest wall clock, so a system clock that stepped back never yields a stamp older than one
   already stored (F04 findings 6 and 12). The host never produces a stamp that is not finite: if it cannot, it
   reports an issue and throws, and it never answers `notStartable` for a snapshot the engine would start.
4. **Finish.** `.finished` is stored, the workout is materialised (with the slots' misses from `MissTracking`,
   applied to the program as stored at that moment and only when the active program is the workout's), the log is
   compacted, and only then is the ending update published; `current()` is nil afterwards. If the save fails,
   `finish` throws, the log is kept, nothing is lost, and no ending update is published until a save succeeds: a
   second `finish` retries it and publishes once, and so does the launch step on the next foreground or relaunch.
   What `current()` and open streams show between the failed save and the retry is the implementer's to define, on
   the protocol's documentation and in the notes.
5. **Discard.** `.discarded` is stored, the log is compacted, the ending update is published; nothing reaches
   history.
6. **Recovery** (`resumeFromStore()`; the launch runs it as `LaunchStep.resumeWorkout`, after `loadSettings`, and
   owns the step's task as it owns the others). For each log the store has not compacted:

   | Stored when the app died | The step | Afterwards |
   |---|---|---|
   | nothing, or a `started` that never reached the store | nothing | no workout |
   | a live log | resumes it: no haptic, no effect run | `current()` is the workout, with the same sets, cursor and rest |
   | `finished` stored, not materialised | materialises (misses from the program as stored now), compacts | the workout is in history; no live workout |
   | materialised, not compacted | materialises again (no change), compacts | the same |
   | `discarded` stored, not compacted | compacts | nothing in history |
   | a log that replays to nothing | keeps it and logs a notice | no workout |
   | a log with rows this version cannot read | live: resumes from what it reads; ended: keeps it | a workout, or none |
   | a save that throws | keeps the log, records the step as failed, carries on with the other logs | retried on the next foreground |

   Running the step twice changes nothing. A scene-phase task that is cancelled never cancels the step.
7. **Kill and relaunch** (the brief's criterion 12), on a real database file: after `started` is stored; in the
   middle of a workout with a rest running; after `finished` is stored and before the save; after the save and
   before the compaction; after `discarded` and before the compaction. Each gives the row above.
8. **`StartWorkoutUseCase.start(_:replacingLive:)`**: `.started` (a workout built by `SessionBuilder` from the
   stored program, exercises, last performances and settings, then `session.start`); `.resumed` (a live workout with
   the same source, rule 17); `.conflict(live:)` (a live workout with another source: nothing changes); with
   `replacingLive: true` the live workout is discarded and the new one started. It throws `programNotActive`,
   `dayNotInProgram` or `emptyDay`, and starts nothing then.
9. **The app.** When the database opens, the iPhone's composition builds the host over the GRDB stores, binds
   `workoutSession`, and the launch runs the step. A failure is recorded and retried on the next foreground. The
   watch app is unchanged (it gets the host in F18).
10. **Subscribers and effects.** An ended subscriber is dropped when a publication finds it ended: no lock, no
    unstructured task. The host forwards haptics only; it runs no notification effect yet (S6) and ignores
    `.transmit` and `.updateLiveActivity`.
11. **The contract grows.** It gains a seeded script of calls made at once (starts, applies, ends, subscriptions, and
    a subscriber that acts on what it is told), checked as one history: every update follows from the one before it
    by exactly one call that succeeded, every success is published once, every refusal is one the protocol allows
    for that call, a late stream is a suffix of the history, and haptics are the engine's. It passes on the host over
    suspending stores and on the fake, and a fault shows it can fail.
12. **Budget.** An `apply`, including its append to the GRDB store, takes under 30 ms (architecture §15), measured
    in the nightly tier.

## Plan amendments — slice S3, the persistence follow-up (orchestrator, 2026-10-05)

S1 (the seam, #27) and S2 (the host, #29) are on `main`. This section is S3's specification; where it and anything
above disagree, this section wins. Evidence and line references are in `F10-active-workout/implementation-notes.md`
("Inputs the implementer needs › S3", S2's "Inputs for S3", the review's SF5, the rulings).

S3 finishes the save of a finished workout: the program change a swap asked for lands with the workout, and the
workout's event log is dropped in the same transaction. No screen; nothing the lifter sees changes yet (the swap
sheet is S8).

1. **A program change lands with the workout.** Given a finished workout whose `programUpdates` name a stored slot
   of the workout's own program and a stored exercise, `materialize` stores the workout and sets that slot's
   exercise, in one transaction. Nothing else of the program changes, and the slots' misses are written as before.
   (This is the default of the open product question on "Also update program": the program changes when the workout
   is saved, so a discarded workout leaves it alone.)
2. **What cannot be applied is skipped, not fatal.** An update that names a slot that is not stored, a slot of
   another program, or an exercise that is not stored is logged and skipped; the workout and the other updates are
   still stored.
3. **Saving twice changes nothing.** Materialising the same finished workout again leaves every row of every table
   as it was, the program's included.
4. **The log goes with the save.** `materialize` can be asked to drop the workout's event log in the same
   transaction. When it succeeds, no event of that workout remains; when it fails, nothing changed: no history row,
   no program change, the log whole.
5. **The host uses it.** A finish is: store `finished`, then one transaction (the workout, its records, the misses,
   the program updates, the log dropped), then the ending update. Over the database a workout can no longer be in
   history and still shown as live, `finish` no longer throws for a workout that is already in history, and
   recovery's row "saved, not compacted" remains only for stores that are not one database. The protocol's
   documentation, the failure table in the notes and architecture §6 say so.
6. **The fakes follow** (ADR-008): the in-memory stores apply the same rules, refuse what the database refuses in
   the same order, and are held to the database by the shared contract and the seeded differential scripts.
7. **No migration.** The schema and the version-1 fixtures are unchanged.
8. **Budgets hold** (architecture §15): storing a new workout at the end of history with its program updates and
   the log dropped stays under 50 ms on the 20,000-set fixture, in the nightly lane.
9. **The PR lane gets cheaper.** #29's host suites doubled the iOS test step on CI (998 s against 422 s before it).
   The seeded matrices of the session suites are cut in the PR lane (fewer seeds or set-ups; every clause, every
   kind of store and every fault still run at least once) so that the session suites cost at most a third of what
   they do now, measured locally and reported; the nightly lane keeps the full matrix.

Not in S3: the swap event's payload (O10 is decided when S8 starts), anything History edits or deletes (F13), any
screen.

## Plan amendments — slice S4, the cover and the header (orchestrator, 2026-10-08)

Cut from `main`, which now holds the session host (S1 to S3), the tab shell and the localization rule (#28),
the scrolling-screens convention (testing-strategy §2.5 to §2.6) and F11's editing rules. The first slice of
the workout a lifter can see: starting or resuming a workout opens a full-screen cover with a header (minimize,
the elapsed time, finish) over an otherwise empty body. Logging sets comes in S5. The plan's S4 row lists the
files; "Inputs the implementer needs › S4 — cover and header", "What the cover needs from the shell", and the
"Inputs for S4" sections of S2 and S3 give the calls. About 580 product lines planned. Accepted when:

1. **Start** (criterion 1). From the app's root, asking for a workout of a program's day through the launcher
   runs `StartWorkoutUseCase`, and the cover appears over the tabs showing that workout: its name, "0:00"
   counting up, and the progress segments of criterion 13 with none done.
2. **Resume.** With a live workout, asking for the same day shows that workout as it is, with its real elapsed
   time. Minimize closes the cover and leaves the workout live; asking again shows it again. After the app is
   killed and relaunched with a live workout, the launcher can show it (recovery is S2's; this slice only
   reads the session).
3. **Resume never goes through the start refusal** (F11's finding): a live workout is shown from the session's
   own state even when its day was since deleted or emptied in the program; `StartWorkoutUseCase.start` is
   called only when no workout is live or the day asked for differs.
4. **The conflict** (criterion 2). Asking for another day while a workout is live shows the dialog of the
   brief with its exact texts and its choices (resume the live one; discard it and start the new one; cancel),
   and each choice does what it says, in that order, with nothing started when the discard fails.
5. **Finish, for now.** "Finish" opens a dialog with "Discard" and "Keep lifting" only (the save and the
   receipt are S7). Discard ends the workout through the session, closes the cover and leaves nothing live;
   a discard that fails is shown and the workout stays.
6. **The elapsed time** is drawn from the workout's start with `Text(timerInterval:)` (one `WorkoutTimeline`
   value gives views their time, fixed in previews and tests), is "1:01:05" past an hour, and what VoiceOver
   says for it does not carry a frozen time (F09 S4's ruling: a label without the time).
7. **The store** (`WorkoutStore`, a skeleton here) follows the M1 conventions: `@MainActor @Observable`,
   synchronous intents, its work run from the root's task, `Loadable` state, no unstructured task; it follows
   `WorkoutSessionClient.updates()` and never plays haptics twice (this slice plays none).
8. **The presentation of the header** is pure and holds every string, resolved in `WorkoutCopy` from
   `FeatureWorkout`'s own String Catalog under standards §7; the module's source test forbids ambient clock,
   calendar, locale and zone, as `FeatureToday`'s and `FeatureProgram`'s do.
9. **The shell.** `LedgerAppKit` presents the cover from the launcher above the tabs (`MainRoot`'s `body`, as
   the conventions reserve it), maps `WorkoutRoute`, and the Debug menu gains "Start sample workout" so the
   cover can be reached before Today is wired. No other screen changes.
10. **Tests.** The store against `FakeWorkoutSessionClient` and the in-memory stores (start, resume, conflict
    with each choice, discard, failures, a session update arriving while the dialog shows); the presentation
    word for word; snapshots of the header as the plan lists; one pinned VoiceOver tree for the cover; one UI
    test in the PR lane that starts the sample workout from the Debug menu, sees "0:00" advance, minimizes,
    resumes and discards.
11. **Wiring of the module** as `FeatureToday` and `FeatureProgram` have it: the target's `resources`, the
    coverage thresholds, the snapshot and preview registrations; the gate's catalog and preview steps pass.

## Plan amendments — slice S4 after round 1 (orchestrator, 2026-10-08)

The tester's lifecycle table held over the fake and the real host and under 80 seeded fault sequences (81
tests; two left red on findings); the reviewer approved with five should-fix items and found no path to two
live workouts or a lost one. Rulings, which add to S4's eleven criteria:

12. **The conflict dialog shows its way out** (review SF1, F10-S4-4): three visible choices, "Resume it",
    "Discard and start new" and "Cancel", the last drawn as an ordinary button as "Keep lifting" is.
    (Default until Pete answers; an alert is the other form.)
13. **When every set is logged, every segment reads done** (F10-S4-1): no segment is current.
14. **The elapsed time never traps** (F10-S4-2): a start that is not a finite time reads "0:00".
15. **A start that fails says why, also after a discard** (F10-S4-3): the same reasons as a plain start (the
    day has no exercise; the day is gone; the block has ended).
16. **A failure line claims only what is known** (review SF3): when the session could not be read again after
    a failed call, the text does not say that nothing was changed.
17. **The UI test proves what it says** (review SF2): it reads "0:00", then a later time, by the label's
    value; no check in it can pass without the thing it names. **No unstructured task** in the module is
    pinned by the source test (SF4). The translator's comment on "Exercise %lld of %lld" names each number
    (SF5).
18. **The conflict can be reached in the app** (F10-S4-5): the Debug menu gains a second row that asks for a
    sample workout of another day, and one UI test starts one, asks for the other, and takes each of the
    three choices in turn. If this would take the slice past 1,000 product lines, it moves to S5 and the
    implementer says so. Kill and relaunch with a live workout stays with F15, which needs a UI-test launch
    that keeps its database.
