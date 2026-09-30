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
