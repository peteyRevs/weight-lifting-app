# F18 — Watch app screens (`WatchFeatureWorkout`)

| | |
|---|---|
| Milestone | M2 |
| Status | ready |
| Depends on | F06, F07, F16 |
| Branch | `feat/F18-watch-app` |
| Design refs | `design/prototype/LedgerWatch.dc.html` → screen labels: `Watch — before workout`, `Watch — set ready`, `Watch — rest timer`, `Watch — session list`, `Watch — end workout`, `Watch — summary` |
| Spec refs | `docs/product-spec.md` §4.1–4.5, §5.1–5.2 (field derivations), §7.4, §7.7, §8.3, §8.5 (watch roles), §8.8, §9 (watch gaps); `docs/product-decisions.md` #6, #7, #16, #17; R1 D6, D9, D10, §5 |

## Goal
After this ships, a lifter can run a whole workout from the wrist: see today's plan, step the weight with the Digital Crown, adjust reps, log sets, rest with a ring that buzzes at zero, jump between exercises, end (save or discard) and read a summary — all driven by the same `WorkoutSessionClient` the phone uses, with Always-On and VoiceOver handled.

## User stories
- As a lifter, I can start today's session from the watch so that the phone stays in my bag.
- As a lifter, I can turn the crown to change the weight by my exercise's step, feel a detent per step, and tap "Done set".
- As a lifter, I can rest with a countdown ring, add 30 s or skip, and feel a buzz at zero without looking.
- As a lifter, I can open the session list, jump to another exercise, and end the workout safely (Save / Discard / Keep lifting).
- As a lifter, with my wrist down the screen stays readable and hides my heart rate.

## Scope
**In:** six screens exactly per spec §4.3 and the prototype; `WatchWorkoutStore` (`@Observable @MainActor`) deriving every presentation value in spec §5.1 from `WorkoutState` + HR stream + `Settings`; crown weight stepping; haptics via an injected `haptics` dependency; Always-On; `WKApplicationDelegate` wiring in the app shell; watch typography scale; snapshot tests at 42/46/49 mm; accessibility.
**Out (explicitly):** transport (F17 — this brief consumes `WorkoutSessionClient`; until F17 merges, tests use `FakeWorkoutSessionClient`); program cache and standalone start data (F19 — F18 reads `ProgramRepository`, which is empty until F19 pushes); Smart Stack (F22); "Still lifting?" prompt on watch (F23); double-tap `handGestureShortcut` (post-launch); water lock; weight ± buttons (spec §5.2 `onWUp/onWDown` remain unbound, as in the prototype).

## Touches
- `LedgerKit/Sources/WatchFeatureWorkout/WatchWorkoutRoot.swift`, `WatchWorkoutRoute.swift`
- `LedgerKit/Sources/WatchFeatureWorkout/WatchWorkoutStore.swift`, `WatchPresentation.swift` (pure derivations)
- `LedgerKit/Sources/WatchFeatureWorkout/Screens/IdleScreen.swift`, `SetReadyScreen.swift`, `RestScreen.swift`, `SessionListScreen.swift`, `EndConfirmScreen.swift`, `SummaryScreen.swift`
- `LedgerKit/Sources/WatchFeatureWorkout/Components/CrownWeight.swift`, `SetDots.swift`, `HeartRateLine.swift`
- `LedgerKit/Sources/LedgerDesign/Watch/WatchTokens.swift`, `RestRing.swift` (watch variant), `WatchPill.swift`
- `LedgerKit/Sources/LedgerDomain/Haptics.swift` (`Haptics` protocol if F07 has only the key), `LedgerKit/Sources/LedgerTestSupport/Fakes/FakeHaptics.swift`
- `Apps/LedgerWatch/LedgerWatchApp.swift`, `Apps/LedgerWatch/WatchAppDelegate.swift`, `Apps/LedgerWatch-Info.plist` (`WKSupportsAlwaysOnDisplay = true`)
- `LedgerKit/Tests/WatchFeatureWorkoutTests/…`, `LedgerKit/Tests/LedgerDesignTests/WatchComponentsSnapshotTests.swift`
- `Localizable.xcstrings` (all watch strings)

