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
- Performance budget: tap → row state change < 16 ms (one frame); `apply` round-trip incl. persist < 30 ms; the rest's time is the store's reading of the injected date once a second, on the injected clock, and only the rest panel observes it: no `TimelineView`, and nothing else of the cover is drawn again at a tick (S6, criteria 3 as amended and 16; the line read "rest ring animates via `TimelineView(.animation)` with no per-second store updates" until then); cover presentation < 200 ms.
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
19. **Rulings on round 2** (F10-S4-7 to -9). A refused replacement keeps its reason also when the session
    could not be read again. A workout that ended elsewhere while the conflict dialog showed is reported as
    ended, not as discarded (one neutral text). While any set is not logged exactly one segment is current:
    the cursor's exercise if it still has a set to log, otherwise the first exercise that has one.
20. **Deferred to F17, with the product owner's wording** (F10-S4-8): a workout that ended elsewhere while the
    conflict dialog showed is still reported with the "discarded" text. It cannot happen on one phone; it can
    once the watch syncs. Proposed wording: "Your workout in progress has ended." A cursor that names no row
    leaves no segment current, as the tester pins.

## Plan amendments — slice S5, logging the sets of a solo exercise (orchestrator, 2026-10-09)

The plan's S5 alone (about 485 product lines planned; a presentation, views and a store in one slice have
landed 40–60 % over plan, so past about 800 the implementer stops and reports, with the seam presentation +
store / views as the split). Cut from `main`, which holds the cover, its header and the store that follows the
session (S4). After this slice a lifter can log a workout of solo exercises set by set under the cover; rest,
finish, swap and supersets come later and their buttons are not drawn yet (no dead button). The inputs are in
the notes ("Inputs for S5", after S4's sections). The slice is accepted when:

1. **The page** (convention of testing-strategy §2.5–§2.6): the header stays pinned and the body is
   `ScrollView { WorkoutPage(model:) }`; trees and snapshots come from the page; the screen keeps its one
   nightly UI test, which now logs sets.
2. **The current exercise's card** (brief, "Copy (exact)"): the eyebrow "Exercise 2 of 5", the title, the
   TARGET line "5 × 5 @ 185 lb · RPE 8", "Last" with the date and the scheme or "No history yet" (then no
   "Repeat"), the column header "#", "lb" or "kg", "reps", one row per set ("1"…, "D" for a drop set), and
   "+ Add set". Every string is final in the model (`WorkoutPresentation+Card`); pounds and kilograms.
3. **Logging** (criterion 3 of the brief, without rest): the check on the shown row applies `setLogged`; the
   row is drawn done; the cursor moves by rule 20 as the engine says; a done row's check un-logs it. The
   store sends no rest event; the rest panel is S6's and nothing of it is drawn.
4. **Steppers** (criterion 5): "+" and "−" on weight apply `setTargetChanged` by the Domain's step for the
   exercise's equipment and the lifter's unit, never under 0; reps never under 1; a stepper on a row that is
   not shown selects it first. The steps and limits are the Domain's; the presentation and the store add no
   rule.
5. **Repeat and add** (criterion 9): "Repeat" gives every set of the exercise the last workout's weight and
   reps (done flags unchanged); "+ Add set" appends a copy of the last row with no drop flag, and the header's
   segment for that exercise widens.
6. **Remaining**: the list "REMAINING" of the exercises still to do with "5 × 5"; a tap jumps there.
   Supersets are S9's: a workout that holds one draws its members as solo exercises would not be right, so
   say in the report what this slice draws for such a day, and draw nothing that logs wrongly.
7. **Taps are applied in order, each once** (the plan's pump): intents are synchronous; one task of the root
   drains them; two quick "+" give two steps; a double tap on a check logs once; while an intent's work
   awaits, later taps wait their turn and none is lost or applied to a stale workout. No unstructured task.
8. **A failed apply** shows through the failure path S4 built (its alert and texts); the page stays as the
   session last said. `isBusy` disables the page's controls as it does the header's.
9. **Orange once** (criterion 13): the check on the shown row is the page's one accent; every icon-only
   control has a spoken label; each set row is read as one stop with its controls as the design system's
   set row does it; steppers are adjustable.
10. **Sizes and settings**: nothing cut or overlapping at `.accessibility3`, Bold Text, Increase Contrast,
    right to left, 375 and 402 pt; every target 44 pt. A check that can see a word cut inside its frame is
    used (F11 S9's tester wrote one: `ProgramViewsCutAdversarialTests`; copy its idea).
11. **Words**: `WorkoutCopy` and the module's catalog under standards §7; counted texts take their plural
    form by the catalog's language, as `ProgramCopy`'s `Locale.forCountedText` does (bring the same fix to
    this module's counted texts; `FeatureToday`'s is a separate chore). Texts the brief does not give are
    listed for the product owner.
12. **Pure and total**: the presentation reads no ambient clock, calendar, locale or zone; a workout with no
    exercise, an exercise with no set, a slot whose exercise is not stored, a cursor at the end all give a
    model and do not trap.

**Not in this slice:** rest and haptics (S6), finish and the receipt (S7), swap (S8), supersets (S9), any
change to the session engine's rules, `LedgerAppKit` beyond what the Debug rows need, the project file or a
test plan.

## Plan amendments — slice S5 after round 1 (orchestrator, 2026-10-10)

The reviewer approved with six should-fix items; the tester found five bugs (two of them the reviewer's, two
latent) and one question, left seven tests failing, and its 16 seeded storms of taps agree with the same taps
made one at a time. Rulings, which add to S5's twelve criteria:

13. **Criterion 7 is reworded.** Taps are applied in order, each once, planned at their turn on the newest
    workout. A refused change drops the taps waiting behind it and says so through the alert (a set is never
    logged at a weight the lifter did not see); nothing else drops a tap.
14. **Minimize keeps the taps made before it** (F10-S5-1): taps still waiting when "Minimize" is tapped are
    applied; the workout goes on and loses no set.
15. **A restart plans on the newest workout** (F10-S5-2, -3): after the cover's tasks start again, a waiting
    tap is planned on the session's current workout, not on the one last drawn, and an answer kept from
    before the restart is forgotten.
16. **"REMAINING" lists only what can be logged** (F10-S5-4, review S-1; criterion 6's own words): a later
    exercise with no set left is not listed, so no jump leads to a page with nothing to do. Its "n × m"
    counts the working sets, as the card's target line does, not the drop set (review N-9).
17. **The page starts at the top when the shown exercise changes** (F10-S5-5, review S-2): after a jump or
    the cursor's move to another exercise the eyebrow and the name are on screen at every text size.
18. **A second touch does not undo a set just logged** (F10-S5-6, review S-3): an un-log within one second
    of the set's `doneAt` is ignored, as a pure rule in the edit's plan using the moment `make` already
    receives; no timer. After that second, the check un-logs as before. (One second and the rule itself are
    listed for the product owner; the prototype has no guard.)
19. **Room between the two facts** (review S-5, N-8): at every size "Last" stands nearer its own value than
    the target's.
20. **Housekeeping** (review N-2, N-4, N-10): the comments that contradict the code; the test name that
    still says 27 keys.
21. **Accepted as built:** the queue with a wake signal; a day with a superset as switching solo cards until
    S9; "1 pounds" in speech; the look decisions; an un-logged row does not become the shown row.

The tester's seven failing tests pass unedited. **For the product owner, with S9:** how a lifter goes back
to an earlier or a finished exercise (the spec lists later ones only); whether orange on every logged row's
disc and on the shown row's ring is the "once per surface" he wants (the design system's set row draws
both). **For S7:** a refused change while the finish dialog is open (review N-1). **Chore:** the
counted-text helper moves to a shared place with `FeatureToday`'s fix.

**Criterion 13, amended after round 2** (orchestrator, 2026-10-10; F10-S5-7): two things drop waiting taps and
no other: a refused change, and the session's updates ending (the failed screen, whose "Close" closes the
cover). A call that never returns under "Minimize" is accepted as a hung discard is: no timeout. **For S9**
(implementer's question): once the watch syncs, a chosen exercise whose every set is then logged elsewhere
stays on screen with nothing to log; the choice should give way.

## Plan amendments — slice S6, rest and haptics (orchestrator, 2026-10-10)

The plan's S6. Cut from `main` at release 0.10.0, which holds solo logging (S5). About 385 product lines
planned; slices with a store in them have landed far over plan, so the implementer reports the count at
each stage and stops past about 800 with a proposed split (the natural one: the two client protocols with
their fakes and `LiveHaptics`, against the panel). The notes' "S6 — rest and effects" and "Inputs for S6"
are part of this contract. The slice is accepted when:

1. **The rest panel is drawn while a rest is shown** (brief criteria 3 and 6): `RestRing` with the time
   left as m:ss, the line naming the next set (from `WorkoutPresentation.activeSet`), "+30s" and "Skip
   rest". It floats over the page at the bottom of the cover (v2); the page keeps bottom room so its last
   row and "+ Add set" can be scrolled clear of it. With `autoRest` off no panel ever shows.
2. **What is shown is `WorkoutState.shownRest`**, a Domain addition: the running rest; after it has ended,
   the same rest until a set is logged, the rest is skipped or it is extended; otherwise nil. The view and
   the presentation decide nothing about when a rest exists.
3. **The clock rule (ADR-004)**: the time left and the ring's fraction are `RestTimer.remaining(at:)` and
   `fraction(at:)` of the injected date, drawn on a timeline; nothing counts down in a stored property.
   After 40 s in the background the panel shows the wall-clock time left; a rest that ended meanwhile
   shows "0:00" and "Rest over".
4. **"Rest over"** stays until "+30s" (a new 30 s rest, decision #7), "Skip rest" or the next logged set.
5. **"+30s" and "Skip rest" are two `WorkoutEdit` cases through the one tap queue**, one event each:
   `restExtended(amount: .seconds(30), extendsShownRest: remaining > .zero, tappedAt: now)` with both
   read from the tap's injected date, and `restSkipped`. S5's rules hold for them: applied in order, each
   once; a refused change drops the later taps; "Minimize" waits.
6. **Un-logging a set never cancels a rest** (rule 22); the one-second undo guard is unchanged.
7. **Haptics**: `HapticsClient.play(_:)` in the Domain; a recording fake; the unimplemented stub;
   `LiveHaptics` in `LedgerAppKit`, bound in `AppComposition`. Exactly one subscriber, the workout store's
   `follow()` loop, plays each update's `haptics`, each once, also across the cover's tasks restarting.
   `.restOver` is played once when the shown rest reaches zero while the cover is up, not again on a
   redraw, a return from the background or a reopened cover whose rest had already ended.
8. **Notifications**: `NotificationsClient.scheduleRestOver(at:)` (replacing any scheduled one) and
   `cancelRestOver()` in the Domain, with a recording fake and the stub. The host, not the store, runs
   `.scheduleRestNotification` and `.cancelRestNotification`, so that they run with no cover up. The live
   client stays unimplemented in the app until F23: no permission prompt and no system notification in
   this slice, and the app must not trap on the unimplemented client when a rest starts (how is the
   implementer's proposal, stated in the notes).
9. **A full-width `PillButton`** in `LedgerDesign`; its gallery references are recorded again and the
   change in every re-recorded image is accounted for.
10. **Orange once on the panel**: "Skip rest" (brief criterion 13), pinned by a test or a list. While the
    panel is up, say in the notes what else on the cover is orange, for Pete.
11. **Texts**: only the brief's and the prototype's ("+30s", "Skip rest", "Rest over", the next-set
    line); each in the module's catalog through a `WorkoutCopy` file; any text they do not give is listed
    for Pete. A counted text takes its form by the catalog's language (`forCountedText`, moved to
    `WorkoutCopy.swift` if a second file needs it).
12. **VoiceOver**: the panel is reachable after the card; the time left is read as a duration, not as
    digits and a colon, and is not announced every second; "+30s" has a spoken label that says what it
    does; every target is 44 pt.
13. **Sizes and settings**: nothing is cut or overlaps at `.accessibility3` on 375 and 402 pt, light and
    dark, with Bold Text and right to left; the panel never covers the shown row's check in a way that
    cannot be scrolled clear. Snapshots as the plan's table (the panel resting and rest over, the whole
    screen resting).
14. **Reduce Motion**: the ring does not animate between ticks when it is on.
15. **The UI tests** `WorkoutLogging` and the testers' pass with the panel present (skipping the rest or
    tapping through it); one UI test taps "+30s" and "Skip rest".

**Not in this slice:** the system notification itself and its permission (F23), the watch, finish and the
receipt (S7), swap (S8), supersets (S9), the project file or a test plan.

## Plan amendments — slice S6, rulings during G1 (orchestrator, 2026-10-10)

The implementer stopped on one point and asked: the tester's `sources_readNothingAmbient`
(`WorkoutWordsAdversarialTests`) forbids the spellings "Timer" and "TimelineView" anywhere in
`FeatureWorkout`, against criterion 2 (the shown rest is a `RestTimer`) and criterion 3 ("drawn on a
timeline"). The rulings, as given:

1. **"Timer" against `RestTimer`: the criterion wins.** The check's `scanned(_:)` blanks the exact spelling
   `RestTimer` and nothing wider, so Foundation's `Timer` (`Timer.publish`, `Timer.scheduledTimer`) is still
   caught. A control in the implementer's own tests, not in the tester's file, shows that a planted
   `Timer.scheduledTimer` still fails the check. The edit is listed in the notes.
2. **"TimelineView": the tester's check stands, and criterion 3 is amended.** `TimelineView`'s date is the
   system's clock, not the injected one: the ambient read the check exists to stop, and a panel drawn from it
   cannot be tested at a chosen instant. **Criterion 3, as amended:** the time left and the ring's fraction
   are `RestTimer.remaining(at:)` and `fraction(at:)` of the injected date, computed at every tick of a
   clock-driven tick; no `TimelineView`, no `Timer`, no stored countdown. A stored "now" that the injected
   clock advances is not a countdown in a stored property: what is forbidden is a stored remaining value that
   is decremented. What stays: the right time left at once on a return from the background (the tick reads
   the date again; it does not add a second), "0:00" and "Rest over" for a rest that ended meanwhile, and
   `.restOver` once (criterion 7). `forbidden` is not edited for this. If the ring wants a smoother motion
   than a step a second, that is a look question: it is drawn stepped at each tick, with an implicit
   animation between ticks unless Reduce Motion is on (criterion 14), and noted for the product owner.
3. **".formatted(" on the spoken time** is removed the implementer's way (the format style's `format(_:)`
   with the injected locale); no edit to the check.
4. **`haptics = FakeHaptics()` as a default of `withTestDependencies`** is approved on two conditions: a
   fresh recording fake for each call, never one shared between tests; and the app's composition still binds
   the live client itself, with a test that fails if `AppComposition` leaves `haptics` unbound. It is
   recorded in the notes as a change to shared test support.

## Plan amendments — slice S6 after round 1 (orchestrator, 2026-10-10)

The reviewer requested changes (one blocking item, five should-fix); the tester left four tests red and put
seven questions. The rulings, which add to S6's fifteen criteria:

16. **A tick redraws the rest panel and nothing else** (review S6-B1, its option c). The store keeps
    `moment` and `keepRestTime()`. `rest` leaves `WorkoutModel` and `now:` leaves
    `WorkoutPresentation.screen`; `store.restPanel` is the only reader of `moment`; `WorkoutScreen` has a
    bottom-inset slot, filled by a small view that reads `store.restPanel`. Pinned on the host: reading
    `store.model` under `withObservationTracking` does not fire on a tick, and reading `store.restPanel`
    does. The brief's non-functional line and `docs/architecture.md` §13 say what is built: the store ticks
    once a second from the injected clock; only the panel observes it; no `TimelineView`.
17. **The panel leaves the page room at every text size** (tester F10-S6-4, review S6-SF2). At least 120 pt
    of the page show between the header and the panel on the 375 pt home-button phone, the 375 pt notch
    phone and the iPhone 17, at every size to `.accessibility5`. The way: a compact panel at the
    accessibility sizes, in the cheapest form that reaches it and no further: no ring (the time as text,
    the state line, the next-set line); then the two buttons side by side where their words fit whole; then
    dropping the next-set line. Nothing may be cut and targets stay 44 pt. The tester's
    `screen_leavesThePageRoom_beyondTheCriterion` passes unedited (its threshold is 44 pt).
18. **The time of a tap is the time it was tapped** (the tester's question 1; criterion 5's own words).
    "+30s" and "Skip rest" carry the injected date read when `send` is called, not when the queue reaches
    them: behind a held save, "+30s" tapped with 2 s left extends the shown rest. The same for a log's
    `doneAt` and the other edits where it is the same small change.
19. **The ring does not ease after zero** (review S6-SF5): no animation when the rest is over.
20. **The tester's three notes with red tests**: F10-S6-2 (a rest already skipped in the session is buzzed
    if the page has not heard) and F10-S6-3 (a haptic lost when `follow()` starts again between a change
    and its update) are fixed. **F10-S6-1** (the wall clock set back at "Rest over", then a tap) is left
    red and not fixed: a wall clock set backwards under "Rest over" is rare, and the tester rated it a
    note. The notes say what happens, why the harness's shape rules out a local fix, and what a real fix
    would take; the tester pins it as built in round 2, and it is recorded for F17 with the other clock
    cases.
21. **Recorded, not built** (the notes' inputs): `Settings.watchBuzz` gating the phone's buzz at zero belongs
    to the slice that builds Settings' effect on the workout (F14; spec §4.5, testing-strategy D11); the
    brief's VoiceOver announcements ("Rest, 1:30 remaining", "Rest over") go into S7's criteria; F23:
    recovery re-asserts the notification, `rest_runsWithoutANotificationsClient` becomes a test that fails
    when the client is missing, a `start` onto a kept log schedules; F18: `follow()` awaits the haptics
    client before the next update; F17: the two peer cases in the tester's question 7; S9: the superset
    cases in the tester's question 2.

**Two rulings during the fix round**, on tester's expectations that a ruling inverts; both edits are listed
for the tester's audit in round 2:

- `screen_roomIsMeasured`'s last assertion (55 to 75 pt of page on the iPhone 17 at `.accessibility5`, the
  old panel's) becomes the compact panel's measured value ± 10 pt, with a comment naming ruling 17 and the old
  range; nothing else in that test changes. The notes say what the app itself shows there now.
- `eachSecond_oneChange_thePageUntouched` watches both: `store.model` changes 0 times in the 10 s and
  `store.restPanel` 10 times; `restPanel`'s clock reads "2:20"; 0 changes of either after the rest's end.
  Ruling 16 inverts exactly that expectation.

## Plan amendments — slice S7, finish and receipt (specification, 2026-10-13)

**A split is proposed: S7a finish and save, then S7b the receipt.** The plan gave S7 about 490 product
lines. Counted honestly with what has since been put on it (the rest announcements and their client, the
refusal under the sheet, the wait for queued taps, the failed save, the live records) it is about 1,230
planned lines (560 + 670, "Estimate" below), and slices with a store have landed 25 % (S6) to 90 % (S5) over
plan. One pull request would pass 1,000 (standards §10). The seam leaves no dead button: after S7a "Save
workout" stores the workout and the cover closes onto Today's Logged card (what v2 does, spec rule 33);
S7b keeps the cover up for the receipt. S7a merges before S7b is cut (no stacked PRs). Until the
orchestrator rules (R1), criteria 1 to 24 are S7a's, 25 to 37 are S7b's, and 38 to 40 hold in each part
for its own views.

Cut from `main` at `77b33ec`, which holds the cover, solo logging and the rest panel (S4 to S6). After
S7a a lifter can end a workout and have it in history, and VoiceOver is told when a rest starts and ends.
After S7b the saved workout shows its receipt (time, sets, volume, new records, logged against prescribed)
before "Done" returns to Today. The notes' "S7 — finish and receipt" and the "Inputs for S7" of S2, S3, S5
and S6 are part of this contract; where they and this section disagree it is listed under "For the
orchestrator to rule".

### S7a — finish and save

**The sheet**

1. **"Finish" opens a sheet, not the system dialog** (R2). `dialog == .finish` presents `FinishSheet` on
   `SheetChrome` with the title "End workout?" (a VoiceOver heading), "Keep lifting" as the chrome's
   cancel, the line of criterion 2, "Save workout" (`PrimaryButton`) and "Discard" (`PillButton`,
   outline, `fillsWidth`) under it. The `confirmationDialog` leaves `WorkoutRoot`. "Keep lifting", a
   swipe down and VoiceOver's escape each send `.keepLifting` and leave the workout untouched.
2. **The line** is two lookups joined with " · " in the presentation (R4): "23 of 25 sets logged" and
   "24,180 lb moved" ("kg moved" in a kilogram workout). The numbers are `WorkoutState.doneSets`,
   `totalSets` and `volume.formatted(in: state.units)` of the workout the store shows. The total picks the
   plural form, with `locale.forCountedText`; the done count and the volume are passed as text.
3. **The sheet follows the workout.** A change that arrives while it is up (a queued tap landing, a set
   logged elsewhere) redraws the line and the state of "Save workout"; the sheet stays (S4's table, row
   S8).
4. **Zero sets.** With `doneSets == 0` "Save workout" is disabled and looks disabled; "Discard" and "Keep
   lifting" answer. `send(.save)` with no done set changes nothing and calls nothing: the guard is the
   store's, not only the button's.
5. **The model is pure and final**: `WorkoutPresentation.finishSheet(_:isSaving:locale:) ->
   WorkoutFinishModel` holds every string, `canSave` and `isEnabled`; the view decides nothing. A workout
   with no exercise gives "0 of 0 sets logged · 0 lb moved" and does not trap.
6. **Orange once**: "Save workout" is the sheet's one accent, pinned as S6's criterion 10 is. "Discard"
   is not drawn in a destructive colour (the brief gives it none; O1).
7. **Identifiers**: `workout.finish.save`, `workout.finish.discard`, `workout.finish.keep` (the last two
   unchanged, so the UI tests that discard keep passing unedited).

**The save**

8. **"Save workout" saves once.** `send(.save)` sets `isSaving`, reads the injected date once (the end
   of the workout is the time of the tap, S6 ruling 18) and makes the next `saveAttempt`; the root's
   `.task(id: store.saveAttempt)` runs `store.save()`, which calls `session.finish(endedAt:)` with that
   date. No unstructured task. A second tap, and every other intent, does nothing while `isSaving`.
9. **No logged set is lost** (input 3; R3). Taps queued before "Save workout" are applied first, in
   order, each once, planned on the newest workout; `finish` is called only when the queue is empty and
   the last `apply` has answered. So a tap queued before "Finish" is in the saved workout, and the `Asked`
   log reads every change, then `.finished(endedAt)`. A call that never returns is waited for, as under
   "Minimize": no timeout.
10. **While it saves** the sheet stays up with its three controls disabled and its interactive dismissal
    off; the header, the page and the rest panel are disabled by `isBusy`.
11. **If the queue leaves no done set** (the last logged set's un-log was waiting), `finish` is not
    called: `isSaving` is false again and the sheet shows criterion 4's state.
12. **A change refused under the sheet wins** (S5 review N-1). Whether the sheet is waiting for an answer
    or for a save: the taps behind the refused one are dropped (S5 ruling 13), a waiting save is withdrawn
    (`isSaving` false, `finish` not called), the sheet goes down and `dialog == .editFailed` shows S5's
    alert over the cover. A workout is never saved without a change the lifter believes was made. After
    "OK" the cover is as the session last said, and "Finish" opens the sheet again.
13. **Saved.** When `finish` returns a state whose phase is `.finished`, or the stream's ending update
    carries one, whichever comes first: `exit == .route(.saved(id))`, once; the cover closes; the app
    selects Today, which shows the Logged card (F09's, from the same ending update). `.workoutFinished`
    is played once, by `follow()`, in either order of the two.
14. **Discard is unchanged**: one tap, the queued taps are dropped, S4's rows S5 to S7 and its
    `discardFailed` alert hold, now from the sheet's button.

**Error paths**

15. **A save that fails is shown, and nothing is lost.** Any error of `finish` other than
    `noLiveWorkout` and a cancellation with the cover (`invalidEndDate`, `incompleteLog`, what the store
    threw), and a returned state that is not finished: logged (never as a cancellation), `isSaving`
    false, the sheet down, `dialog == .saveFailed`, the cover up. The alert reads "Couldn't save this
    workout" / "It's still on this iPhone. Try again." with "Try again" and "Close" (R7). It offers no
    "Discard": after a failed save a discard would store the workout (tester's note on S2).
16. **"Try again"** runs `finish` again with the same `endedAt` as the first attempt (the host keeps the
    first end anyway). **"Close"** takes the alert down and leaves the cover as the session shows it. The
    store keeps no knowledge of a waiting end beyond that (R10): what the lifter does next meets the rules
    already built (a tap whose `apply` completes the save ends through criterion 13; one that is refused
    shows S5's alert; "Minimize" closes).
17. **`noLiveWorkout` is no failure**: the workout ended by another hand first. `isSaving` stays until
    the ending update says how: finished closes as `.saved(id)`, discarded as `.discarded`.
18. **The cover's tasks starting again mid-save.** A cancelled `save()` shows nothing (the host
    completes the call in a task of its own). The task that starts again runs the same attempt with the
    same `endedAt`. Every outcome is one of: the finished state is returned; `noLiveWorkout` and the
    stream says finished; `noLiveWorkout` and a new stream's first element is nil. All three end in
    `exit == .route(.saved(id))` with the id of the workout being saved: never `.nothingToShow`, never
    the failure alert, and history holds the workout once. A pump that starts again while the save
    waits plans the waiting taps on the session's workout (S5 ruling 15) and the save follows them.
19. **A workout ended elsewhere while the sheet shows** closes the cover as S4's rows S9 and S10 say,
    sheet included.

**Rest announcements** (deferred from S6, ruling 21; brief, "Accessibility")

20. **A client.** `AnnouncementsClient.announce(_:) async` in `LedgerDomain/Protocols/Clients.swift`; the
    key `announcements`, its unimplemented stub, a recording fake in `LedgerFakes` (a fresh one per
    `withTestDependencies` call, as `FakeHaptics` is); `LiveAnnouncements` in `LedgerAppKit`, bound in
    `AppComposition`, with a test that fails when the composition leaves it unbound. Posting is ambient,
    so no file of `FeatureWorkout` posts one itself (the source test pins it).
21. **"Rest, 1 minute, 30 seconds remaining"** is announced once for each shown rest that has time left,
    from `keepRestTime()`'s first pass for it: when a set's log starts a rest, when "+30s" makes a new
    one (O8), and when the cover opens on a running rest. The time is `RestTimer.remaining(at:)` of the
    injected date, rounded up to the second and put in words by the formatter the panel's `spokenTime`
    uses (R8). Not again at a tick, on a redraw, on a return from the background, or when the cover's
    tasks start again with the same rest.
22. **"Rest over"** is announced exactly where and when `.restOver` is played (S6 criterion 7 and ruling
    20: once for a rest, only when it was seen running and ended on time), after the haptic. A rest that
    was skipped, replaced by the next set's, or already over when the cover opened announces nothing.
23. Both texts are `WorkoutCopy` lookups. Whether VoiceOver speaks the announcement over its own reading
    of the row just activated cannot be seen in a test process: the notes say what a device does.

**Words and conventions**

24. Lookups only in `WorkoutCopy+Finish.swift` (and `+Rest` for criterion 21), English text as the key,
    every key in the catalog as `translated`; the views in `FeatureWorkout/Views/`; no `Timer`,
    `TimelineView` or `.formatted(`; the module's source tests pass unedited. `docs/architecture.md` §13
    gains the key.

### S7b — the receipt

25. **A workout this cover saved shows its receipt; the cover stays up.** Criterion 13 changes for a
    save the lifter asked for in this cover (`send(.save)` was accepted): the finished state, from
    `finish`'s return or from the ending update, whichever comes first, sets the store's receipt once and
    `store.model == .receipt(ReceiptScreenModel)`; no exit yet. A workout finished by another hand still
    closes the cover as `.saved(id)` with no receipt (S4's row S10), and so does criterion 18's third
    outcome, where no finished state reached the store (O7).
26. **"Done"** sets `exit == .route(.saved(id))`; the app selects Today, which already shows the Logged
    card. `WorkoutRoute` gains no case (R5). Identifier `workout.receipt.done`.
27. **The screen** (convention §2.5–§2.6) is a pinned header and `ScrollView { ReceiptPage(model:) }`:
    the header holds the date, the workout's name (a heading) and "Done"; the page is
    `LedgerDesign`'s `ReceiptLayout`. Trees and references come from `ReceiptParts`.
28. **The date** is the day the workout started (decision #26), as the brief writes it: "Wednesday,
    September 16", from the injected calendar and locale, with a format style's `format(_:)`. The name is
    the workout's, as stored.
29. **Three tiles**: "TIME" with `ClockText.elapsed(summary.elapsed)` ("24:22", "1:01:05"); "SETS" with
    "23/25"; "LB MOVED" or "KG MOVED" with `summary.volume.formatted(in:)` ("24,180"). `summary` is
    `WorkoutEngine.summary(finished, prs:)`; the presentation adds no arithmetic.
30. **The records line** shows only when `summary.prs` is not empty: "1 new PR this session" / "3 new
    PRs this session", by `locale.forCountedText`. The records are `PersonalRecords.detect(workout:
    against: bests, now: startedAt)` over `StatsQueries.bests(before:for:)` for the workout's exercises
    (brief, Inputs from F05, item 3). The store passes nothing to the save: F05 stores its own (R6). A
    deload workout has none.
31. **Bests that cannot be read** leave the line out; the failure is logged; the receipt shows with the
    tiles and rows; nothing is retried. The receipt never waits for the bests more than their one read:
    until it answers, the receipt shows without the line.
32. **The rows**: "LOGGED" (a heading) and "Prescribed on the right"; then one row for each exercise in
    the workout's order with `ReceiptRow.name`, `target` and one chip for each entry of `actual` ("5 ×
    185×5", "185×4", "—"), shown as the Domain gives them (not catalog entries). Chips wrap.
33. **`ReceiptLayout` is string-only** (`LedgerDesign/Components`): a model of final strings, no
    `LedgerDomain` type, no lookup, tokens only; it is in the gallery and the component previews. F13
    reuses it. `docs/architecture.md` §11 lists it.
34. **Pure and total**: `WorkoutPresentation.receipt(_:records:locale:calendar:) -> ReceiptScreenModel`
    reads nothing ambient; a workout with no exercise, an exercise with no done set ("—"), a start that
    is not finite and a zero volume all give a model.
35. **No orange control on the receipt**: "Done" is ink. Orange is the "TIME" label and the records
    line (prototype); listed in the notes for the product owner.
36. **The live record** (brief, Inputs from F05, item 3). The bests are read once when the cover shows
    the workout. When a logged set makes a record that the workout did not hold before, the store plays
    `.personalRecord` once for that record (exercise and kind) in the store's life; the records the
    workout already holds when the cover opens are not played; an un-log and a second log of the same set
    do not play it twice. Nothing is drawn for it (O10). **This is the first thing to leave the slice**
    if S7b passes about 800 lines: it then goes with S8, which reads bests for a swapped exercise anyway.
37. **Nothing of the live workout remains** on the receipt: no rest panel, no rest tick, no announcement;
    `keepRestTime()` has ended with the workout.

### Accessibility (both parts)

38. **Sizes**: nothing cut, overlapping or out of reach from `.large` to `.accessibility5` on 375 pt
    (home-button and notch phones) and on the iPhone 17 (402 pt), light and dark, checked by a cut check
    of `ProgramViewsCutAdversarialTests`' kind; every target 44 pt. At the accessibility sizes: the sheet
    is its pinned title and cancel over `ScrollView { FinishSheetPage }` (a sheet whose content scrolls,
    §2.6) with both buttons full width; the receipt's tiles stand one per row, a row's target stands
    under its name, "Done" stands under the title. Numerals shrink before they wrap and never truncate
    ("1,234,567").
39. **Bold Text and right to left**: the same checks pass with Bold Text, and with the layout mirrored
    (the sheet's cancel and the receipt's "Done" at the other edge, a row's target at the other edge). A
    Domain-formatted line ("5 × 185×5", "24:22") keeps its characters in the same order.
40. **VoiceOver**, pinned as trees from the parts:
    - Sheet: "End workout?" (heading); "Keep lifting" (button); the line as one stop, "23 of 25 sets
      logged, 24,180 lb moved"; "Save workout" (button; dimmed at zero sets and while saving); "Discard"
      (button). The escape gesture is "Keep lifting".
    - Receipt: the date; the name (heading); "Done" (button); three tiles, each one stop: "TIME, 24
      minutes, 22 seconds" (the duration in words, never "24:22"), "23 of 25 sets logged", "24,180 lb
      moved" (the sheet's two lookups); the records line; "LOGGED" (heading); then each exercise as one
      stop: its name, "Prescribed 5 × 5 @ 185 lb", "Logged 5 × 185×5, 185×4" or "Nothing logged".
      "Prescribed on the right" is hidden from VoiceOver: it describes the picture.
    - The announcements of criteria 21 and 22.

### Texts

From the brief ("Copy (exact)", line 55) and the spec, word for word:

| Text | Where | Source |
|---|---|---|
| "End workout?", "Save workout", "Discard", "Keep lifting" | sheet | brief :55; spec :452–453 (the watch's overlay) |
| "%@ of %lld sets logged" (one: "%@ of %lld set logged") · "%@ lb moved" / "%@ kg moved" | sheet; spoken tiles | brief :55 "%lld of %lld sets logged · %@ lb moved", as two keys (R4) |
| "Rest, %@ remaining", "Rest over" | announcements | brief :82 ("Rest, 1:30 remaining"), with the time in words (R8); "Rest over" is S6's key |
| "Done", "TIME", "SETS", "LB MOVED", "KG MOVED" | receipt | brief :55; spec :291–292 |
| "%lld new PRs this session" (one: "%lld new PR this session") | receipt | brief :55; spec :293 |
| "LOGGED", "Prescribed on the right" | receipt | brief :55; spec :294 |
| "Close", "OK", "Couldn't save that change", "Try again." | alerts | already in the catalog (S4, S5) |

The date, the elapsed time, "23/25", the volume, the targets and the chips are formatted values, not
catalog entries.

**Invented — for the product owner** (none is in the brief or a prototype):

| Text | Where | Note |
|---|---|---|
| "Couldn't save this workout" | failed save, title | from the planner's draft (notes, "Decisions for Pete" 5), whose default holds |
| "It's still on this iPhone. Try again." | failed save, message | the draft read "…and Ledger will try again."; no product name (standards §7), no promise (R7) |
| "Try again" | failed save, button | the draft's |
| "Prescribed %@" | receipt row, spoken only | so a listener can tell the target from what was logged |
| "Logged %@" | receipt row, spoken only | the same |
| "Nothing logged" | receipt row, spoken only | what "—" is read as |

"Close" on the failed save reuses the existing key; its translator's comment is widened to cover both
uses.

### Snapshot references

From `FinishSheetParts`, `ReceiptParts` and the gallery, on the pinned simulators; none of the whole
cover (a presented sheet is not a part of the hosted screen).

| Part | New references | Count |
|---|---|---|
| S7a | `FinishSheet` {withSets, zeroSets} × {light, dark} at `.large`; withSets × {light, dark} at `.xLarge`; withSets dark at `.accessibility3` | 7 |
| S7b | `ReceiptView` {withPRs, noPRs, kg} × {light, dark} × {`.large`, `.xLarge`}; withPRs dark at `.accessibility3` | 13 |
| S7b | `ReceiptLayout` in `LedgerDesignTests`, the phone matrix | 6 |

26 new (the plan's budget row says 25: it had one `.accessibility3` for both views). Changed: the
`DesignGallery` reference and the composites that include it (up to 5), all in S7b; S7a changes none.
Each PR stays under 20 changed.

### Tests the criteria ask for

Store tests against `FakeWorkoutSessionClient`, the host over the in-memory stores (`WorkoutScene.onHost`)
and the test target's session doubles (`GatedSession`, `FlakySession`) for a held and a failing
`finish`; the fake gains no failure switch (R9). The presentation word for word, pounds and kilograms.
The trees of criterion 40. One PR-lane UI test in S7a: start the sample workout, log a set, "Finish",
"Save workout", Today shows the Logged card; in S7b it reads the receipt's "1/…" tile and taps "Done"
first. The nightly `WorkoutLogging` passes.

### Not in this slice

Swap (S8) and supersets (S9), a receipt row for a superset's letters included; the system notification
and its permission (F23); the watch, `Settings.watchBuzz` and "Resting · watch buzzes at zero" (F14, F17
to F19); history screens and Today's "View session" opening a receipt (F12, F13); the spec's empty
receipt ("Nothing logged yet…": a receipt here always has a workout); "Still lifting?" (F23); HealthKit;
telling a reader that an end is waiting (R10); a failure switch on `FakeWorkoutSessionClient` and the
waiting-end contract clauses; any change to the engine, the host, the Day editor's destructive question,
the project file or a test plan.

### Estimate (product lines: Swift, not blank, not comment)

| S7a | Lines | S7b | Lines |
|---|---|---|---|
| `Views/FinishSheet.swift` (with its page) | 85 | `LedgerDesign/Components/ReceiptLayout.swift` (model, tiles, rows, gallery entry) | 165 |
| `WorkoutFinishModel.swift` | 30 | `Views/ReceiptScreen.swift`, `Views/ReceiptHeader.swift` | 80 |
| `WorkoutPresentation+Finish.swift` | 55 | `ReceiptScreenModel.swift` | 30 |
| `WorkoutCopy+Finish.swift`, `+Rest` | 100 | `WorkoutPresentation+Receipt.swift` | 85 |
| `WorkoutStore+Finish.swift` | 105 | `WorkoutCopy+Receipt.swift` | 115 |
| `WorkoutStore.swift`, `+Pump`, `+Rest` | 55 | `WorkoutStore+Receipt.swift` (receipt, bests, "Done") | 60 |
| `WorkoutAction.swift`, `WorkoutModel.swift` | 20 | the live record (criterion 36) | 60 |
| `WorkoutRoot.swift` | 30 | `WorkoutStore.swift`, `WorkoutModel.swift`, `WorkoutScreen.swift`, `WorkoutRoot.swift` | 40 |
| `Workout+Previews.swift` | 25 | `Workout+Previews.swift` | 35 |
| `Clients.swift`, the key and its stub | 30 | | |
| `LedgerAppKit/LiveAnnouncements.swift`, `AppComposition.swift` | 25 | | |
| **Planned** | **560** (+ about 25 in `LedgerFakes`) | **Planned** | **670** |
| **Expected, at the overrun seen** | **700–900** | **Expected** | **750–950** |

Each implementer reports the count at each stage and stops past about 800 with what leaves: in S7a the
announcements (criteria 20 to 23, about 110 lines, a pull request of their own); in S7b the live record
(criterion 36).

### For the orchestrator to rule

- **R1. One slice or two.** The plan: one, about 490 lines, on `feat/F10-s7-finish-receipt`. This count:
  about 1,230. Recommended: S7a on `feat/F10-s7-finish` (this branch), S7b on `feat/F10-s7b-receipt` cut
  after S7a merges.
- **R2. Dialog or sheet.** The brief says "finish dialog" and `Views/FinishDialog.swift`; the plan and
  the default of decision 6 say `Views/FinishSheet` on `SheetChrome`; `main` has a `confirmationDialog`;
  neither phone prototype asks at all (v1 goes to the receipt, v2 to Today), and "End workout?" is the
  watch's overlay. Recommended: the sheet, with "Keep lifting" as the chrome's cancel (O1).
- **R3. Queued taps at a save.** The notes' "Inputs for S7" (S5) say they "should be dropped, as
  `startDiscard()` does"; S5's ruling 14 and this task's inputs say none is lost. Recommended: applied
  first (criterion 9); the notes' sentence is superseded.
- **R4. The line's key.** The brief writes one key with two `%lld`; standards §7 allows one count in a
  key and joins two facts with " · ". Recommended: two keys, the total picking the form.
- **R5. Names the code has replaced.** The brief's criterion 10 calls `finishAndMaterialise()` and its
  `WorkoutRoute` is `.live` / `.receipt(WorkoutSummary)`; `main` has `finish(endedAt:)` and
  `.minimized` / `.saved(WorkoutID)` / `.discarded`. Recommended: the receipt is drawn inside the cover,
  the route is unchanged, and `.saved` goes on selecting Today (S4's open question 6).
- **R6. Who computes what at finish.** The brief's criterion 10 has F10 compute "PRs/misses"; the
  inputs from F05 (item 2) and S2 (criterion 4) give the stored records to F05 and the misses to the
  host. Recommended: the store computes records only to draw them and to play the haptic.
- **R7. The failure line must not overclaim** (S4 ruling 16). The draft says the app "will try again".
  The store cannot tell a save that failed (true: an end waits) from an end the store refused to
  append, `invalidEndDate` or `incompleteLog` (false: nothing waits). Recommended: one alert and the
  neutral line "It's still on this iPhone. Try again.".
- **R8. The announced time.** The brief writes "Rest, 1:30 remaining"; S6's criterion 12 has the time
  read as a duration, never as digits and a colon. Recommended: "Rest, %@ remaining" with the words.
- **R9. The fake and the contract.** The notes say that when the fake gains a scriptable save failure
  the waiting end's rules become contract clauses. Recommended: S7 does not give it one (the test
  target's doubles and the host over the in-memory stores cover the store), so the clauses stay recorded.
- **R10. A waiting end is still not told to readers** (S2's SF2; the ADR-004 paragraph due before
  F17). S7 is written without it: after "Close" the cover may show a workout that accepts no change, and
  Today shows "Resume" for it, until a retry succeeds. Recommended: accept for M1; a failing save needs a
  full disk.
- **R11. The brief's test plan.** Its snapshot matrix (`FinishDialog`, `ReceiptView` × {light, dark} ×
  {default, XL}) and test names are replaced by the table above and testing-strategy §6.

### Open questions for the product owner (the default holds until answered)

- **O1. How "End workout?" asks.** A sheet with an orange "Save workout" and a plain "Discard", the
  system's dialog, or an alert: part of the app-wide question on destructive questions. Default: the
  sheet (decision 6's default). The Day editor is not touched.
- **O2. "Discard" is one tap** in the sheet, with no second question, as in the brief and on the watch.
  Default: one tap.
- **O3. May a workout that cannot be saved be abandoned?** Default: no; the failed save offers "Try
  again" and "Close" only.
- **O4. The failed save's wording** (the three invented texts). Default: as listed.
- **O5. What "1 new PR" counts.** One lift can set two records (best estimated 1RM, best weight at
  those reps). Default: the number of records, `summary.prs.count`, the number F05 stores for the
  workout; the other reading is the number of exercises with a record.
- **O6. The receipt's date and header.** "Wednesday, September 16" (brief) or the prototype's
  "WEDNESDAY, AUG 19"; the header pinned with "Done" always in reach, or scrolling with the page as in
  the prototype. Default: the brief's date; pinned.
- **O7. No receipt for a workout the cover did not see finish** (ended elsewhere, or saved while the
  cover's tasks restarted). Default: the cover closes onto Today's Logged card.
- **O8. "+30s" is announced** as a new rest ("Rest, 45 seconds remaining"). Default: yes.
- **O9. "Prescribed on the right" when the layout is mirrored** (the target is then on the left).
  Default: the brief's words; the translator's comment says the target stands at the trailing edge.
- **O10. A record made during the workout is felt, not shown** (a buzz; no "PR!" mark, which no
  prototype draws). Default: the buzz alone.

### Rulings before G1 — slice S7 (orchestrator, 2026-10-13)

- **R1.** Two slices, S7a then S7b, as drafted. Criteria 1 to 24 are S7a's, 25 to 37 are S7b's, and 38 to 40
  hold in each part for its own views.
- **R2.** "End workout?" is a sheet on `SheetChrome` with "Keep lifting" as its cancel, replacing the cover's
  `confirmationDialog` for this question. The Day editor is not touched. Listed for the product owner.
- **R3.** Taps queued before "Save workout" are kept and applied before `finish`; none is dropped. The notes'
  sentence in "Inputs for S7" (S5) is superseded.
- **R4.** Two keys joined with " · ", per standards §7.
- **R5.** Follow `main`: no `finishAndMaterialise()`, no `.receipt` route; the cover sends `.saved`.
- **R6.** Records and misses are computed by F05 and the host; the workout store computes nothing of its own
  in S7a.
- **R7.** One neutral alert for a save that did not go through; no promise that the app "will try again".
- **R8.** Rest announcements say the time in words, as S6's criterion 12 does; the brief's "1:30" form is not
  used.
- **R9, R10, R11.** Accepted as drafted.
- **Product defaults.** O1 to O4 and O8 hold as drafted until the product owner answers; each is one small,
  named place in the code, so that changing it is cheap. The invented texts are used as drafted and listed in
  the notes for the product owner.
- **Stop rule.** If S7a's product lines pass about 800, the rest announcements and their client (criteria 20
  to 23) leave for a later slice and the implementer says so; never more than 1,000.