## Domain changes
No new persisted types. Presentation derivations (pure, unit-tested, in `WatchPresentation`):
- `WatchMode` = `summary` if `phase == .finished` and summary not dismissed; `idle` if no live workout; `rest(endsAt)` if `rest != nil && now < endsAt`; `go` if `rest != nil && endsAt ≤ now < endsAt + 1.2 s`; else `ready`. Overlays `list` / `end` exist only in `ready`/`rest`/`go`; a mode change closes `list` but not `end` (spec §4.2).
- `setLabel` = `"[{letter} · ]SET {n} OF {sets}"` using `SupersetRounds` letters; `elapsed` = `startedAt` → now, "m:ss" (frozen on summary); `nextLine`, `planLine`, `weekLabel`, `nextSessionLine`, `listLabel`, `endLine`, `volume` exactly per spec §4.3/§5.1, unit from `Settings.units` ("LB"/"KG").
- Crown: local `Double` binding in display units = active set's target weight; `digitalCrownRotation(detent:from: 0, through: 2000, by: step, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true, onChange:onIdle:)` on a `.focusable()` view (R1 D10); displayed weight updates on `onChange` (next frame); `onIdle` commits `.changeTarget(weight:)` once; if the displayed value is stale vs a remote update while not rotating, the binding follows state.
- Reps "−"/"+" → `.changeTarget(reps:)` (min 1). "Done set" → `.logSet` with the displayed weight/reps; the engine (decision #6) decides rest and cursor. "+30s" → `.extendRest(by: 30 s)` (or starts a 30 s rest when at zero, decision #7). "Skip" → `.skipRest`. Row tap → `.selectExercise`. "Save workout" → `.finish`; "Discard" → `.discard`; "Done" → dismiss summary (local flag).
- Haptics (`Haptics` protocol, watch impl uses `WKInterfaceDevice.current().play(_:)`, ≥ 100 ms apart, R1 §5.3): `.setLogged` → `.click`; `.restOver` → `.notification`, gated by `Settings.watchBuzz` (spec §4.5) — the store owns one task sleeping with `continuousClock` until `endsAt`, cancelled on skip/extend/finish; `.prStart` → `.success`. No haptic in `.solo` remote-apply paths beyond these three (HR sampling pauses during haptics, R1 §3.1).
- "GO" (spec §4.5 resolved): at zero the rest screen title becomes "GO" for 1.2 s with the buzz shake (`buzz .38s ×3`) then transitions to `ready`; "+30s" after zero restarts a 30 s rest titled "REST". Reduce Motion: no shake, title + haptic only.
- Always-On (R1 §5.5): `@Environment(\.isLuminanceReduced)` → HR line `.privacySensitive()` + hidden, orange → 60 % alpha, set dots outlined, `TimelineView(.periodic(from:by: 60))` for elapsed; `Text(timerInterval:)` keeps the rest countdown ticking for free.
- Frontmost: the running `HKWorkoutSession` (F16) keeps the app on screen; no `WKExtendedRuntimeSession` (R1 §5.4).
- Undesigned states (spec §9): no program cached → idle shows "No program on watch" + "Open %@ on iPhone" (outlined pill; `%@` = `CFBundleDisplayName`, never a literal — see `docs/product-decisions.md` › Naming); HealthKit `.denied` → set-ready HR line shows "— BPM" and a one-time "Allow Health in iPhone Settings" line; `.anotherWorkoutSessionStarted` → banner "Apple Workout took over · logging continues".

## Acceptance criteria
1. Given a cached program with today scheduled, when idle renders, then it shows week label ("WEEK 1 OF 8" / "WEEK 8 OF 8 · DELOAD"), day name, plan line "{n} exercises · {sets} sets · {first} first" and an orange "Start" pill; given a rest day, then "Rest day", "Nothing scheduled today." and the outlined "Next: Friday · UB" line, non-interactive.
2. Given "Start" tapped, when the store sends `.start`, then the screen is set-ready within one state emission with set label "SET 1 OF 5", exercise name, weight, "× reps", "RPE 8", five dots, HR line and "Done set".
3. Given a superset slot, when set-ready renders, then the label reads "A · SET 2 OF 3" and the list row names are prefixed "A · ".
4. Given the crown is rotated one detent up on a barbell exercise (step 5 lb), when `onChange` fires, then the numeral shows +5 on the next frame and exactly one `.changeTarget` is sent on `onIdle`; given kg units with step 2.5, then +2.5.
5. Given "Done set" on the last member of a superset round, when the engine starts group rest, then the rest screen appears with `m:ss`, ring `dashoffset = 553 − 553 × remaining/total`, HR, and "Next: 185 lb × 5" or "Next exercise".
6. Given rest reaches zero with `watchBuzz` on, when `endsAt` passes, then `.notification` plays once, the title reads "GO" for 1.2 s, then set-ready shows; with `watchBuzz` off, no haptic but the same visuals.
7. Given "+30s" during rest, when tapped, then `endsAt` moves +30 s and the ring rescales (`total` grows); given "+30s" at zero, then a new 30 s rest starts titled "REST".
8. Given the exercise name is tapped, when the list opens, then rows show index (orange when current), name, "{sets} × {reps} @ {w}", "✓" when done, the current row has the orange 16 % fill + border, and the header reads "{done} OF {n} DONE".
9. Given a list row tap, when sent, then `.selectExercise` targets that slot and the list closes; given a remote mode change while the list is open, then it closes.
10. Given "End workout", when the confirm shows, then "End workout?" and "{done} of {total} sets logged · {volume} lb moved"; "Save workout" → `.finish` → summary; "Discard" → `.discard` → idle; "Keep lifting" → list.
11. Given the summary, when rendered, then elapsed (frozen), "{done}/{total}" SETS, volume LB MOVED, AVG BPM (from `HealthWorkoutRecord`), NEW PR (orange when > 0), and "Done" returns to idle.
12. Given `isLuminanceReduced`, when the set-ready or rest screen renders, then HR is hidden, nothing updates faster than once per minute except `Text(timerInterval:)`, and the layout does not shift.
13. Given the watch app is launched by `handle(_ workoutConfiguration:)` or `handleActiveWorkoutRecovery()`, when the delegate runs, then the store receives the corresponding `HealthSessionEvent` and shows set-ready without a tap (**device**).
14. Given VoiceOver, when on set-ready, then the weight is an adjustable element ("185 pounds, adjustable"), buttons have labels ("Decrease reps", "Increase reps", "Done set"), and the ring reads "Rest, 42 seconds remaining".
15. Given Reduce Motion, when rest hits zero, then no shake animation plays and the haptic still does.
16. Given no cached program, when idle renders, then "No program on watch" with the outlined "Open %@ on iPhone" pill, `%@` resolved from `CFBundleDisplayName` (spec §9 state).

## Test plan
- Unit (WatchFeatureWorkoutTests): `test_mode_idleReadyRestGoSummary`, `test_mode_goWindowIs1200ms`, `test_listClosesOnModeChange_endDoesNot`, `test_setLabel_supersetLetter`, `test_elapsed_frozenOnSummary`, `test_planLine_variants`, `test_nextSessionLine_withinWeek_elseNextWeek`, `test_crown_commitsOnceOnIdle`, `test_crown_followsRemoteWhenIdle`, `test_reps_minimumOne`, `test_addRest_atZeroStartsThirtySeconds`, `test_buzz_gatedByWatchBuzz`, `test_buzzTaskCancelledOnSkipExtendFinish`, `test_haptics_minimumSpacing100ms`, `test_volume_formattedThousands`, `test_units_kgLabelsAndStep`
- Snapshot (WatchFeatureWorkoutTests + LedgerDesignTests): each of the six screens × {42, 46, 49 mm} × {default, Always-On (`isLuminanceReduced`)} × {lb, kg}; `RestRing` at 0 %, 50 %, 100 %; `CrownWeight` at 3 and 4 digits.
- UI (LedgerWatchUITests, nightly): flow `start → log 2 sets → rest → skip → list → end → save → summary`, plus `performAccessibilityAudit()` on set-ready and rest.
- Device (F20): crown detents feel, buzz at zero with wrist down, Always-On after 15 s.
- Reduce Motion (from F06 review N5): with Reduce Motion on, the buzz shows an opacity pulse and no shake. `accessibilityReduceMotion` is get-only in the 26.5 SDK and `ImageRenderer` can't sample mid-animation, so this is a UI test or a device check.

## Non-functional
- Performance budget: crown detent → numeral update next frame (architecture §15; signpost `watch.crown`), measured with `.ledgerFont`'s per-body font construction included (F06 review N2: ~43 µs per call on the host; if over budget, cache by role, size and weight, and decide where the cache lives per standards §3); screen transition < 100 ms; no per-second timers besides `TimelineView`/`Text(timerInterval:)`.
- Accessibility: minimum label 11 pt (17 px ÷ 1.5, spec §4.1); Dynamic Type via `@ScaledMetric` up to the watch's largest size without clipping the 3-digit weight; contrast ≥ 4.5:1 for informational text (raise 35–45 % alphas to 55 % where text carries meaning — decisions "Accessibility" line); Reduce Motion honoured.
- Offline behaviour: all screens work `.solo`; connection state shown as one line under the set label when not connected (copy from F17).

## Risks / unknowns
- Archivo `wdth` axis on watchOS (risk R2) — if the F06 spike fell back to static instances, use them; no raw fonts here.
- `digitalCrownRotation` `through:` upper bound in display units: 2000 lb / 1000 kg; verify no clamp haptic at start.
- Prototype's "GO" edge (spec §4.5) is resolved above; if product disagrees, only `WatchPresentation` changes.
- Spec §5.2 says the watch `onLog` path is not superset-aware; decision #6 makes it the engine's job — nothing here special-cases supersets.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Every screen file ≤ 150 lines with `#Preview` per state (idle plan / rest day / no program; ready lb / kg / superset; rest / go; list; end; summary with and without PRs).
- [ ] Snapshot set at three case sizes committed; reviewer design-fidelity check against the prototype (risk R6).
- [ ] `WKApplicationDelegate` used (no `WKExtension`), R1 D9.
- [ ] Strings in `Localizable.xcstrings`; eyebrows ≤ 6 per screen (decision #17).

---
_Filled in by agents during delivery:_
- `F18-watch-app/implementation-notes.md`
- `F18-watch-app/test-findings.md`
- `F18-watch-app/review.md`
