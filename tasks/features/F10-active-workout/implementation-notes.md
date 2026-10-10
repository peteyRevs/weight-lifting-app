# F10 — implementation notes

## Slice plan (planning agent, 2026-10-04)

From a read-only pass against `main` `a526874`. Nothing was built or run. Line estimates are product code
(non-blank, non-comment; tests, `LedgerTestSupport`, `LedgerSnapshotTesting`, docs and string catalogs left
out), with `LedgerFakes` counted separately. Paths are under `LedgerKit/Sources/` unless they start with
`Apps/`, `scripts/` or `docs/`.

Nine slices, about 3,150 product lines plus about 160 in `LedgerFakes`. The brief expected one PR; the
orchestrator expected five to seven slices. Nine is what a 500-line target gives: the phone UI alone is about
2,100 lines. Two merges that stay under the 1,000-line cap are named under "Decisions for the orchestrator"
(O16) if fewer PRs matter more than smaller ones.

| Slice | Contents | Criteria | Est. | Depends on |
|---|---|---|---|---|
| **S1** seam (`feat/F10-s1-session-seam`) | `LedgerDomain/Protocols/WorkoutSessionClient.swift`: `WorkoutSessionClient`, `WorkoutSessionUpdate` (with `live` and `feedback(from:)`), `WorkoutSessionError`. `LedgerDomain/Units/ClockText.swift`: the one m:ss formatter F09 and F10 share. `LedgerDependencies/Keys/SessionKeys.swift` (`workoutSession`, preview value = an empty fake) and `Unimplemented/UnimplementedSession.swift`. `LedgerFakes/FakeWorkoutSessionClient.swift` (engine-backed, records events). `LedgerTestSupport/Engine/WorkoutSessionClientContract.swift`, run against the fake in `LedgerSyncTests`. Key rows added to `DependencyKeysTests`, `UnimplementedStubTests`, `PreviewValueTests`. Docs: architecture §13 key list. | none on its own; unblocks F09 and the brief's last DoD line | ~115 + ~110 fakes | main |
| **S2** host (`feat/F10-s2-session-host`) | `LedgerDomain/Engine/HybridLogicalClock.swift`; `LedgerDomain/UseCases/StartWorkoutUseCase.swift` (+ `StartWorkoutError`); `LedgerSync/LocalWorkoutSessionActor.swift` (+ `+Recovery`, `+Effects` extensions): serialised operations, HLC stamping, `seq`, the host loop for own actions, `resumeFromStore()`, finish → materialise (with misses) → compact, discard → compact. `LedgerPersistence/DatabaseLaunch.swift`: `LaunchStep.resumeWorkout` and a `run(_:retrying:_:)` hook that owns the step's task. `LedgerAppKit/AppComposition.swift`: build the actor when the database opens, bind `workoutSession`, run the step in `resume(in:)`. Contract and seeded differential tests (actor vs fake); kill-and-relaunch matrix on a real file in `LedgerAppKitTests`. Docs: architecture §6. | 1 (build + start), 2 (decision half), 12; host half of 3, 10, 11 | ~390 | S1 |
| **S3** persistence follow-up (`feat/F10-s3-program-updates`) | `WorkoutRepository.materialize` applies `workout.programUpdates` in its transaction: `LedgerPersistence/Repositories/GRDBWorkoutRepository.swift`, `LedgerFakes/InMemoryWorkoutRepository.swift` + `InMemoryProgramRepository.swift`, protocol docs in `LedgerDomain/Protocols/Repositories.swift`, new clauses in `WorkoutRepositoryContract`, a differential case for the fakes. No migration (`slot.exercise_id` exists). If O10 is approved, also the engine's swap snapshot. | 8 (program half) | ~50 + ~20 fakes (+ ~25 with O10) | S2; Pete #1 |
| **S4** cover and header (`feat/F10-s4-cover`) | `FeatureWorkout`: `WorkoutRoute`, `WorkoutLauncher` + `.workoutCover(_:onRoute:)` (start, resume, conflict dialog, full-screen cover), `WorkoutRoot` (loader), `WorkoutStore` skeleton, `WorkoutPresentation+Header`, `Views/WorkoutScreen`, `Views/WorkoutHeader` (Minimize, elapsed, Finish → "Discard" / "Keep lifting" only), `Views/WorkoutTimeline` (time for views, fixed in snapshots), `FeatureWorkout+Previews`, `Resources/Localizable.xcstrings`. `LedgerDomain`: `WorkoutState.checkedCursor`. `LedgerAppKit/AppRoot.swift`: the launcher and the modifier. Debug menu: "Start sample workout" (`LedgerDesign/Gallery/DebugMenu.swift` takes extra rows). `Package.swift` and `scripts/coverage-thresholds.json` entries. | 1 (cover, 0:00), 2 (dialog), 11, 13 (segments); discard half of 10 | ~580 | S2; the localisation chore (O12) |
| **S5** solo exercise (`feat/F10-s5-solo-logging`) | `Views/ExerciseCard` (eyebrow, title, Target line, Last + Repeat, column header, set rows, steppers, "+ Add set"), `Views/RemainingList`, `WorkoutPresentation+Card`, the store's intent pump and handlers: select, log, un-log, weight and reps steppers, repeat, add set, jump to a remaining exercise. Drop rows labelled "D". | 3 (log, cursor), 5, 9, 13 | ~485 | S4 |
| **S6** rest and effects (`feat/F10-s6-rest`) | `Views/RestPanel` (ring on a timeline, next-set line, "+30s", "Skip rest", "Rest over"), `WorkoutPresentation+Rest`. `LedgerDomain`: `HapticsClient.play(_:)`, `NotificationsClient.scheduleRestOver(at:)` / `cancelRestOver()`, `WorkoutState.shownRest`. Stubs and recording fakes. `LedgerAppKit/LiveHaptics.swift`, bound in `AppComposition`. The host runs notification effects; the store plays forwarded haptics and `.restOver` once. `LedgerDesign`: a full-width `PillButton`. | 3 (rest, autoRest off), 6, 7 | ~355 + ~30 fakes | S5 |
| **S7** finish and receipt (`feat/F10-s7-finish-receipt`) | `Views/FinishSheet` ("End workout?" on `SheetChrome`), `Views/ReceiptView`, `WorkoutPresentation+Receipt`, `LedgerDesign/Components/ReceiptLayout.swift` (string-only; F13 reuses it), the store's finish and discard, the receipt route, live records (`StatsQueries.bests(before:for:)` + `PersonalRecords.detect`) with the `.personalRecord` haptic, kg variants, the save-failed state. | 10 | ~490 | S6 |
| **S8** swap (`feat/F10-s8-swap`) | `LedgerDomain/Rules/SwapAlternatives.swift` (curated, then pattern + muscle, then muscle; deduped; at most 8), `Views/SwapSheet`, `WorkoutPresentation+Swap`, the store's swap: event, re-target of undone sets, "Also update program", bests for the new exercise. | 8 | ~390 (~330 with O10) | S3, S7; Pete #3 |
| **S9** supersets (`feat/F10-s9-supersets`) | `Views/SupersetBlock` (legend, "Round r of n", "Rest 1:15 after B", swap inside the block), row labels A1 / B1 / AD, `WorkoutPresentation+Superset`; `SupersetRounds.rounds(block:exercises:)` made public. | 4 | ~275 | S8 |

What each slice leaves in the app:

- S1–S3: nothing visible. After S2 a live workout survives a relaunch, and Today (F09) can show Resume.
- S4: a workout can be started (debug menu, or Today once F09 has it), minimised, resumed, discarded and
  recovered after a kill. The cover shows the header only.
- S5: a solo workout can be logged. A superset day works too, but shows its members one at a time until S9;
  the engine already runs rounds and group rest.
- S6: rest runs. S7: the workout can be saved and shows its receipt. S8: swap. S9: the superset block.

Order notes:

- S3 is early because it is small and changes only stores, fakes and contracts, so the Domain and
  persistence work is finished before the screens start.
- Finish (S7) comes before swap and supersets so that a workout can be saved as early as possible.
- Supersets are last, after swap, to keep snapshot churn low: the swap button changes every solo screenshot
  (11 references, under the 20-per-PR limit of testing-strategy §2.5), and the superset references are then
  recorded once with the button in place.

## Brief vs main

| The brief says | `main` has (file:line) | The plan does |
|---|---|---|
| Fake and fixtures in `LedgerTestSupport/Fakes`, `/Fixtures` | Fakes and fixtures live in `LedgerFakes` (ADR-008; `LedgerFakes/InMemoryStores.swift:13`, `Fixtures/Fixtures.swift:13`); `LedgerTestSupport` holds contracts and `withTestDependencies` (`WithTestDependencies.swift:17`) | `LedgerFakes/FakeWorkoutSessionClient.swift`, `LedgerFakes/Fixtures/Fixtures+Workout.swift`; the contract in `LedgerTestSupport` |
| `Apps/Ledger/Sources/LedgerApp.swift` registers the key and calls `resumeFromStore()`; `Apps/Ledger/Sources/RootView.swift` holds the cover | `Apps/Ledger/LedgerApp.swift:8-13` only builds `AppComposition.launch()`; the root is `LedgerAppKit/AppRoot.swift:16-38`; keys are bound in `AppComposition.swift:128-136`; async launch steps run in `AppComposition.swift:96-106` | The actor is built and bound in `AppComposition`; the cover is a `FeatureWorkout` modifier on `AppRoot`'s `.ready` content |
| `resumeFromStore()` is called "at launch" | Launch steps are an enum (`LedgerPersistence/DatabaseLaunch.swift:9-14`) run by `DatabaseLaunch`, which owns one task per step (`:126-144`); two tests pin the list (`LedgerAppKitTests/LaunchOrderTests.swift:28-39`, `LedgerPersistenceTests/DatabaseLaunchTests.swift:113-117`) | New `LaunchStep.resumeWorkout`, run through a `DatabaseLaunch.run` hook after `loadSettings`; both tests updated in S2 |
| `LedgerDomain/Workout/…` files | No such folder: `Engine/`, `Model/`, `Protocols/`, `Rules/`, `Storage/`, `Units/`, `Catalog/` | `Protocols/WorkoutSessionClient.swift`, `UseCases/StartWorkoutUseCase.swift` (new folder), `Engine/HybridLogicalClock.swift` |
| `var updates: AsyncStream<…> { get }` | Two consumers (Today and the cover) need a stream each; fakes register observers synchronously behind a `Mutex`, product stores use actors (ADR-008 decision 4, standards §4) | `func updates() async -> AsyncStream<WorkoutSessionUpdate>`: a new stream per call, registered on the actor |
| `WorkoutSessionUpdate { state: WorkoutState; effects; origin }` | "The store needs no origin filter for haptics" (brief, Inputs from F04, item 2); after a finish there is no workout to hold | `state: WorkoutState?`, no `origin` |
| `resumeFromStore()` on the protocol | Only the composition root calls it | A method of `LocalWorkoutSessionActor`, not of the protocol; every protocol method waits for recovery first |
| `finishAndMaterialise() -> WorkoutSummary`; assumes `WorkoutRepository.finish(_:)` | `materialize(_:slotUpdates:)` (`LedgerDomain/Protocols/Repositories.swift:67`); the receipt is `WorkoutEngine.summary(_:prs:)` (`Engine/WorkoutEngine.swift:90`); records are F05's (decision #27) | `finish(endedAt:) -> WorkoutState`; the store builds the summary with `bests(before:for:)` (`Repositories.swift:134`) and `PersonalRecords.detect(workout:against:now:)` (`Rules/PersonalRecords.swift:56`) |
| `SessionBuilder.build(program:week:day:history:)` | `build(program:weekIndex:day:exercises:history:settings:id:device:now:)` (`Rules/SessionBuilder.swift:16-26`); `resumable(_:program:weekIndex:day:)` is rule 17 (`:73-84`) | The use case loads exercises, history and settings and calls both |
| Repeat sends `setTargetChanged` per set | `allSetsRepeated(exerciseIndex:weight:reps:)` (`Engine/WorkoutEvent.swift:31`) | One event |
| "+ Add set" via `setAdded` | `setAdded(exerciseIndex:set: LoggedSet)`; the device makes the `SetID` (`WorkoutEvent.swift:29`) | The store makes the id from `@Dependency(\.uuid)` |
| `ProgramRepository.replaceSlotExercise(slot:with:)` "if F05 lacks it" | Not on the protocol (`Repositories.swift:25-39`); `materialize` does not apply `programUpdates` (`Repositories.swift:62`, `GRDBWorkoutRepository.swift:42`); a separate call is not atomic with the workout (brief, Inputs from F05, item 5) | S3 applies `programUpdates` inside `materialize`'s transaction; no new method (Pete #1) |
| The store runs `.scheduleRestNotification` / `.cancelRestNotification` | `NotificationsClient` is empty (`Protocols/Clients.swift:12`); a discard from the conflict dialog happens with no cover and no store alive | The host runs notification effects through an injected `NotificationsClient` (S6); `effects` carries haptics only (O5) |
| `@Dependency(\.haptics)` plays haptics | `HapticsClient` is empty (`Clients.swift:8`); stubs and fakes are empty (`UnimplementedDevices.swift:14`, `DeviceFakes.swift:25`) | S6 adds `play(_:)`, a recording fake, and `LiveHaptics` in `LedgerAppKit` |
| Swap: the store keeps `[ExerciseID: Exercise]` for names and steps | The engine's swap changes only `exerciseID` and `name` (`Engine/WorkoutEngine+Reduce.swift:144-154`): `equipment`, `step` and `lastPerformance` stay the original's, and history stores that equipment and step (`LedgerPersistence/Migrations.swift:155-156`) | O10: either the swap event carries the replacement's snapshot (recommended), or the store looks them up |
| Stepper step from `Equipment.defaultStep(in:)` + `Settings.units` | The step and units are snapshotted in the state (`Model/WorkoutExercise.swift:17`, `Model/WorkoutState.swift:50`) | The stepper uses `exercise.step` and `state.units`; `Weight.advanced(bySteps:of:)` (`Units/Weight.swift:81`) |
| Copy has "lb" in every format | Units are per workout (`WorkoutState.swift:50`); the receipt rows and the Last line are already formatted by the Domain (`Model/WorkoutSummary.swift:49-68`, `Model/LastPerformance.swift:22`) | Formats take the unit as an argument; Domain-formatted lines are shown as given (O12) |
| VoiceOver: "Set 2, 185 pounds, 5 reps, not done"; steppers "with the step in the value"; numbers wrap at AX5 | `SetRow` reads the summary as its label and "Pending" / "Current set" / "Done" as its value (`LedgerDesign/Components/SetRow.swift:118-124`); a stepper's label is its step and its value the current weight (`SetRowSteppers.swift:66-69`); numerals shrink, never wrap (F06 notes, decision 5) | Follow the components; the tests pin what they read |
| `LedgerDesign/Components/ReceiptLayout.swift` is the only design addition | F06 did not build a full-width pill or disabled pill looks (F06 notes :795) | S6 adds the full-width `PillButton`; S7 adds `ReceiptLayout`; everything else is composed in `FeatureWorkout` from tokens |
| Tests named `test_…` | testing-strategy §6: `subject_condition_expectation`, no `test` prefix | Renamed (see "Test plan changes") |
| `Localizable.xcstrings` in `FeatureWorkout/Resources` | No string catalog in the repo; `Package.swift` has no `defaultLocalization`; `AppRoot.swift:45-46` uses literals | O12 |
| F17 expects to switch the store "from its F10 local reducer loop" | — | F10 uses the session client from the start, so that F17 PR shrinks |
| architecture §6: `WorkoutSessionActor` "publishes `WorkoutState` as an `AsyncStream`" | — | S2 updates §6 to the names and the update type above |

## Seams with F08, F09 and later features

### What F09 gets from S1

```swift
// LedgerDomain/Protocols/WorkoutSessionClient.swift
public struct WorkoutSessionUpdate: Hashable, Sendable {
    /// Live; or finished / discarded in the one update that ends it; nil when there is no workout.
    public let state: WorkoutState?
    /// Feedback for the screen to play, in order (`feedback(from:)`). Empty in a stream's first element.
    public let effects: [Effect]
    public init(state: WorkoutState?, effects: [Effect] = [])
    public var live: WorkoutState? { get }                      // `state` when its phase is `.live`
    public static func feedback(from effects: [Effect]) -> [Effect]   // the one forwarding rule: `.haptic` only
}

public enum WorkoutSessionError: Error, Equatable, Sendable {
    case workoutInProgress(WorkoutID)   // start while a workout is live
    case notStartable(WorkoutID)        // start with a snapshot that is not live
    case noLiveWorkout                  // apply, finish or discard with nothing live
    case incompleteLog(WorkoutID)       // finish while the log holds envelopes this version cannot read
}

public protocol WorkoutSessionClient: Sendable {
    /// The workout as it stands (first element, no effects), then every change. A new stream per call.
    func updates() async -> AsyncStream<WorkoutSessionUpdate>
    /// The live workout, or nil. Waits for the launch recovery.
    func current() async throws -> WorkoutState?
    func start(_ initial: WorkoutState) async throws
    /// Stamps, reduces and stores the event; returns the state after it.
    @discardableResult func apply(_ event: WorkoutEvent) async throws -> WorkoutState
    /// Ends and stores the workout; returns the finished state. Calling it again retries a failed save.
    func finish(endedAt: Date) async throws -> WorkoutState
    func discard(endedAt: Date) async throws
}

// LedgerDomain/Units/ClockText.swift
public enum ClockText { public static func minutesSeconds(_ duration: Duration) -> String }   // "0:00", "24:22"

// LedgerDependencies/Keys/SessionKeys.swift
public extension DependencyValues { var workoutSession: any WorkoutSessionClient { get set } }

// LedgerFakes/FakeWorkoutSessionClient.swift
public actor FakeWorkoutSessionClient: WorkoutSessionClient {
    public init(live: WorkoutState? = nil, device: DeviceID = Fixtures.deviceID,
                now: @escaping @Sendable () -> Date = { Fixtures.now })
    public private(set) var applied: [WorkoutEvent]     // start, apply, finish and discard, in order
}
```

For F09: `for await update in await session.updates()`; show Resume when `update.live != nil`, with
`ClockText.minutesSeconds(live.elapsed(at: now))`. In a test, `FakeWorkoutSessionClient(live: try
Fixtures.seedSession())` (`LedgerFakes/Fixtures/Fixtures+Program.swift:169`), then `finish(endedAt:)` to see
the flip. `StartWorkoutUseCase` is not in S1: F09 only emits `TodayRoute.startWorkout` and `.resumeWorkout`.

### Shared files, per slice

| File | F10 changes | Slice | Others |
|---|---|---|---|
| `LedgerAppKit/AppRoot.swift` | One `@State private var workout = WorkoutLauncher()` and `.workoutCover(workout)` on the `.ready` content (`:26-32`); a debug-menu row | S4 | F09 replaces `TodayPlaceholder` with the tab shell (`:27`); F08 adds the "no active program" branch |
| `LedgerAppKit/AppComposition.swift` | `init`'s `onOpen` (`:39-43`) builds the actor; `bind` (`:128-136`) sets `workoutSession`; `resume(in:)` (`:96-106`) runs the step. S6 adds `haptics` to `bind` | S2, S6 | none expected |
| `LedgerPersistence/DatabaseLaunch.swift` | `LaunchStep.resumeWorkout` (`:13`), `run(_:retrying:_:)` beside `task(for:)` (`:126-144`) | S2 | none |
| `LedgerKit/Package.swift` | `FeatureWorkout` target gains `resources: [.process("Resources")]` (`:131-135`); `"FeatureWorkout"` joins `snapshotTestTargets` (`:67`). **No new edge**: `package-graph.expected.txt` does not change | S4 | F08 and F09 add their own names to line 67; `defaultLocalization: "en"` (`:72-73`) is needed once, by whoever is first (O12) |
| `scripts/coverage-thresholds.json` | `"FeatureWorkout"` joins `required` (`:15`) | S4 | F08, F09 add theirs to the same line |
| `LedgerFakes` | New `FakeWorkoutSessionClient.swift` (S1) and `Fixtures/Fixtures+Workout.swift` (S4 on); `DeviceFakes.swift:25-32` (S6); `InMemoryWorkoutRepository.swift:33-45` and `InMemoryProgramRepository.swift` (S3) | S1, S3, S4, S6 | Each lane adds its own fixture file; nobody edits `Fixtures+Program.swift` |
| `LedgerDependencies` | New `Keys/SessionKeys.swift`, `Unimplemented/UnimplementedSession.swift` (S1); `UnimplementedDevices.swift:14-16` (S6) | S1, S6 | none |
| `LedgerDesign/Gallery/DebugMenu.swift` | `DebugMenu(diagnostics:actions:)`: extra rows a composition root passes (`:23-35`) | S4 | F09 keeps the long press on `today.title` that opens it |
| `LedgerDesign/Components/PillButton.swift` | A full-width variant; its gallery references are recorded again | S6 | none |
| `docs/architecture.md` | §13 (S1), §6 (S2), §11 component list (S6, S7) | — | — |

### Merge order

1. **F10 S1** first. F09 and F08 start from it.
2. **F09's tab shell** and **F08's root branch**, in either order. Both edit `AppRoot.swift:24-38`.
3. **F10 S2** before F09's Today slice. Until S2 binds the actor, `workoutSession` is the stub in the app:
   `updates()` logs a fault and ends at once (harmless, but loud on every launch).
4. **F10 S4** after the tab shell if possible: the modifier goes on whatever the `.ready` branch shows, so it
   also works on `TodayPlaceholder`. Whichever of F10 S4 and F09's Today merges second adds the two lines that
   map `TodayRoute.startWorkout` to `await workout.start(source)` and `.resumeWorkout` to `workout.resume()`.
5. S5–S9 touch only F10's own files, `LedgerDesign` (S6, S7) and `LedgerDomain` additions.

### What the cover needs from the shell, and what F10 can do without it

`FeatureWorkout` exports `WorkoutLauncher` (an `@Observable` store), `View.workoutCover(_:onRoute:)` and
`WorkoutRoute` (`.minimized`, `.saved(WorkoutID)`, `.discarded`). The shell holds one launcher, attaches the
modifier above the tab view, and calls `start` / `resume` when Today emits its routes. The conflict dialog,
the cover and every F10 string stay in `FeatureWorkout`. Nothing reads a dependency key until the first
`start` or `resume`, so creating the launcher while the database is still closed is safe (F07 S3: no key is
read before `.ready`).

Before the shell and F08's program exist, the real database has no program, so nothing can start a workout.
S4 therefore adds a Debug-only row to the debug menu, "Start sample workout": it saves `Fixtures.seedProgram()`
if there is no active program and starts its first day. That gives the orchestrator a way to check S4–S9 on
the simulator, including kill and relaunch, without waiting for the other lanes.

### What later features hang on F10

- **F17** adds received envelopes to `LocalWorkoutSessionActor` (append, `replay`, `effects(from:to:)`), the
  transport for `.transmit`, the drift bound, and the rule for two live logs. The HLC, `seq`, recovery, the
  update stream and the launch step are already there. Its "switch the store to the session client" PR is not
  needed.
- **F18** drives the same protocol from the watch, tests with `FakeWorkoutSessionClient`, runs
  `LaunchStep.resumeWorkout` from `WatchComposition`, and reads `WorkoutState.checkedCursor` and
  `WorkoutState.shownRest`.
- **F21** handles `.updateLiveActivity` in the host (ignored until then) and reads `checkedCursor`.
- **F23** supplies the live `NotificationsClient`; the host already calls it. The "Still lifting?" Finish uses
  `finish(endedAt:)` with the last set's time.
- **F13** reuses `ReceiptLayout`. **F25** puts the plate line under the active row. **F15** drives the flow
  through the identifiers listed under "Inputs the implementer needs".

## Decisions for Pete

1. **"Also update program": when does the program change?**
   You swap Bench Press for Dumbbell Bench Press with the toggle on.
   - *A, with the saved workout:* next week's Upper A lists Dumbbell Bench Press only if you finish and save.
     If you discard the workout, the program still says Bench Press.
   - *B, at once:* the program changes when you tap "Use". Discarding the workout later does not undo it.
   - Recommendation: **A**. The program and the workout are saved together, so they can never disagree, and a
     discarded workout leaves nothing behind.
   - Default if you don't answer: A.

2. **"Also update program": what does next week ask for?**
   The swap changes the slot's exercise, not its numbers. After Bench (185 lb) becomes Dumbbell Bench in the
   program, next week's session asks for "Dumbbell Bench Press 5 × 5 @ 190 lb": the bench numbers, plus the
   usual step. The "Last" line beside it shows what you really lifted ("5×5 @ 60 lb"), and "Repeat" fills
   that in with one tap.
   - *A, accept this for now:* fix the weight once in the Program builder (F11), or tap Repeat each session.
   - *B, restart the slot from what you lifted:* needs a new progression rule and about one more slice.
   - Recommendation: **A** for M1, and revisit with F24 (progression states).
   - Default: A.

3. **Swap: which weight does a replacement with no history start at?**
   Decision #13 says "its last-known load, else the original's load". The brief's risk note says "else its
   own start load". They differ when the equipment differs.
   - *A, decision #13 as written:* Bench 185 → Dumbbell Bench (never done) shows 185 per dumbbell.
   - *B, the replacement's own start load:* shows 15 lb, the catalog's beginner default; Bench → Incline
     Bench (also a barbell) shows 45 lb, the empty bar.
   - *C, by equipment:* same equipment keeps the load (Incline Bench shows 185); different equipment takes
     the replacement's start load (Dumbbell Bench shows 15).
   - A replacement you have done before always starts at its last load, in every option.
   - Recommendation: **C**. Default: A.

4. **Elapsed time after an hour.** The prototype counts minutes only: "61:05". The same text appears in the
   workout header, on Today's Resume button and on the receipt's TIME tile.
   - Recommendation: **"1:01:05"** from 60 minutes on. Default: "61:05", as the prototype.

5. **What you see when saving fails** (a full disk, for example). The brief has no copy for it.
   - A set that could not be saved: the row stays as it was, with "Couldn't save that. Try again."
   - A workout that could not be saved at Finish: "Couldn't save this workout. It's still on this iPhone, and
     Ledger will try again." with "Try again" and "Close". Nothing is lost; the next launch retries by itself.
   - Recommendation and default: this wording, marked for your copy review.

6. **Two pieces with no v2 design.**
   - *Target:* v2 has no TARGET pill. Recommended: a quiet line above "Last", in the same style, "Target
     5 × 5 @ 185 lb · RPE 8", with no orange (orange stays on the active row's check).
   - *"End workout?":* recommended as a bottom sheet in the swap sheet's style, with "Save workout" as the
     orange button, "Discard" as an outlined pill and "Keep lifting" as the cancel.
   - Default: both as recommended.

You do not need to look at: the slice order, type and method names, how the workout is stored and recovered
after a kill, the clock and sequence rules, the fakes and contracts, the string catalog set-up, the snapshot
matrix, or the cross-lane merge order.

## Decisions for the orchestrator

Needed before S1 (F09 codes against them): O1–O6. Needed before any lane's first screen: O12–O14.

- **O1. `updates()` is an async method that returns a new stream per call.** Reason: Today and the cover both
  subscribe, registration happens on the actor so no update is missed, and no `Mutex` is needed in a product
  actor. Streams are unbounded: a dropped element would drop a haptic.
- **O2. `WorkoutSessionUpdate.state` is optional and `origin` is dropped.** Reason: "no workout" needs a
  value, and nothing filters by origin.
- **O3. `resumeFromStore()` stays off the protocol; every protocol method waits for recovery.** Reason: a
  start can then never race the launch and create a second live log, whatever order the launch runs in.
- **O4. `apply` returns the new state.** Reason: two quick taps on "+" must each start from the weight the
  first one left; the store handles intents one at a time and takes the returned state as its base.
- **O5. The host runs the rest-notification effects; `effects` carries haptics only.** Reason: a discard
  from the conflict dialog, the launch step and (later) the watch's events all happen with no workout screen
  alive, and a screen-run cancel would be lost. The rule is one Domain function
  (`WorkoutSessionUpdate.feedback(from:)`), which the fake uses too. Otherwise: the brief's way, the store
  runs them.
- **O6. The fake is a second, engine-backed implementation, held to the actor by a shared contract and
  seeded scripts.** Reason: `LedgerFakes` may depend on `LedgerDomain` only (ADR-008), so it cannot wrap the
  actor; F07 showed that an unchecked fake drifts.
- **O7. `StartWorkoutUseCase` goes in S2, in `LedgerDomain/UseCases`.** Reason: F09 needs only the route;
  standards §3 puts use cases in the Domain.
- **O8. S3 applies `programUpdates` inside `materialize`; no `replaceSlotExercise`; no migration.** Reason:
  atomic with the workout, and the engine's docs already say so (`Effect.swift:32-35`,
  `WorkoutState.swift:51-53`). A slot that is not stored, or an exercise that is not stored, is logged and
  skipped, as misses are. Depends on Pete #1.
- **O9. The host builds `slotUpdates` from `ProgramRepository.active()`, and only when its id is the
  workout's program.** Reason: no protocol change. Cost: a workout whose program is no longer active records
  no misses. The alternative is to put `program(id:)` (`GRDBProgramRepository.swift:27`) on the protocol,
  with a fake method, a stub and a contract clause.
- **O10. Let the swap event carry the replacement's `equipment`, `step` and `lastPerformance` (an F04
  follow-up inside S3, about 25 lines).** Reason: without it the phone store, the watch store, the plate line
  and history each have to look the replacement up, and the watch has no history to look in. The fields are
  optional, so a version-1 payload still decodes; S3 must prove that against the `payload-v001` fixtures, or
  add payload version 2. Otherwise: S8 keeps a lookup in the store (about 60 more lines there) and F18
  repeats it.
- **O11. `LaunchStep.resumeWorkout` runs after `loadSettings`, through a `DatabaseLaunch.run` hook; iPhone
  only until F18.** Reason: the launch owns the step's task (F7-S2-3), and O3 makes the order harmless.
- **O12. Localisation pattern, for all three lanes.**
  - `Package.swift` gets `defaultLocalization: "en"` once: recommend a ten-line chore PR by the orchestrator
    before the first screen slice, to avoid a three-way conflict.
  - Each feature: `Resources/Localizable.xcstrings`, source language English, keys are the English text;
    target gains `resources: [.process("Resources")]`.
  - Strings are resolved in the feature's presentation code with `String(localized:bundle: .module,
    comment:)` and handed to `LedgerDesign` as `String` (F06: components take text already localised). No
    literal in a view.
  - Lines the Domain already formats (`ReceiptRow`, `LastPerformance.line`, `Weight.formatted`,
    `Volume.formatted`, `RestDuration.label`, `ClockText`) are shown as given and are not in the catalog.
  - One shared source scan in `LedgerTestSupport`, like `PreviewScan`: every key used in a feature is in its
    catalog, and the reverse. Catalogs are written by hand; `xcodebuild` does not update them.
- **O13. Store pattern.** `@MainActor @Observable final class`, one per screen; dependencies as
  `@ObservationIgnored @Dependency`; state as one enum per store (`loading` / content / failure) rather than a
  shared `Loadable`; pure `nonisolated` presentation builders that return display strings; views call
  synchronous intent methods, which yield into a stream that the root's `.task { await store.run() }` drains.
  Reason: standards §3 and §4 forbid tasks that outlive the view, and F07 S3 showed that previews must draw a
  state while a separate loader holds the `.task`.
- **O14. Routing pattern.** Each feature: `public struct XRoot: View` with `onRoute: (XRoute) -> Void`, and
  `public enum XRoute`. `AppRoot` resolves routes. A feature that presents itself over the others (the
  workout) exports its own presenter and modifier, as above. Reason: architecture §12, with all of a
  feature's copy kept in its own module.
- **O15. A Debug-only "Start sample workout" row in the debug menu (S4).** Reason: S4–S9 can be checked on
  the simulator before F08 and F09 land.
- **O16. Nine slices.** If fewer PRs matter more: S5 + S6 (about 840 lines) and S8 + S9 (about 665) each
  stay under the cap. Recommend keeping nine: rest and swap are where test rounds are most likely to fail.
- **O17. `HybridLogicalClock` and `ClockText` live in `LedgerDomain`.** Reason: pure, shared by both devices
  and by the fake; the test-side model is already there (`LedgerDomainTests/Engine/Adversarial/
  HLCHostAdversarialSupport.swift:12-26`).
- **O18. `.restOver` plays only when zero is crossed while the screen is active**, never on return from the
  background. Reason: a buzz for a rest that ended minutes ago is noise; F23's notification covers the
  background.
- **O19. Snapshot matrix.** Whole-screen states in light and dark at `.large`; the surface that carries the
  text also at `.xLarge`; one dark `.accessibility3` per surface. Reason: 55 feature references (the brief's
  matrix gives 48, none at an accessibility size) plus 6 for `ReceiptLayout`, and no PR changes more than 20
  existing ones; see "Test plan changes".
- **O20. Copy nit.** The check's label on a logged row: the brief says "Unlog set 2", `SetRow`'s doc says
  "Undo set 2". Recommend "Undo set 2".

## Test plan changes

### Renamed, moved, added

Names follow testing-strategy §6 (no `test` prefix; one suite per type).

| Brief | Becomes | Where | Slice |
|---|---|---|---|
| `test_startUseCase_noLive_buildsAndStarts`, `_sameSource_resumes`, `_differentSource_conflict`, `_lastPerformanceInjected` | `StartWorkoutUseCaseTests`: `start_noLiveWorkout_buildsAndStarts`, `start_sameSource_resumes`, `start_differentSource_reportsConflict`, `start_replacingLive_discardsThenStarts`, `start_fillsLastPerformance`, `start_programNoLongerActive_throws`, `start_emptyDay_throws` | `LedgerDomainTests/UseCases` | S2 |
| `test_actor_apply_assignsMonotonicSeqAndPersists` and the six other `test_actor_…` | `LocalWorkoutSessionActorTests`: `apply_assignsNextSeq_andStoresBeforePublishing`, `updates_yieldCurrentStateFirst`, `resumeFromStore_replaysALiveLog`, `resumeFromStore_finishedLog_materialisesThenCompacts`, `finish_materialisesThenCompacts`, `start_whileLive_throws`, `effects_forwardHapticsOnly` | `LedgerSyncTests` | S2 |
| — | `HybridLogicalClockTests` (stamp, observe, non-finite stamps, a clock stepped back) | `LedgerDomainTests/Engine` | S2 |
| — | `LocalWorkoutSessionActorTests`: `apply_storeFails_leavesStateAndSeq`, `apply_cancelledCaller_stillStores`, `twoCallersAtOnce_keepOrderAndSeq`, `finish_materialiseFails_keepsLog_secondFinishRetries`, `discard_compacts`, `resumeFromStore_discardedLog_compacts`, `_nilLog_isKept`, `_unreadableRows_neverMaterialiseOrCompact`, `_recoversTheClock_afterAStepBack`, `_twice_doesNothingTwice`, `finish_writesMissesFromTheStoredProgram` | `LedgerSyncTests` | S2 |
| — | `WorkoutSessionClientContract` clauses, on the fake (S1) and on the actor (S2); `sessionScripts_fakeAndActorPublishTheSame(seed:)` | `LedgerTestSupport`, run in `LedgerSyncTests` | S1, S2 |
| `test_eventStore_replayAfterKill_matchesLastState` (LedgerPersistenceTests) | `WorkoutRelaunchTests`: a composition on a real file, dropped and rebuilt at each kill point (table under S2 in "Inputs") | `LedgerAppKitTests` (it links Sync and Persistence; `Harness` already builds compositions on a temp file) | S2 |
| — | `WorkoutRepositoryContract` clauses: `programUpdates` change the stored slot's exercise; an unstored slot or exercise is skipped; misses and other fields untouched; a second materialise changes nothing | `LedgerTestSupport`, run on GRDB and the fake | S3 |
| `test_store_…` (16) | `WorkoutStoreTests` (+ `WorkoutStoreRestTests`, `WorkoutStoreFinishTests`, `WorkoutStoreSwapTests`), same subjects without the prefix, e.g. `check_appliesSetLogged`, `stepperOnAnotherRow_selectsItFirst`, `restZero_playsRestOverOnce`, `finish_zeroSets_saveDisabled` | `FeatureWorkoutTests` | S5–S8 |
| `test_store_scheduleRestNotification_onRestStarted` | `LocalWorkoutSessionActorTests.restStarted_schedulesTheNotification`, `skipOrFinish_cancelsIt` (O5) | `LedgerSyncTests` | S6 |
| `test_store_swapAlternatives_orderCuratedPatternMuscle` | `SwapAlternativesTests` (order, dedupe, at most 8, never the exercise itself) | `LedgerDomainTests/Rules` | S8 |
| `test_presentation_…` (5) | `WorkoutPresentationTests`: `rowLabels_soloDropSuperset`, `progressSegments_proportional`, `remaining_onlyLaterExercises`, `supersetRoundTitle`; `receiptChips_runLength` is already covered by `LedgerDomainTests/Model/ReceiptRowTests.swift` | `FeatureWorkoutTests` | S4, S5, S9 |
| — | `WorkoutLauncherTests` (start, resume, conflict → resume, conflict → discard and start, failure) | `FeatureWorkoutTests` | S4 |
| — | `WorkoutAccessibilityTests`: one pinned VoiceOver tree per view (header, card, rest panel, finish sheet, receipt, swap sheet, superset block), read with `accessibilityElements` | `FeatureWorkoutTests` | S4–S9 |
| — | `StringCatalogTests` (O12), `PreviewTests` (registry + `PreviewScan`) | `FeatureWorkoutTests` | S4 |
| UI flow `onboard_start_log_finish_history` | Stays F15's. F10 supplies the identifiers | — | — |

### Snapshots per slice

Measured on `main`: 124 references, 4,308,969 bytes, mean 34.7 kB. A sheet-sized view is 25–27 kB at
`.large`, 28–30 kB at `.xLarge`, 59–69 kB at `.accessibility3` (`sheetChrome_*`, `emptyState_*`). Estimates
below use 10 kB for the header strip, 30–40 kB for a card or sheet, 70 kB for a whole screen and 90–120 kB at
`.accessibility3`.

| Slice | New references | Count | Est. bytes | Existing references changed |
|---|---|---|---|---|
| S4 | `WorkoutHeader` × {light, dark} × {large, xLarge} | 4 | 0.04 MB | none |
| S5 | whole screen {soloActive, soloWithDrop, noHistory} × {light, dark}; `ExerciseCard` × {light, dark} at xLarge; one dark AX3 | 9 | 0.6 MB | none |
| S6 | `RestPanel` {resting, restOver} × 4; whole screen resting × {light, dark}; one dark AX3 | 11 | 0.5 MB | `PillButton` gallery (6) and the composite sheets that include it (up to 4) |
| S7 | `FinishSheet` {withSets, zeroSets} × {light, dark} + withSets at xLarge × 2; `ReceiptView` {withPRs, noPRs, kg} × 4; one dark AX3; `ReceiptLayout` gallery × 6 | 25 | 1.1 MB | `DesignGallery` (1) and composites (up to 4) |
| S8 | `SwapSheet` × 4; one dark AX3 | 5 | 0.2 MB | 11: the title row gains the swap button (S5's 9, S6's 2 whole screens) |
| S9 | whole screen {supersetRound2, remainingEmpty} × {light, dark}; `SupersetBlock` × {light, dark} at xLarge; one dark AX3 | 7 | 0.5 MB | none |
| **Total** | | **61** | **≈ 2.9 MB** | every PR stays under 20 changed |

Time in a snapshot is fixed: views take "now" from `WorkoutTimeline`, which the tests pin to `Fixtures.now`.
`Text(timerInterval:)` and `Text(_:style: .timer)` are not used, because they read the real clock.

### Tests on `main` that break

| Test | Why | Fixed in |
|---|---|---|
| `LedgerAppKitTests/LaunchOrderTests.swift:28-39` (`launch_runsTheStepsInOrder`: the whole log, and `LaunchStep.allCases`) | new step | S2 |
| `LedgerPersistenceTests/DatabaseLaunchTests.swift:113-117` (`steps_inOrder`) | new step | S2 |
| `LedgerDesignTests`: `ComponentSnapshotTests` (PillButton), `DesignGalleryTests`, `PreviewTests`, the composite sheets in `PhoneComponentSnapshotTests` | new or changed components | S6, S7 |

Not broken by F10, but worth knowing: `LedgerWatchAppKitTests/WatchCompositionTests.swift:32` pins the watch's
whole launch log, which F10 does not change; `LedgerAppKitTests/TodaySnapshotTests` and the `today.title` UI
tests are F09's to replace. S1 and S3 only add rows and clauses.

## Risks

**Host and concurrency**

- *Actor re-entrancy.* Every operation suspends on the event store, so two calls can interleave on the actor,
  read the same state and `seq`, and collide. Operations must run one after another (a chain of tasks the
  actor owns), whatever the callers do.
- *A cancelled caller.* SwiftUI cancels the cover's `.task` on Minimize. GRDB's async writes throw on
  cancellation, so a set ticked just before Minimize would be lost if the write ran in the caller's task.
  Each operation runs in a task the actor owns; the caller only waits. This is F7-S2-3 again.
- *State before storage.* The actor commits state, clock and `seq` only after `.persist` succeeds. A failed
  append leaves all three untouched and throws.
- *Finished but not saved.* `.finished` is stored before `.materialize` runs (ADR-004's order). If the save
  throws, the workout is over but not in history. The actor keeps the finished state and the log; a second
  `finish` and every launch retry. The refusals F05 names (`nulInText`, `inexactWeight`, `nonFiniteDate`)
  cannot come from stepper values or catalog names, so in practice this is a full or locked disk.
- *Launch.* The step's task belongs to `DatabaseLaunch`; a scene-phase change cancels the caller, never the
  step. A failed recovery is recorded once, retried only in the foreground, and retried by the next protocol
  call. One log that fails to materialise must not stop the others.
- *Unreadable rows.* While `unreadableCount(for:) > 0` the host resumes from what it can read and never
  materialises or compacts; `finish` throws `incompleteLog`. Only damage can cause it in M1.
- *Two live logs* cannot arise on one device, because `start` refuses. If recovery finds two, it resumes the
  one that started last, keeps the other and logs a fault. The real rule is F17's.
- *Seeded scripts.* `SeededGenerator` and `RandomWorkout` live in `LedgerDomainTests`, which `LedgerSyncTests`
  cannot import. S1's contract needs its own small script generator in `LedgerTestSupport`, over
  `EventBuilders`.

**Presentation**

- *Purity.* The reviewer greps `FeatureWorkout` for `Date()`, `Date.now`, `Timer`, `.timer` and
  `timerInterval`. Event times come from `@Dependency(\.date)`; view time from `WorkoutTimeline`; the rest
  shown, the cursor, the next row, rounds and group rest all come from Domain functions.
- *The rest card after zero.* The engine keeps an ended rest in the state until a set starts another. In a
  superset, logging A2 after the rest ended starts none, so "Rest over" would stay through B2. The rule
  ("show the rest until a set is done after it ended") is a Domain function, `WorkoutState.shownRest`, not
  view code; F18 needs the same rule.
- *The cursor.* A `started` snapshot's cursor is not validated (F04 review N7) and may be `nil` (an empty
  day). Views read `WorkoutState.checkedCursor` and never index with the raw one. `StartWorkoutUseCase`
  refuses an empty day (`emptyDay`), and F09 should not offer Start for one.
- *Stale state between taps.* The update stream and `apply`'s return value both set the store's state. The
  intent pump takes the returned state as the base for the next intent; the stream delivers effects and
  remote changes.
- *Tap latency.* The brief wants a row to change within a frame and `apply` under 30 ms including the write.
  The row changes only after the write, by design: showing a tick the log does not hold could lose a set.
  The button's pressed look is the instant feedback. Measure with a signpost; a nightly performance test on a
  real file pins 30 ms.
- *Start latency.* The use case reads the catalog and up to eight "Last" lines before the cover opens; the
  budget is 200 ms. Each query's budget is 50 ms at 20,000 sets, so the worst case is over. Measure in S2;
  if it is slow, open the cover in its loading state once the conflict check has passed.

**Accessibility**

- *One tree per view, pinned.* F06's lesson. Never put `.accessibilityLabel`, `.accessibilityValue` or
  `.accessibilityIdentifier` on a `SetRow` from outside: it reaches both of its buttons
  (`SetRow.swift:25-27`). Name the row with `accessibilitySummary`. UI tests find a set by its check's label
  ("Log set 2").
- *The rest card* is one element: "Rest, 1:30 remaining", then "Rest over". The ring already carries
  `.updatesFrequently` (`RestRing.swift:36`). Posting the announcements is a side effect a snapshot cannot
  see; give `RestPanel` an injectable announcer so a test can.
- *Reduce Motion:* the ring's timeline is `.periodic(by: 1)` instead of `.animation`.
- *Large text:* steppers stack and numerals shrink at accessibility sizes (F06); the Target and Last lines
  and the rest card's buttons must wrap or stack, which the AX3 references show.
- *System dialog.* The conflict dialog is a system `confirmationDialog`; it is tested through the launcher's
  state, not by snapshot.

**Tooling**

- *Previews.* A `.task` inside a scroll view traps `ImageRenderer` (F07 S3, deviation 6). `WorkoutRoot` holds
  the `.task`; previews and snapshots draw `WorkoutScreen` from a model.
- *`@Observable` with `@Dependency`* needs `@ObservationIgnored`. Presentation builders must be `nonisolated`
  in a target whose default isolation is the main actor.
- *Lint limits:* 300 lines per file, 150 per type body, 40 per function, 150 per view. Hence the
  `WorkoutPresentation+…` and actor extension files.
- *`LedgerDesign` additions* compile for watchOS too, and each needs a gallery entry, a preview case,
  snapshots and a pinned VoiceOver tree. That is why only the full-width pill and `ReceiptLayout` go there.
- *String catalogs under `swift test`.* The host gate builds every target with SwiftPM, which copies an
  `.xcstrings` file without compiling it. English keys still resolve to themselves; plural variants do not.
  Tests that check plurals must run in the simulator plans (they do: `FeatureWorkoutTests` is not in the host
  filter).
- *Performance budgets (architecture §15).* The launch step runs after the first frame and reads one short
  query when no workout is stored, so cold launch is unaffected. Replaying a 500-envelope log is pinned under
  5 ms (`LedgerDomainTests/Engine/ReplayPerformanceTests.swift:16-25`, nightly). Finishing writes one workout
  at the end of history: the budget is under 50 ms.

## Inputs the implementer needs

### Every slice

Read `docs/engineering-standards.md` (all), `docs/architecture.md` §3, §4, §6, §13, the brief with both
"Inputs" sections, and this file. Screen slices also read testing-strategy §2.5–2.6 and the F07 notes'
"Decisions and deviations" for S3 (`tasks/features/F07-composition-di/implementation-notes.md:855-887`).

Prototype regions (the files are large; read only these):

- `design/prototype/Ledger v2.dc.html` 133–260, the look: header 134–149; title and swap 151–161; Last and
  Repeat 163–167; column header 169–174; rows and steppers 176–200; add set 201–202; REMAINING 204–217; rest
  card 220–240; swap sheet 242–258.
- `design/prototype/Ledger.dc.html` 510–656, the v1 behaviour: header 513–523; TARGET 537–541; LAST 545–549;
  superset legend 551–562; rows 571–594; REMAINING 599–610; rest sheet 613–634; swap sheet 636–652. Script:
  `buildSession` 989–1007, `logSet` 1008–1063, `nextOf` 1064–1074, `altsFor` 1075–1080, the screen's values
  1474–1562.
- `design/prototype/Ledger.dc.html` 451–505: Session receipt.

Rules for every screen slice:

- The store holds: the last `WorkoutState`, a local `selectedSetID`, sheet flags, the bests, the receipt, an
  error. It never holds a cursor, a remaining time, an elapsed time or a done flag of its own.
- Selection: the shown row is `selectedSetID` if that set still exists, else `checkedCursor`. Tapping an
  undone row sends `exerciseSelected` and clears the local selection. Tapping a done row sets it locally (the
  engine ignores a done row, rule 11). A change of the engine's cursor clears it. The shown exercise is the
  one that holds the shown row.
- Identifiers for F15: `workout.header.minimize`, `.elapsed`, `.finish`; `workout.card.title`, `.swap`,
  `.repeat`, `.addSet`; `workout.remaining.row.<n>`; `workout.rest.card`, `.extend`, `.skip`;
  `workout.swap.row.<n>`, `.updateProgram`; `workout.finish.save`, `.discard`, `.keep`;
  `workout.receipt.done`. Set rows are found by label.
- Tokens: `LedgerColor` (`Tokens/LedgerColor.swift:18-52`), `LedgerFont.Role` (`Tokens/LedgerFont.swift:13-15`),
  `LedgerSpacing` (`:6-13`), `LedgerRadius` (`:6-12`). `LedgerPressStyle` is internal to `LedgerDesign`.

### S1 — seam

- Read: ADR-008; ADR-004 "The host loop"; `LedgerDependencies/Keys/DeviceKeys.swift:13-97` and
  `Unimplemented/Unimplemented.swift:5-27` (the key and stub pattern); `LedgerFakes/DeviceFakes.swift`,
  `InMemoryWorkoutEventStore.swift:8-62` (an actor fake); `LedgerTestSupport/Engine/
  WorkoutEventStoreContract.swift:10-60` and `Persistence/ContractClause.swift:6-18` (the contract pattern);
  `Engine/EventBuilders.swift:6-131`.
- Calls: `WorkoutEngine.reduce(_:_:)` (`LedgerDomain/Engine/WorkoutEngine.swift:43`); `EventEnvelope.init`
  (`Engine/EventEnvelope.swift:32`); `Effect` (`Engine/Effect.swift:20-39`); `WorkoutState.elapsed(at:)`
  (`Model/WorkoutState.swift:111`); `Fixtures.seedSession()`, `Fixtures.deviceID`, `Fixtures.now`
  (`LedgerFakes/Fixtures/Fixtures+Program.swift:169`, `Fixtures.swift:34-36`).
- Signatures: as under "What F09 gets from S1". The stub's `updates()` returns `stub.emptyStream()`; the
  rest throw `stub.failure()`.
- Contract clauses: the first element is the current state with no effects; `start` then `current()`; a
  second `start` throws `workoutInProgress`; a snapshot that is not live throws `notStartable`; `apply` with
  nothing live throws `noLiveWorkout`; `apply`'s return equals the next update's state; an update's effects
  are exactly `feedback(from:)` of the engine's; two subscribers both get every update in order; `finish`
  returns a finished state with `endedAt`, publishes it, and then `current()` is nil and a new stream starts
  with nil; `discard` likewise.
- Add the key's row to `LedgerDependenciesTests/DependencyKeysTests.swift:23-37`,
  `UnimplementedStubTests.swift` and `PreviewValueTests.swift`.

### S2 — host

- Read: ADR-004 with its whole amendment; the brief's "Inputs from F04" and "Inputs from F05";
  `tasks/features/F17-live-sync.md` "Inputs from F04" items 1–5 and both "Inputs from F05"; the F07 notes on
  the launch (`:459-494`, and fix round 2 at `:706`); the test-side host model
  `LedgerDomainTests/Engine/Adversarial/HLCHostAdversarialSupport.swift:12-176`.
- Calls: `WorkoutEventStore` (`Protocols/WorkoutEventStore.swift`): `append` :19, `envelopes(for:)` :24,
  `unreadableCount(for:)` :32, `highestSeq(for:device:)` :35, `uncompactedWorkoutIDs()` :47,
  `newestWallClock()` :51, `compact(workout:)` :53. `WorkoutEngine.replay` (`Engine/WorkoutEngine+Replay.swift:11`).
  `WorkoutRepository.materialize(_:slotUpdates:)` (`Protocols/Repositories.swift:67`). `ProgramRepository.active()`
  (`:26`). `MissTracking.update(slot:exercise:weekIndex:isDeload:)` (`Rules/MissTracking.swift:10`).
  `SessionBuilder.build` and `.resumable` (`Rules/SessionBuilder.swift:16-26`, `:73-84`).
  `ExerciseRepository.all()` (`Repositories.swift:9`), `StatsQueries.lastPerformance(exerciseID:)` (`:110`),
  `SettingsRepository.load()` (`:91`). `DatabaseLaunch.task(for:retrying:_:)` (`LedgerPersistence/DatabaseLaunch.swift:126-144`)
  and `fail(_:_:)` (`:165-168`). `AppComposition` `init` `:29-45`, `resume(in:)` `:96-106`, `bind` `:128-136`.
  `LedgerStores` (`LedgerPersistence/LedgerStores.swift:7-28`). Test harness: `LedgerAppKitTests/Support/Harness.swift`;
  write failures with a SQLite trigger, as `LaunchStepTaskAdversarialTests.swift:21-24` does.
- Signatures:

```swift
public struct HybridLogicalClock: Hashable, Sendable {
    public private(set) var newest: Date?
    public init(newest: Date? = nil)
    public mutating func observe(_ stamp: Date)      // a non-finite stamp is ignored
    public mutating func stamp(now: Date) -> Date     // max(now, newest + 1 ms); becomes newest
}

public struct StartWorkoutUseCase: Sendable {
    public enum Outcome: Hashable, Sendable {
        case started(WorkoutState), resumed(WorkoutState), conflict(live: WorkoutState)
    }
    public init(session: any WorkoutSessionClient, programs: any ProgramRepository,
                exercises: any ExerciseRepository, stats: any StatsQueries,
                settings: any SettingsRepository, device: DeviceID,
                now: @escaping @Sendable () -> Date, newID: @escaping @Sendable () -> UUID)
    public func start(_ source: WorkoutSource, replacingLive: Bool = false) async throws -> Outcome
}
public enum StartWorkoutError: Error, Equatable, Sendable {
    case programNotActive(ProgramID), dayNotInProgram(DayTemplateID), emptyDay(DayTemplateID)
}

public actor LocalWorkoutSessionActor: WorkoutSessionClient {
    public init(events: any WorkoutEventStore, workouts: any WorkoutRepository,
                programs: any ProgramRepository, device: DeviceID,
                now: @escaping @Sendable () -> Date)       // S6 adds `notifications:`
    @discardableResult public func resumeFromStore() async throws -> WorkoutState?
}

// DatabaseLaunch
public func run(_ step: LaunchStep, retrying: Bool,
                _ body: @escaping @MainActor () async throws -> Void) async
```

- An own action, in order: wait for recovery; stamp (`seq` is `highestSeq + 1`, kept in memory after recovery
  or `start`); `reduce`; if it returns no effects the event was ignored: change nothing and store nothing;
  `.persist` → `append` (a throw stops here); commit state, clock and `seq`; `.materialize` → misses from the
  stored program, `materialize`, then `compact`; `.discardLog` → `compact`; `.transmit` and
  `.updateLiveActivity` do nothing yet; publish `(state, feedback(from: effects))`; after a terminal event the
  current workout is nil.
- Recovery: the clock from `newestWallClock()`; then each uncompacted log by `replay`:

| Stored when the app died | The launch step | The lifter sees |
|---|---|---|
| nothing, or the `started` never reached the store | nothing | Start workout |
| a live log | resumes it; no effects, no haptic | Resume · m:ss; the same sets, cursor and rest (from `endsAt`) |
| `finished` stored, not materialised | materialises with misses from the program as stored now, then compacts | the Logged card; no cover |
| materialised, not compacted | materialises again (an upsert: no change), then compacts | the same |
| `discarded` stored, not compacted | compacts | Start workout; nothing in history |
| a log that replays to nil | keeps it, logs a notice | nothing |
| a log with unreadable rows | live: resumes from what it reads; ended: keeps it | Resume, or nothing |
| a save that throws | keeps the log, records `.failed(.resumeWorkout)`, carries on with the other logs | nothing lost; retried on the next foreground |

### S3 — persistence follow-up

- Read: F05 notes `:980-992` (decisions 4–6) and `:1180-1192`; ADR-008 decision 5 (the fakes refuse what the
  database refuses, in the same order).
- Calls and places: `GRDBWorkoutRepository.materialize` (`LedgerPersistence/Repositories/GRDBWorkoutRepository.swift:49-62`)
  and its `writeMisses` (`:149-169`), the pattern to follow; `slot.exercise_id` (`Records/SlotRecords.swift:51`);
  `InMemoryWorkoutRepository.materialize` (`LedgerFakes/InMemoryWorkoutRepository.swift:33-45`) and
  `InMemoryProgramRepository.writeMisses` (`InMemoryProgramRepository.swift:81`); the doc lines to change
  (`LedgerDomain/Protocols/Repositories.swift:60-62`, `GRDBWorkoutRepository.swift:42`);
  `WorkoutRepositoryContract` (`LedgerTestSupport/Persistence/WorkoutRepositoryContract.swift`), whose
  `full` workout already sets a `programUpdates` entry for an unstored slot (`:135`).
- If O10 is approved: `WorkoutEvent.exerciseSwapped` (`Engine/WorkoutEvent.swift:34`), `swap`
  (`Engine/WorkoutEngine+Reduce.swift:144-154`), `isWellFormed` (`Engine/EventEnvelope.swift:77-93`: a
  snapshot's `lastPerformance.date` must be finite), `ModelOracle+Edits.swift`, the fixtures in
  `LedgerPersistenceTests/Fixtures/payload-v001/event-exerciseSwapped.json`, and an ADR-004 note on rule 8.

### S4 — cover and header

- Read: spec §3.7 item 1, §7.7 rule 36; v2 lines 134–149; architecture §12; F07 notes S3 deviations 2 and 6.
- Calls: `ProgressSegments(_:label:value:)` and `ProgressSegment(length:state:)`
  (`LedgerDesign/Components/ProgressSegments.swift:4-16`, `:36`); `PillButton(_:style:action:)`
  (`PillButton.swift:16`); `LedgerIconView` (`LedgerIcon.swift:58`); `SupersetRounds.blocks(in:)`
  (`LedgerDomain/Rules/SupersetRounds.swift:28`); `ClockText`; `DebugMenu` (`LedgerDesign/Gallery/DebugMenu.swift:8-47`);
  `AppRoot` (`LedgerAppKit/AppRoot.swift:16-38`); the preview registry pattern (`LedgerAppKit/AppKit+Previews.swift:7-25`)
  and `PreviewScan`; `assertLedgerSnapshot(of:named:devices:themes:typeSizes:)` (`LedgerSnapshotTesting/LedgerSnapshot.swift:73`);
  `withTestDependencies` (`LedgerTestSupport/WithTestDependencies.swift:39`).
- Public surface:

```swift
public enum WorkoutRoute: Hashable, Sendable { case minimized, saved(WorkoutID), discarded }
@MainActor @Observable public final class WorkoutLauncher {
    public init()
    public func start(_ source: WorkoutSource) async     // use case → cover, or the conflict dialog
    public func resume()                                   // the cover, for the live workout
}
public extension View {
    func workoutCover(_ launcher: WorkoutLauncher, onRoute: @escaping (WorkoutRoute) -> Void = { _ in }) -> some View
}
public struct WorkoutRoot: View                             // the cover's content
public extension WorkoutState { var checkedCursor: Cursor? { get } }   // LedgerDomain: nil unless it names a row
```

- A segment is one exercise: length its set count; done when every set is done, current when it holds the
  shown row, upcoming otherwise.
- *Corrected after S4 (review S4-N6):* the surface above is stale in two places. `WorkoutLauncher.start(_:)` is a
  synchronous intent, as `resume()` is (the rulings below), and `WorkoutRoot` is internal: the app uses
  `WorkoutLauncher`, `View.workoutCover(_:onRoute:)` and `WorkoutRoute` only.

### S5 — solo exercise

- Read: spec §3.7 item 2 and "Interactions", §7.4 rules 18, 20, 22, §7.5 rules 25, 26, 28; v2 lines 151–217;
  v1 lines 537–549.
- Calls: `SetRow` (`LedgerDesign/Components/SetRow.swift:40-49`; the `Text` summary form `:70-79`),
  `SetRowHeader` (`SetRowHeader.swift:9`), `SetRowSteppers` (`SetRowSteppers.swift:22-29`), `HairlineList`,
  `HairlineRow` (`HairlineRow.swift:17-22`), `Eyebrow` (`Eyebrow.swift:16`). Events (`Engine/WorkoutEvent.swift`):
  `exerciseSelected` :21, `setLogged` :23, `setUnlogged` :25, `setTargetChanged` :27, `setAdded` :29,
  `allSetsRepeated` :31. `Weight.advanced(bySteps:of:)` (`Units/Weight.swift:81`), `Weight.formatted(in:)`
  (`:101`), `Reps(clamping:)` (`Units/Reps.swift:18`), `RPE.label` (`Units/RPE.swift:29`),
  `LastPerformance.line(units:calendar:)` (`Model/LastPerformance.swift:22`), `WorkoutExercise`
  (`Model/WorkoutExercise.swift:7-59`), `LoggedSet` and `SetKind` (`Model/LoggedSet.swift:4-35`).
- Weight floors at zero, reps at one. "+ Add set" copies the last row, or 0 × 8 for an empty list (spec
  §3.7). Repeat is hidden without a `lastPerformance`.

### S6 — rest and effects

- Read: spec §3.7 item 4, §7.4 rules 19, 22, 23, §3.10 "Active workout (v2)"; decision #7; ADR-004 "The clock
  rule"; v2 lines 220–240; brief criteria 3, 6, 7.
- Calls: `RestRing(progress:label:size:)` (`LedgerDesign/Components/RestRing.swift:13`),
  `RestTimer.remaining(at:)` and `fraction(at:)` (`Model/RestTimer.swift:19`, `:29`), `restExtended` :44 and
  `restSkipped` :46, `Haptic` (`Engine/Effect.swift:4-12`), `PrimaryButton` (`PrimaryButton.swift:17`),
  `Clients.swift:8-12`, `UnimplementedDevices.swift:14-16`, `DeviceFakes.swift:25-32`,
  `AppComposition.bind` (`:128-136`).
- Additions:

```swift
public protocol HapticsClient: Sendable { func play(_ haptic: Haptic) async }
public protocol NotificationsClient: Sendable {
    func scheduleRestOver(at endsAt: Date) async       // replaces any scheduled one
    func cancelRestOver() async
}
public extension WorkoutState { var shownRest: RestTimer? { get } }   // nil once a set is done after the rest ended
```

- "+30s": `restExtended(amount: .seconds(30), extendsShownRest: remaining > .zero, tappedAt: now)`, both from
  the injected date at the tap. With `autoRest` off no rest starts, so no card shows.

### S7 — finish and receipt

- Read: spec §3.6, §7.6 rules 30–32, §7.7 rule 34; v1 lines 451–505; decisions #3, #5, #25, #26, #27; the
  brief's "Inputs from F05" items 1–3 and 8; Pete #4–#6.
- Calls: `WorkoutEngine.summary(_:prs:)` (`Engine/WorkoutEngine.swift:90`), `WorkoutSummary` and `ReceiptRow`
  (`Model/WorkoutSummary.swift:4-45`), `StatsQueries.bests(before:for:)` (`Protocols/Repositories.swift:134`),
  `PersonalRecords.detect(workout:against:now:)` with `now: state.startedAt` (`Rules/PersonalRecords.swift:56`),
  `WorkoutState.doneSets`, `totalSets`, `volume` (`Model/WorkoutState.swift:90-105`), `Volume.formatted(in:)`
  (`Units/Volume.swift:22`), `SheetChrome` (`SheetChrome.swift:20-25`), `StatTile` and `StatTileRow`
  (`StatTile.swift:24-30`, `:96`).
- The receipt's date is the day the workout started (decision #26), from the injected calendar and locale.

### S8 — swap

- Read: spec §3.7 item 5, §7.5 rule 27; decision #13 and Pete #1–#3; v2 lines 242–258; brief criterion 8 and
  its third risk.
- Calls: `Exercise` (`Model/Exercise.swift:31-66`: `curatedAlternatives`, `pattern`, `primaryMuscle`,
  `equipment`), `Exercise.startLoad(in:)` (`:71`), `Equipment.defaultStep(in:)` (`:9`),
  `ExerciseRepository.all()`, `StatsQueries.lastPerformance(exerciseID:)`, `exerciseSwapped` :34,
  `setTargetChanged` :27, `HairlineRow` with a text accessory, `IconPillButton` (`IconPillButton.swift:10`).
- `SwapAlternatives.ranked(for exercise: Exercise, in catalog: [Exercise]) -> [Exercise]` in `LedgerDomain/Rules`.

### S9 — supersets

- Read: spec §3.7 (superset legend, row labels), §7.4 rules 19–20, §7.7 rule 44; decision #6; v1 lines
  551–562 and script 1474–1493; brief criterion 4.
- Calls: `SupersetRounds` (`LedgerDomain/Rules/SupersetRounds.swift`): `blocks(in:)` :28, `displayOrder` :34,
  `isLastOfRound` :39, `groupRest` :45, `letter(forMemberAt:)` :51, and the private `rounds` :78, to be made
  public. `RestDuration.label` (`Units/RestDuration.swift:26`).
- "Round r of n": r is the round that holds the first undone row, n the number of rounds. The legend marks
  the member that holds the shown row.

## Orchestrator rulings (2026-10-04)

Pete approved the M1 opening lanes (F08, F09, F10 in parallel) on 2026-10-04. The plan above is accepted with the
rulings below. Where a ruling and the plan disagree, the ruling wins.

**Slices.** Nine, as planned (O16). S1 seam (`feat/F10-s1-session-seam`) starts now; F09's last slice builds on it.
S4 (the cover) waits for F09 S1 (the tab shell and the localization scaffolding) as well as S2.

**The plan's decisions.**
- O1–O6 accepted: `updates()` is an async method returning a new unbounded stream per call; `state` is optional and
  there is no `origin`; `resumeFromStore()` is the host's, and every protocol method waits for recovery; `apply`
  returns the new state; the host runs the notification effects and `effects` carries haptics only
  (`WorkoutSessionUpdate.feedback(from:)` is the one rule); the fake is engine-backed and held to the host by a
  shared contract and seeded scripts.
- For S2, from O3: recovery must be started by the first protocol call if the launch step has not run, so a call
  can never wait for ever.
- O7 accepted: `StartWorkoutUseCase` in `LedgerDomain/UseCases`, S2. O8 accepted, pending Pete's decision 1.
- O9 accepted for M1: misses are recorded only when the active program is the workout's.
- O10: decided when S3 starts. It changes an engine payload, so it needs the version-1 fixtures proven and, if
  ADR-004 is amended, Pete's review of that PR.
- O11 accepted. O12–O14: replaced by "M1 shared conventions" below; the copy file is `WorkoutCopy.swift`, and
  `WorkoutLauncher`'s start and resume are synchronous intents.
- O15 accepted: a Debug-only "Start sample workout" row. O17 accepted: `HybridLogicalClock` and `ClockText` in
  `LedgerDomain`.
- O18 accepted: `.restOver` plays only when zero is crossed while the screen is active.
- O19 accepted: the snapshot matrix. O20 accepted: "Undo set 2".

**`ClockText` (S1).** m:ss under an hour ("0:00", "24:22"), h:mm:ss from sixty minutes ("1:01:05"), which is also
what SwiftUI's timer text shows. Put to Pete (the prototype prints "61:05"); a change is one line and its tests.

**Pete's decisions.** Asked on 2026-10-04; until he answers, these hold: (1) "Also update program" lands with the
saved workout; (2) a program swap keeps the slot's numbers; (3) decision #13 as written, with the by-equipment rule
recommended to Pete before S8; (5) the drafted failure wording without the product name; (6) the target as a quiet
line and "End workout?" as a sheet.

### M1 shared conventions (orchestrator, 2026-10-04; the same text is in the F08, F09 and F10 notes)

The three planners proposed the same patterns with small differences. These are the rulings; they hold for every M1
feature. F09 S1 lands the localization scaffolding and writes rules 1 and 3 into `docs/engineering-standards.md` §7 and
`docs/architecture.md` §4; once that slice is on `main`, the docs are the source and this block is a summary.

1. **Localization.**
   - One hand-written `Resources/Localizable.xcstrings` per module that has copy. Source language English. The key is
     the English text with its format specifiers. The target gains `resources: [.process("Resources")]`;
     `defaultLocalization: "en"` is set once in `Package.swift` (F09 S1).
   - All of a module's copy is resolved in its copy file(s): `<Feature>Copy.swift` (and `<Feature>Copy+<Area>.swift`
     when it grows), a `nonisolated enum` whose members return `String`, or `Text` only where the string embeds a live
     view such as a timer. No other file in the module holds a user-facing literal or a localized lookup: views,
     stores, presentation builders and `LedgerDesign` components receive `String`s.
   - Lines the Domain already formats (weights, volumes, receipt rows, the last-performance line, rest labels, clock
     text) and data (program and day names, catalog names) are shown as given and are not catalog entries.
   - One shared helper in `LedgerTestSupport/Localization/` and one test per module: every key the copy files use is in
     the catalog and the reverse; no lookup or user-facing literal outside the copy files; a plural key has `one` and
     `other`. A key holds at most one counted value; fragments are joined with " · ".
   - Shipped copy never contains the product name (`docs/product-decisions.md` › Naming).
2. **Stores.** `XRoot` (public; owns the store in `@State`; runs its async work from `.task` / `.task(id:)`),
   `XScreen(model:)` (only draws a state; what previews, snapshots and accessibility tests use), `XStore`
   (`@MainActor @Observable final class`; dependencies as `@ObservationIgnored @Dependency`; synchronous intents; no
   stored `Task` and no `Task { }` in a store or a view), `XPresentation` (a `nonisolated` namespace of pure functions
   from inputs to a display model). State is `Loadable<Model>` (`LedgerDomain`, lands with F09 S2) when the states
   are exactly loading / loaded / failed, otherwise a store-specific enum. Tests never sleep: they call the async
   method directly or await `Observations`.
3. **Routing.** A feature exposes `public nonisolated enum XRoute: Hashable, Sendable` and
   `XRoot(onRoute: @escaping @MainActor (XRoute) -> Void)`. `onRoute` is **synchronous**: a route is an intent, and the
   app resolves it (`LedgerAppKit/Routes.swift`, `Routes+<Feature>.swift`; every tab's stack is keyed by the one
   `AppDestination`). A feature never presents another feature. A feature with no exit the app must resolve
   (onboarding) has no route. A feature that presents itself over the tabs (the workout) exports its presenter and
   modifier; its start and resume entry points are synchronous intents as well, drained by its own `.task`.
4. **Shared one-line files** (`Package.swift` `snapshotTestTargets`, `scripts/coverage-thresholds.json` `required`,
   `LedgerTestSupport/Previews/PreviewScan.swift` `registeredModules`): add only your module's name. The orchestrator
   resolves the conflicts when it merges `main` into a branch.
5. **Accessibility.** One intended VoiceOver tree per component or screen, written down in these notes and pinned by a
   table-driven test before the tester starts (F06's lesson).
6. **Test names** follow `docs/testing-strategy.md` §6 (`subject_condition_expectation`, a sentence as the display
   name), not the briefs' `test_…` names.

## Slice S1 — session seam (G1 implementer, 2026-10-04)

Built on `92a63bd`, in the worktree `F10-s1`, on `feat/F10-s1-session-seam`. Nothing is committed and no PR is open.
Paths are under `LedgerKit/` unless they start with `docs/` or `tasks/`.

### What landed

| File | Contents |
|---|---|
| `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift` (new) | `WorkoutSessionClient` (the six calls, as the brief's amendments sign them), `WorkoutSessionUpdate` (`state`, `effects`, `live`, `feedback(from:)`), `WorkoutSessionError` |
| `Sources/LedgerDomain/Units/ClockText.swift` (new) | `ClockText.minutesSeconds(_:)` |
| `Sources/LedgerDependencies/Keys/SessionKeys.swift` (new) | `DependencyValues.workoutSession`; `WorkoutSessionKey`: live value the stub, preview value a fake with no workout (`#if DEBUG`), test value the library's default |
| `Sources/LedgerDependencies/Unimplemented/UnimplementedSession.swift` (new) | `UnimplementedWorkoutSession`: `updates()` logs and ends at once, the other five log and throw |
| `Sources/LedgerFakes/FakeWorkoutSessionClient.swift` (new) | the engine-backed fake, inside `#if DEBUG` |
| `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract.swift`, `+Lifecycle`, `+Updates`, `+Model`, `+Scripts` (new) | the contract: 17 clauses, the rules as a model, seeded scripts. Five files because of the 300-line lint limit |
| `Tests/LedgerSyncTests/WorkoutSessionClientContractTests.swift` (new) | the clauses and 200 seeded scripts on the fake; the script generator's own checks |
| `Tests/LedgerSyncTests/WorkoutSessionClientContractFaultTests.swift`, `Support/FaultyWorkoutSession.swift` (new) | a second, independent client with eleven switchable faults: each must break a named clause and be noticed by a script |
| `Tests/LedgerSyncTests/FakeWorkoutSessionClientTests.swift` (new) | what the fake adds to the contract: `applied`, `init(live:)`, the stamp, forgotten streams |
| `Tests/LedgerSyncTests/Support/Tags.swift` (new) | `Tag.sync`, `Tag.property` (see deviation 14) |
| `Tests/LedgerDomainTests/Units/ClockTextTests.swift`, `Protocols/WorkoutSessionUpdateTests.swift`, `Protocols/WorkoutSessionClientTests.swift` (new) | the formatter; `feedback(from:)` and `live`; the protocol's shape and errors |
| `Tests/LedgerDependenciesTests/DependencyKeysTests.swift`, `UnimplementedStubTests.swift`, `PreviewValueTests.swift` | the key's row in each, and a test that binds the key to a fake |
| `docs/architecture.md` §13 | the key, its stub and its preview value |

Unchanged: `Package.swift`, `package-graph.expected.txt` (no new edge), `scripts/coverage-thresholds.json`, the test
plans, `project.pbxproj`, `AppComposition`. Nothing of S2 to S9 is in the tree.

### Decisions and deviations

The design points the orchestrator asked to settle are 1 to 7.

1. **An event the engine ignores: `apply` returns the workout as it stands and nothing is published. An event the
   engine accepts is published once, also when it leaves the state as it was.** So an update is published exactly
   when the event enters the log (`.persist`).
   - Why, from ADR-004: an ignored envelope is "no state change and no effects" (`docs/adr/ADR-004…md:138-141`), so
     there is nothing to store, run or announce; an accepted one "belongs in every log even when it changes nothing
     here, because a peer may order it differently" (`Sources/LedgerDomain/Engine/WorkoutEngine.swift:39-40`), so it
     happened, and the stream says so. The plan's S2 text already reads this way (this file, line 564).
   - The alternative, "publish only when the state changed", was rejected: criterion 3 ("equal to the next update's
     state") would not hold for an accepted event that changes nothing, and a done set logged again with the same
     values changes nothing yet buzzes, so "changed" cannot be the rule anyway.
   - What the engine ignores on a live workout: a second `started`, a date that is not finite, a rest outside
     `0 ... longestRest` (`WorkoutEngine.swift:31-36`). What it accepts without a change: a row that does not exist,
     a done row selected (rule 11), a done set logged again.
   - Consequence: `finish(endedAt:)` and `discard(endedAt:)` with a date that is not finite end nothing. `finish`
     then returns the workout still live, because `WorkoutSessionError` (final) has no case for it. Pinned by the
     clause "an event the engine ignores…"; see open question 2.
2. **`start` judges the snapshot before the session.** A snapshot the engine would not start throws `notStartable`
   whether or not a workout is live; only then `workoutInProgress` (which names the live workout, not the new one).
   `notStartable` also covers a live snapshot that is malformed (a date that is not finite), which the brief does
   not mention: the engine ignores its `started`, and a start cannot succeed with no workout. Pinned, so that the
   fake and the host refuse in the same order (ADR-008 decision 5's rule, applied here).
3. **`apply` never starts a workout** (`apply(.started)` with nothing live throws `noLiveWorkout`), **and a terminal
   event through `apply` ends the workout exactly as `finish` and `discard` do.** The fake has one path for all four
   calls (`FakeWorkoutSessionClient.swift:99-122`); a host with a separate finish path would drift, so both are
   clauses.
4. **After the update that ends a workout there is no further update until the next start.** `state` is nil only in
   a stream's first element. Existing subscribers learn of the end from the finished or discarded state
   (`update.live == nil`); a stream opened afterwards starts with nil.
5. **The contract uses the protocol only, and is parameterised by the client it is handed**
   (`ContractClause<any WorkoutSessionClient>`, as the store contracts; `violations(of:)` takes a factory).
   What it deliberately does not observe, and so does not constrain: an envelope's stamp (device, `seq`, wall
   clock); what is stored; the effects a host runs itself (notification, Live Activity, materialise, compact);
   recovery; a failing store. It reads streams without waiting on a clock: each clause ends with one recognisable
   change (`markEnd(of:)`: a one-second rest ending a day after the start, or the start of a workout of its own) and
   reads every stream up to it. A client that publishes too few or too many updates therefore gets a line naming
   the first difference, not a hang. Only a client that never publishes that last change, or whose streams have no
   first element, keeps a clause waiting until the suite's one-minute limit fails it.
6. **A terminated subscriber is removed without a task.** A stream's `onTermination` runs synchronously on whatever
   thread cancels or drops it, so it cannot touch actor state, and standards §4 forbid the unstructured `Task` that
   could. It appends its id to a `Mutex<[Int]>` (`FakeWorkoutSessionClient.swift:27-30`, `:73-75`); every
   `updates()` and every publication first drops those ids (`dropEnded`, `:141-149`). The fake therefore holds at
   most the streams that ended since its last subscription or publication.
   - Why not "prune when `yield` reports `.terminated`" alone: it prunes only at a publication. Today's screen
     coming and going while no workout starts would add a continuation each time, without bound, until the next
     start.
   - `LedgerFakes` may use a `Mutex` (ADR-008 decision 4; `Support/ObservedState.swift:75-77` also removes an
     observer from `onTermination`, under its lock). For the host see open question 1.
   - Shown by `FakeWorkoutSessionClientTests.droppedStreams_areForgottenAtTheNextSubscription` (1,000 streams opened
     and dropped with nothing published: one is held), `cancelledStream_isForgottenAtTheNextPublication`,
     `openStreams_staySubscribed`. They read `subscriberCount`, which is internal (`@testable import LedgerFakes`).
     Mutants M1 and M2 below fail them.
7. **The fake's stamp is deterministic and unobservable.** Device: the `device` it was built with. `seq`: 1 for the
   `started`, then one more per accepted event; an ignored event takes none. Wall clock: the injected `now()`, read
   once per call, never `Date()` (`stamp_changesNothingObservable` counts the reads and shows that another device
   and a moving clock change no update; mutant M11). The fake keeps no log and exposes no envelope, so nothing a
   test can write against the fake depends on the stamp, and the host's hybrid logical clock cannot disagree with
   it. `device:` and `now:` are kept as the plan's signature has them (this file, lines 116-120), though no caller
   can see their effect.
8. **`applied` lists every ask**, in call order, including a call the fake refused and an event the engine ignored
   (criterion 7: "records what it was asked"). A screen test asserts what its store asked for, whatever came of it.
9. **`FakeWorkoutSessionClient(live:)` runs the engine's `started` on the snapshot.** One the engine would not start
   reports an issue, which fails the test that passed it, and leaves no workout: the same choice as
   `InMemoryStores`' illegal seed (`Sources/LedgerFakes/InMemoryStores.swift:71-74`, finding F7-10).
10. **The contract includes the rules as a model and seeded scripts** (the plan's risk "Seeded scripts", line 393).
    `script(seed:)` writes 80 calls from a SplitMix64 generator: starts, set edits, rests, a swap, calls that must
    be refused or ignored, and endings by all three routes; `scriptViolation(seed:on:)` runs them on a client beside
    the model and compares every return, every throw, `current()` after every call, and two streams (one from the
    start, one opened at a call the seed picks). S2's `sessionScripts_fakeAndActorPublishTheSame(seed:)` is then
    one line per seed on the actor: both are held to the engine, so they agree with each other.
11. **The clauses are shown to bite.** `FaultyWorkoutSession` (test target) is a second client written from the
    protocol's documentation, with eleven faults a host could have. Each fault must break the clause named for it
    and be noticed by a script within twenty seeds; with no fault it keeps the whole contract. This was not in the
    plan; it is test code only.
12. **`ClockText` counts seconds in `Int128`** (`Duration.attoseconds`), not through `Duration.components`, whose
    `Int64` conversion would trap on the 2^63 s that `WorkoutState.elapsed(at:)` saturates at
    (`Sources/LedgerDomain/Model/WorkoutState.swift:111-113`). It rounds down to whole seconds, and imports nothing.
13. **The preview value is computed, not a `static let`**, as the stores' are (`Keys/StoreKeys.swift:98-111`): the
    library caches a key's value per test, so each test's preview context gets its own fake.
14. **Files outside the slice's list, and why.** `Tests/LedgerSyncTests/Support/Tags.swift`: testing-strategy §6
    wants a layer tag on every suite and `LedgerSyncTests` had none; the new suites carry `.sync`, the existing ones
    are untouched. `Tests/LedgerSyncTests/Support/FaultyWorkoutSession.swift` and
    `WorkoutSessionClientContractFaultTests.swift`: decision 11. `Tests/LedgerDomainTests/Protocols/`: a new folder
    beside `Engine/`, `Units/`, mirroring the source folder.
15. **Not done, by design.** The protocol's `finish` doc does not yet say "calling it again retries a failed save"
    (the plan's wording): the contract cannot make a save fail, so it is S2's sentence to add with its test.
    Architecture §6 still says `WorkoutSessionActor` publishes `WorkoutState`: S2's edit, as planned.

### Criteria → tests

| # | Criterion (brief, "Plan amendments") | Tests |
|---|---|---|
| 1 | first element is the workout as it stands, no effects; later changes in order; two subscribers each get every update | clauses 1, 11, 12, 13, 14, 17; every script (two streams) |
| 2 | `start` makes a live snapshot current; second `start` → `workoutInProgress`; not live → `notStartable`; nothing live → `noLiveWorkout` | clauses 2, 3, 4, 5 |
| 3 | `apply` returns the state after the event = the next update's state; effects = `feedback(from:)` of the engine's | clauses 10, 15, 16; `WorkoutSessionUpdateTests` (the rule itself: `feedback_keepsTheHapticsInOrder`, `_forwardsEachHaptic`, `_dropsWhatTheHostRuns`, `_ofTheEnginesEffects`) |
| 4 | `finish` returns the finished state, one update, then `current()` nil and a new stream starts nil; `discard` likewise | clauses 6, 7, 8, 9; `WorkoutSessionUpdateTests.live_followsThePhase` |
| 5 | `resumeFromStore()` is not on the protocol; every method waits for recovery | `WorkoutSessionClientTests.protocol_isTheSixCalls` (a type with the six calls alone conforms). The waiting is the host's: **not verifiable in S1** |
| 6 | key `workoutSession`; stub's `updates()` ends at once, the rest throw; preview value a fake with no workout | `DependencyKeysTests.test_unimplementedDependencyFailsLoudly` (row `workoutSession`), `workoutSession_boundToAFake_isTheOneRead`; `UnimplementedStubTests.workoutSession`; `PreviewValueTests.previewSession_isAFakeWithNoWorkout` |
| 7 | the fake is in `LedgerFakes`, runs the real engine, records what it was asked, passes the shared contract, is absent from Release | `WorkoutSessionClientContractTests.fake_keepsTheClause` (17 cases), `fake_runsTheScriptByTheRules` (200 seeds), `violations_ofTheFake_areNone`; `FakeWorkoutSessionClientTests.applied_recordsEveryAsk_inCallOrder`, `initLive_holdsTheWorkout`, `initLive_unstartableSnapshot_reportsAnIssue`; the Release build and symbol check below |
| 8 | `ClockText.minutesSeconds`: m:ss, h:mm:ss from sixty minutes, "0:00" when negative | `ClockTextTests.minutesSeconds_table` (17 rows), `_extremes_doNotTrap`, `_ofElapsedTime` |

### The contract's clauses

`WorkoutSessionClientContract.clauses`, in order. Each gets a fresh client with no workout.

Lifecycle (`+Lifecycle.swift`):
1. a new client has no workout: `current()` is nil and a stream starts with a nil state
2. `start` makes a live snapshot current and publishes it, with no effects
3. a second `start` throws `workoutInProgress`, changes nothing and publishes nothing (the same snapshot, and another)
4. a snapshot the engine would not start throws `notStartable`, live workout or not (finished, discarded, malformed)
5. `apply`, `finish` and `discard` with nothing live throw `noLiveWorkout` and publish nothing (`apply(.started)` too)
6. `finish` returns the finished state, publishes it once (with `.haptic(.workoutFinished)`), then there is no
   workout: `current()` nil, a new stream starts nil
7. `discard` publishes the discarded state once (no effects), then there is no workout
8. a terminal event through `apply` ends the workout as `finish` and `discard` do
9. after a workout ends another can start, and earlier subscribers see it; a second `finish` or `discard` of the
   ended one throws `noLiveWorkout`

Updates (`+Updates.swift`):
10. `apply` returns the state after the event; the next update carries it and the engine's haptics (one event of
    each of ten kinds, each checked against `WorkoutEngine.reduce`)
11. a stream opened on a live workout starts with it, without the last event's effects
12. two subscribers, one from before the start, each get every update in order
13. updates under rapid `apply` calls arrive in order, none dropped or merged (sixty edits, read afterwards)
14. callers at once: every event is applied once, in one order every subscriber sees (eighteen commuting edits from
    a task group; the final state holds all of them)
15. an event the engine accepts is published once even when it changes nothing here
16. an event the engine ignores returns the workout unchanged and publishes nothing (also `finish` and `discard` at
    a date that is not finite)
17. a subscriber whose task is cancelled stops; the others keep getting every update

Scripts (`+Scripts.swift`, `+Model.swift`): `scriptViolation(seed:on:)`, decision 10.

### Mutants

Each was applied alone to the source, the host suites run, and the file restored (`f10s1/mutants.py`, log
`f10s1/mutants1.log` in the scratch folder). All eighteen fail at least one test.

| Mutant | Failing tests (first) |
|---|---|
| M1 `updates()` does not forget ended streams | `droppedStreams_areForgottenAtTheNextSubscription` |
| M2 a publication does not forget ended streams | `cancelledStream_isForgottenAtTheNextPublication` |
| M3 a stream keeps only its newest update | the contract (clause 13 and others), the scripts, `openStreams_staySubscribed` |
| M4 an update carries every effect | the contract, the scripts, `initLive_holdsTheWorkout`, the preview test |
| M5 a refused `apply` is not recorded | `applied_recordsEveryAsk_inCallOrder` |
| M6 no first element | the contract, the scripts, five fake tests (the run hit its ten-minute cap: the preview test had no time limit then; it has one now) |
| M7 an ended workout stays current | the contract, the scripts |
| M8 an ignored event is published | the contract, the scripts |
| M9 the session is judged before the snapshot | the contract, the scripts |
| M10 an unstartable seed is silent | `initLive_unstartableSnapshot_reportsAnIssue` |
| M11 the stamp reads `Date()` | `stamp_changesNothingObservable` |
| M12 `feedback(from:)` keeps the rest notification | three `WorkoutSessionUpdateTests`, `initLive_holdsTheWorkout` (not the contract: its expected updates use the same function, which is the criterion) |
| M13 `live` is the state in any phase | `live_followsThePhase`, the scripts |
| M14 the clock text never shows hours; M15 a negative duration prints its magnitude | `ClockTextTests` |
| M16 the stub's `updates()` yields; M17 its `current()` answers nil | `UnimplementedStubTests.workoutSession` |
| M18 the preview value is the stub | `previewSession_isAFakeWithNoWorkout` |

The eleven faults of `FaultyWorkoutSession` (first element carries effects, every effect forwarded, ignored events
published, unchanged states skipped, the state before returned, the ended workout kept current, a nil update after
the end, the session judged first, a start through `apply`, newest-only streams, a silent discard) each break their
clause and are each noticed by a script: `WorkoutSessionClientContractFaultTests`.

### Code lines

Added lines of `git diff -U0 92a63bd`, new files whole, blank and whole-line comment lines excluded
(`f10s1/count-lines.py`).

| Group | File | Added |
|---|---|--:|
| Product | `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift` | 36 |
| | `Sources/LedgerDomain/Units/ClockText.swift` | 15 |
| | `Sources/LedgerDependencies/Keys/SessionKeys.swift` | 19 |
| | `Sources/LedgerDependencies/Unimplemented/UnimplementedSession.swift` | 23 |
| | **Product total** (plan: about 115) | **93** |
| LedgerFakes | `Sources/LedgerFakes/FakeWorkoutSessionClient.swift` (plan: about 110) | **111** |
| LedgerTestSupport | the contract: `…Contract.swift` 110, `+Lifecycle` 199, `+Updates` 208, `+Model` 72, `+Scripts` 187 | 776 |
| Tests | 3 changed files (+48, −1) and 8 new ones | 624 |

Product is 19 % under the estimate and the fake 1 % over. No product line was removed.

### Gate and coverage

**Full gate.** `/usr/bin/python3 <sim-lock> scripts/check.sh` from the worktree root, on the tree above. Started
18:12:35, waited 1,073 s for the lock (F08's gate, then F09's), then **exit 0, `check.sh OK`, 722 s**: tools 1 s,
format 0 s, lint 87 s, iOS build 138 s, iOS tests 251 s, watchOS build 40 s, watchOS tests 202 s, coverage 2 s.
17 test targets ran and passed (PR), 8 (PR-Watch). The build was cold (the worktree had no `.derivedData`). Log:
`f10s1/gate1.log` in the scratch folder, with `GATE_EXIT=0` appended by the shell.

After the gate, one mutant was applied to the fake and reverted, to copy the message in "How to verify by hand"
(`cmp` against the saved original: identical), and this section was appended. No source differs from the gated tree.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 228 / 237 | 96.20 % | 90 % | ✓ |
| LedgerDesign | 2113 / 2175 | 97.14 % | 60 % | ✓ |
| LedgerDomain | 2045 / 2063 | 99.12 % | 95 % | ✓ |
| LedgerFakes | 1434 / 1449 | 98.96 % | 90 % | ✓ |
| LedgerHealth | 47 / 48 | 97.91 % | 80 % | ✓ |
| LedgerPersistence | 2479 / 2497 | 99.27 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 8377 / 8503 | 98.51 % | 80 % | ✓ |

The five new source files are each at 100 % of their lines in the iOS bundle (`xccov`): `WorkoutSessionClient.swift`
23 / 23, `ClockText.swift` 13 / 13, `SessionKeys.swift` 5 / 5, `UnimplementedSession.swift` 19 / 19,
`FakeWorkoutSessionClient.swift` 107 / 107; the watchOS bundle measures the Domain two and the fake the same.

**Warnings.** None in this slice's files. The build still prints the three it printed before
(`PayloadVersionAdversarialTests.swift:29` and a `@Test` expansion in `SettingsDecodingAdversarialTests.swift`, "will
never be executed"; `LedgerDesignTests/PreviewTests.swift:90`), with xcbeautify's "exit code 0 but produced no
further output" lines beside them (F05 notes, line 1125).

**Release build.** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
**exit 0** (59 s after an earlier Release build; 115 s the first time). No Release object names
`FakeWorkoutSessionClient` (0 symbols; the Debug objects: 825), and the Release `FakeWorkoutSessionClient.o` is an
empty file's (6 symbols against 358). The stub is in both.

**Host.** Step 1 of "How to verify by hand" passes: 33 tests in `LedgerSyncTests`, 11 in the three Domain suites, 54
in `LedgerDependenciesTests`. `scripts/check.sh --lint-only` exits 0 (71 s; the full gate runs it too).

**Tree.** `git status --short` shows the files listed under "What landed" and nothing else:
`M` `docs/architecture.md`, the three `LedgerDependenciesTests` files and this file; `??` the four product files, the
fake, the five contract files, `Tests/LedgerDomainTests/Protocols/`, `Tests/LedgerDomainTests/Units/ClockTextTests.swift`,
`Tests/LedgerSyncTests/Support/` and the three new `LedgerSyncTests` suites. `Package.swift` and
`package-graph.expected.txt` are unchanged.

**Not verified.**
- Criterion 5's second half (every method waits for recovery): there is no recovery before S2.
- The scripts against a real `WorkoutRepository`: whether `materialize` accepts every workout they finish is argued
  under "Inputs for S2", not run.
- The apps were not launched by hand. Nothing reads the new key yet, and the gate's UI smoke tests passed.
- The size of a held continuation (open question 1, option B) was not measured.
- `AsyncStream` calling `onTermination` when a stream is dropped unread is what decision 6 relies on. Apple documents
  the cancellation case; the dropped case is shown by `droppedStreams_areForgottenAtTheNextSubscription` on the host
  and on both simulators, not by documentation.

### How to verify by hand

From the worktree root:

1. The seam on the host (no simulator, about 20 s after a build):
   `env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'LedgerSyncTests|LedgerDependenciesTests|ClockTextTests|WorkoutSessionUpdateTests|WorkoutSessionClientTests'`
   Expect 33 + 11 + 54 tests, one known issue in the first run (the unstartable seed) and sixteen in the last.
2. The contract biting: in `Sources/LedgerFakes/FakeWorkoutSessionClient.swift` change `.unbounded` to
   `.bufferingNewest(1)` and run step 1. `fake_keepsTheClause` fails, among others, with "updates under rapid apply
   calls arrive in order, none dropped or merged: updates: got 0, expected 61; at 0 got no update, expected live
   workout F100, 0 of 18 sets done, effects []". Undo it.
3. Release: `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`, then, in
   `.build/out`,
   `find Intermediates.noindex/LedgerKit.build/Release Products/Release -name '*.o' -print0 | xargs -0 nm 2>/dev/null | grep -v ':$' | grep -c FakeWorkoutSessionClient`
   prints 0 (with `Debug` in both paths: 825).
4. The gate: `/usr/bin/python3 <sim-lock> scripts/check.sh`.

### Open questions

1. **How does S2's host forget a terminated subscriber?** The host is a product actor, where standards §4 allow a
   `Mutex` only for "state that a system framework callback writes synchronously … where an actor could be reached
   only after the callback returned". `AsyncStream`'s `onTermination` is such a callback (the concurrency runtime
   calls it on the cancelling thread), but it is not the case Pete ruled on (`MirroringStartRegistrar`).
   - *A:* the fake's way, a `Mutex` of ended ids. Bounded however the screens come and go.
   - *B:* prune only when `yield` reports `.terminated`. No lock; a continuation per subscription is kept until the
     next publication, so they pile up while no workout is live (one small allocation each, not measured, freed
     at the next start).
   - Recommendation: **A**, with one line in standards §4 naming `onTermination`. It needs the orchestrator's ruling
     before S2 starts. The contract accepts either (it cannot see the difference).
2. **`finish(endedAt:)` at a date that is not finite returns a state that is still live.** It cannot happen with
   `@Dependency(\.date)`. Recommendation: leave the error enum as it is; S7's store shows the receipt only when the
   returned state's phase is `.finished`, and treats anything else as "not saved".
3. **Does the fake need scriptable failures** (a store that refuses an `apply` or a `finish`) for S5's and S7's
   "couldn't save" states? Recommendation: add them in the slice that first needs one, as a fake-only switch; the
   contract stays about a healthy client.
4. **A start with the id of a workout that already ended.** The fake accepts it (the fake's own test does it); a
   host may meet a stored workout or an uncompacted log under that id. No clause does it, so S2 is free.
   Recommendation: S2 decides and, if it refuses, the fake follows and a clause is added; `StartWorkoutUseCase`
   always makes a fresh id, so no screen depends on the answer.
5. **Updates for a peer's envelopes (F17).** The contract covers a device's own calls. A rebuild that changes
   nothing has no effects (`WorkoutEngine.effects(from:to:)` returns none), so the natural rule there is "publish
   when the rebuild changed the state". Recommendation: F17 adds that as a clause of its own.
6. **Elapsed time past an hour** is already with Pete ("1:01:05" against the prototype's "61:05"); a change is the
   one `guard` in `ClockText` and two rows of its table.

### Inputs for S2: what the host must do to pass the contract

(Corrected in fix round 1, as the orchestrator asked: the clause numbers, `haptics`, an end at a date that is not
finite, the clauses whose calls overlap, the save before the ending update, pruning, and the host's own stamp. This
list is current; "S1 fix round 1" below says what changed. Brought up to date again in the touch-up of 2026-10-05:
clauses 23 and 24, the second half of clause 8, logged sets in clause 18, what S2 adds to the contract, the stores
that suspend, and the counts of faults.)

Run it as the fake does: `@Test(arguments: WorkoutSessionClientContract.clauses)` with `clause.check(host)` on a
fresh actor over empty in-memory stores, and `scriptViolation(seed:on:)` over the same seeds. Run the clauses on an
actor whose recovery has not been started, too: the first protocol call must start it (the ruling on O3). When a
run of the clauses times out, run one script first: it names a missing first element at once.

- **`updates()`** registers the continuation and yields the current live workout (or nil) with no haptics, in one
  turn of the actor, with no suspension between reading the state and registering. Streams are `.unbounded`.
  Clause 22 opens eight streams while sixty applies run, and fails a host that suspends in between.
- **One operation at a time, whatever the callers do** (the plan's chain of tasks the actor owns). Clauses 18 to 24
  and the second half of clause 8 send their calls from task groups:
  - 18: eighteen events at once, five of them logged sets. Each update follows from the one before by one event not
    yet seen and carries the engine's haptics for it; `current()` is the last update's state.
  - 19: twelve starts at once. One wins, eleven throw `workoutInProgress` naming it.
  - 20: twelve ends at once. One ends the workout, eleven throw `noLiveWorkout`.
  - 21: a finish against seventy-two adds. Each add lands before the end or throws `noLiveWorkout`, and the end is
    the last update.
  - 22: eight streams opened beside sixty adds (see `updates()` above).
  - 23: a start against forty-eight adds, on a client with no workout. An add made before the start throws
    `noLiveWorkout`; from the start on they land. The stream reads: no workout, the start, then the adds that
    landed, as one history. So the start is published before anything that follows it: do not suspend between
    committing a start and publishing it.
  - 24: a subscriber that, on the update telling it of the start, reads `current()` and applies an edit, as a
    screen does. The workout must be current and the edit accepted, although `start` may not have returned yet. So
    commit before you publish. With 23: commit and publish in one turn of the actor.
  - 8, second half: eight ends at a date that is not finite beside one finish the engine takes. Each of the eight
    throws `invalidEndDate` (it came first) or `noLiveWorkout` (it came after), and never returns. So decide the
    refusal from the `reduce` of that call, in the same turn, not by looking at what is live after a suspension.
    The finish must end the workout: a refused end leaves nothing behind that refuses the next one.

  A host with an `await` between a check and its commit fails these only in a run where two calls did overlap, so
  one green run is weak evidence. Two things follow, both S2's:
  - **Run the contract several times over** on the host before calling it sound (orchestrator's ruling after fix
    round 1), and again whenever the actor's serialisation changes.
  - **Run it over stores that suspend** (re-review, R1): a wrapper in test support around the in-memory stores whose
    every method starts with `await Task.yield()`. The host's own suspension is an `await` on a store, and a hop to
    an idle store actor lets nobody in, so over plain in-memory stores a host with an `await` between a check and
    its commit can still pass. The wrapper makes each of those a point where another call does get in. The clauses
    themselves no longer need a second thread for the overlap: every call is a task of its own, or the task gives
    way after each call (see "S1 touch-up").
- **S2 adds the general form of the overlap clauses to the contract** (orchestrator's ruling after the close-out,
  second part). Clauses 18 to 24 are pairs of call kinds chosen by hand, and twice a tester found one more pair. S2
  replaces the hunt for pairs with one check:
  - **What it runs:** a seeded script of calls made at once, not one after another. The calls are starts, applies,
    ends (`finish` and `discard`) and subscriptions (`updates()` opened while the others are in flight), and at least
    one subscriber that acts on what it is told (it calls the client from inside its loop over the stream, as the
    one in clause 24 does). The seed fixes the calls; the scheduler fixes their order.
  - **How it is judged:** as one history, whatever order the scheduler chose. All five must hold:
    1. every update follows from the one before it by exactly one call that succeeded (the engine's result for
       that call on that state);
    2. every call that succeeded is published once, and nothing else is published;
    3. every call that was refused threw an error the protocol allows for that call (`start`: `notStartable`,
       `workoutInProgress`; `apply`: `noLiveWorkout`; `finish` and `discard`: `noLiveWorkout`, `invalidEndDate`;
       `finish` on a host also `incompleteLog`, which no script provokes), and no call returned that should have
       thrown;
    4. a stream opened late is a suffix of the history: its first element is a state that was published (without
       haptics), and after it every later update, none missing and none twice;
    5. the haptics of every update are the engine's for the call that made it.
  - **Where it runs:** on the host over the stores that suspend (above), and on the fake.
  - What S1 leaves for it: `historyIssue` (`…Contract+Overlap.swift:54`) is rule 1 and 5 for applies on one workout;
    `Model` and `Outcome` (`…Contract+Model.swift`) say what each call may answer; `outcomesAtOnce` and
    `outcomes(ofApplying:…)` are the two ways of sending calls at once. The scripts of `…Contract+Scripts.swift`
    are sequential and stay. A new seeded generator is not needed: `SplitMix64` is in
    `LedgerFakes/Support/SplitMix64.swift` now.
  - Further exploration of overlap shapes is S2's tester's work, against the host.
- **An own action:** stamp, `reduce`. No effects: return the workout as it stands, store nothing, take no `seq`,
  publish nothing. Otherwise store, commit, and publish `(state, haptics(from: effects))` exactly once, also when
  the state did not change. Updates leave in the order the events were applied.
- **`start`:** `reduce(nil, started)` first. No state: `notStartable(snapshot.id)`, before anything is stored and
  whether or not a workout is live. Then `workoutInProgress(live.id)`. A refused start changes and publishes nothing.
- **Nothing live:** `apply` (any event, `.started` included), `finish` and `discard` throw `noLiveWorkout`, at a
  date that is not finite too.
- **The end:** one update carrying the finished or discarded state; then `current()` is nil and a new stream starts
  with nil. No nil update goes to the streams already open. `apply(.finished)` and `apply(.discarded)` end the
  workout through the same path as `finish` and `discard`.
- **An end the engine ignores** (a date that is not finite). Through `apply` it is an ignored event: the workout is
  returned as it stands. `finish` and `discard` throw `invalidEndDate`, and nothing is stored, ended or published
  (clause 8). Test the outcome, not the date: `finish` is `apply`, then "still live? throw", so the engine's rule is
  not written a second time.
- **The ending update follows the save.** The protocol now promises that the finished update is published once the
  workout is stored, and the discarded one once its log is dropped (review SF3), because Today re-reads history when
  it arrives. The contract cannot see a store, so this needs the host's own test: subscribe; `finish`; at the moment
  the finished update is read, `WorkoutRepository.workout(id:)` already returns the workout; for a discard,
  `uncompactedWorkoutIDs()` no longer lists the log. With a save that fails, no ending update is published and
  `finish` throws; write onto the protocol what the open streams see then (review, "The host").
- **A cancelled subscriber** must not disturb the others or the next subscription (clause 17). Forget an ended stream
  when `yield` reports `.terminated` at a publication, as the fake does
  (`Sources/LedgerFakes/FakeWorkoutSessionClient.swift:111-121`): no lock, no task, no `onTermination`. The cost the
  reviewer measured is 234 bytes per subscription that ended with nothing published since, freed at the next
  publication.
- **The host's own stamp is never the caller's fault** (orchestrator, after G2). If the host cannot stamp a finite
  time, it reports an issue and throws an error of its own. It must not answer `notStartable` for a startable
  snapshot, nor return from `apply` as if the engine had ignored the event: check the stamp before `reduce`.
- What the scripts send: ad-hoc workouts (no source) of `EventBuilders`' exercises, ids `0xF200 + n`, never the same
  id twice; weights in whole 5 lb steps and finite dates, chosen so that `materialize` should accept every finished
  one (**not run against a repository in S1**; the reviewer read the schema and agrees); swaps with "Also update
  program" on slots no program holds; and `finish` and `discard` at a date that is not finite.
- Not in the contract, so the host's own tests must cover them: the stamp (HLC, `seq` from `highestSeq`), what is
  stored and in what order, the notification effects, recovery, a failing store, `incompleteLog`, a second `finish`
  retrying a save. When a save can be retried, add the plan's sentence to `finish`'s doc.
- `FaultyWorkoutSession` (`Tests/LedgerSyncTests/Support`) lists thirty-one ways to fail the contract, at least one
  for every clause; a new clause should come with a fault that breaks it. Nine of them show only when two calls
  are inside the client at once: an `await` between a check and its commit, or between a commit and its
  publication.

### Inputs for F09 S6: Today on the session

(Corrected in fix round 1: `haptics` for `effects`, `ClockText.elapsed`, the fake's initialiser, and what Today does
when a workout ends. Corrected in the touch-up of 2026-10-05: Today does not play haptics.)

- Read the key in the store: `@ObservationIgnored @Dependency(\.workoutSession) var session`. Subscribe from
  `TodayRoot`'s `.task`, never from a stored task:

  ```swift
  func watchWorkout() async {
      for await update in await session.updates() {
          liveWorkout = update.live          // nil hides Resume: no workout, or the update that ended it
          if let ended = update.state, ended.phase != .live {
              await reloadHistory()          // the workout is stored by now (or its log dropped)
          }
      }
  }
  ```

  The first element arrives at once with the workout as it stands, so there is no separate "load" call and no
  `current()`. Today never calls `apply`.
- **When an update's state is not live, re-read history.** Today's Logged card, week strip and tiles come from
  queries that are not live streams, so `liveWorkout = update.live` alone hides Resume and shows "Start workout" for
  a day that was just finished. The protocol promises that the ending update is published once the workout is stored
  (or its log dropped), so the reload may run when it arrives.
- **Tell a finish from a discard with `update.state?.phase`:** `.finished` (the day is logged) or `.discarded`
  (nothing was stored; the reload changes nothing).
- **Today reads `state` only and never plays `update.haptics`** (ruling after fix round 1). Every subscriber
  receives every update with its haptics, and Today stays subscribed under the workout cover, so a second player
  would make one set buzz twice. Exactly one subscriber in the app plays them, and it is on the workout side; which
  F10 object that is (the workout screen's store, or the launcher that outlives the cover) is decided when F10 S6
  adds `HapticsClient.play`. The `haptics` doc comment says the same (`Protocols/WorkoutSessionClient.swift:72-73`).
- The button's text is `ClockText.elapsed(live.elapsed(at: now))`, with `now` from the view's timeline or
  `@Dependency(\.date)`. It needs no catalog entry (a Domain-formatted line).
- Until S2 binds the host, the app's `workoutSession` is the stub: `updates()` logs one fault and ends at once, the
  loop falls through, and Resume never shows. Write the loop so that falling through is harmless.
- In a test: `let fake = FakeWorkoutSessionClient(live: try Fixtures.seedSession())` (the initialiser takes nothing
  else), then `withTestDependencies { $0.workoutSession = fake } operation: { … }`
  (`DependencyKeysTests.workoutSession_boundToAFake_isTheOneRead` is the pattern). Run `watchWorkout()` as a child
  of a task group, await the store's change with `Observations`, call `fake.finish(endedAt:)` or
  `fake.discard(endedAt:)` to see Resume go, `fake.start(_:)` to see it come back, then cancel the group. No sleep
  is needed: every call has published its update by the time it returns.
- In a preview the key is a fake with no workout. A preview of the Resume state binds
  `FakeWorkoutSessionClient(live:)` with `withDependencies`, or better draws `TodayScreen(model:)` from a model.
- `StartWorkoutUseCase` is S2's. Today only emits its routes.

### S1 — orchestrator rulings after G3 (2026-10-04)

G3 asked for changes: 1 Blocking, 4 Should fix, 7 nits (`review.md`). Rulings for fix round 1:

- **B1 accepted.** `finish(endedAt:)` and `discard(endedAt:)` throw the new `WorkoutSessionError.invalidEndDate` (no
  payload) when the workout is still live after the call, end nothing and publish nothing. The guard tests the
  outcome, not the date. `apply(.finished(…))` and `apply(.discarded(…))` at such a date stay ignored events: `apply`
  returns the workout unchanged. Clause 16 is split as the review says.
- **SF1 accepted, in this slice:** the two clauses (a stream opened while calls are in flight; starts at once).
- **SF2 accepted:** a fault for clauses 3, 8, 14 (`await Task.yield()` between reading and committing) and 17, and for
  each new clause; the "written from the documentation" sentence is softened.
- **SF3 accepted:** the protocol promises that the ending update is published once the workout is stored (or its log
  dropped); S2 gets the host test; F09 S6's input says to re-read history when an update's state is not live.
- **SF4 accepted:** `FakeWorkoutSessionClient.init(live:)` only; it stamps with `Fixtures.deviceID` and `Fixtures.now`.
- **N5 accepted as a type:** `WorkoutSessionUpdate.haptics: [Haptic]` replaces `effects: [Effect]`, and
  `WorkoutSessionUpdate.haptics(from: [Effect]) -> [Haptic]` replaces `feedback(from:)`. A host cannot forward
  another kind of effect, and a screen plays `update.haptics` without filtering. This supersedes the signature in
  the brief's amendments (updated there).
- **N4 accepted:** `ClockText.elapsed(_:)` replaces `minutesSeconds(_:)`; the format past an hour is still with Pete.
- **N1, N2, N3, N6 accepted** as the review writes them (N6: one shared seeded generator, the existing one).
- **Open question 1 / review answer (e): prune when `yield` reports `.terminated`,** in the fake now and in S2's host.
  No lock, no task, no change to standards §4. Measured cost: 234 bytes per subscription that ended with nothing
  published since, freed at the next publication. The fake's `Mutex`, `dropEnded`, `subscriberCount` and their three
  tests go (N7), and with them the repo's only `@testable import LedgerFakes`.
- Open questions 2 (closed by B1), 3, 4 and 5 as the implementer recommends.

**G2 round 1 (strike 1)** found the fake sound and the contract thin where calls overlap (`test-findings.md`).
Rulings, for the same fix round:

- **F10-S1-1** is review B1: both calls throw `invalidEndDate`. The brief's criterion 4 now says so.
- **F10-S1-2** goes away with SF4: the fake has no injected clock.
- **F10-S1-3 accepted:** the concurrent clause walks the first subscriber's stream; each update must follow from the
  one before it by exactly one of the edits not yet seen.
- **F10-S1-4 accepted, and it replaces SF1's two clauses with four:** starts at once, ends at once, an `apply`
  against an end, and a stream opened during applies. The tester's checks in
  `LedgerSyncTests/Adversarial/SessionSeam*AdversarialSupport.swift` show what each must catch; the clauses are
  written in the contract, not imported from the tester's files.
- **F10-S1-5 accepted:** the unstartable snapshots gain a rest that is too long and one inner date that is not finite.
- **F10-S1-6 accepted:** the two self-comparing clauses take their expected ended state from the engine; every
  clause has a fault that breaks it (review SF2). A client with no first element still waits for the time limit;
  the contract's documentation says to run a script first.
- For S2, from the tester's note: the host's own stamp is never the caller's fault. If the host cannot stamp a
  finite time it reports an issue and throws; it must not answer `notStartable` for a startable snapshot.

### S1 fix round 1 (G1 implementer, 2026-10-04)

On `0950170` plus the orchestrator's two uncommitted files (the brief's amendments and the rulings above), which are
left as they were. Nothing is committed. Paths are under `LedgerKit/` unless they start with `docs/` or `tasks/`. The
round was interrupted once by a usage limit; on resuming, the state was read back from disk (`git status`, file
times against the gate's log, the host suites, the Release build) before this section was written.

#### What changed, per item

**1. API**

| Item | Change | Where |
|---|---|---|
| B1, F10-S1-1 | `WorkoutSessionError.invalidEndDate`, no payload. `finish` and `discard` throw it when the workout is still live after the call; the guard tests the outcome (`finished.phase != .live`), not the date. `apply(.finished(…))` and `apply(.discarded(…))` at such a date stay ignored events | `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift:110-112` (case), `:46-63` (docs); `Sources/LedgerFakes/FakeWorkoutSessionClient.swift:82-95`; the model, `…Contract+Model.swift:103-113` |
| N5 | `WorkoutSessionUpdate.haptics: [Haptic]` and `haptics(from: [Effect]) -> [Haptic]` replace `effects` and `feedback(from:)` | `WorkoutSessionClient.swift:72-96` |
| N4 | `ClockText.elapsed(_:)` replaces `minutesSeconds(_:)`; the body is unchanged | `Sources/LedgerDomain/Units/ClockText.swift:9` |
| SF4, F10-S1-2 | `FakeWorkoutSessionClient.init(live:)` only. It stamps with `Fixtures.deviceID` and `Fixtures.now`, in one static function the initialiser uses too | `FakeWorkoutSessionClient.swift:27`, `:97-105` |
| N1 | `updates()`: "one update for each call whose event the engine accepts … A host may publish further updates for changes that do not come from this client's calls" | `WorkoutSessionClient.swift:13-15` |
| SF3 | `finish`: the ending update "is published once the workout is stored, so a consumer may read history when it arrives"; `discard`: "once the workout's log is dropped" | `WorkoutSessionClient.swift:47-48`, `:57-58` |
| Criteria 1, 2, 4 as revised | The protocol's docs now say what holds when calls overlap: a stream opened in flight, starts at once, ends at once, an `apply` that loses to an end | `WorkoutSessionClient.swift:9-11`, `:17-19`, `:29-31`, `:43`, `:49-50` |

**2. Subscribers** (review answer (e), N7). The fake forgets a stream when `yield` reports `.terminated` at a
publication: `FakeWorkoutSessionClient.swift:107-121`. The `Mutex`, `dropEnded`, `subscriberCount`, `import
Synchronization`, `onTermination` and my three tests of the count are gone, and with them the repo's only
`@testable import LedgerFakes`. One behavioural test stays:
`FakeWorkoutSessionClientTests.endedStreams_disturbNoLaterSubscriberOrPublication` (`:121`): 5,000 streams opened
and dropped with nothing published, then 200 readers cancelled one per edit; the kept subscriber hears every update
in order and a late one starts with the last state.

**3. Contract** (22 clauses, were 17; the list is below)

| Item | Change | Where |
|---|---|---|
| B1 | Clause 16 split: it keeps `.finished(never)` and `.discarded(never)` through `apply` as ignored events; new clause 8, "finish and discard at a date the engine ignores throw invalidEndDate, end nothing and publish nothing". Clause 5 also calls both with nothing live at such a date (`noLiveWorkout`) | `…Contract+Updates.swift:130-162`; `+Lifecycle.swift:176-195`, `:106-129` |
| F10-S1-3 | The concurrent clause walks the first subscriber's stream: each update must be the engine's for the state before it and one edit not yet seen (`historyIssue`) | `+Overlap.swift:42-63`, `:68-96` |
| F10-S1-4, SF1 | Four clauses, written here: starts at once (12 starts); ends at once (6 finishes, 6 discards; the winner's return and update are the model's); an apply against an end (6 tasks × 12 adds against one finish); a stream opened while calls are in flight (8 streams during 60 adds) | `+Overlap.swift:100-256` |
| F10-S1-5 | `unstartable` gains a live snapshot with a rest an hour and a second long, and one with a set done at a date that is not finite. The scripts' refused snapshot is now one of three kinds | `+Lifecycle.swift:67-81`; `+Scripts.swift:132-145` |
| F10-S1-6 | "A terminal event through apply…" and "after a workout ends…" take the ended states, their haptics and the edit's update from `engineUpdate`, not from what the client returned | `+Lifecycle.swift:198-254` |
| N3 | `defer { signal.finish() }` in the cancelled subscriber's task | `+Updates.swift:173` |
| SF2 | `FaultyWorkoutSession`: 26 faults, at least one for every clause, checked by `everyClause_hasAFault`. Five need two calls inside the client at once: an `await` (a hundred `Task.yield()`) between a check and its commit. The "written from the documentation" sentence now says it is a stand-in built like the fake, and that the host is the real second implementation | `Tests/LedgerSyncTests/Support/FaultyWorkoutSession.swift:5-9`, `:181-185`; `…+Fault.swift`; `WorkoutSessionClientContractFaultTests.swift:21-45` |
| N2 | `fixedSeeds`: twenty seeds whatever `LEDGER_PROPERTY_SEED_COUNT` says, for the three tests. With the variable at 1 the suites pass | `Tests/LedgerSyncTests/WorkoutSessionClientContractTests.swift:20-26` |
| N6 | The scripts draw from `LedgerFakes`' `SplitMix64`, now public; `ScriptGenerator` is gone | `Sources/LedgerFakes/FakeLinkBus.swift:186-203`; `+Scripts.swift:22` |
| Ruling on F10-S1-6 | The contract's documentation says to run a script first when the clauses time out | `…Contract.swift:17-22` |

Moved: `Step` from `+Scripts.swift` to `+Model.swift`, unchanged; `callersAtOnce` from `+Updates.swift` to the new
`+Overlap.swift`, with the other clauses whose calls overlap (its only change is the walk of F10-S1-3).

**4. Notes for other slices.** "Inputs for S2" and "Inputs for F09 S6" above (this file, lines 1082-1185) are
corrected in place and say so in their first line: the end at a date that is not finite, the host test for "the
ending update follows the save", pruning on `.terminated`, the host's own stamp, the clause numbers; re-reading
history when an update's state is not live, `update.state?.phase`, `update.haptics`, `ClockText.elapsed`. The rest
of the G1 section above is the record of round 0 and is not rewritten, so it still names `feedback(from:)`,
`minutesSeconds` and seventeen clauses. `docs/architecture.md` §13 is unchanged: no name in it changed.

**5. The tester's files:** "Sanctioned test edits" below.

#### The contract's clauses as they now stand, with the fault for each

Faults marked * show only when two calls are inside the client at once. No test can force that, so
`fault_breaksItsClause` gives such a fault ten runs and needs one report; every other fault must be reported by the
first run.

| # | Was | Clause | Faults that break it |
|---|---|---|---|
| 1 | 1 | a new client has no workout: `current()` is nil and a stream starts with a nil state | `duplicatesTheFirstElement` |
| 2 | 2 | `start` makes a live snapshot current and publishes it, with no haptics | `startBuzzes` |
| 3 | 3 | a second `start` throws `workoutInProgress`, changes nothing and publishes nothing | `secondStartReplaces` |
| 4 | 4 | a snapshot the engine would not start throws `notStartable`, live workout or not (five snapshots) | `judgesTheSessionFirst`, `judgesSnapshotsByPhaseAlone` |
| 5 | 5 | `apply`, `finish` and `discard` with nothing live throw `noLiveWorkout` and publish nothing | `startsThroughApply` |
| 6 | 6 | `finish` returns the finished state, publishes it once, then there is no workout | `keepsTheEndedWorkoutCurrent`, `publishesNilAfterTheEnd` |
| 7 | 7 | `discard` publishes the discarded state once, then there is no workout | `discardsSilently` |
| 8 | new | `finish` and `discard` at a date the engine ignores throw `invalidEndDate`, end nothing and publish nothing | `returnsFromAnIgnoredEnd` |
| 9 | 8 | a terminal event through `apply` ends the workout as `finish` and `discard` do | `terminalThroughApplyStaysLive`, `movesTheEndThroughApply` |
| 10 | 9 | after a workout ends another can start, and earlier subscribers see it | `refusesAStartAfterAnEnd` |
| 11 | 10 | `apply` returns the state after the event; the next update carries it and the engine's haptics | `returnsTheStateBefore`, `dropsTheHaptics` |
| 12 | 11 | a stream opened on a live workout starts with it, without the last event's haptics | `firstElementCarriesHaptics` |
| 13 | 12 | two subscribers, one from before the start, each get every update in order | `servesOneSubscriber` |
| 14 | 13 | updates under rapid `apply` calls arrive in order, none dropped or merged | `keepsOnlyTheNewestUpdate` |
| 15 | 15 | an event the engine accepts is published once even when it changes nothing here | `skipsUnchangedStates` |
| 16 | 16 | an event the engine ignores returns the workout unchanged and publishes nothing (through `apply`) | `publishesIgnoredEvents` |
| 17 | 17 | a subscriber whose task is cancelled stops; the others keep getting every update | `cancellationEndsEveryStream` |
| 18 | 14 | callers at once: every event is applied once, and each update follows from the one before | `losesAnEditBetweenCallers` * |
| 19 | new | starts at once: one succeeds, the others throw `workoutInProgress` naming it | `startsTwiceAtOnce` * |
| 20 | new | ends at once: exactly one ends the workout, in one update; the others throw `noLiveWorkout` | `endsTwiceAtOnce` * |
| 21 | new | an `apply` against an end lands before it or throws `noLiveWorkout`; the end is the last update | `appliesAfterTheEnd` * |
| 22 | new | a stream opened while calls are in flight starts with a published state and misses no later update | `registersAfterASuspension` * |

`forwardsEveryEffect`, a fault of round 0, cannot be written any more: an update holds `[Haptic]`.

How often an overlap fault shows: with the tests changed to allow one run instead of ten (and changed back), each
of the fifteen overlap cases (these five and the tester's ten `racy…` clients) was reported in every one of 80 runs
of the two suites on this host, under a load average near 6. Both simulators reported all of them in the gate. It
stays a statement about the scheduler, not a proof.

#### Sanctioned test edits (for the tester's audit)

Line numbers are the file's at `0950170`. "Mechanical" means the API rename with the matching value and nothing
else. All 61 remaining test functions of the tester pass; none is disabled or wrapped in `withKnownIssue`.

| File (`Tests/…/Adversarial/`) | Lines | Edit |
|---|---|---|
| `LedgerDependenciesTests/…/WorkoutSessionKeyAdversarialTests.swift` | 87 | mechanical: `effects: [.haptic(.workoutFinished)]` → `haptics: [.workoutFinished]` |
| `LedgerDomainTests/…/ClockTextAdversarialTests.swift` | 5, 97, 102, 107, 112, 122, 138 | mechanical: `ClockText.minutesSeconds(` → `ClockText.elapsed(` (six calls and the doc comment). The test functions keep their `minutesSeconds_…` names |
| `LedgerDomainTests/…/WorkoutSessionUpdateAdversarialTests.swift` | 6-7, 29-34, 38, 41-42, 45, 47-48, 50, 55, 64, 67, 76-78, 90, 96, 104, 112-114, 120, 123, 127 | mechanical: `feedback(from:)` → `haptics(from:)` in calls, the doc comment and five display names; `onlyHaptics` returns `[Haptic]` (a `compactMap` in place of the `filter`); expected values `[.haptic(x)]` → `[x]`, and `Self.haptics` (the effects) is compared with `Haptic.allCases`; `effects:` → `haptics:`. The test functions keep their `feedback_…` names |
| `LedgerSyncTests/…/SessionSeamAdversarialSupport.swift` | 58-63, 86, 147, 152 | mechanical: `Seam.haptics` returns `[Haptic]`; `effects:` → `haptics:`; `update.effects` → `update.haptics` in `brief` |
| `…/SessionSeamOracleAdversarialSupport.swift` | 83, 85, after 92, 105, 120 | **expectation, non-finite end:** `finish` and `discard` go through a new private `end(_:)` that answers `.refused(.invalidEndDate)` when the engine ignored the end on a live workout (10 lines). Lines 105 and 120 mechanical |
| `…/SeamFaultAdversarialSupport.swift` | 29 | **deleted case `forwardsEveryEffect`** (see below) |
| | 43-45, 76 | **expectation, non-finite end:** `nonFiniteEndThrows` ("throws for a finish or discard whose date the engine ignores") became `nonFiniteEndReturns` ("returns from …"): the documented behaviour and the fault changed places. It stays outside `sequential`, as before |
| `…/WrongSessionClientAdversarialSupport.swift` | 18, 38, 81, 117, 194, 203 | mechanical: `[Effect]` → `[Haptic]`, `effects:` → `haptics:` |
| | 156, 164-165 | **expectation, non-finite end:** `ignored(_:_:)` throws `WorkoutSessionError.invalidEndDate` for `finish` and `discard` unless the fault is `nonFiniteEndReturns` (it used to return unless the fault was `nonFiniteEndThrows`) |
| | 196 | the `forwardsEveryEffect` arm of `forwarded(_:)`, deleted with its case |
| | 236-238 | `SeamRefusal` deleted: nothing throws it now |
| `…/SessionSeamRacesAdversarialSupport.swift` | 133 | mechanical |
| `…/SessionSeamHistoryAdversarialSupport.swift` | 18 | mechanical |
| `…/SessionSeamEventsAdversarialSupport.swift` | 10, 12, 28-29 | mechanical: `haptics: [Haptic]`, `[.setLogged]` |
| `…/FakeSessionUpdatesAdversarialTests.swift` | 46, 83, 99-100 | mechanical |
| `…/FakeSessionStreamsAdversarialTests.swift` | 28-31, 65 | mechanical |
| `…/FakeSessionLifecycleAdversarialTests.swift` | 101 | mechanical |
| `…/FakeSessionDifferentialAdversarialTests.swift` | 126 | mechanical |
| | 93 | **expectation, non-finite end:** the kinds `"finish ignored"`, `"discard ignored"` → `"finish invalidEndDate"`, `"discard invalidEndDate"` |
| `…/FakeSessionEndingAdversarialTests.swift` | 55-56, 78 | mechanical |
| | 90-109 | **expectation, non-finite end:** `finish_nonFiniteDate_returnsTheWorkoutStillLive_contraryToCriterion4` → `finish_nonFiniteDate_throwsInvalidEndDate_leavingTheWorkoutLive`: the two lines that read the returned state are one line expecting `.refused(.invalidEndDate)`; the display name, the comment above and the failure message follow. The rest of the test (still live, nothing published, a later finish works) is as it was |
| | 111-125 | **expectation, non-finite end:** `discard_nonFiniteDate_returnsNormally_leavingTheWorkoutLive` → `discard_nonFiniteDate_throwsInvalidEndDate_leavingTheWorkoutLive`: `== .returned` → `== .refused(.invalidEndDate)`; display name and message follow |
| | 7-9 | the suite's doc comment no longer mentions the stamp |
| | 126-151 | **deleted:** two tests (below) |
| `…/SessionContractBiteAdversarialTests.swift` | 85-93 | **expectation, non-finite end:** `clientThatThrowsForANonFiniteEnd_isRejectedByTheContract` → `clientThatReturnsForANonFiniteEnd_isRejectedByTheContract`: it runs `WrongSessionClient(.nonFiniteEndReturns)` and expects exactly one complaint, from the clause "finish and discard at a date the engine ignores throw…" |
| `…/FakeSessionForgettingAdversarialTests.swift` | whole file | **deleted** (below) |

Deleted tests of the tester, with the reason:

| Test | Cases | Reason |
|---|---|---|
| `FakeSessionForgettingAdversarialTests.thousandsOfDroppedStreams_areForgotten` | 1 | its subject is `subscriberCount`, which is removed. What a caller can see of it is in `endedStreams_disturbNoLaterSubscriberOrPublication` |
| `FakeSessionForgettingAdversarialTests.streamsEndedMidWorkout_areForgottenAtTheNextPublication` | 1 | the same |
| `FakeSessionEndingAdversarialTests.stamp_deviceAndABackwardsClock_changeNothing` | 20 | its subject is the removed `device:` and `now:` parameters |
| `FakeSessionEndingAdversarialTests.stamp_nonFiniteClock_changesNothing` | 3 | the same; it was F10-S1-2's failing test, and the finding goes with the parameter |
| the case `SeamFault.forwardsEveryEffect` | 3 (one each in `faultyClient_isRejectedByAClauseOrAScript`, `…ByAClause`, `…ByTheOracle`) | **not on the sanctioned list.** A client can no longer forward another kind of effect: `WorkoutSessionUpdate.haptics` is `[Haptic]`, so `forwarded(_:)` cannot return the engine's effects. There is no mechanical translation; `dropsHaptics` still covers a client that forwards the wrong haptics |

Left alone though the round made them stale, for the tester to decide: the `minutesSeconds_…` and `feedback_…`
function names; `error_casesAreDistinct`'s "four cases" (it does not list `invalidEndDate`); the comments in
`SessionContractBiteAdversarialTests.swift` at 49-51, 57-60 and 71-76 that describe cases as failing; and
`notForTheClauses`, whose two faults the clauses alone now reject as well.

The tester's wrong clients against the new contract: `faultyClient_isRejectedByAClauseOrAScript` 31 of 31,
`faultyClient_isRejectedByAClause` 29 of 29, `racyClient_isRejectedByAClause` 10 of 10 (it was 5 of 10),
`independentClient_keepsTheContract` passes with the no-fault client now throwing `invalidEndDate`.

#### Mutants of this round's code

`f10s1/fix1/mutants.py`, logs `mutants-a.log` and `mutants-b.log` in the scratch folder. Each run is its own process
group, killed whole on a timeout.

| Mutant | Result |
|---|---|
| F1 `finish` returns from an end the engine ignored; F2 `discard` likewise | fail the contract (clause 8), the scripts, the tester's differential and F10-S1-1 tests, my fake test |
| F3 a publication forgets the streams still open | 25 tests fail; the run reached my 420 s cap, because readers then wait for the suites' time limits |
| F4 a publication never forgets a stream | **survives, as ruled:** nothing a caller can see depends on it |
| F5 `haptics(from:)` reverses the order | two of the tester's tests at first, and none of mine: my order test used a sequence that reads the same backwards. It now uses one that does not, and fails too |
| F6 `haptics(from:)` drops `.restOver` | `haptics_forwardsEachHaptic` and two of the tester's |
| F7 a stream keeps only its newest update | 31 tests |
| F8 the session judged before the snapshot; F10 an ignored event published | the contract, the scripts, the tester's lifecycle and update tests |
| F9 an unstartable seed is silent; F11 a refused `apply` not recorded | the two `init(live:)` tests; `applied_recordsEveryAsk_inCallOrder` and three of the tester's |

#### Code lines

The same count as before (`git diff -U0`, blank and whole-line comment lines excluded).

| | Round 0 | Now | This round |
|---|--:|--:|---|
| Product (four files) | 93 | 93 | +10, −10: the protocol file +9, −9; `ClockText` +1, −1 |
| `LedgerFakes/FakeWorkoutSessionClient.swift` | 111 | 90 | +29, −50 |
| `LedgerFakes/FakeLinkBus.swift` | not touched | +3, −3 | `public` on `SplitMix64`, its initialiser and `next()` (N6) |
| `LedgerTestSupport`, the contract (six files) | 776 | 1,011 | +480, −245; about 160 of each are `+Scripts.swift` moving one indent inside `#if DEBUG` |

#### Gate, Release build, host

- **Full gate:** `/usr/bin/python3 <sim-lock> scripts/check.sh` from the worktree root, in the background, the
  shell appending the status to `f10s1/fix1/gate1.log`. Started 20:41:18, lock acquired at once, **`check.sh OK`,
  `GATE_EXIT=0`, 578 s**: lint 63 s, iOS build 41 s, iOS tests 228 s, watchOS build 34 s, watchOS tests 207 s.
  17 test targets ran and passed (PR), 8 (PR-Watch). iOS: 1,712 tests, 1,691 passed, 0 failed, 12 skipped, 9
  expected failures; watchOS: 1,531, 1,514 passed, 0 failed, 12 skipped, 5 expected failures.
- **It is the final tree.** After the interruption I checked, from disk: no file outside the build folders is newer
  than the gate's start except this notes file; both result bundles hold this round's tests (the 22 clause cases,
  `everyClause_hasAFault`, the tester's racy cases), all passed.
- **Run again after the interruption**, on the same tree (log `f10s1/fix1/gate2.log`): started 23:17:20, lock acquired
  at once, **`check.sh OK`, `GATE_EXIT=0`, 530 s** (lint 62 s, iOS build 13 s, iOS tests 236 s, watchOS build 14 s,
  watchOS tests 203 s); the same 17 and 8 targets, the same test counts and the same coverage. Only this notes file
  changed after it started.
- **Coverage** (the gate's table): LedgerDependencies 96.20 %, LedgerDomain 99.12 % (2043 / 2061), LedgerFakes
  98.95 % (1419 / 1434), LedgerSync 91.17 %, overall 98.51 % (8360 / 8486); every threshold met.
  `WorkoutSessionClient.swift` 21 / 21, `ClockText.swift` 13 / 13, `FakeWorkoutSessionClient.swift` 92 / 92.
- **Release build:** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
  **exit 0** (34 s), run again after the interruption. No Release object names `FakeWorkoutSessionClient`,
  `InMemoryStores`, `SplitMix64`, `FakeLinkBus` or `Fixtures` (0 symbols each; Debug: 723, 451, 105, 1139, 758), and
  `Release/LedgerFakes.o` is 1,176 bytes with one symbol.
- **Host**, after the interruption: `swiftformat --lint` and `swiftlint --strict` exit 0; `LedgerSyncTests` 70 tests
  pass, `LedgerDomainTests` 795, `LedgerDependenciesTests` 63. The known issues in those runs are the tests' own
  subject (a fake built on an unstartable snapshot, an unconfigured key), as before the round.
- **No test helper is left running.** One was: mutant F3's run timed out and its `swiftpm-testing-helper`, which
  sits in a process group of its own, outlived the group kill. I stopped it (pid 86959) and the scratch scripts now
  stop this worktree's helpers on a timeout.

#### Not done as written, and questions

1. **"Play `update.haptics`" in F09's input.** It is there. I added two cautions next to it, because as written it
   would make one set buzz twice: every subscriber gets every update, Today stays subscribed under the workout
   cover, and the workout screen plays haptics from S6 (when `HapticsClient` first has a `play`). Recommendation:
   exactly one subscriber plays them, the workout screen; Today reads `state` only. The orchestrator's to rule.
2. **Two edits to the tester's files go beyond "mechanical"**, both forced by the rulings: the deleted
   `forwardsEveryEffect` fault (the type removed it), and `nonFiniteEndThrows` turned into `nonFiniteEndReturns`
   instead of only changing an expected value (the old documented behaviour is now the fault, so the client's
   default had to change for `independentClient_keepsTheContract`). Both are in the table above.
3. **N6 has a cost.** The existing generator lives in `LedgerFakes`, which is empty in a Release build, so
   `…Contract+Scripts.swift` is now inside `#if DEBUG` (as `WithTestDependencies.swift` is), and `script(seed:)`
   and `scriptViolation(seed:on:)` exist in Debug only. Tests are Debug, and the Release build passes. It also
   touches `FakeLinkBus.swift`, outside the slice's list (three `public`s and a comment).
4. **The overlap clauses cannot be forced to bite**, only given the chance: see the 80 runs above. A host that
   fails them will fail most runs, not necessarily every run.
5. **"Inputs for S2" and "Inputs for F09 S6" are edited in place**, as asked, which departs from "append only" for
   those two sections. Everything else in my earlier section is untouched.
6. **Not changed:** `WorkoutSessionUpdate.state`'s "the one update that ends it", which the review suggests keeping
   open for F17 (a late envelope may change a finished state). The brief's amendment still has those words.

Not verified: anything on a device; the host (S2) against the new clauses, which only its own run can show; the
scripts against a real repository, as before; a non-English locale for `ClockText`.

### S1 — orchestrator rulings after fix round 1 (2026-10-04)

- **Who plays haptics (the implementer's question 1): exactly one subscriber in the app, and it is on the workout
  side.** Today reads `state` only and never plays `update.haptics`. Which F10 object plays them (the workout
  screen's store, or the launcher that outlives the cover) is decided when S6 adds `HapticsClient.play`.
- The two edits to the tester's files that go beyond a rename (the deleted `forwardsEveryEffect` fault, and
  `nonFiniteEndThrows` becoming `nonFiniteEndReturns`) follow from the rulings; the tester audits them.
- N6's cost is accepted: the seeded scripts exist in Debug builds only, like the rest of what leans on `LedgerFakes`.
- The overlap clauses give a racy host the chance to fail rather than force it; S2 runs the contract on its host
  several times over before it calls the host sound.

### S1 — orchestrator rulings after the close-out (2026-10-05)

G3 approved the fix round (0 Blocking; R1, R2, three nits). G2's close-out closed findings 1 to 6, audited the edits
to its files, and found one more contract gap, **F10-S1-7**: four more pairs of overlapping calls that no clause
runs. That is the second time the gap is "one more pair", so the answer is in two parts.

- **Now, in a touch-up of this slice:** the four checks join the contract, written there from the tester's
  (`Seam.startVersusApplyFault`, `Seam.reactionFault`, logs among the concurrent clause's events,
  `Seam.invalidEndRaceFault`), each with a fault that breaks it; R1 (`await Task.yield()` after each call in the two
  loops of clauses 21 and 22, so the overlap does not depend on a second thread); R2 (the haptics ruling written
  into "Inputs for F09 S6" and the `haptics` doc comment); N-a, N-b; the note about an end the engine takes after
  an ignored one becomes part of the ignored-end clause. The tester then verifies that its failing test passes
  unchanged. That is a check, not a third round.
- **In S2, where there is a real second implementation to hold:** the pairs are replaced by the general form. S2 adds
  to the contract a seeded script of calls made at once (starts, applies, ends, subscriptions, and a subscriber that
  acts on what it is told), checked as one history: every update follows from the one before it by exactly one
  call that succeeded, every success is published once, every refusal is one the protocol allows for that call, a
  late stream is a suffix of the history, and haptics are the engine's. It runs on the host over stores that
  suspend, and on the fake. Further exploration of overlap shapes is S2's tester's work, against the host.
- N-c is fixed in the brief ("no haptics").

### S1 touch-up (G1 implementer, 2026-10-05)

On `92eb79c`, uncommitted. The five items of the ruling above and nothing else: no API change, nothing of S2, no
refactor. The tester's files are untouched (`git diff 92eb79c -- 'LedgerKit/Tests/*/Adversarial'` prints nothing),
and its `racyClient_isRejectedByAClause` passes, all eight cases. Paths are under `LedgerKit/`; `…Contract` stands
for `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract`.

#### What changed, per item

1. **F10-S1-7.** The checks are written in the contract from the tester's; nothing is imported from its files.
   - **(a) A start against applies:** new clause 23, `startAgainstApplies` (`…Contract+StartOverlap.swift:10-34`).
     One start, the first task of the group, races four tasks of twelve adds on a client with no workout. The
     stream must read: no workout, the start, then one history of the adds that landed. Every add landed or threw
     `noLiveWorkout`, the landed ones are the published ones, no add of a task is refused after an earlier one
     landed, and `current()` is the last update's state.
   - **(b) A subscriber that acts on what it is told:** new clause 24, `reactsToTheStart` (`:43-71`). A child task
     reads a stream until an update shows a live workout, then calls `current()` and `apply`, while the parent is
     in `start`. `current()` must be the workout and the apply accepted; a second subscriber must read no workout,
     the start, the edit.
   - **(c) Logs among the concurrent events:** clause 18, `callersAtOnce` (`…Contract+Overlap.swift:82-111`). The
     five rows of the first exercise are now logged (`:89-91`); the other thirteen keep their stepper edit. The
     walk (`historyIssue`) compares whole updates, so each must carry the engine's haptics for its event. Logs do
     not commute (the cursor and the rest depend on the order), so "`current()` is the state after the edits in
     list order" became "`current()` is the last update's state" (`:107`); that every event is in the history once
     is still the walk's and the count's.
   - **(d) Ends the engine ignores, beside one it takes:** the second half of clause 8, `invalidEnd`
     (`…Contract+Lifecycle.swift:185-214`, the race at `:197-202`). Eight ends at a date that is not finite, four
     through `finish` and four through `discard`, are sent at once with one finish at 600 s, the ignored ones
     listed first. Each of the eight may only throw `invalidEndDate` or `noLiveWorkout`; one that returns fails the
     clause.
   - **An end the engine takes after an ignored one** (the tester's `.invalidEndSticks` note): the same finish. It
     comes after the two refused ends of the clause's first half, and must return the finished state, publish it
     once and leave no workout (`:210-212`).
   - Each has a fault in `FaultyWorkoutSession` and a line in `brokenClauses`, which is the table
     `everyClause_hasAFault` reads (`Tests/LedgerSyncTests/Support/FaultyWorkoutSession+Fault.swift:60-69`, `:92-96`,
     `:125-129`; the behaviour in `FaultyWorkoutSession.swift:48-65`, `:133-158`). See the table below.
2. **R1.** `await Task.yield()` after each call of a task that makes several in a row: `…Contract+Overlap.swift:192`
   (clause 21's six tasks of twelve adds, and clause 23's four, which share
   `outcomes(ofApplying:inTasksOf:beside:leading:on:)`, `:176-208`) and `:267` (clause 22's sixty adds). The other
   overlap clauses, and clause 8's race, make every call a task of its own; clause 24's two sides are a child task
   and its parent, and the child only acts on an update. The file's header (`:9-11`) states the rule for whoever
   adds a clause. Measurements below.
3. **R2.** `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift:72-73`: "Every subscriber receives them;
   exactly one, on the workout side, plays them. Today reads `state` only." The type's summary (`:66-67`) no longer
   says "what the screen should play". In "Inputs for F09 S6" the bullet that told Today to play them is replaced
   by the ruling.
4. **N-a.** `Sources/LedgerFakes/FakeWorkoutSessionClient.swift:111-121`: `publish` is a loop that yields to each
   stream and keeps those that did not answer `.terminated`. **N-b.** `SplitMix64` is in
   `Sources/LedgerFakes/Support/SplitMix64.swift` (20 lines, inside `#if DEBUG`, the text unchanged);
   `FakeLinkBus.swift` lost those lines (204 → 185).
5. **"Inputs for S2"** now holds the second part of the ruling (what S2 adds to the contract, how it is judged,
   where it runs), "run the contract several times over", the stores that suspend (the re-review's R1, fix 2), the
   seven overlap clauses and clause 8's second half with what each asks of the host, and thirty-one faults.

#### The clause list's additions, with the fault for each

Twenty-four clauses now (`FakeWorkoutSessionClient keeps the contract clause`: 24 cases), thirty-one faults.
Faults marked * show only when two calls are inside the client at once.

| # | Clause | What is new | Fault added | What the fault does |
|---|---|---|---|---|
| 8 | `finish` and `discard` at a date the engine ignores throw `invalidEndDate`, end nothing and publish nothing | a finish the engine takes afterwards | `refusesEveryEndAfterOne` | once an end was refused, every later end is |
| 8 | (the same) | eight ignored ends at once with that finish | `judgesAnIgnoredEndLater` * | decides the refusal after a suspension, by whether a workout is live then |
| 18 | callers at once: every event is applied once, and each update follows from the one before | five of the eighteen events are logged sets | `dropsHapticsUnderOverlap` * | an update loses its haptics when another apply is inside the client |
| 23 | a start against applies: the start is published first, then the applies that landed, as one history | new | `publishesTheStartLate` * | `start` commits, suspends, publishes |
| 24 | a subscriber acting on the start's update finds the workout current and its apply accepted | new | `commitsTheStartLate` * | `start` publishes, suspends, commits |

`refusesEveryEndAfterOne` is also noticed by a seeded script within twenty seeds
(`fault_isNoticedByAScript`, 21 cases now). `fault_breaksItsClause` has 31 cases; nine get ten tries.

The tester's four failing cases, and the clause that now reports each (from `Contract.violations`):
`.startPublishesLate` → 23; `.startCommitsLate` → 24; `.dropsHapticsUnderOverlap` → 18;
`.judgesAnEndByWhatIsLiveLater` → 8. `clientThatReturnsForANonFiniteEnd_isRejectedByTheContract`, which demands
that exactly one clause complains about a client that returns from an ignored end, still passes: that is why (d)
is in clause 8 (see "Not done as written", 1).

#### The one-thread check

How: the reviewer's way. `swift test --skip-build --filter <suites>` run N times from a scratch script
(`f10s1/touchup/stress.py`: each run in a process group of its own, killed with its test helper on a timeout), once
as it is and once with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` in the environment, which narrows Swift's
cooperative pool to one thread. On this Mac under a load average between 5 and 8. For the one-try rows I changed
`fault_breaksItsClause` from ten tries to one, added two throwaway tests giving each of the tester's eighteen racy
clients one `Contract.violations` run, measured, and put the file back (`cmp` against the saved copy: identical).

| What ran | Default pool | One thread |
|---|---|---|
| The five contract suites as written (mine and the tester's two), ten tries per overlap fault | 30 of 30 green | 20 of 20 red, on the tester's own checks only (below); every test that goes through the contract green |
| `fault_breaksItsClause` with **one try**: my nine overlap faults | 40 of 40 green | 40 of 40 green |
| The same plus one try for each of the tester's eighteen racy clients (27 cases) | 30 of 30 green | 30 of 30 green |
| One try, **with the two yields taken out** (then put back, `cmp`) | 1 of 12 red (`registersAfterASuspension`) | 12 of 12 red, each on exactly `appliesAfterTheEnd` and `registersAfterASuspension` |

So the reviewer's result is reproduced without the yields, and with them every overlap fault, mine and the
tester's, was reported by its first try in every run on both pools. It is still a measurement on one host, not a
proof.

**For the tester:** on one thread, two tests in its files fail in every run, both for the client that registers a
stream after a suspension: `racyClient_isRejectedByThisSuitesOverlapChecks` at
`SessionContractBiteAdversarialTests.swift:111` (`.racyLateRegistration`) and at
`SessionContractRoundTwoAdversarialTests.swift:116` (`.registersBeforeItsFirstElement`). They run the suite's own
`Seam` checks, not the contract, so nothing here changes them, and the gate does not run on one thread. The cause
is likely R1's (a task that makes its calls in a row without giving way). I did not touch them.

#### Code lines

The same count as before (`git diff -U0 92eb79c`, blank and whole-line comment lines excluded).

| | Added | Removed | |
|---|--:|--:|---|
| Product (`WorkoutSessionClient.swift`) | 0 | 0 | comments only |
| `LedgerFakes` | 20 | 17 | `SplitMix64` moved (15 of each), `publish` +5, −4 |
| `LedgerTestSupport`, the contract (seven files) | 123 | 27 | `+StartOverlap.swift` 57 (new, 72 lines), `+Overlap.swift` +51, −24 (294 lines), `+Lifecycle.swift` +15, −3 (273 lines) |
| Tests (`FaultyWorkoutSession`, two files) | 54 | 13 | five faults |

No test file of mine changed: the tests are parameterised over `clauses` and `Fault.allCases`.

#### Gate, Release build, host

- **Full gate:** `/usr/bin/python3 <sim-lock> scripts/check.sh` from the worktree root, in the background, the shell
  appending the status to `f10s1/touchup/gate1.log`. Started 00:56:49, lock acquired at once, **`check.sh OK`,
  `GATE_EXIT=0`, 572 s**: lint 61 s, iOS build 43 s, iOS tests 234 s, watchOS build 35 s, watchOS tests 196 s.
  17 test targets ran and passed (PR), 8 (PR-Watch). iOS: 1,729 tests, 1,708 passed, 0 failed, 12 skipped, 9
  expected failures; watchOS: 1,548, 1,531 passed, 0 failed, 12 skipped, 5 expected failures. The skips and the
  expected failures are the same counts as at fix round 1's gate.
- **It is the final tree.** No file outside the build folders is newer than the gate's start; this section's gate
  lines were written afterwards and are the only change since. Both result bundles hold this round's cases, all
  passed: the two new clauses on the fake, the five new faults in `fault_breaksItsClause`, and the tester's four
  clients in `racyClient_isRejectedByAClause`.
- **Coverage** (the gate's table): LedgerDependencies 96.20 %, LedgerDomain 99.12 % (2043 / 2061), LedgerFakes
  98.94 % (1413 / 1428), LedgerSync 91.17 %, overall 98.51 % (8354 / 8480); every threshold met.
- **Release build:** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
  **exit 0** (34 s). No Release object names `FakeWorkoutSessionClient`, `InMemoryStores`, `SplitMix64`,
  `FakeLinkBus` or `Fixtures` (0 symbols each; Debug: 731, 451, 110, 1139, 2621), and `Release/LedgerFakes.o` is
  1,176 bytes with one symbol.
- **Host** (`env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'LedgerSyncTests|LedgerDependenciesTests|LedgerDomainTests'`, never `--build-system native`): `LedgerSyncTests` 86
  tests pass, `LedgerDomainTests` 796, `LedgerDependenciesTests` 63. `swiftformat --lint` and `swiftlint --strict`
  exit 0, with no new suppression.
- **No test helper is left running** (`ps` shows none for this worktree). 9.7 GB free after the gate.

#### Not done as written, and findings

1. **(d) is in clause 8, not in clause 20 ("ends at once").** The ruling says "among the overlapping ends". The
   tester's `clientThatReturnsForANonFiniteEnd_isRejectedByTheContract` demands that a client which returns from an
   ignored end breaks exactly one clause, the one whose name starts "finish and discard at a date the engine ignores
   throw". Such a client would also break clause 20 if the ignored ends raced there, and I may not edit that test.
   In clause 8 the same race costs nothing: the client already fails that clause. The rule checked is the ruling's:
   each ignored end beside an end the engine takes only throws `invalidEndDate` or `noLiveWorkout`.
2. **The ten tries stay** in `fault_breaksItsClause`. The re-review's R1, fix 3, says to keep them only if a fault
   needs them; on this host none does (table above). I left the test as it is because the task said no other
   change and I have no one-try measurement on the simulators. Changing `10` to `1` is one line
   (`Tests/LedgerSyncTests/WorkoutSessionClientContractFaultTests.swift:39`); the orchestrator's to rule.
3. **Clause 24 waits for the time limit** on a client that never tells an open stream of a start, as every clause
   does on a client that never publishes its last change. Its doc comment says so. No wrong client that the
   tester's tests or mine run through the contract does that: all of them finished within their limits.
4. **Clause 18 no longer pins the final state** to one value (1 c). A client that applied every event once and
   published each in order cannot end elsewhere than its own last update, so nothing is lost; the sentence is here
   because the check's wording changed.
5. **A host run of every test target** fails in one place that this round does not touch: `LedgerDesignTests`'
   rendering suite, 53 issues, all "`ArchivoFile…` is nil" (the font file is not found beside the test bundle on
   macOS). The gate runs that suite on the simulators.

Not verified: anything on a device; the host (S2) against clauses 23, 24 and 8's second half; the one-try
measurement on a simulator.

### S1 — orchestrator rulings after the touch-up (2026-10-05)

- The check for an end at a date that is not finite among overlapping ends stays in clause 8 (the tester's test
  asks for exactly one complaining clause). Accepted.
- The overlap clauses keep their ten tries. Accepted.
- The orchestrator's full gate on the touch-up's tree exited 0. The tester's files are unchanged since `92eb79c`.

## Slice S2 — orchestrator's brief (2026-10-05)

S1 merged as #27 (`95b0837`). S2's specification is the brief's last section, "Plan amendments — slice S2". What it
adds to the plan's S2 row, from S1's rounds:

- The host prunes ended subscribers when a `yield` reports `.terminated`, as the fake does.
- Recovery is started by the first protocol call if the launch step has not run.
- The ending update is published after the save; the host's own stamp is never the caller's fault.
- The contract's pair-by-pair overlap clauses are joined by a seeded script of calls made at once, checked as one
  history (criterion 11), and the host is run against the contract over stores that suspend, several times over.
- `update.haptics` is `[Haptic]`; exactly one subscriber plays them, on the workout side (decided in S6).
- The fake has no scriptable failures yet: S2 tests a failing store through the real stores (a SQLite trigger) or
  a store wrapper of its own in test support.

## Slice S2 — host and start use case (G1 implementer, 2026-10-05)

On `48403f5`, in the worktree `F10-s2`, on `feat/F10-s2-session-host`. Nothing is committed and no PR is open.
Paths are under `LedgerKit/` unless they start with `docs/`, `tasks/` or `scripts/`. Scratch files are in
`scratchpad/f10s2/` (written `f10s2/…` below).

### The stop, and the ruling

The first hand-back of this slice was a stop. One existing test failed because of the slice, in a tester's file
under `Tests/*/Adversarial/`, which I may not edit: `LaunchAdversarialTests.randomPhases_matchTheModel` (F07's
tester, 60 seeds), whose hand-written model of the iPhone launch had no `resumeWorkout` step. The plan's list of
tests that break (this file, lines 358-364) names `LaunchOrderTests` and `DatabaseLaunchTests` only. The
orchestrator ruled that the launch gaining a step is a change of specification, sanctioned one edit to that
model, and asked for the slice to be finished. The edit is under "Sanctioned test edits".

### What landed

| File | Contents |
|---|---|
| `Sources/LedgerDomain/Engine/HybridLogicalClock.swift` (new) | `HybridLogicalClock`: `newest`, `observe(_:)`, `stamp(now:) -> Date?`, `tick` |
| `Sources/LedgerDomain/UseCases/StartWorkoutUseCase.swift` (new) | `StartWorkoutUseCase`, its `Outcome`, `StartWorkoutError` |
| `Sources/LedgerSync/LocalWorkoutSessionActor.swift` (new) | the host: state, the six protocol calls, the queue (`inTurn`), own actions, publishing |
| `Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift` (new) | `resumeFromStore()`, `needsRecovery`, the recovery pass, completing an end, the misses |
| `Sources/LedgerSync/LedgerSyncError.swift` (new) | `LedgerSyncError.noFiniteStamp` |
| `Sources/LedgerPersistence/DatabaseLaunch.swift` | `LaunchStep.resumeWorkout` (`:14`); `run(_:retrying:_:)` (`:129`) |
| `Sources/LedgerAppKit/AppComposition.swift` | builds the host when the database opens (`:44`), binds `workoutSession` (`:147`), runs the step (`:115-120`) |
| `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift` | doc comments only: what a failed save leaves (criterion 4) |
| `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract+ConcurrentScripts.swift`, `+ConcurrentHistory.swift` (new) | criterion 11: the seeded script of calls made at once, and its judge |
| `Sources/LedgerTestSupport/Engine/StoreProbe.swift` (new) | `StoreProbe`, `ProbedStores`: stores that give way, wait, throw and record |
| `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract+Model.swift` | `Model.init(standing:)`, three lines |
| `Tests/LedgerSyncTests/LocalWorkoutSessionActor{,Clock,Contract,End,Miss,Performance,Recovery,Serial}Tests.swift`, `WorkoutSessionConcurrentScriptTests.swift`, `Support/HostSupport.swift` (new) | the host's suites: 61 test functions |
| `Tests/LedgerDomainTests/Engine/HybridLogicalClockTests.swift`, `UseCases/StartWorkoutUseCaseTests.swift` (new) | 8 and 10 |
| `Tests/LedgerPersistenceTests/DatabaseLaunchStepTests.swift` (new) | `run(_:retrying:_:)`, 3 |
| `Tests/LedgerAppKitTests/WorkoutRelaunchTests.swift`, `WorkoutSessionWiringTests.swift` (new) | criteria 7 and 9: 5 and 6 |
| `docs/architecture.md` §6, and one clause in §4 | the host, recovery, the use case |

Outside the slice's list, and why:
- `LedgerSyncError.swift`: standards §8, a module's own error, for the stamp.
- `StoreProbe.swift`: the brief's "a store wrapper of its own in test support".
- `…Contract+Model.swift`: the judge needs the rules from a given state.
- `Tests/LedgerSyncTests/Support/Tags.swift`: `.performance` and `.slow`, for criterion 12's suite.
- `docs/architecture.md` §4: its launch sentence would otherwise be stale.
- `WorkoutSessionClient.swift`: criterion 4 asks for the documentation.

Unchanged: `Package.swift`, `package-graph.expected.txt`, `project.pbxproj`, the test plans,
`scripts/coverage-thresholds.json`, the watch app. `tasks/todo.md` is not written: the slice's file list excludes
it and the orchestrator owns it across lanes.

### Decisions and deviations

`Actor` is `Sources/LedgerSync/LocalWorkoutSessionActor.swift`, `Recovery` its `+Recovery.swift`.

1. **Re-entrancy: a queue of tasks the actor owns** (`Actor:108-124`). `start`, `apply`, `finish`, `discard` and
   recovery each call `inTurn`, which, before it suspends, takes the place after the operation queued last and
   starts a `Task` that waits for that one and then runs.
   - *No interleaving:* an operation starts only when the one before has ended, so none reads state another has
     not committed.
   - *No reordering:* the place is taken in the turn the call reaches the actor, so operations, and their
     updates, run in arrival order.
   - *No deadlock:* an operation waits only for the one before it and awaits only the stores. No operation calls a
     method that queues: `begin`, `perform`, `end` (`Actor:162-227`), `recover` and `ready` (`Recovery:34-49`) are
     the unqueued bodies.
   - *No starvation:* first in, first out; nothing can overtake. A store that never returns stops the queue, as a
     held database lock would.
   - *Cancellation:* the task is the actor's, so a caller cancelled at any point still has its event stored, and
     only waits (the plan's risk "A cancelled caller"). GRDB refuses a cancelled task's write, which
     `cancelledCaller_isStoredInTheDatabase` shows on the real store.
   - *Rejected:* a continuation-based gate with the work in the caller's task (mutant M2: a cancelled caller's
     write throws, so a set ticked before Minimize is lost); `withTaskCancellationShield`, which would do it with
     no unstructured task, but is iOS 27 / watchOS 27 only (Apple's documentation, checked today) and the minimum
     is 26.
   - `current()` and `updates()` (`Actor:70-87`) do not queue once recovery has run: decision 2 makes that safe.
2. **`live` changes only in the actor turn that publishes the change** (`Actor:137-140`, `:174-175`,
   `:208-209`; `Recovery:97-100`). A reader at any turn sees the last update's state, with no suspension between
   a commit and its publication (clauses 22 to 24).
3. **Criterion 4's open point: until a finished workout is stored, every reader still sees it as it stood.**
   `current()` returns the workout as before the finish, open and new streams show it, and no update is published
   (`ending`, `Actor:40-42`; `settle()`, `Recovery:124-130`).
   - *Why, from what a screen needs:* (a) Today's Resume and the cover agree, so the lifter can go back in and
     finish; (b) `start` answers `workoutInProgress`, so no second workout of the day can be started over one that
     is not yet in history, which the other choice (`current()` nil) invites; (c) it is the rule the protocol
     already has for a refused append: a call that throws changes nothing a reader can see.
   - *What follows:* a second `finish` retries and returns the state ended at the first call's date
     (`Actor:215-220`); `apply` and `discard` complete the pending end first (`Actor:186`), then throw
     `noLiveWorkout`, or what the save throws; the launch step completes it on the next foreground and publishes
     without a haptic (`Recovery:66-75`, `:106-112`).
   - *After a relaunch* nothing is live while the save keeps failing (only the finished state can be rebuilt), so
     another workout can start: `unsavedWorkout_afterARelaunch_leavesNothingLive`. Open question 2.
   - Written on the protocol: `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift`, the type's doc and
     `current`, `apply`, `finish`, `discard`, `incompleteLog`.
4. **A log that cannot be dropped after the save is treated as a failed save** (`complete(_:)`,
   `Recovery:138-150`): one rule, "an end is complete when its log is gone", for finish, discard, retries and
   recovery. The cost: `finish` can throw although the workout is in history. Open question 3.
5. **When an append throws, the next call reads the store before it acts** (`persist`, `Actor:247-254`;
   `ready()`, `Recovery:44-49`). A store that refused leaves nothing changed; one that stored the envelope and
   then threw is picked up, and streams get the corrected state without a haptic. GRDB rolls back on a throw, so
   this is for a store that lies, not for M1's.
6. **Recovery is one idempotent pass** (`reconcile()`, `Recovery:53-80`), used by the launch, by the first
   protocol call when the launch has not run it, by the call after a failed append, and by the foreground retry.
   - A store it cannot read throws and leaves the host knowing no more than before: calls throw until a pass reads
     through, and a stream opened meanwhile starts with what is known and hears the workout a later pass resumes.
   - A save that throws is collected, the other logs are dealt with, and the first failure is thrown at the end.
   - Two live logs: the one that started last is resumed, the other kept, a fault logged (`Recovery:85-101`).
7. **The clock and `seq`.** `HybridLogicalClock` is a value in the actor; `seq` is the highest stored for the live
   workout from this device, in memory. An own action stamps a copy and keeps it only once the envelope is stored
   (`Actor:164-174`, `:190-201`). Recovery observes `newestWallClock()` and reads `highestSeq`
   (`Recovery:54-56`, `:95-96`). A system clock that steps back gives `newest + 1 ms`. One that is not finite
   gives no stamp: the host logs a fault and throws `LedgerSyncError.noFiniteStamp` before `reduce`
   (`Actor:232-243`), so never `notStartable` and never "ignored".
   - **Deviation:** `stamp(now:)` returns `Date?`, not the plan's `Date`
     (`Sources/LedgerDomain/Engine/HybridLogicalClock.swift:46`). The plan's type cannot say "no stamp", and
     criterion 3 needs it said before `reduce`.
8. **"Reports an issue" is a fault-level log and a typed throw; it is not `reportIssue`.** The orchestrator asked
   for the mechanism the fakes use unless a standard forbids it.
   - That mechanism is swift-issue-reporting's `reportIssue` (`Sources/LedgerFakes/InMemoryStores.swift:73`).
     `LedgerFakes` links it by ADR-008's amendment (`docs/adr/ADR-008-ledger-fakes-module.md:69-72`), and all of
     `LedgerFakes` is `#if DEBUG`.
   - `LedgerSync` links `LedgerDomain` only (`package-graph.expected.txt`, "library LedgerSync: LedgerDomain").
     Calling `reportIssue` from the host needs a new edge in `Package.swift`. **The rule is standards §2**
     (`docs/engineering-standards.md:62-63`): "Adding a dependency edge in `Package.swift` that violates this
     diagram requires an ADR." `scripts/check-package-graph.sh` fails the gate on it, and architecture §1 allows
     product code two third-party dependencies, "nothing else without an ADR". So I kept the log.
   - *What a test sees:* the typed error, asserted in six cases
     (`Tests/LedgerSyncTests/LocalWorkoutSessionActorClockTests.swift:67`, `:87-93`: two tests, each for NaN, +∞
     and −∞).
   - *What a developer sees:* a fault in the log, as for every other "cannot happen" in product code
     (`Sources/LedgerDependencies/Unimplemented/Unimplemented.swift:23-27`, `DatabaseLaunch.fail`).
   - What `reportIssue` would add: a test that reaches it without expecting to fails by itself, and Xcode shows a
     runtime issue in a Debug run. Open question 1 says what it costs.
9. **`start` stamps seq 1** and does not ask the store (`Actor:165`). S1's open question 4 (a start with the id of
   an ended workout) stays as the fake has it: accepted. Open question 4.
10. **A log with rows this version cannot read:** `finish` is refused before anything is stored (`incompleteLog`,
    the workout stays live; `Actor:196-199`); `discard` ends the workout and keeps the log; recovery keeps an ended
    one (`Recovery:138-145`, `:113-115`). So the lifter is never stuck with a workout that can neither be finished
    nor dropped.
11. **Deviation: `needsRecovery` on the actor** (`Recovery:28-30`), beyond the plan's signature. The composition
    retries the step on a foreground only while it is true (`Sources/LedgerAppKit/AppComposition.swift:116-117`).
    That is how a finish whose save failed is retried by the launch (criterion 4) while
    `LaunchOrderTests.resume_again_runsNothingTwice` still holds. Mutants M13 and M17 pin both halves.
12. **Deviation: `AppComposition.database` is a `lazy var`** (`AppComposition.swift:25-33`), so that `onOpen` can
    hand the stores back to the composition (`opened`, `:44-55`); `self` cannot be captured in `init` before
    `database` exists. `DatabaseLaunchTests.Subject` already builds its launch this way. The import of
    `LedgerSync` is no longer conditional (`:12`): the module exists on every platform.
13. **Deviation: the use case reads `exercise(id:)` per slot**, not the plan's `all()`
    (`Sources/LedgerDomain/UseCases/StartWorkoutUseCase.swift:102-108`): it needs the day's exercises, not the
    catalog. It builds the session before it discards a live workout (`:92-95`), so a build that fails leaves that
    workout alone. A live workout of the same source is resumed whatever `replacingLive` says (`:85-87`).
14. **Misses** (`slotUpdates`, `Recovery:155-173`) use `workout.isDeload` (what the lifter was prescribed), the
    slot as stored now, and nothing when the active program is not the workout's or the workout is ad hoc. The id
    check is the ruling's rule (O9); real stores already keep a slot in one program, so only a stand-in store can
    tell the difference (`finish_judgesTheProgramByItsID`, mutant M11).
15. **The effects are not run by a loop over `[Effect]`.** `perform` runs them in the engine's order as
    straight-line code: `.persist`, then the end (`.materialize` or `.discardLog`), then the haptics with the
    update (`Actor:178-211`). An end is completed from the state's phase, as recovery and a retry must do anyway
    (they have a state, not effects), so there is one way to complete an end, not two. The list still decides what
    it alone knows: whether the event was ignored, and the haptics. S6 adds the notification cases.

### Criteria → tests

| # | Tests |
|---|---|
| 1 | `LocalWorkoutSessionActorContractTests`: `host_keepsTheClause` (24 clauses × 6 set-ups: in-memory, GRDB, suspending; recovered at launch or not), `violations_ofTheHost_areNone` (× 6), `sessionScripts_fakeAndActorPublishTheSame` (200 seeds × 6) |
| 2 | `LocalWorkoutSessionActorTests`: `apply_assignsNextSeq`, `apply_storesBeforePublishing`, `apply_ignoredEvent_storesNothing`, `apply_storeRefuses_changesNothing`, `start_storeRefuses_startsNothing`, `append_lostAcknowledgement_isRecovered`, `start_afterAnEnd_startsItsSeqAtOne` |
| 3 | `LocalWorkoutSessionActorClockTests`: `stamps_surviveAStepBack`, `relaunch_continuesTheClock` (× 2), `start_clockNotFinite_isTheHostsFault` (× 3), `apply_clockNotFinite_isTheHostsFault` (× 3), `recovery_skipsNonFiniteStamps`; `HybridLogicalClockTests` (8) |
| 4 | `LocalWorkoutSessionActorEndTests`: `finish_storesThenSavesThenDrops`, `finish_publishesAfterTheSave` (× 2), `endingUpdate_arrivesAfterTheStoreIsDone`, `finish_saveFails_secondFinishRetries`, `finish_compactFails_waitsAndRetries`, `pendingEnd_isCompletedBeforeAnyChange`, `pendingEnd_isCompletedByTheLaunchStep`, `finish_storeRefusesTheEnd_nothingEnds`, `finish_lostAcknowledgement_isCompletedFromTheStore`, `finish_incompleteLog_staysLive`; `LocalWorkoutSessionActorMissTests` (6) |
| 5 | `LocalWorkoutSessionActorEndTests`: `discard_dropsTheLog`, `discard_compactFails_secondDiscardCompletes` |
| 6 | `LocalWorkoutSessionActorRecoveryTests` (13: one per row of the table, twice, two live logs, each read failing, a stream opened meanwhile); `LocalWorkoutSessionActorSerialTests`: `callsDuringRecovery_waitForIt`, `firstProtocolCall_startsRecovery` (× 4); `WorkoutSessionWiringTests.cancelledCaller_neverCancelsTheStep`; `DatabaseLaunchStepTests.run_cancelledCaller_neverCancelsTheStep` |
| 7 | `WorkoutRelaunchTests`: `killedAfterTheStart_resumes`, `killedMidWorkout_resumesTheSameState`, `killedBeforeTheSave_isSavedAtLaunch`, `killedBeforeTheDrop_isSavedAgainUnchanged`, `killedAfterTheDiscard_dropsTheLog`: a real file, a second composition booted on it, the workout started through `StartWorkoutUseCase` |
| 8 | `StartWorkoutUseCaseTests` (10) |
| 9 | `WorkoutSessionWiringTests` (6); `DatabaseLaunchStepTests` (3); `LaunchOrderTests.launch_runsTheStepsInOrder`; `DatabaseLaunchTests.steps_inOrder` |
| 10 | `LocalWorkoutSessionActorTests`: `effects_forwardHapticsOnly`, `endedStreams_disturbNoOne`; the contract's clause 17 |
| 11 | `WorkoutSessionConcurrentScriptTests`: `fake_isOneHistory` (200 seeds), `host_isOneHistory` (200 × 6), `noFault_isOneHistory`, `overlapFault_breaksAScript` (9 faults), `script_dependsOnItsSeedAlone`, `scripts_holdEveryKindOfAction` |
| 12 | `LocalWorkoutSessionActorPerformanceTests.apply_withItsAppend_isUnderBudget`, nightly lane only, as `ReplayPerformanceTests` is |

Also: `LocalWorkoutSessionActorSerialTests`: `laterCallers_startFromWhatTheFirstStored`, `cancelledCaller_stillStores`,
`cancelledCaller_isStoredInTheDatabase`, `cancelledCaller_keepsItsTurn` (the design point on re-entrancy).

### The failure table

| Step that fails | Memory | Store | Caller | Subscribers | Retry | Relaunch |
|---|---|---|---|---|---|---|
| append, any event (`apply_storeRefuses_changesNothing`, `start_storeRefuses_startsNothing`, `finish_storeRefusesTheEnd_nothingEnds`) | unchanged; marked unrecovered | GRDB: nothing (rolled back) | the store's error | nothing | reads the store first; the same `seq` and stamp when nothing was stored | replay |
| append that stored and then threw (`append_lostAcknowledgement_isRecovered`, `finish_lostAcknowledgement_…`) | unchanged; marked unrecovered | the envelope | the store's error | nothing, until the next call | the next call adopts what is stored and publishes it without a haptic; an end is completed | replay |
| the clock is not finite (`…ClockTests`) | unchanged | nothing | `noFiniteStamp`, a fault logged | nothing | works once the clock reads a time | — |
| `materialize`, after `.finished` is stored (`finish_saveFails_secondFinishRetries`, `pendingEnd_…`) | `live` as before the finish; the end pending; clock and `seq` advanced | the log with its `finished`; no history row | the store's error | nothing; `current()` still the workout | `finish`: saves, compacts, publishes once, returns the state ended at the first date. `apply`, `discard`: complete it, then `noLiveWorkout`. `start`: `workoutInProgress`. Foreground: the step, no haptic | saved by the step; nothing live meanwhile |
| `compact`, after the save (`finish_compactFails_waitsAndRetries`) | the same | the log, and the history row | the store's error | nothing | saves again (no change), compacts, publishes once | saved again unchanged, compacted (`killedBeforeTheDrop_…`) |
| `compact`, after `.discarded` (`discard_compactFails_secondDiscardCompletes`) | the same, a discard pending | the log | the store's error | nothing | `discard`: compacts, publishes. `finish`: completes it, then `noLiveWorkout` | compacted |
| a read during recovery (`storeUnreadable_theNextCallRetries` × 4) | as before the pass | untouched | the store's error, from every call | a stream starts with what is known | the next call or foreground runs the pass again | — |
| a save during recovery (`saveThatThrows_keepsItsLog_andCarriesOn`) | the other logs dealt with; the live one resumed | that log kept | the step throws; a protocol call does not | — | the next foreground | the next launch |

### Sanctioned test edits (for the tester's and the reviewer's audit)

**`Tests/LedgerAppKitTests/Adversarial/LaunchAdversarialTests.swift`** (F07's tester). Ten lines added, none
removed or changed (`git diff --numstat`: `10 0`). Line numbers are the file's now.

| Lines | Edit |
|---|---|
| 98-99 | in `Model`, after `var hasLoadedSettings = false`: a doc comment naming this ruling, and `var hasResumedWorkout = false` |
| 139-142 | in `Model.resume(_:)`, inside `if isOpen { … }`, after the settings block: a four-line comment saying what follows and why the step never fails here |
| 143-146 | `if !hasResumedWorkout { log.append("began resumeWorkout"); hasResumedWorkout = true }` |

What the model now says of the step:
- *Its place:* after `loadSettings`, before `activateCompanionSession`, as `AppComposition.resume(in:)` runs it.
- *When it runs:* in the first `resume` that finds the database open, whatever the phase. For a database that
  failed to open at boot, that is the foreground call that opens it, which is the only call that can.
- *Done or failed:* it begins once and succeeds. Neither fault the test injects reaches it (a file that is not a
  database; a trigger on `exercise`): it only reads an empty event log.
- *Retried:* never here, because a step that succeeded has no work left (`needsRecovery` is false).

No second change was needed. The test's assertions, seeds, faults, `spelled` and every other test in the file are
as they were. The step's failure and its retry need a fault this test does not inject; they are in
`WorkoutSessionWiringTests` (`stepFailure_isRecorded_andRetriedInTheForeground`,
`failedFinish_isRetriedOnTheNextForeground`). All 60 seeds pass. Mutant M17, which retries the step on every
foreground, fails this test among others, so the model does constrain the step.

The two pinned step lists, as the brief told me to update:

| File | Lines | Edit |
|---|---|---|
| `Tests/LedgerAppKitTests/LaunchOrderTests.swift` | 34, 38-41 | `.event(.began(.resumeWorkout))` between the settings and the companion session; `.resumeWorkout` in `LaunchStep.allCases` |
| `Tests/LedgerPersistenceTests/DatabaseLaunchTests.swift` | 114-117 | `.resumeWorkout` in `LaunchStep.allCases` |

No other existing test file is edited. `git status --short | grep Adversarial` prints that one file.
`Tests/LedgerSyncTests/Support/Tags.swift` gains two tags and is not a test.

### Code lines

`f10s2/count-lines.py` (S1's, with this base): added lines of `git diff -U0 48403f5`, new files whole, blank and
whole-line comment lines excluded.

| File | Added | Removed |
|---|--:|--:|
| `Sources/LedgerSync/LocalWorkoutSessionActor.swift` | 170 | 0 |
| `Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift` | 123 | 0 |
| `Sources/LedgerDomain/UseCases/StartWorkoutUseCase.swift` | 85 | 0 |
| `Sources/LedgerAppKit/AppComposition.swift` | 31 | 17 |
| `Sources/LedgerDomain/Engine/HybridLogicalClock.swift` | 24 | 0 |
| `Sources/LedgerPersistence/DatabaseLaunch.swift` | 12 | 1 |
| `Sources/LedgerSync/LedgerSyncError.swift` | 3 | 0 |
| `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift` | 0 | 0 |
| **Product** (plan: about 390; stop at about 550) | **448** | 18 |
| `LedgerTestSupport` (4 files) | 423 | 0 |
| Tests (20 files) | 1,934 | 2 |

Product is 15 % over the estimate, mostly recovery and the pending end. Nothing was compressed to fit; the actor's
own actions are a `private extension` in the same file because of the 150-line type limit.

### The repeated contract runs

`f10s2/stress.py`: `swift test --skip-build --filter 'LocalWorkoutSessionActorContractTests|WorkoutSessionConcurrentScriptTests|LocalWorkoutSessionActorSerialTests'`,
each run a process of its own. One run is 144 clause cases, 6 `violations` passes of 24 clauses, 1,200 sequential
scripts and 1,200 concurrent scripts on the host (a third of each over the stores that give way inside every
call), 200 concurrent scripts on the fake, and the serial suite. Load average between 3 and 6.

| Pool | Runs | Green | Time |
|---|--:|--:|--:|
| default | 60 | **60** | 674 s |
| one thread (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) | 60 | **60** | 1,462 s |

So 8,640 clause cases, 72,000 sequential and 72,000 concurrent scripts on the host per pool, none failing.
The host's sources did not change after these runs (the mutants below were each put back and compared byte for
byte); three tests were added afterwards and are in the gate's run, not in these.

It stays a measurement on one Mac. What makes it more than that is mutant M1: the same suites fail at once on a
host without the queue.

### Criterion 11: the script, and the faults that break it

`WorkoutSessionClientContract.concurrentScriptViolation(seed:on:)` uses the protocol alone. A script is an
optional opening start, six tasks of six actions run at once (starts, adds, repeats, rests, finishes, discards,
streams opened in flight, calls that must be refused or ignored), and a subscriber on a stream opened first that,
on the update telling it of a workout, reads `current()` and logs a set. It is judged as one history
(`…Contract+ConcurrentHistory.swift`): the five rules of the brief, each a function there.

How many of the twenty fixed seeds report each fault of `FaultyWorkoutSession`, measured with a throwaway test
(added, run, deleted; `f10s2/faultcounts-*.log`):

| Fault that needs two calls inside the client | Default pool | One thread |
|---|--:|--:|
| `losesAnEditBetweenCallers`, `endsTwiceAtOnce`, `appliesAfterTheEnd`, `registersAfterASuspension`, `publishesTheStartLate`, `commitsTheStartLate` | 20 each | 20 each |
| `startsTwiceAtOnce` | 19 | 19 |
| `dropsHapticsUnderOverlap` | 10 | 7 |
| `judgesAnIgnoredEndLater` | 6 | 8 |

All nine are reported on both pools. `overlapFault_breaksAScript` asks for one seed in twenty.

Of the 22 faults that need no overlap, the concurrent script reports 16 by a violation and 2 by throwing from
its last change (`keepsTheEndedWorkoutCurrent`, `refusesAStartAfterAnEnd`; the sequential script's `markEnd`
throws the same way). It never reports four, by construction: `cancellationEndsEveryStream` (no subscriber is
cancelled), `judgesSnapshotsByPhaseAlone` (its refused snapshot is a finished one), `movesTheEndThroughApply` and
`terminalThroughApplyStaysLive` (it ends workouts by `finish` and `discard` only). The clauses and the sequential
scripts cover those. Open question 6.

### Mutants

`f10s2/mutants.py`, logs `mutants1.log` and `mutants2.log`: each applied alone to the source, the suites run, the
file put back and compared byte for byte. **17 of 17 fail at least one test.**

| Mutant | Failing tests (first) |
|---|---|
| M1 `inTurn` runs the operation at once, no queue | `host_keepsTheClause`, `violations_ofTheHost_areNone`, `host_isOneHistory`, `laterCallers_…`, `cancelledCaller_keepsItsTurn` |
| M2 the operation runs in the caller's task (queued, cancellable) | `cancelledCaller_isStoredInTheDatabase`, `cancelledCaller_keepsItsTurn` |
| M3 an event is published before it is stored | `apply_storesBeforePublishing`, `apply_storeRefuses_changesNothing`, 2 more |
| M4 clock and `seq` kept although the append was refused | `apply_storeRefuses_changesNothing` |
| M5 the ending update is published before the save | `finish_publishesAfterTheSave`, `finish_saveFails_…`, `host_isOneHistory`, 4 more |
| M6 a save that fails leaves no workout current | `finish_saveFails_…`, `pendingEnd_…` (2), 4 more |
| M7 recovery does not restore the clock | `relaunch_continuesTheClock`, `recovery_skipsNonFiniteStamps`, `liveLog_isResumed` |
| M8 recovery does not restore `seq` | `liveLog_isResumed`, `firstProtocolCall_startsRecovery`, 4 more |
| M9 the stamp is the raw system clock | `stamps_surviveAStepBack`, `HybridLogicalClockTests` (3), 7 more |
| M10 an incomplete log is completed | `finish_incompleteLog_staysLive`, `unreadableRows_resumeOrKeep` |
| M11 misses written whatever program is active | `finish_judgesTheProgramByItsID` |
| M12 a failed append is trusted to have stored nothing | `append_lostAcknowledgement_isRecovered`, `finish_lostAcknowledgement_…` |
| M13 the host never says it has work left | `failedFinish_isRetriedOnTheNextForeground`, `stepFailure_…`, 4 more |
| M14 the launch runs the step in the caller's task | `run_cancelledCaller_neverCancelsTheStep` |
| M15 a start is not judged against the session | `host_keepsTheClause`, `sessionScripts_…`, `host_isOneHistory`, 4 more |
| M16 recovery drops a log that replays to nothing | `logWithoutAStart_isKept`, `unreadableRows_resumeOrKeep` |
| M17 the composition retries the step on every foreground | `resume_again_runsNothingTwice`, `randomPhases_matchTheModel`, 3 more |

Two findings of the first round, both fixed with a test:
- **M11 survived.** With real stores a slot belongs to one program, so "the active program is the workout's" and
  "the active program holds the workout's slots" cannot differ, and no test could tell. I kept the check (it is
  the ruling's rule, O9, and does not lean on another module's invariant) and added
  `finish_judgesTheProgramByItsID`, over a stand-in program store.
- **M2 was caught for a weak reason** (a cancelled `for await`). The in-memory stores ignore cancellation, so
  `cancelledCaller_stillStores` could not see it. `cancelledCaller_isStoredInTheDatabase` runs the same on GRDB,
  whose async write throws in a cancelled task.

### Gate and coverage

**Full gate.** `/usr/bin/python3 <sim-lock> scripts/check.sh` from the worktree root, in the background, the
shell appending the status to `f10s2/gate2.log`. Started 05:25:59, waited 460 s for the lock (F08's gate), then
**`check.sh OK`, `GATE_EXIT=0`, 725 s**: lint 62 s, iOS build 24 s, iOS tests 323 s, watchOS build 27 s, watchOS
tests 287 s, coverage 2 s. 17 test targets ran and passed (PR), 8 (PR-Watch). iOS: 1,822 tests, 1,800 passed, 0
failed, 13 skipped, 9 expected failures; watchOS: 1,630, 1,612 passed, 0 failed, 13 skipped, 5 expected failures.
Against S1's last gate that is one more skipped on each (this slice's timing suite, nightly only) and the same
expected failures. 8.4 GB were free before it, 8.2 GB after.

**It is the final tree.** Only this notes file changed after it started. The iOS result bundle holds this
slice's suites, all passed: the contract on the host (1,350 cases), the concurrent scripts (1,412), kill and
relaunch (5), the wiring (8 cases), `Adversarial F07 S2 · iPhone launch` with its 60 seeds, `Launch order`, and
the rest of the table under "Criteria → tests"; the timing suite is skipped there, as intended. The watchOS
bundle holds `LedgerSyncTests` and `LedgerDomainTests` too: the host's suites passed on the watch simulator.

**An earlier run, on a tree I then changed** (`f10s2/gate1.log`): started 05:07:09, 240 s for the lock,
`check.sh OK`, `GATE_EXIT=0`, 739 s, the build cold. Its build output showed five compiler warnings in a test
file of mine ("no calls to throwing functions occur within 'try'", `StartWorkoutUseCaseTests`), which I had missed
on the host because I searched my build logs for errors only. I removed the five `try`, recompiled every file I
touched on the host (the one warning left is `PayloadVersionAdversarialTests.swift:29`, as before the slice), and
ran the gate again. The coverage is the same in both.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 228 / 237 | 96.20 % | 90 % | ✓ |
| LedgerDesign | 2113 / 2175 | 97.14 % | 60 % | ✓ |
| LedgerDomain | 2122 / 2140 | 99.15 % | 95 % | ✓ |
| LedgerFakes | 1415 / 1428 | 99.08 % | 90 % | ✓ |
| LedgerHealth | 47 / 48 | 97.91 % | 80 % | ✓ |
| LedgerPersistence | 2498 / 2516 | 99.28 % | 90 % | ✓ |
| LedgerSync | 338 / 341 | 99.12 % | 90 % | ✓ |
| Overall | 8761 / 8885 | 98.60 % | 80 % | ✓ |

Per file, in the iOS bundle (`xccov`): `LocalWorkoutSessionActor.swift` 155 / 155, `+Recovery.swift` 152 / 152,
`HybridLogicalClock.swift` 22 / 22, `StartWorkoutUseCase.swift` 57 / 57, `WorkoutSessionClient.swift` 21 / 21.
`LedgerSync`'s three uncovered lines are `CompanionSessionActivator.swift`'s, as before (31 / 34). The lines not
covered in `LedgerDomain` and `LedgerPersistence` are 18 each, as at S1's gate, so every line this slice added to
them is covered. `AppComposition.swift` is 134 / 135 (`LedgerAppKit` is not gated).

**Warnings.** None in this slice's files. The cold build printed the three it printed before the slice
(`PayloadVersionAdversarialTests.swift:29`, a `@Test` expansion beside it, `LedgerDesignTests/PreviewTests.swift:90`),
with xcbeautify's "exit code 0 but produced no further output" lines beside them.

**Format and lint**, on the final tree: `swiftformat --lint` 0 of 635 files, exit 0; `swiftlint --strict` exit 0;
no new suppression. The gate runs both again.

**Host**, on the final tree (`f10s2/host4.log`): `LedgerDomainTests` 814 tests, `LedgerPersistenceTests` 452,
`LedgerSyncTests` 147, `LedgerDependenciesTests` 63, `LedgerAppKitTests` 49, `LedgerWatchAppKitTests` 35, all
passed, exit 0. Every S1 test passes unedited; the tester's files are untouched but for the sanctioned ten lines.

**Release build.** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
**exit 0**, 50 s, no warning (`f10s2/release1.log`). No Release object names `FakeWorkoutSessionClient`,
`InMemoryStores`, `InMemoryWorkoutEventStore`, `SplitMix64`, `FakeLinkBus` or `Fixtures` (0 symbols each; Debug:
740, 539, 241, 125, 1139, 2638), and `Release/LedgerFakes.o` is 1,176 bytes with one symbol, as at S1. The host,
the clock and the use case are in it (818, 119 and 186 symbols). Only test files changed after this build.

**Criterion 12, by hand on the host:** `LEDGER_TEST_LANE=nightly swift test … --filter
LocalWorkoutSessionActorPerformanceTests`: passed; 20 applies on a real file, on a log of 200 events: 95th
percentile 98 µs, median 74 µs, against 30 ms (`f10s2/attachments/session-apply.txt`).

**Tree.** `git status --short` shows the files under "What landed", the sanctioned edit and this file, and nothing
else; HEAD is `48403f5`; nothing is staged or committed.

**Shared state, as the orchestrator asked.** Nothing odd. The lock was held by F08's gates each time I looked
(05:07 and 05:26), by live processes a few minutes old, and was released to mine both times; at 04:12 its file
was empty. Of the `swift-test` processes I saw that were not mine, the one at 02:40 ran in the `F09-s1` worktree
(its working directory); the two at 04:12 and 05:07 filtered other lanes' suites (`FeatureOnboardingTests`,
`LoadableAdv…`) and were seconds old. I left all three. No test helper of this worktree is running.

**Housekeeping.** Builds of mine that failed to compile left `*.cstemp` files in this worktree's
`LedgerKit/.build`, which then failed code signing; I deleted them each time. Before the second gate 6.6 GB were
free, under the 8 GB line, so I deleted this worktree's `LedgerKit/.build` (2.3 GB, ignored build output of
mine); the host commands above therefore start with a cold build. `swiftformat` was run over the files I touched
only.

### How to verify by hand

From the worktree root:

1. The host: `env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerSyncTests`.
   Expect 147 tests in 25 suites, with 13 known issues (S1's, on purpose); the timing suite is skipped outside
   the nightly lane.
2. Kill and relaunch, the wiring and the launch: `--filter 'WorkoutRelaunchTests|WorkoutSessionWiringTests|LaunchOrderTests|LaunchAdversarialTests|DatabaseLaunch'`.
3. The contract biting on the host: in `Sources/LedgerSync/LocalWorkoutSessionActor.swift`, replace the body of
   `inTurn` (`:117-123`) by `return try await operation()` and run step 1. `host_keepsTheClause` fails, among
   others. Undo it. (`python3 f10s2/mutants.py M1` does this and puts the file back.)
4. Many times over: `python3 f10s2/stress.py 60 '<the filter above>'`, then the same with
   `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` as a last argument.
5. Criterion 12 on the host: `LEDGER_TEST_LANE=nightly swift test … --filter LocalWorkoutSessionActorPerformanceTests --attachments-path <folder>`.
6. Release: `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`, then,
   in `.build/out`,
   `find Intermediates.noindex/LedgerKit.build/Release Products/Release -name '*.o' -print0 | xargs -0 nm 2>/dev/null | grep -v ':$' | grep -c FakeWorkoutSessionClient`
   prints 0.
7. The gate: `/usr/bin/python3 <sim-lock> scripts/check.sh`.

### Open questions

1. **`reportIssue` for the stamp** (decision 8). It needs `IssueReporting` on the `LedgerSync` target (one line in
   `Package.swift`, one in `package-graph.expected.txt`), an amendment like ADR-008's, `import IssueReporting`
   and one call beside the log; the six clock cases then expect the issue (`withKnownIssue`). The library is
   already linked through Dependencies. Recommendation: do it as a follow-up once the amendment is agreed; I did
   not add a dependency edge to a product module on my own.
2. **After a relaunch a workout that still cannot be saved leaves the slot free**, so the same day can be started
   again. Recommendation: accept for M1 (it needs a save that fails across a relaunch); S7's copy already says the
   app will try again.
3. **`finish` throws when only the compaction failed**, though the workout is in history. Recommendation: keep the
   one rule. The alternative announces the end and leaves a finished log that a later launch saves again, over any
   edit made in History meanwhile (F17 "Inputs from F05", S3).
4. **A start with the id of a workout already in history** would overwrite it at finish. Recommendation: leave; the
   use case always makes a new id. F17 should decide before a peer can start a workout.
5. **A pending end that the launch step completes while another workout is live** (only after a relaunch) is saved
   without an update, because an ended update for another workout would hide Resume. Today then learns of it at
   its next history read. Recommendation: F09 re-reads history on a return to the foreground.
6. **The concurrent script ends workouts by `finish` and `discard` only**, and cancels no subscriber. Adding
   terminal events through `apply` and a live but malformed snapshot is about six lines in its writer.
   Recommendation: leave to the tester, whose brief is further overlap shapes.
7. **Criterion 12 is measured on the host only.** Recommendation: read the first nightly run's
   `session-apply.txt`; the budget is 300 times the host's figure.

### Inputs for S3 and S4, and for F09 S6

Corrected in place in fix round 1 (2026-10-05), as S1's inputs were: S3's transaction (review SF5), S4's replace
and its Debug row, what a waiting end means for callers (SF2), S7's two open questions and F17's list are new, and
the line numbers are that round's. `Actor` is `Sources/LedgerSync/LocalWorkoutSessionActor.swift`, `Recovery` its
`+Recovery.swift`, `Protocol` `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift`.

- **S3:** `materialize` is called from one place, `complete(_:)` (`Recovery:142-154`), for a finish, its retries
  and recovery, so `programUpdates` applied there reach all three. A second materialise of the same workout must
  still change nothing: `killedBeforeTheDrop_isSavedAgainUnchanged` compares every row of six tables.
  **Drop the workout's log inside `materialize`'s transaction** (SF5, the orchestrator's ruling): a parameter on
  `materialize`, a contract clause, the fake following. "Saved but not compacted" then cannot exist over GRDB:
  `finish` no longer throws for a workout that is already in history, `complete(_:)` no longer compacts after a
  save (`Recovery:150-153`), and the failure table's row "`compact` after the save" is left for stores that are
  not one database. The tests of that row (`killedBeforeTheDrop_…` among them) then need such a store, or go.
- **S4:** build `StartWorkoutUseCase` from the keys (`workoutSession`, the four stores, `deviceID`, `date`,
  `uuid`). `.conflict(live:)`, then `start(_:replacingLive: true)`. A workout that ended between the two is no
  longer an error: the new one starts (F10-S2-2). A cancelled `.task` loses no tapped event. When `finish`
  throws, the workout is still current: show the failure over the screen as it is, and "Try again" is `finish`
  again. `emptyDay`, `programNotActive` and the builder's `weekOutOfRange` need a state each.
  **The Debug "Start sample workout" row (O15) makes a new workout id for every start.** With a fixed fixture id
  the second finish throws `duplicateIdentifier` every time, which is the third consequence below, and a start
  under an id whose log was kept now continues that log (F10-S2-4) and shows what it replays to.
  The start itself is fast: 9 ms at the 95th percentile over 20,000 sets on the Mac host (fix round 1, N7), so
  the cover's loading state is for a slow disk, not for the usual case. Not measured on a phone.
- **A waiting end, for S4, S7 and F09 S6** (written on `finish`, `Protocol:69-89`). Between a save that failed and
  its completion, `current()` and every stream show the workout as it stood, with a phase of `.live`. Nothing
  tells a reader that its end is stored. Three things follow:
  1. **A `discard` then completes the save.** It saves the waiting finish and throws `noLiveWorkout`; so does an
     `apply`. A lifter who answers a failed save with "Discard" gets the workout in history.
  2. **`StartWorkoutUseCase` resumes it or reports a conflict on it,** as for any live workout. For the same day
     it answers `.resumed`, and the cover opens a workout that accepts no change. For another day it answers
     `.conflict`; replacing it then saves it and starts the new one, or throws the store's error and starts
     nothing.
  3. **A save that can never succeed leaves no exit in this process.** `finish`, `apply` and `discard` throw the
     store's error each time, `start` answers `workoutInProgress`, and every return to the foreground runs the
     failing step again and logs a fault. Only a relaunch frees the workout's place. The tester's
     `HostUnsavableAdversarialTests` pin this (F10-S2-1); M1's screens cannot produce such a workout as long as
     every start makes a new id.
- **S6:** the notification effects go where `perform` commits (`Actor:215-225`) and in `conclude`; recovery runs
  none, so decide whether a resumed rest reschedules its notification. `EndEffectsTests` (LedgerDomainTests) pins
  what the host relies on when it completes an end from the state's phase: `.materialize(state)` for the finish,
  `.discardLog` for the discard, neither for any other envelope. It fails if S6's effects change that.
- **S7:** "Try again" after a failed save is `finish` again, and it keeps the first call's end date. **Two
  questions are open and are not decided in S2** (the orchestrator's ruling after G2 and G3):
  1. whether a lifter may abandon a workout that cannot be saved: Pete's to decide;
  2. how a reader is told that an end is waiting: the orchestrator's, with an ADR-004 paragraph before F17 is
     planned. ADR-004 is not changed in this slice.

  **When the fake gains a scriptable save failure, the rules of a waiting end become contract clauses:** the
  three consequences above, "the first save that succeeds publishes the one ending update", "a retried `finish`
  returns the state ended when the first call said", and "after a relaunch the unsaved workout is not shown".
  Today only the host's own tests and the tester's hold them (`LocalWorkoutSessionActorEndTests`,
  `HostEndFailureAdversarialTests`, `HostUnsavableAdversarialTests`), because the fake cannot fail a save.
- **F09 S6:** the stream's first element arrives only after recovery, so read history when it arrives, not before:
  a launch that saves a workout the app was killed in publishes nothing, because no stream was open. Re-read
  history whenever an update's state is not live, the first element included. Until a finished workout is stored
  Today still shows Resume; that is intended, and it includes a workout whose save failed: Resume then opens a
  workout that accepts no change (consequence 2), until S7 decides the two questions. `workoutSession` is now the
  host in the app, not the stub.
- **F17:**
  - `discard(endedAt:)` names no workout (S1's protocol), so `StartWorkoutUseCase` discards whatever is live at
    that moment, not the workout the lifter agreed to replace (review N8). One phone cannot put an end and a
    start by another caller in between; a peer can.
  - `start` continues a kept log from this device's highest `seq` (`Actor:173`). A kept log that holds only a
    peer's envelopes has none, so the start takes `seq` 1 and the host then shows what the whole log replays to.
    If that log already holds an end the engine accepts after the new `started`, the start returns, the pass
    completes that end, and nothing is live. Only damage plus a reused id reaches this today; untested.
  - `seq + 1` traps at `UInt64.max` (`Actor:175`, `:206`). No device writes that many events; a peer's envelope
    cannot raise this device's `seq`, which is read per device.
  - An operation added to the host's queue must not call a method that queues: `inTurn` now asserts it in Debug
    (`Actor:122`), which stops the test instead of the host.
  - When memory shows a workout and the store holds no log that replays to it, recovery logs a fault and leaves
    the workout shown (`Recovery:90-93`, review N3). What the host should do then is not decided.

### Not verified

- **Criterion 12 on a simulator or a device.** The timing suite is skipped in the PR lane and I did not run the
  nightly plan; the 98 µs is a Mac's.
- **The repeated runs on a simulator.** Sixty runs per pool are the host's; each gate ran the contract once on
  the iOS simulator and once on the watch's.
- **Anything on a device,** and the app launched by hand. No screen reads the host yet. The gate's UI smoke
  tests passed; they launch the app through this `AppComposition`, but assert nothing about the host or the step.
- **A kill by the system.** The five kill points drop a composition and boot another on the same file, with the
  step that "died" refused by a SQLite trigger. No process was killed.
- **`reportIssue`:** not adopted (decision 8, open question 1), so nothing shows that a test reaching the fault
  by accident fails by itself.
- The three tests added after the repeated runs have each passed on the host and in both gates, not sixty times.

### S2 — orchestrator rulings after G1 (2026-10-05)

- The edit to F07's tester model (`LaunchAdversarialTests`, ten lines: the `resumeWorkout` step) is the sanctioned
  one; S2's tester and reviewer audit it.
- **Decision 8 accepted:** the host's "cannot stamp a finite time" is a typed throw and a fault-level log. No new
  dependency edge for `reportIssue` (standards §2 puts one behind an ADR, and this does not earn it).
- 448 product lines against a plan of 390: under the 500 target; nothing to declare.
- The other deviations (the task queue the actor owns; what readers see between a failed save and its retry;
  `stamp(now:)` optional; `needsRecovery`; the lazy database; `exercise(id:)`; straight-line effects) go to the
  reviewer and the tester to judge.
- The orchestrator's full gate on the tree exited 0 before this entry was written.

### S2 — orchestrator rulings after G2 and G3 (2026-10-05)

G3 approved: 0 Blocking, 5 Should fix, 10 nits; it found no way to lose, duplicate or corrupt a workout over the
GRDB stores, and judged that the actor-owned task queue fits standards §4 as written (F07 S2's precedent). G2 round
1: 128 tests, no way found to lose or double a workout; four findings, five tests failing on purpose.

For fix round 1:
- **SF1 accepted:** the protocol's and architecture §6's wording is corrected as the review writes it.
- **SF2, documented now, decided before S7.** Between a failed save and its completion the workout is shown as it
  stood, and three consequences are written on `finish`'s documentation and in the inputs for S4, S7 and F09 S6:
  a `discard` then completes the save; `StartWorkoutUseCase` resumes or reports a conflict on it; and a save that
  can never succeed leaves no exit in this process. The behaviour does not change in S2 (nothing is lost, and no
  path through M1's screens produces a workout the store refuses). Two questions stay open and are recorded as
  inputs for S7: whether a lifter may abandon a workout that cannot be saved (Pete), and how a reader is told that
  an end is waiting (the orchestrator, with an ADR-004 paragraph before F17 is planned; an ADR change is Pete's to
  review, so it is not made in this slice). The tester's two pinning tests for F10-S2-1 stay as they are.
- **SF3 accepted** (no polling loop in the wiring test).
- **SF4 and F10-S2-3 accepted:** the concurrent script's judge accepts `noLiveWorkout` only where the history allows
  it, and the acting subscriber's stream is read to the end.
- **SF5 goes to S3:** the log is dropped inside `materialize`'s transaction, so "saved but not compacted" cannot
  exist; S3's inputs say so.
- **F10-S2-2 accepted:** with `replacingLive`, a live workout that has ended by the time of the discard is not an
  error; the new workout is started.
- **F10-S2-4 accepted:** `start` reads the store's highest `seq` for the workout and device, so memory follows the
  store when a log of that id is kept.
- **Nits:** taken as the review writes them unless one costs more than a few lines; any not taken is listed with
  its reason.
- For S4: the Debug "Start sample workout" row makes a new workout id for every start. For S7: when the fake gains a
  scriptable save failure, the rules of a waiting end become contract clauses.

### S2 fix round 1 (G1 implementer, 2026-10-05)

On `677fc49`, tree clean at the start. Nothing is committed. Paths are under `LedgerKit/` unless they start with
`docs/` or `tasks/`. `Actor` is `Sources/LedgerSync/LocalWorkoutSessionActor.swift`, `Recovery` its
`+Recovery.swift`, `Protocol` `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift`, `UseCase`
`Sources/LedgerDomain/UseCases/StartWorkoutUseCase.swift`, `Judge` and `Script`
`Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract+ConcurrentHistory.swift` and
`…+ConcurrentScripts.swift`. The full gate was not run, as the brief says: everything below is the Mac host's.

#### What changed, per item

| Item | Change | Where |
|---|---|---|
| 1. SF1 | The type: what a call that throws can still let readers see (an end that was waiting, and after a failed write the state found in the store); "in this process" for the one workout there may be. `current`: "the `live` of the last update". `finish`: "That holds in this process. After a relaunch the unsaved workout is no longer shown, another can be started, and the launch step saves the first when it can." | `Protocol:13-18`, `:31`, `:78-79` |
| 1. SF1 | Architecture §6, the "finished" bullet: the same two corrections | `docs/architecture.md:289-293` |
| 1. SF1 | The actor's own comment: a call whose append is refused leaves memory as it was; an end that is stored and cannot be completed has moved the clock and `seq` on | `Actor:17-21` |
| 2. SF2 | `finish`: nothing tells a reader that an end is waiting, and the three consequences. No behaviour changed; ADR-004 is not amended | `Protocol:69-76`, `:81-89` |
| 2, 8 | "Inputs for S3 and S4, and for F09 S6" above, corrected in place (its first paragraph says so): S3's transaction, S4's replace and Debug row, the waiting end's three consequences for S4, S7 and F09 S6, S7's two open questions and its contract clauses, F17's list | this file, the section before "Not verified" |
| 3. SF3 | The wiring test waits for the second `.began(.resumeWorkout)` on a stream the harness feeds from `record`; the bounded yield loop is gone | `Tests/LedgerAppKitTests/WorkoutSessionWiringTests.swift:160-166`; `Tests/LedgerAppKitTests/Support/Harness.swift:24`, `:53` |
| 4. SF4 | The judge places what each task did at points of the history, in the task's own order: a call that published stands at its update; a call that was refused or ignored, a stream opened in flight and a `current()` each need a point where the rules allow them, no earlier than what the same task did before. So `noLiveWorkout` passes only where nothing was live then. The opening call is judged against the first state alone | `Judge:15-42` (`Deed`), `:52-90`, `:95-114`, `:119-141` |
| 4. F10-S2-3 | The acting subscriber's stream is read on from its reaction to the end and must equal the stream opened first. The subscriber now logs two sets, not one | `Script:104-107`, `:123`, `:180-205` |
| 4 | Every script holds a start, an end the engine ignores and an end it takes, one place apart in three tasks | `Script:63-81` |
| 4, faults | `refusesAnApplyUnderOverlap` (an apply that finds another inside throws `noLiveWorkout`; breaks "callers at once") and `repeatsAnUpdateOnTheSecondStream` (the second stream opened gets its second update twice; breaks "two subscribers") | `Tests/LedgerSyncTests/Support/FaultyWorkoutSession.swift:20-23`, `:71-81`, `:223-228`; `…+Fault.swift:70-73`, `:99`, `:134-135` |
| 4, tests | The script's shape; each overlap fault must be reported by at least 4 of the 20 fixed seeds (was 1); the acting stream's fault must be reported by all 20, as the acting stream's | `Tests/LedgerSyncTests/WorkoutSessionConcurrentScriptTests.swift:34-54`, `:73-89`, `:91-101` |
| 5. F10-S2-2 | With `replacingLive`, a discard that throws `noLiveWorkout` is not an error: the new workout is started | `UseCase:98-102`, docs `:19-20`, `:69-72`; test `Tests/LedgerDomainTests/UseCases/StartWorkoutUseCaseTests.swift:143` with the session `EndsAfterTheLook` (`:219`) |
| 6. F10-S2-4 | `start` reads `highestSeq(for:device:)` and stamps the next `seq`. When a log of that id was kept, it then reads the store again (one recovery pass) and shows what the whole log replays to, with no haptic; with no kept log a start costs one more read and nothing else changes | `Actor:171-191`; test `Tests/LedgerSyncTests/LocalWorkoutSessionActorTests.swift:197` |

The tester's five failing tests pass on both pools with no tester file touched (`git status --short | grep
Adversarial` and `git diff 677fc49 -- 'LedgerKit/Tests/*/Adversarial'` are both empty), and the two tests that pin
F10-S2-1 (`HostUnsavableAdversarialTests`) pass unchanged.

**SF1, one clause that is not the review's wording.** The review's sentence for the type is "A call that throws
stores and publishes nothing of its own". Its own point 4 says a finish whose save fails has stored its envelope,
so I wrote "publishes nothing of its own, and has stored nothing, except an end that reached the log before its
save or its drop failed".

#### Nits

| Nit | Taken | What | Where |
|---|---|---|---|
| N1 | yes, as documentation | `finish`: a retry can find the end completed in between and then throws `noLiveWorkout`. `start`: after a lost answer it names the caller's own workout | `Protocol:74-76`, `:40-41` |
| N2 | yes | An own envelope the store says it already held: the host is marked unrecovered and throws `LedgerSyncError.alreadyStored(key)`; the next call reads the store | `Actor:260-273`; `Sources/LedgerSync/LedgerSyncError.swift:9-12`; test `LocalWorkoutSessionActorTests.swift:173` |
| N3 | yes, the log | Recovery logs a fault when the host shows a workout and no stored log replays to it. The workout stays shown; what else to do is F17's | `Recovery:90-93`; test `LocalWorkoutSessionActorRecoveryTests.swift:170` ("documents") |
| N4 | yes, one sentence | `run` is for a step the launch does not run itself | `Sources/LedgerPersistence/DatabaseLaunch.swift:128-129` |
| N5 | yes | A task-local set while an operation runs, asserted at the top of `inTurn` | `Actor:52-53`, `:118-126` |
| N6 | yes | `PerformanceBudget.apply` and `.runs`; architecture §15 gains the row | `Tests/LedgerSyncTests/Support/PerformanceBudget.swift`; `LocalWorkoutSessionActorPerformanceTests.swift`; `docs/architecture.md:506` |
| N7 | yes, measured once | Below | |
| N8 | no code | An input for F17 (the inputs section above). The protocol is S1's and a peer is F17's | |
| N9 | yes | `EndEffectsTests`: over every property seed, a random log that ends by a finish or a discard: `.materialize` of the state it leaves for the finish, `.discardLog` for the discard, neither for any other envelope | `Tests/LedgerDomainTests/Engine/EndEffectsTests.swift` |
| N10 | **not taken** | It needs the first CI run's times, which I do not have. Host times are under "Host runs" | |

**N5 is not shown by a test.** An assertion that fires ends the process, and the suites have no exit test. The
assert ran in every Debug test of this round and never fired.

**N7.** A throwaway test in LedgerPersistenceTests, deleted after the run: the stats performance suite's seed
(a file database, 20,000 sets in 400 workouts, 12 exercises), an active program whose day has 8 slots, each with a
last performance, and `StartWorkoutUseCase` over the GRDB stores and the fake session. One warm-up, then 20
starts: **p95 9.1 ms, median 7.0 ms, slowest 9.2 ms**, against the plan's 200 ms. On the Mac host, Debug; not on
a phone or a simulator.

#### Criterion 11 after SF4: what the faults show

Reports out of the 20 fixed seeds, ten runs on each pool (a throwaway test, deleted):

| Fault | Default pool | One thread |
|---|---|---|
| `judgesAnIgnoredEndLater` (the weakest) | **8 to 11** | 9 |
| `refusesAnApplyUnderOverlap` (new) | 11 to 13 | 10 |
| `dropsHapticsUnderOverlap` | 10 to 14 | 12 |
| `startsTwiceAtOnce` | 18 to 19 | 19 |
| `commitsTheStartLate` | 19 | 19 |
| `registersAfterASuspension` | 19 to 20 | 20 |
| `appliesAfterTheEnd`, `publishesTheStartLate`, `endsTwiceAtOnce`, `losesAnEditBetweenCallers` | 20 | 20 |
| `repeatsAnUpdateOnTheSecondStream` (new, no overlap needed) | 20 | 20 |

- **The weakest fault is reported by 8 of 20 seeds at the least** (the review counted 6, and 8 on one thread).
  The test asks for 4. With the ignored end and the real one at the same place of two tasks, as the review writes
  it, one run gave 8; a start one place before and the real end one place after gave the table's figures, and I
  kept that.
- **Why not more.** The stand-in looks again a hundred yields after the ignored end came in, and strikes only if
  nothing is live then. By then the script's other tasks have run on, and in about half the scripts one of them
  has started another workout. By the place of the ignored end the reports were 2, 3, 4 and 4 of 5 seeds: the
  later it comes, the less follows it. I did not move every ignored end to the end of its script, because that
  fits the script to this stand-in's window and not to a host's. When the fault does strike it is always
  reported: the rules allow an ignored end to return at no point.
- **`refusesAnApplyUnderOverlap` is what shows SF4.** Under the old judge a `noLiveWorkout` passed wherever it
  was thrown. It is reported by half the scripts and not by all, because a refusal whose task published nothing
  afterwards can still be placed at a later point where nothing was live. To do better the judge would need to
  know when each call began and ended, not only its task's order.

Mutants of this round (`fix1/mutants-fix1.py`: each applied alone, the named suites run, the file put back and
compared byte for byte):

| Mutant | Killed by |
|---|---|
| R1 the use case rethrows the discard's `noLiveWorkout` | 3 tests: mine and the tester's two |
| R2 `start` stamps `seq` 1 whatever the store holds | 1: `start_overAKeptLog_followsTheStore` |
| R3 `start` over a kept log keeps the bare snapshot | 2: mine and the tester's |
| R4 an envelope the store already held is taken for stored | 1: `apply_envelopeAlreadyStored_readsTheStore` |
| R5 the judge places a refusal anywhere in the history | 2: `overlapFault_breaksAScript` and the tester's margin test |
| R6 the acting stream is read only up to its reaction | 2: `faultOnTheActingStream_breaksEveryScript` and the tester's |
| E1 the engine drops a finished workout's log instead of materialising it | `EndEffectsTests` |
| E2 a discard has no `.discardLog` | `EndEffectsTests` |
| E3 a skipped rest drops the log | `EndEffectsTests` |
| E4 a finish materialises the state as it was before the end | `EndEffectsTests` |

Ten of ten killed. Not mutated: the documentation, N3's log line, N5's assertion.

#### Files outside the slice's list, and why

- `Tests/LedgerAppKitTests/Support/Harness.swift` (F07's): `onEvent`, called from `record`. SF3's fix as the
  review writes it needs the harness to tell of an event; nothing else in the harness changed.
- `Tests/LedgerSyncTests/Support/FaultyWorkoutSession.swift` and `+Fault.swift` (S1's stand-in): the two faults.
- `Sources/LedgerSync/LedgerSyncError.swift`: the case `alreadyStored`, and `import LedgerDomain` for
  `EnvelopeKey`. LedgerSync already depends on LedgerDomain: no new edge.
- `Sources/LedgerPersistence/DatabaseLaunch.swift`: N4's sentence.
- New: `Tests/LedgerDomainTests/Engine/EndEffectsTests.swift`, `Tests/LedgerSyncTests/Support/PerformanceBudget.swift`.

#### Host runs, lint, Release build

`env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
'^(LedgerSyncTests|LedgerDomainTests|LedgerAppKitTests|LedgerPersistenceTests)\.'` on the final tree, once as it
is and once with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` (`fix1/final-default.log`, `fix1/final-onethread.log`):

| Target | Default pool | One thread |
|---|---|---|
| LedgerSyncTests | 244 tests in 43 suites, passed (13 known issues, S1's) | 244 tests, **2 issues**, both below |
| LedgerPersistenceTests | 452 tests in 104 suites, passed (1 known issue) | the same |
| LedgerDomainTests | 838 tests in 138 suites, passed | the same |
| LedgerAppKitTests | 63 tests in 15 suites, passed | the same |
| Exit | **0** | **1** |

At `677fc49` on the default pool (`fix1/baseline.log`) the counts were 239, 452, 836 and 63, with 13 issues, all
in the tester's five tests. This round adds five tests to Sync and two to Domain.

**One thread: two of S1's tester tests fail, in every run, and they are not this round's.**
`racyClient_isRejectedByThisSuitesOverlapChecks` at `SessionContractBiteAdversarialTests.swift:111`
(`.racyLateRegistration`) and at `SessionContractRoundTwoAdversarialTests.swift:116`
(`.registersBeforeItsFirstElement`), in 8 of 8 runs of the Sync target on one thread, and when the two suites run
alone (14 tests, 2 issues). They are the two that S1's touch-up records above as failing on one thread in every
run ("The one-thread check", "For the tester"). They run the tester's own `Seam` checks on the tester's own
clients and call nothing this round changed. Everything else passed on one thread: the tester's five tests, the
two that pin F10-S2-1, and mine. I did not run the two at `677fc49`, which needs a checkout.

| Command | Exit | Result |
|---|---|---|
| The filter above, default pool | 0 | the table |
| The same, one thread | 1 | the two S1 tests |
| `stress.py 20 '<nine suites>'`: the script suite, the host's contract, serial and own-action suites, the tester's three script and kept-log suites, the wiring suite, the use case's | 0 | 20 of 20 green, 231 s |
| The same with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` | 0 | 20 of 20 green, 585 s |
| `LEDGER_TEST_LANE=nightly swift test … --filter LocalWorkoutSessionActorPerformanceTests`, once | 0 | passed with the budget moved to `PerformanceBudget` |
| `scripts/check.sh --lint-only` | **0** | format, `swiftlint --strict`, package graph, script tests; 61 s. No new suppression |
| `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file` | **0** | no warning; no symbol of `FakeWorkoutSessionClient`, `InMemoryStores`, `SplitMix64`, the stand-in or the scripts in a Release object |
| `scripts/check.sh` (full gate) | not run | the orchestrator's, as the brief says |

**For N10.** The Sync target took 14.5 to 22.5 s on the default pool, with the load, against 14.4 s at `677fc49`,
and 52 to 56 s on one thread. On one thread every test waits for all the others, and the suites' limit is one
minute, so the tests that span the run have a few seconds left there. Skipping the whole script suite took 5 s
off the one-thread run, so this round's share is small; the rest is S1's and S2's suites as they were. Nothing
timed out in any run.

#### Code lines

`count-lines.py` as before (`git diff -U0`, blank and whole-line comment lines excluded):

| | Against `48403f5` (the slice) | This round, against `677fc49` |
|---|---|---|
| Product | **+466 −18** (was +448) | +23 −5 |
| Test support | +500 −0 | +147 −70 |
| Tests, the tester's included | +6095 −7 | +205 −15 |

Under the stop line of about 550.

#### Not verified, and what I saw

- **The full gate, and anything on a simulator or a device.** Not run, as the brief says. The orchestrator runs it.
- **The two S1 tester tests that fail on one thread, at `677fc49`.** I could not build that commit without
  moving HEAD. That they are not this round's rests on S1's notes ("The one-thread check"), on their failing when
  the two suites run alone, and on their calling nothing this round changed.
- **N5's assertion** (no exit test), **N10** (no CI times), and **N7 on a phone**.
- **The repeated runs** are 20 per pool of nine suites, not the 60 of the first round, and on the host.
- **A start under a kept log that already holds an end** (the inputs for F17): reasoned from the code, not tested.
- A compiler warning in the tester's file, seen when the test target was recompiled:
  `Tests/LedgerSyncTests/Adversarial/RacyHostAdversarialSupport.swift:151`, "no 'async' operations occur within
  'await' expression". Not touched. A warning in a test target did not fail the first round's gates
  (`PayloadVersionAdversarialTests.swift:29` is in both of their logs).
- Nothing odd in shared state. Other lanes' builds kept the load average between 3 and 22 during the runs.
- No test helper process was left running.

### S2 — orchestrator's close (2026-10-05)

- The orchestrator's full gate on the fix round's tree exited 0. The tester's five tests pass and the tester's files
  are unchanged since `677fc49`, which was the tester's closing condition: **G2 is closed. G3 approved.**
- Known, not this slice's: on a one-thread pool two of S1's tester tests fail in every run (that tester's own
  overlap checks need a yield between calls, as the contract's got in S1's touch-up). Queued as a follow-up.
- Nit N10 is not taken (it needs CI timings); N8 is a note for F17.

## Slice S3 — orchestrator's brief (2026-10-05)

S2 merged as #29 (`6c5939d`). S3's specification is the brief's last section, "Plan amendments — slice S3".

- **O8 stands** (the program change is applied inside `materialize`; no `replaceSlotExercise`; no migration), with
  one addition from F05 S2's lesson: an update may only touch a slot of the workout's own program.
- **SF5 from S2's review is in scope:** the log is dropped in `materialize`'s transaction, and the host stops
  compacting after a save.
- **O10 is not in S3.** The swap event keeps its payload; S8 decides, and an ADR-004 change would go to Pete.
- **CI cost (criterion 9).** #29's macOS job took 38 minutes: the iOS build 1,148 s on a cold cache (a new branch
  restores nothing) and the iOS tests 998 s, against 570 s and 422 s for #27. The tests are the part this slice can
  cut. The step's deadline in `check.sh` is 2,400 s, so there is little room left.
- Some of S2's tests, the implementer's and the tester's, pin "the save succeeded and the compaction failed". Over
  the database that state goes away. The implementer's own tests are its to change; a tester's test that
  contradicts criteria 4 or 5 is not edited: it is listed with the criterion, and the tester moves it.

## Slice S3 — the persistence follow-up (G1 implementer, 2026-10-05)

On `95ac9b8`, in the worktree `F10-s3`, on `feat/F10-s3-program-updates`. Nothing is committed and no PR is open.
Paths are under `LedgerKit/` unless they start with `docs/`, `tasks/` or `scripts/`. Scratch files are in
`scratchpad/f10s3/` (written `f10s3/…` below). Short names: `Repositories` is
`Sources/LedgerDomain/Protocols/Repositories.swift`, `GRDB` `Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift`,
`Events` `Sources/LedgerPersistence/Events/GRDBWorkoutEventStore.swift`, `Recovery`
`Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift`, `Fake` `Sources/LedgerFakes/InMemoryWorkoutRepository.swift`,
`FakePrograms` and `FakeEvents` its neighbours `InMemoryProgramRepository.swift` and `InMemoryWorkoutEventStore.swift`,
`Linked` `Sources/LedgerTestSupport/Persistence/WorkoutRepositoryContract+Linked.swift`. The full gate was not run, as
the brief says: everything below is the Mac host's, plus two runs of two test targets on the iOS simulator for
criterion 9.

**Two things are not as the specification asks, and one tester test fails by ruling:**

1. **Criterion 9 is met for the suites I may change and not for the session suites as a whole.** The session
   suites cost 58.1 s before and 36.9 s after on the simulator: 64 %, not a third. The implementer's suites went
   from 25.7 s to 5.9 s (23 %). The tester's suites are 31 s of what is left, and I may not edit them. The
   figures and the edits they need are under "Criterion 9".
2. **`materialize(_:slotUpdates:)` stays on the protocol beside the new call** (decision 1): four tester types
   conform to `WorkoutRepository`, and a requirement they do not implement would stop their targets compiling.
3. `WorkoutRelaunchAdversarialTests.kill_afterTheSaveBeforeTheCompaction_compactsOnRelaunch` fails, as criteria 4
   and 5 say it must. It is under "Tester tests that now contradict a criterion".

### What landed

| File | Contents |
|---|---|
| `Sources/LedgerDomain/Protocols/Repositories.swift` | `materialize(_:slotUpdates:)`'s documentation: program updates are applied, and by which rule. New requirement `materialize(_:slotUpdates:droppingLog:) -> Bool` (`:87`) with its default (`:109-115`) |
| `Sources/LedgerDomain/Protocols/WorkoutEventStore.swift`, `WorkoutSessionClient.swift` | documentation only: who drops a finished workout's log; what `finish` stores in one transaction, and what a failed save leaves |
| `Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift` | both forms of `materialize` (`:55`, `:69`); `writeProgramUpdates` (`:205-247`) |
| `Sources/LedgerPersistence/Events/GRDBWorkoutEventStore.swift` | `deleteLog(of:in:)` (`:92`), the one statement `compact` and the save both run |
| `Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift` | `complete(_:)` (`:147-162`): one call that saves and drops; the compaction after it only when the repository answers that the log is still there |
| `Sources/LedgerFakes/InMemoryWorkoutRepository.swift`, `InMemoryProgramRepository.swift`, `InMemoryWorkoutEventStore.swift`, `InMemoryStores.swift` | the linked stores follow: `writeSave(misses:exercises:inProgram:)`, `drop(_:)`, the event store linked into the workout store |
| `Sources/LedgerTestSupport/Persistence/WorkoutRepositoryContract+Linked.swift` (new) | `linkedClauses` (six), `Program.difference(from:)`, three public fixtures |
| `Sources/LedgerTestSupport/Persistence/WorkoutRepositoryContract.swift` | `HistoryStores.events`, optional |
| `Sources/LedgerTestSupport/Engine/StoreProbe.swift` | `ProbedWorkoutRepository` forwards the new call |
| `Tests/LedgerPersistenceTests/WorkoutRepositoryLinkedTests.swift` (new) | the rows and statements of a save: 7 test functions, 12 cases |
| `Tests/LedgerPersistenceTests/LinkedSaveDifferentialTests.swift` (new) | seeded scripts, the linked fakes against GRDB: 30 seeds in the PR lane, every seed in the nightly one |
| `Tests/LedgerPersistenceTests/{InMemoryContractTests,WorkoutRepositoryTests,MigrationCompatibilityTests}.swift`, `Performance/RecordReplayPerformanceTests.swift`, `Performance/PerformanceBudget.swift`, `Support/RepositoryTesting.swift` | the linked clauses on both stores; an unlinked fake; the version-1 fixture; criterion 8's timing |
| `Tests/LedgerSyncTests/LocalWorkoutSessionActorSaveTests.swift`, `LocalWorkoutSessionActorProgramTests.swift` (new) | criterion 5 on the host: 4 and 5 tests |
| `Tests/LedgerSyncTests/LocalWorkoutSessionActor{End,Recovery,Contract}Tests.swift`, `WorkoutSession{ClientContract,ConcurrentScript}Tests.swift`, `Support/{HostSupport,Tags}.swift`; `Tests/LedgerAppKitTests/WorkoutRelaunchTests.swift` | changed: listed under "Tests changed" |
| `docs/architecture.md` | §5 (`WorkoutState.programUpdates`), §6 (the save, recovery, the `.materialize` comment), §7 (the `workout_event` row), §15 (the budget's row) |

Unchanged: `Migrations.swift`, every fixture under `Tests/LedgerPersistenceTests/Fixtures/`, `Package.swift`,
`package-graph.expected.txt`, `project.pbxproj`, every test plan, `scripts/`, ADR-004 and ADR-008, every file under
a `Tests/*/Adversarial/` folder (`git status --short | grep Adversarial` prints nothing), `tasks/todo.md`.

### Decisions and deviations

1. **The shape: a second requirement, `materialize(_:slotUpdates:droppingLog:) -> Bool`, with a default**
   (`Repositories:72-87`, `:109-115`).
   - *The parameter* is the ruling's. `droppingLog: true` asks for the save and the end of the log as one step.
   - *The answer* is whether the log went with the save. A repository knows whether it shares a database with
     the log; the host does not, and a flag on the host could disagree with its stores. So the path for a store
     that is not one database needs no configuration: such a repository answers `false`, and the host then
     compacts in a second step (`Recovery:157-161`), which is S2's path, row for row.
   - *The default* (`Repositories:109-115`) is that repository: it saves through `materialize(_:slotUpdates:)` and
     answers `false`. A wrapper that forwards only the old call therefore loses the one transaction and nothing
     else. `WorkoutEventStore.unreadableCount(for:)` has no default for the opposite reason: there a wrapper that
     did not forward would let the host drop rows it cannot see.
   - **Deviation: the old requirement stays.** One requirement with `droppingLog` and a convenience for the
     two-argument call would be smaller. Four types in tester files conform to `WorkoutRepository` and implement
     only the old call: `HistoryModel` (`Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:6`),
     `SiegeWorkoutRepository` and `SabotagedWorkoutRepository` (`Tests/LedgerSyncTests/Adversarial/HostSiegeStoresAdversarialSupport.swift:66`,
     `HostSiegeSabotageAdversarialSupport.swift:61`), `BriefWorkoutRepository`
     (`Tests/LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift:41`). Removing the requirement they
     implement stops three test targets compiling, and I may not edit them. Open question 4.
   - *Why the workout repository may delete event rows.* A workout's log is that workout before it was saved
     (ADR-004 rule 5), and the save is what ends its use, so "saved" and "log gone" are one fact, and two
     transactions make room for a third state, which is SF5. The repository drops that one log, on request,
     never reads an envelope and never writes one. Over GRDB it does not hold the SQL either: `compact` and the
     save both run `GRDBWorkoutEventStore.deleteLog(of:in:)` (`Events:92`, called at `GRDB:83`).
   - *What it does not do.* It does not check that the log is complete. The host still asks
     `unreadableCount(for:)` first (`Recovery:148`), in a read of its own, as before S3. Open question 7.
2. **The order of writes in the transaction** (`GRDB:75-85`): the workout's place in history (a read), its rows
   (workout, exercises, sets), its records, the misses, the program updates, the log.
   - Every refusal the protocol names is thrown before the misses are written. What comes after never refuses:
     it skips, and logs at notice level. So a refused workout has changed no slot and dropped no log even before
     the rollback.
   - Anything that fails later (a full disk; in the tests a trigger on `slot_miss`, on `slot.exercise_id` or on
     `workout_event`) rolls all of it back: `lateFailure_rollsEverythingBack` compares every row of ten tables.
   - The log goes last so that a log is never dropped ahead of a statement that can still be refused. Mutant G9
     (the log first) is seen only by the statement order, which `save_isOneTransaction_inOrder` pins.
3. **Which update is applied** (`writeProgramUpdates`, `GRDB:205-247`). An entry is applied when its slot is
   live, under a live day, of the workout's own live program (`source.programID`), and its exercise has a row.
   - *Another program's slot* is never written. This is the class of F05 S2's B1 (a save that silently took over
     another program's rows): a workout of block 1 that is saved late must not rewrite block 2. The check is one
     query that joins `slot`, `day_template` and `program` (`GRDB:216-222`) and reads no id out of the database.
   - *The exercise* is checked as a program save checks it (`ProgramRows.refuseUnknownExercises`): the row
     exists, deleted or not, which is what the slot's foreign key asks. Without the check the update would fail
     the foreign key and with it the whole save.
   - *An ad-hoc workout* has no program, so every entry is skipped.
   - *The active program plays no part.* A swap lands on the workout's program whether or not it is the active
     one. The misses differ: the host sends none when another program is active (S2, ruling O9).
     `finish_anotherProgramActive_changesTheWorkoutsProgram` pins both.
   - *What is written:* `slot.exercise_id` and that row's `updated_at`. The slot's numbers, its misses and the
     program's own row are untouched (Pete's default 2: a program swap keeps the slot's numbers).
   - *A slot that already holds the exercise* is not written at all (`GRDB:231-233`), so a second materialisation
     still runs no `INSERT` and no `UPDATE`, as F05's decision 1 says.
   - *Two updates for one slot* cannot be given: `programUpdates` is a dictionary, and the engine keeps the
     latest swap of a slot. Entries are applied in slot-id order, so the statements run in one order.
4. **Idempotence.** Materialising the same workout again changes no row of any table, with the log gone or
   there again (`secondSave_writesNoRow`; the contract's `programUpdatesTwice` on both stores).
   - It is not idempotent against a program that was edited in between: a second materialisation sets the slot
     back to the workout's swap, as re-sent slots would clear misses recorded since (F10 "Inputs from F05",
     item 6). Over the database nothing materialises a workout twice any more, because no log is left to do it
     from. Open question 2.
   - A workout read from history has no `programUpdates` (a live-only field, reset on a read), so storing one
     again never touches a program.
5. **The host** (`complete(_:)`, `Recovery:147-162`): `unreadableCount`, the misses from the program as stored
   now, then one call that saves and drops. It returns at once when the repository answers that the log went
   with the save, and compacts otherwise. A discarded workout's log is compacted as before. Nothing else in the
   host changed: the waiting end, `settle()`, `reconcile()` and `needsRecovery` are S2's. The tables below say
   what each call now does.
6. **The fakes** (ADR-008 decision 5).
   - `InMemoryWorkoutRepository` writes the misses and the program updates, and drops the log, inside its own
     write, after the last statement that can throw (`Fake:52-67`): all or nothing, in the database's order.
   - The program store takes both in one step, `writeSave(misses:exercises:inProgram:)` (`FakePrograms:81-93`),
     so that store never holds half of a save.
   - **`InMemoryWorkoutEventStore` keeps its logs behind a `Mutex`, and is still an actor** (`FakeEvents:13`,
     `drop(_:)` at `:73`). A write under a lock cannot wait for an actor, and a save that awaited the event
     store after its own write would let a reader see the workout in history with its log still there, which is
     the state this slice removes. ADR-008 decision 4 says the event store "stays an actor"; it does, so the ADR
     is not edited. An actor whose state sits behind a lock is a class in all but name. Open question 3.
   - *Lock order:* history, then programs, then exercises; history, then events. Never the other way.
   - *What the fake cannot give.* The programs and the log change under their own locks, inside the history's
     write. A reader that reads history never sees half a save. A reader that reads only the programs and the
     log, at that instant, can see the program changed and the log still there. One lock over the six stores
     would close it; I did not rebuild the fakes for it.
   - A stand-alone `InMemoryWorkoutRepository()` holds no log, answers `false`, and its programs check no
     exercise, as before (`unlinkedWorkouts_holdNoLog`).
7. **The contract: a third list, `linkedClauses`** (`Linked:12-35`), beside `clauses` and `storageClauses`.
   F05's oracle `HistoryModel` runs `clauses` (`HistoryContractAdversarialTests.swift:15`) and models neither a
   slot's exercise nor the log, as it does not model columns. `HistoryStores.events` is optional for the same
   subject.
8. **The differential scripts.** The three that exist are tester files (`Fakes{History,Store,Catalog}DifferentialAdversarialTests`).
   They pass unchanged. I added one of my own, `LinkedSaveDifferentialTests`, for the saves this slice changed.
9. **Criterion 9 by a lane check in the test target, not by a plan change** (`Tests/LedgerSyncTests/Support/Tags.swift:19-26`,
   `WorkoutSessionClientContractTests.swift:29`). No test plan, no `project.pbxproj` and no environment
   variable changed.
10. **ADR-004 rule 5 still reads "compacted after successful materialisation".** Over the database it is now
    "with". ADR-004 is not edited (an ADR change is Pete's to review). Open question 5.
11. **A failing test prints a line, not the values.** The new clauses and suites compare to a `Bool` or a count
    and name what differs (`Program.difference(from:)`, `Linked:38-66`; `difference` in the two row suites), as
    the orchestrator asked during the slice. `WorkoutRelaunchTests` compared every row of six tables inside
    `#expect`; it no longer does.

### Criteria → tests

| # | Tests |
|---|---|
| 1 | `linkedClauses`: `appliesProgramUpdates`, `observersHearTheSave` (GRDB and fakes); `WorkoutRepositoryLinkedTests`: `save_isOneTransaction_inOrder`, `programUpdate_writesTwoColumnsOfOneRow`; host: `LocalWorkoutSessionActorProgramTests` (5) |
| 2 | `linkedClauses.skipsWhatCannotBeApplied`; `estrangedSlot_isSkipped` (× 4: a deleted slot, a deleted day, a deleted program, another program's), `whatCannotBeApplied_writesNoSlot` |
| 3 | `linkedClauses.programUpdatesTwice`; `secondSave_writesNoRow`; `savedLog_isSavedAgainAndDropped` (× 2); `logLeftBehindASavedWorkout_isSavedAgainUnchanged` (a real file, seven tables) |
| 4 | `linkedClauses`: `dropsTheLog`, `refusedSaveChangesNothing`; `lateFailure_rollsEverythingBack` (× 3), `refusedWorkout_rollsEverythingBack`; `saveThatCannotDropTheLog_savesNothing` (a real file) |
| 5 | `LocalWorkoutSessionActorSaveTests` (4); `LocalWorkoutSessionActorEndTests`: `finish_storesThenSavesAndDropsInOneStep`, `finish_publishesAfterTheSave` (× 3), `finish_saveFails_secondFinishRetries` (× 2); `LocalWorkoutSessionActorRecoveryTests`: `finishedLog_isSavedAndDropped` (× 2); `WorkoutRelaunchTests` (6); the host's contract and concurrent scripts in all six set-ups |
| 6 | the six linked clauses on `InMemoryStores` (`workouts_keepTheLinkedClauses`); `LinkedSaveDifferentialTests` (30 seeds, every seed of the lane in the nightly one; `scripts_holdEveryKindOfStep`); `unlinkedWorkouts_holdNoLog`; the tester's three differential suites, unchanged |
| 7 | `MigrationCompatibilityTests.open_savesWithAProgramUpdateAndTheLogDropped` (the version-1 fixture, and the applied migrations after it); `fixture_isAtV001` and `SchemaTests`, unchanged; no migration and no fixture in the diff |
| 8 | `RecordReplayPerformanceTests.finishWithProgramUpdatesAndTheLog_underBudget`, nightly lane only |
| 9 | `Seeds.hostSeeds`; the figures below |

### Mutants

`f10s3/mutants.py`, logs `mutants1.log` and `mutants2.log`: each applied alone, the named suites run, the file put
back and compared byte for byte. **24 of 26 fail at least one test.**

| Mutant | Killed by (first) |
|---|---|
| G1 any stored slot takes the update, whatever its program | `estrangedSlot_isSkipped`, the GRDB linked clause, the differential |
| G2, G3, G4 a deleted slot, a slot under a deleted day, a slot of a deleted program takes it | `estrangedSlot_isSkipped`, each by its own case and by no other test |
| G5 the exercise is not checked | `whatCannotBeApplied_writesNoSlot`, the linked clause, the differential |
| G6 a slot that holds the exercise is written again | `secondSave_writesNoRow` |
| G7 the log is never dropped and the answer is yes; G10 every log is dropped | 7 tests each |
| G8 the log is dropped whatever was asked | the linked clause, the differential |
| G9 the log is dropped before the workout's rows | `save_isOneTransaction_inOrder` alone |
| G11 the answer is always no | 6 tests |
| G12 the program updates are not applied | 8 tests |
| G13 the log is dropped in a transaction of its own, after the save | `saveThatCannotDropTheLog_savesNothing`, `save_isOneTransaction_inOrder`, `lateFailure_rollsEverythingBack` |
| F1 the fake changes any program's slot; F3b an ad-hoc workout's; F2 it checks no exercise | the fake's linked clause, the differential |
| F4 the fake never drops the log and answers yes | 19 tests |
| F5 the fake drops the log whatever was asked; F6 it writes the program and drops the log before the workout can be refused | the fake's linked clause, the differential |
| F7 the fake applies no program update | 8 tests |
| H1 the host compacts after every save; H3 it saves without dropping the log | 7 and 8 tests |
| H2 the host never compacts after a save; D1 the protocol's default answers that it dropped the log | 31 tests each, the tester's siege suites among them |
| **F3 the fake changes a deleted program** | **survives.** The protocol cannot show a deleted program, and saving it again replaces it whole. The database's rule is G4, killed at the row |
| **F8 the fake writes the misses and the exercises in two steps** | **survives.** A stream keeps its newest value, so only a reader racing the save could see the half; I wrote no test that rests on a race |

H2 and D1 also hang one test for good: `finish_publishesAfterTheSave` holds `.compact`, which never comes, and
`StoreProbe.waitUntilHeld()` cannot be cancelled by a time limit. I stopped the helper by hand both times. It is how
the first run of this slice lost ten minutes. Open question 8.

### The failure table

What changed since S2 is in bold. "The database" also means the linked in-memory stores.

| Step that fails | Memory | Store | Caller | Subscribers | Retry | Relaunch |
|---|---|---|---|---|---|---|
| append, any event | unchanged; marked unrecovered | nothing (rolled back) | the store's error | nothing | reads the store first; the same `seq` and stamp when nothing was stored | replay |
| append that stored and then threw (a store that lies) | unchanged; marked unrecovered | the envelope | the store's error | nothing, until the next call | the next call adopts what is stored and publishes it without a haptic; an end is completed | replay |
| the clock is not finite | unchanged | nothing | `noFiniteStamp`, a fault logged | nothing | works once the clock reads a time | — |
| **the save, after `.finished` is stored: one transaction** (`finish_saveFails_secondFinishRetries` × 2, `lateFailure_rollsEverythingBack` × 3, `saveThatCannotDropTheLog_savesNothing`, `finish_saveFails_theProgramWaitsWithTheWorkout`) | `live` as before the finish; the end pending; clock and `seq` advanced | **the log whole, with its `finished`; no history row, no miss, no program change** | the store's error | nothing; `current()` still the workout | `finish`: saves **and drops** in one transaction, publishes once, returns the state ended at the first date. `apply`, `discard`: complete it, then `noLiveWorkout`. `start`: `workoutInProgress`. Foreground: the step, no haptic | saved by the step; nothing live meanwhile |
| **the save that stored and then threw (a store that lies; `finish_saveAnswerLost_theRetryEndsIt`)** | the same | the workout in history, the log gone | the store's error | nothing; `current()` still the workout | `finish`: saves again (no change), publishes once | nothing live, nothing to do |
| `compact`, after the save: **only over stores that are not one database** (`finish_separateStores_compactFails_waitsAndRetries`; the tester's siege suites) | the same | the log, and the history row with its misses and program changes | the store's error | nothing | saves again (no change), compacts, publishes once | saved again unchanged, compacted |
| `compact`, after `.discarded` | the same, a discard pending | the log | the store's error | nothing | `discard`: compacts, publishes. `finish`: completes it, then `noLiveWorkout` | compacted |
| a read during recovery | as before the pass | untouched | the store's error, from every call | a stream starts with what is known | the next call or foreground runs the pass again | — |
| a save during recovery | the other logs dealt with; the live one resumed | that log kept whole, **and nothing of its save** | the step throws; a protocol call does not | — | the next foreground | the next launch |

What each call does now, over the database:

- **`finish`:** stores `finished`; then one transaction; then the ending update. After the transaction nothing
  is left that can fail, so `finish` never throws for a workout that is in history
  (`finish_oneDatabase_neverThrowsOnceSaved`: a compaction made to fail a hundred times is never reached).
- **A second `finish`:** `noLiveWorkout` when the first succeeded; the retry of the whole transaction when the
  first save failed.
- **`discard`:** unchanged: stores `discarded`, compacts in the event store's own transaction, publishes. No
  program changes. A `discard` while a finish waits still saves the workout (S2, SF2).
- **The launch step and a relaunch:** the table below.

### The recovery table

| Stored when the app died | The step | Afterwards |
|---|---|---|
| nothing, or a `started` that never reached the store | nothing | no workout |
| a live log | resumes it: no haptic, no effect run | `current()` is the workout |
| `finished` stored, not saved | **one transaction:** saves, with the misses from the program as stored now and the program updates, and drops the log | in history; no live workout |
| **saved, and the log still there** | saves again, which changes nothing, and drops the log, **in one transaction over the database** | the same |
| `discarded` stored, not compacted | compacts | nothing in history, no program changed |
| a log that replays to nothing | keeps it and logs a notice | no workout |
| a log with rows this version cannot read | live: resumes from what it reads; ended: keeps it | a workout, or none |
| a save that throws | keeps the log whole; nothing is saved; records the step as failed; carries on with the other logs | retried on the next foreground |

The fourth row is the one criterion 5 speaks of. The host no longer produces it over the database. It is still
handled, for two sources: a workout repository that does not hold the log (the protocol's default; every store
of the tester's siege), and a database left so by a build from before this slice. Both are tested
(`savedLog_isSavedAgainAndDropped` × 2; `logLeftBehindASavedWorkout_isSavedAgainUnchanged` on a real file).

### Tests changed, with reasons

All are S2's implementer tests or F05's and F07's implementer tests and support. No tester file is touched.

| File | Change | Why |
|---|---|---|
| `Tests/LedgerSyncTests/Support/HostSupport.swift` | `Subject.init(oneDatabase:)`; `SeparateWorkoutRepository`, which forwards every call but the new one | the two-step path needs a store that is not one database (criterion 5) |
| `LocalWorkoutSessionActorEndTests.swift` | `finish_storesThenSavesThenDrops` → `finish_storesThenSavesAndDropsInOneStep`: the writes are `[.append, .materialize]`, were `[.append, .materialize, .compact]` | criterion 5 |
| | `finish_publishesAfterTheSave`: its cases were `.materialize` and `.compact` on linked stores; now `.materialize` on both kinds of store and `.compact` on separate stores | over one database no compaction follows a save, so a held `.compact` never arrives |
| | `finish_saveFails_secondFinishRetries`: runs on both kinds of store | the row is the same on both |
| | `finish_compactFails_waitsAndRetries` → `LocalWorkoutSessionActorSaveTests.finish_separateStores_compactFails_waitsAndRetries`, on separate stores, assertions unchanged | the row exists only there (criterion 5) |
| `LocalWorkoutSessionActorRecoveryTests.swift` | `finishedLog_isSavedThenDropped` → `finishedLog_isSavedAndDropped` (× 2): `[.materialize]` over one database, `[.materialize, .compact]` over separate stores | criterion 5 |
| | `savedLog_isSavedAgainAndDropped`: on both kinds of store, and it asserts that nothing is left to recover | the row is handled for both |
| `LocalWorkoutSessionActorContractTests.swift`, `WorkoutSessionConcurrentScriptTests.swift`, `WorkoutSessionClientContractTests.swift`, `Support/Tags.swift` | the two host matrices take `Seeds.hostSeeds`; `TestLane.isNightly` | criterion 9. No assertion changed |
| `Tests/LedgerAppKitTests/WorkoutRelaunchTests.swift` | `killedBeforeTheDrop_isSavedAgainUnchanged` is replaced by `saveThatCannotDropTheLog_savesNothing` and `logLeftBehindASavedWorkout_isSavedAgainUnchanged`; both workouts now hold a swap with the program; `rows()` reads `slot` too | the kill point "after the save, before the drop" is gone (criteria 4 and 5): a drop that fails takes the save with it. The second test keeps what the old one showed, from a log put back beside the saved workout |
| `Tests/LedgerPersistenceTests/Support/RepositoryTesting.swift`, `InMemoryContractTests.swift` | `Repositories.events`; `history` and `history()` hand the event store to `HistoryStores` | the linked clauses need the log |
| `Sources/LedgerTestSupport/Persistence/WorkoutRepositoryContract.swift` | `HistoryStores.events`, optional, `nil` by default | the same; the tester's `HistoryStores(workouts:stats:programs:)` still compiles |
| `Sources/LedgerTestSupport/Engine/StoreProbe.swift` | `ProbedWorkoutRepository` forwards `materialize(_:slotUpdates:droppingLog:)` under `.materialize` | a host over probed stores of one database must still get the one transaction |

### Tester tests that now contradict a criterion

**One fails, and is left failing.**

`Tests/LedgerAppKitTests/Adversarial/WorkoutRelaunchAdversarialTests.swift:77-92`,
`kill_afterTheSaveBeforeTheCompaction_compactsOnRelaunch`, at `:85` (`saved.count == 1`) and `:89`
(`relaunched.history() == saved`).

- *What it does:* it refuses `DELETE ON workout_event` with a trigger, expects `finish` to throw with the workout
  already in history, and expects the relaunch to compact.
- *What contradicts it:* criterion 4 ("when it fails, nothing changed: no history row, no program change, the log
  whole") and criterion 5 ("over the database a workout can no longer be in history and still shown as live").
  The trigger now fails the one transaction, so the save is rolled back with the drop.
- *The change it needs,* either of two:
  - keep the kill point and assert what is now right: `:85` becomes `#expect(saved.isEmpty)`, and `:89` becomes
    `#expect(try await relaunched.history() == [Launch.asStored(finished)].compactMap(\.self))` with
    `finished = Launch.folded(Launch.middle + [.finished(endedAt: Launch.end)])`, as the test above it has; the
    title becomes "A finish whose log cannot be dropped saves nothing; the relaunch saves and compacts";
  - or keep the row "saved, log still there" and build it without the host: let the first relaunch save, append
    the finished log again with `stores.events.append`, relaunch, and compare. My
    `logLeftBehindASavedWorkout_isSavedAgainUnchanged` does this.

**None other fails, but the tester should know why.** `SiegeWorkoutRepository` and `SabotagedWorkoutRepository`
implement only `materialize(_:slotUpdates:)`, so every host of the tester's siege gets the protocol's default and
takes the two-step path, over the in-memory backing and over the GRDB one alike. Their tests of a compaction
that fails after the save (`HostEndFailureAdversarialTests.finish_compactionFails_savedOnceAndEndedOnce`,
`HostMissesRetryAdversarialTests`, `HostStartUseCaseAdversarialTests:107`, the siege's `.compact` faults) pass
because of that, and they now test a store that is not one database. Nothing in the tester's Sync suites
exercises the one transaction. To siege it, the two wrappers forward the new call; the `.compact` faults after a
save then stop firing, and the tests that inject them need a wrapper that does not forward. That is the
tester's choice to make.

### Criterion 9: before and after

**How it was measured.** `f10s3/measure.sh <label>`, through the lock, from the worktree root:
`/usr/bin/python3 <sim-lock> f10s3/measure.sh before` on the tree at `95ac9b8`, and `… after` on the tree with
the slice. The script boots the iPhone 17 simulator (iOS 27.0), runs `xcodebuild build-for-testing` and then
`test-without-building` with `-testPlan PR -only-testing:LedgerSyncTests -only-testing:LedgerPersistenceTests` and
`check.sh`'s flags (`-parallel-testing-enabled NO`, timeouts on, 60 s allowance). `f10s3/suites.py` sums, per
suite, the durations of its test runs in the result bundle; the tests run one after another, so the sum is the
time (135 test-seconds of a 141 s test operation in the first run).

| | Before | After |
|---|--:|--:|
| The test step, both targets | 145 s | 120 s |
| `LedgerSyncTests` | 58.5 s, 4,633 runs | 37.3 s, 2,485 runs |
| `LedgerPersistenceTests` | 76.5 s, 4,418 runs | 77.1 s, 4,474 runs |
| Load average when the tests started | 68.6 | 13.8 |

The first run started under another lane's load. It mattered little: the tester's suites, which did not change,
took 32.3 s in it and 31.0 s in the second. The second run was taken before two small changes (the fake's
one-step program write, one more contract clause), so I ran a third on the final tree, at a load of 4.6
(`f10s3/final.xcresult`): 122 s for the step, `LedgerSyncTests` 37.3 s in 2,485 runs, the session suites 36.9 s,
`LedgerPersistenceTests` 75.8 s in 4,476 runs, both targets passing. The slice's own new suites cost 1.4 s
there, 1.3 s of it the differential's 30 scripts. Per session suite (every suite of `LedgerSyncTests` but the
`FakeLinkBus` and companion-session ones):

| Suite | Whose | Before | After |
|---|---|--:|--:|
| `LocalWorkoutSessionActor · the contract` | implementer | 14.7 s, 1,350 runs | 2.1 s, 270 runs |
| `Adversarial F10 S2 · never lost, never doubled` (`HostNeverLostAdversarialTests`) | tester | 12.6 s, 304 | 12.1 s, 304 |
| `WorkoutSessionClient · calls made at once, as one history` | implementer | 9.3 s, 1,415 | 2.0 s, 335 |
| `Adversarial F10 S1 · does the session contract bite` | tester | 4.7 s, 145 | 4.7 s |
| `Adversarial F10 S2 · does the concurrent script bite` | tester | 4.1 s, 17 | 3.7 s |
| `Adversarial F10 S2 · the contract over this suite's stores` (`HostContractRunAdversarialTests`) | tester | 3.8 s, 202 | 3.6 s |
| `Adversarial F10 S1 · the contract after the fix round` | tester | 3.3 s, 39 | 3.3 s |
| `Adversarial F10 S2 · many callers at once` (`HostReentrancyAdversarialTests`) | tester | 1.6 s, 185 | 1.5 s |
| `WorkoutSessionClient · the contract notices a faulty client` | implementer | 0.9 s, 57 | 1.0 s |
| `Adversarial F10 S1 · fake session vs the engine` | tester | 0.8 s, 201 | 0.8 s |
| `WorkoutSessionClient · the contract on the fake` | implementer | 0.7 s, 227 | 0.7 s |
| every other session suite | both | 1.6 s | 1.4 s |
| **The implementer's session suites** | | **25.7 s** | **5.9 s (23 %)** |
| **The tester's session suites** | | 32.3 s | 31.0 s |
| **All session suites** | | **58.1 s** | **36.9 s (64 %)** |

**What was cut.** The two matrices of seeds by host set-ups: `sessionScripts_fakeAndActorPublishTheSame` and
`host_isOneHistory`, each 200 seeds × 6 set-ups in the PR lane, now 20 × 6. The twenty are the fixed seeds, which
existing tests show to reach every call and every refusal (`scripts_reachEveryCallAndRefusal`), every kind of
action (`scripts_holdEveryKindOfAction`) and every overlap fault (`overlapFault_breaksAScript`). The nightly lane
runs every seed of the lane on every set-up, as before: `TestLane.isNightly` reads `LEDGER_TEST_LANE`.

**What still runs once or more in the PR lane.** Every clause on every set-up (144 cases, and `violations` on
each set-up); every kind of store (in-memory, GRDB, suspending), each recovered at launch and not, on 20
sequential and 20 concurrent scripts; every fault of the stand-in, by clause and by script; the fake's 200
sequential and 200 concurrent scripts. No assertion changed.

**Why it is not a third.** The tester's suites were 56 % of the cost before, and no cut of mine reaches them:
with the implementer's suites at zero the whole would still be 53 %. The edits that would get there, which I did
not make:

| Tester suite | Edit | Saves, about |
|---|---|--:|
| `HostNeverLostAdversarialTests` | the PR lane sieges 20 seeds in memory and 20 over GRDB, where it sieges `SeamSeed.all` (200) and `.prefix(100)`; the nightly lane keeps both | 9.5 s |
| `HostContractRunAdversarialTests` | `.prefix(10)` in the PR lane, where it has `.prefix(40)` | 2.7 s |
| `HostReentrancyAdversarialTests` | 30 and 15 storms in the PR lane, where it has 120 and 60 | 1.1 s |

That gives about 23.6 s, 41 %. The last eight points are in the three "does it bite" suites (11.7 s for 201
runs), which run each fault many times over until it strikes; I have not read them closely enough to name a cut.

### Code lines

`f10s3/count-lines.py 95ac9b8` (S2's script): added lines of `git diff -U0 95ac9b8`, new files whole, blank and
whole-line comment lines excluded.

| File | Added | Removed |
|---|--:|--:|
| `Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift` | 50 | 0 |
| `Sources/LedgerDomain/Protocols/Repositories.swift` | 9 | 0 |
| `Sources/LedgerPersistence/Events/GRDBWorkoutEventStore.swift` | 7 | 6 |
| `Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift` | 4 | 1 |
| `Sources/LedgerDomain/Protocols/WorkoutEventStore.swift`, `WorkoutSessionClient.swift` | 0 | 0 |
| **Product** (the brief: about 50 to 90) | **70** | 7 |
| `Sources/LedgerFakes/InMemoryWorkoutEventStore.swift` | 28 | 20 |
| `Sources/LedgerFakes/InMemoryProgramRepository.swift` | 27 | 11 |
| `Sources/LedgerFakes/InMemoryWorkoutRepository.swift` | 20 | 2 |
| `Sources/LedgerFakes/InMemoryStores.swift` | 2 | 2 |
| **`LedgerFakes`** (the plan: about 20) | **77** | 35 |
| `LedgerTestSupport` (3 files) | 247 | 1 |
| Tests (19 files) | 780 | 53 |

The fakes are well over the plan's twenty lines. The plan counted the program update alone. The log's drop
needed the event store's state behind a lock (28 lines, 20 of them the old ones rewritten), and the one-step
program write another 16.

### Host runs, lint, Release build

On the final tree. `env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file
--skip-build --filter '^(LedgerSyncTests|LedgerDomainTests|LedgerAppKitTests|LedgerPersistenceTests|LedgerDependenciesTests)\.'`,
once as it is and once with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` (`f10s3/final-default.log`,
`f10s3/final-onethread.log`). At `95ac9b8` the default pool gave 244, 452, 838, 63 and 63 tests, all passing
(`f10s3/host-baseline-default.log`).

| Target | Default pool | One thread |
|---|---|---|
| LedgerSyncTests | 252 tests in 45 suites, passed (13 known issues, S1's) | 252 tests, **2 issues**: S1's two tester tests, below |
| LedgerPersistenceTests | 466 tests in 106 suites, passed (1 known issue) | the same |
| LedgerDomainTests | 838 tests in 138 suites, passed | the same |
| LedgerDependenciesTests | 63 tests in 11 suites, passed (17 known issues) | the same |
| LedgerAppKitTests | 64 tests in 15 suites, **1 failing**: the tester's test above | the same |
| Exit | **1** | **1** |

- The one-thread failures are `SessionContractBiteAdversarialTests.swift:111` and
  `SessionContractRoundTwoAdversarialTests.swift:116`, the two the brief names. Nothing else fails there.
- Eight tests are new in Sync, fourteen in Persistence and one in AppKit.

| Command | Exit | Result |
|---|---|---|
| The full matrix on the host: `LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=200 swift test … --filter 'LocalWorkoutSessionActorContractTests\|WorkoutSessionConcurrentScriptTests\|WorkoutSessionClientContractTests\|LinkedSaveDifferentialTests'` | 0 | 144 clause cases, 1,200 sequential and 1,200 concurrent scripts on the host, 200 differential scripts; the same on one thread |
| `stress.py 20 '<seven host suites>' LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=200`: the contract, the concurrent scripts, the serial, end, save, recovery and program suites | 0 | 20 of 20 green, 173 s |
| The same with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` | 0 | 20 of 20 green, 432 s |
| `LEDGER_TEST_LANE=nightly swift test … --filter RecordReplayPerformanceTests`, once | 0 | criterion 8 on the Mac host, Debug: the finish save with 2 program updates, 5 misses and a log of 60 dropped, at the end of 400 workouts and 20,000 sets: p95 16.0 ms, median 10.7 ms, against 50 ms. The plain save beside it: p95 14.9 ms, median 9.7 ms (`f10s3/attachments/finish-save.txt`) |
| `scripts/check.sh --lint-only` | **0** | format, `swiftlint --strict`, package graph, pins, script tests. No new suppression |
| `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file` | **0** | no warning; no symbol of `InMemoryStores`, `InMemoryWorkoutEventStore`, `InMemoryWorkoutRepository`, `InMemoryProgramRepository`, `FakeWorkoutSessionClient`, `SplitMix64`, `FakeLinkBus` or `Fixtures` in a Release object; `Release/LedgerFakes.o` is 1,176 bytes, as at S1 and S2 |
| `scripts/check.sh` (full gate) | not run | the orchestrator's |

### Open questions

1. **Criterion 9 is at 64 %, not a third.** Recommendation: the tester makes the three cuts in the table (about
   41 %), with the same lane check, and looks at the "bite" suites for the rest; or the orchestrator sanctions
   those edits as it sanctioned the launch model's in S2. Lowering `LEDGER_PROPERTY_SEED_COUNT` in the PR plan would
   also cut the Domain's and the persistence suites' seeds, which nobody asked for.
2. **A second materialisation sets a slot back if the program was edited in between.** Recommendation: accept
   for M1. Over the database no log is left to materialise from. F17's rebuilds decide it with the misses' rule
   (never re-send an older workout's slots), and F11 should know that a swap can land on a program edited during
   the workout: the slot's exercise is the swap's, its other fields the edit's.
3. **`InMemoryWorkoutEventStore` is an actor with its state behind a `Mutex`.** Recommendation: a mechanical
   follow-up that makes it a final class like the other fakes, with one sentence of ADR-008 decision 4 amended.
   No caller changes: every call is already awaited.
4. **Two forms of `materialize` on the protocol.** Recommendation: keep both. The default is the honest answer
   of a store that holds no log, and it is what keeps every wrapper safe. If one requirement is wanted, the four
   tester types need a two-line forward each.
5. **ADR-004 rule 5** says the log is "compacted after successful materialisation". Recommendation: one line, with
   the paragraph on a waiting end that S2's rulings already owe ADR-004, in a PR Pete reviews.
6. **A skipped program update is silent.** The log says which slot and why; the lifter is told nothing.
   Recommendation: S8 decides. It happens only when the program was edited or deleted during the workout.
7. **The completeness check and the drop are two reads apart** (`Recovery:148`, then the transaction).
   Recommendation: leave for M1, where only the host writes the log and it takes one operation at a time. F17,
   which appends a peer's envelopes, keeps those appends in the host's queue, or moves the check into the
   transaction.
8. **`StoreProbe.waitUntilHeld()` waits for ever when the held call never comes,** and a time limit cannot
   cancel it. Under xcodebuild the 60 s allowance ends the runner; under `swift test` nothing does.
   Recommendation: about eight lines in `StoreProbe` that resume the waiter on cancellation, in the next change
   to that file.
9. **The fake's programs and log are not under the history's lock for a reader that reads only those two**
   (decision 6). Recommendation: leave; say so in ADR-008 when it is next amended.

### Inputs for S4, S7, S8 and F13

Corrected in place in fix round 1 (2026-10-05), as S2's inputs were: S7's sentence on what `finish` may throw and
its "Discard" line, S8's compare-and-set bullet (review S3-SF2) and its last bullet (S3-N6, which was wrong), and
F17's rule for a peer's or a rebuilt workout.

- **S4.** Nothing new to call. When `finish` returns, or its update arrives, the workout is in history, the
  program holds its swaps and the log is gone, all at once. The Debug "Start sample workout" row still needs a
  new workout id for every start.
- **S7.**
  - A failed save leaves nothing half done: no row, no miss, no program change. "Try again" is still `finish`,
    it retries the whole transaction, and it keeps the first end date. S2's three consequences of a waiting end
    stand unchanged, and so do its two open questions.
  - Over the database the call that saves a workout does not throw once the workout is in history, so the
    receipt may read history as soon as `finish` returns. (It would take the host's look at its event store and
    the compaction that answers a failed look to fail one after the other, right after a save that succeeded.)
  - "Discard" after a failed save saves the workout **and** changes the program, as a waiting finish is
    completed first. Decide with Pete's question on abandoning a workout that cannot be saved.
  - `FakeWorkoutSessionClient` stores nothing: a test that the program changed at Finish needs the host over
    `InMemoryStores`, as `LocalWorkoutSessionActorProgramTests` does.
- **S8.**
  - A swap with `alsoUpdateProgram: true` records `programUpdates[slotID]`; the program changes when the
    workout is saved, and never when it is discarded (Pete's decision 1, default A).
  - Only an exercise with a `slotID` can record one (`Sources/LedgerDomain/Engine/WorkoutEngine+Reduce.swift:150`):
    hide the toggle for an ad-hoc workout, or it does nothing.
  - **A later swap of the same slot with the toggle off does not clear the earlier entry** (the same line: the
    entry is only ever written). Bench to dumbbell bench with the toggle on, then to incline with it off, saves
    a workout that did incline and a program that says dumbbell bench. It is the engine's rule (F04), not this
    slice's; decide it with O10.
  - **Make the swap compare-and-set, with O10** (review S3-SF2). Today an entry is applied by every
    materialisation, whenever the slot does not already hold its exercise. So a save that lands after the lifter
    changed that slot (a waiting end completed days later, a retry, a rebuild) sets the slot back to the swap's
    exercise, with no log line: the lifter's later choice is replaced by an older one. The protocol says so now,
    and the contract pins it (`linkedClauses.laterSaveSetsTheSlotBack`). The cure: the swap carries the exercise
    the slot held when the lifter swapped, `programUpdates[slot]` becomes that pair, and an entry is applied
    only while the slot still holds the first of the two. The write is then safe at any time and in any order.
    In the repository it is one more bound value in a query that already reads the slot's exercise
    (`writeProgramUpdates`), the same in the fake, and the clause turns round. It changes an engine payload,
    which is why it goes with O10.
  - The slot keeps its sets, reps, loads and misses (Pete's decision 2, default A), and this workout's miss is
    recorded on it, judged on the replacement's sets against the targets the swap kept.
  - The update goes to the workout's own program even when another is active; the misses do not (ruling O9).
  - `observeActive()` emits the program once the save has changed it (`linkedClauses.observersHearTheSave`), so
    Today's next session follows without a reload.
  - The replacement must have a row: an update naming an exercise with none is skipped. A soft-deleted exercise
    keeps its row, so an update naming one is applied, as a program save accepts it
    (`ProgramRows.holdsExercise(_:in:)`, the one rule for both). No call deletes an exercise today.
  - Nothing tells the lifter that an update was skipped (open question 6).
- **F13.**
  - Over the database a saved workout has no log, so the phone's own finish can no longer bring back a workout
    History deleted, or overwrite `updateSets` edits (F17 "Inputs from F05", S3). One exception in this
    process: a save that committed and was answered as a failure is saved again from memory at the next call or
    foreground. The hazard remains for F17's rebuilds from a peer's envelopes.
  - `delete(id:)` does not undo a program change or a miss: both belong to the program.
  - Storing a workout that was read from history never touches a program (decision 4): it has no
    `programUpdates`.
  - A stored workout's exercise row carries the swapped exercise's id and name with the original's equipment
    and step. That is O10, not decided here.
- **F17.**
  - **The rule for a peer's or a rebuilt workout** (review S3-SF2; for the ADR-004 amendment). A
    materialisation is not free to repeat: each one writes the misses and the program updates again, on the
    program as stored then. So a rebuild that stores an older workout again sends no slots and no
    `programUpdates` (the workout as history returns it has none), until swaps are compare-and-set. A peer's
    finished workout that the phone materialises for the first time carries the peer's `programUpdates`: they
    land on the phone's copy of the program by the same rule (the workout's own program, a stored exercise).
    Decide whether both devices apply a swap, or only the one where the lifter asked for it.
  - Until then the order of saves decides which swap a slot keeps. A recovery pass completes ended logs in the
    order their workouts started (fix round 1, S3-N5); a rebuild path must keep that order.
  - A saved workout has no log on this device. A late envelope for it finds no `started`, replays to nothing
    and is kept: the amendment must say what the host does then.
  - The host looks in its own event store after every save (F10-S3-1), so a workout repository paired with
    another store's log cannot leave one behind. A wrapper around `WorkoutRepository` now has to implement the
    one call and say what it answers; there is no default to fall into.
  - The completeness check and the drop are still two reads apart (open question 7), and
    `GRDBWorkoutRepository` answers for its own queue only.

### Not verified

- **The full gate, anything on watchOS, and the coverage gate.** Not run. The simulator saw only
  `LedgerSyncTests` and `LedgerPersistenceTests`, on iOS, twice.
- **Criterion 8 on a simulator.** The timing suite is nightly only; the 16 ms is a Mac's.
- **Criterion 9 on CI.** The figures are one Mac's, one run each, under different loads. Whether 64 % locally is
  64 % of CI's 576 s I cannot say.
- **The nightly lane's full matrix on a simulator** (2,000 seeds × 6). On the host I ran 200 × 6 with the lane
  set to nightly.
- **The one-step program write in the fake** (mutant F8) and **the fake's deleted program** (F3): no test tells
  them apart.
- **A kill by the system.** As in S2, a kill point is a trigger that refuses a statement.
- Shared state: the disk ran low at about 11:40, as the orchestrator reported. One host run of mine straddled
  it and its log is cut in the middle of a line; I ran it again. The hang in that run was real and is open
  question 8, not the disk. The lock was held by F08's runs when I first asked for it (110 s) and free
  afterwards. No test helper process is left running.

### S3 — orchestrator rulings after G1 (2026-10-05)

- **Deviation 1 accepted for now:** the two-argument `materialize` stays a requirement beside the new call, so the
  testers' conforming types still compile. The reviewer judges whether one of the two should go once the testers'
  types are moved.
- **Criterion 9 is half done:** the implementer's session suites went from 25.7 s to 5.9 s; the S1 and S2 testers'
  suites (about 31 s) are theirs. S2's tester, who tests this slice too, cuts its own in the PR lane by the same
  lane check (nightly keeps the full matrix); S1's tester's suites are cut in the same pass, as sanctioned edits
  limited to how many seeds and set-ups run in which lane.
- **The tester test that fails by ruling** (`kill_afterTheSaveBeforeTheCompaction_compactsOnRelaunch`) is the
  tester's to move: over one database that state no longer exists.
- **ADR-004 rule 5** ("compacted after successful materialisation") now reads "with" over the database. The ADR is
  not edited in this slice; the wording goes into one ADR-004 amendment with the waiting-end paragraph, for Pete's
  review, before F17 is planned.
- This commit has not had the orchestrator's full gate: one test fails by ruling until the tester moves it. The gate
  runs on the tree after the tester's round.

### S3 — orchestrator rulings after G2 and G3 (2026-10-05)

G3 approved: 0 Blocking, 5 Should fix, 6 nits; the save is one transaction in the right order, and it found no way
to lose, duplicate or half-save a workout or to write another program's rows. G2 round 1: the save held; one latent
bug in how the host uses it (two tests failing on purpose); its failing S2 test is replaced; the session suites
now cost 14.6 s in the PR lane against 58.1 s before the slice (criterion 9 is met).

For fix round 1:
- **F10-S3-1 accepted:** the host does not take the repository's word alone. After a save that answered that the
  log was dropped, the host checks its own event store, and compacts there when the log is still present. A host
  whose repository and event store are not one database then ends with the log gone, as the rule "an end is
  complete when its log is gone" asks. The tester's two tests pass unedited.
- **S3-SF1 accepted, now:** `materialize(_:slotUpdates:droppingLog:) -> Bool` is the one requirement, with no
  default and not discardable; the two-argument call is an extension that passes `droppingLog: false`. Every
  conforming type states what it holds. The mechanical change to the testers' conforming types is sanctioned
  (implement the three-argument form: save and answer `false`, or forward where the type wraps a linked store);
  each changed line is listed, and the tester audits it.
- **S3-SF2:** the protocol says now that a later materialisation sets a slot back to the swap's exercise if the
  lifter changed it in between, as it already says of misses. Making the swap compare-and-set belongs to S8 with
  O10; the rule for a peer's and a rebuilt workout goes into the ADR-004 amendment (Pete), before F17 is planned.
- **S3-SF3:** not in this slice. ADR-008's and standards §4's description of the event-store fake is corrected in
  the same amendment PR as ADR-004's; the PR body of this slice says so.
- **S3-SF4 and S3-SF5 accepted** (a probe that fails instead of waiting for ever; programs compared to a `Bool`
  with a printed difference, never whole inside `#expect`).
- **Nits** as the review writes them unless one costs more than a few lines; S3-N5 (recovery deals with ended logs
  in a stated order) is taken.
- **F10-S3-2** (two overlap cases of S1's tester fail on one thread; the cut keeps them in the nightly lane only)
  joins the chore list.

### S3 fix round 1 (G1 implementer, 2026-10-05)

On `f1427aa`, tree clean at the start. Nothing is committed. Paths are under `LedgerKit/` unless they start with
`docs/` or `tasks/`. `Repositories` is `Sources/LedgerDomain/Protocols/Repositories.swift`, `Protocol`
`Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift`, `GRDB`
`Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift`, `Recovery`
`Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift`, `Probe`
`Sources/LedgerTestSupport/Engine/StoreProbe.swift`, `Linked`
`Sources/LedgerTestSupport/Persistence/WorkoutRepositoryContract+Linked.swift`. Scratch files are in
`scratchpad/f10s3/fix1/`. The full gate was not run, as the brief says: everything below is the Mac host's.

**Three things to know first:**

1. **A fifth tester type was changed, which the review does not name.** `OldWrapper`
   (`Tests/LedgerPersistenceTests/Adversarial/LinkedSaveLogAdversarialTests.swift:125`) conforms to
   `WorkoutRepository` through the default that S3-SF1 removes, so its target stopped compiling. I made the same
   mechanical change there and nothing else; its comment and its test's premise are now the tester's to reword
   (under "Sanctioned test edits").
2. **A look that fails is not thrown** (item 2 below). The host compacts instead. I chose that over letting the
   read's error out, so that the call that saves a workout still does not throw once the workout is in history.
3. **In the nightly lane on one thread three tests fail**, none of them this round's by what they check: S1's
   tester's two overlap-check tests and S2's timing test. In the PR lane nothing fails on either pool.

#### What changed, per item

| Item | Change | Where |
|---|---|---|
| 1. S3-SF1 | `materialize(_:slotUpdates:droppingLog:) -> Bool` is the one requirement: no default, not discardable. The two-argument call is an extension method that passes `droppingLog: false` and drops the answer | `Repositories:54-88`, `:110-115` |
| 1 | The forwarding methods are gone from the GRDB repository and the fake; each states what it answers (its own queue's log; the linked event store's, or none) | `GRDB:32-87`; `Sources/LedgerFakes/InMemoryWorkoutRepository.swift:38-64` |
| 1 | The stub, the probe's wrapper and `SeparateWorkoutRepository` implement the one form: the stub throws, the probe passes the call on with its answer, the separate repository saves and answers `false` | `Sources/LedgerDependencies/Unimplemented/UnimplementedStores.swift:62`; `Sources/LedgerTestSupport/Engine/ProbedStores.swift:89`; `Tests/LedgerSyncTests/Support/HostSupport.swift:100` |
| 1 | The testers' conforming types: under "Sanctioned test edits" | |
| 2. F10-S3-1 | After a save that answered `true` the host looks in its own event store (`holdsNoLog(of:)`: one `uncompactedWorkoutIDs()`), and returns only when the log is not listed. Listed, or the look failed: it compacts, as after an answer of `false` | `Recovery:150-181`, `:183-202` |
| 2 | What the answer means, and that a caller holding an event store looks there | `Repositories:79-83`; `GRDB:22-26` (the queue), `:61-62`; `Sources/LedgerDomain/Protocols/WorkoutEventStore.swift:40-44`, `:55-57`; `Protocol:89-94`; `docs/architecture.md` §6 |
| 3. S3-SF2 | "changes nothing, the program included as long as it was not edited in between"; a new bullet: an entry is applied by every materialisation, and one made after the lifter changed the slot sets it back; store an older workout again without its `programUpdates` | `Repositories:60-61`, `:70-72`; `GRDB:50-52` |
| 3 | The same rule as a contract clause, on GRDB and the linked fakes: stored again without its entries a workout leaves the program alone, with them it sets the slot back | `Linked:26-29`, `:181-205` |
| 3 | Compare-and-set into the inputs for S8, and the rule for a peer's or a rebuilt workout into the inputs for F17 | this file, "Inputs for S4, S7, S8 and F13", corrected in place (its first paragraph says so) |
| 4. S3-SF4 | `waitUntilHeld()` throws `StoreProbe.NeverHeld`, which names the held call, when its task is cancelled before the call came, as a suite's time limit cancels it. The waiters sit behind a `Mutex`, so the cancellation handler lets one go without waiting for the actor, and a waiter cancelled before it could wait is marked so | `Probe:26-39`, `:53-62`, `:92-123`, `:142-148`; six callers now `try` |
| 4 | `StoreProbe.swift` went over the file limit with it: the probed store wrappers moved, unchanged but for item 1, to a file of their own | `Sources/LedgerTestSupport/Engine/ProbedStores.swift` (new) |
| 5. S3-SF5 | The host's program suite compares programs by `Program.difference(from:)`, and a saved workout by a `Bool`: no whole program or workout inside `#expect` | `Tests/LedgerSyncTests/LocalWorkoutSessionActorProgramTests.swift:36-44`, and the eleven expectations that use them |
| 6. S3-N5 | A recovery pass reads every log first, then completes the ended ones in the order their workouts started, then by id (`startedBefore`, which `resume` uses too) | `Recovery:15-17`, `:62-88`, `:116-119` |

**Item 2, the design.** `complete(_:)` saves; on `true` it looks; it returns when the log is not listed, and in
every other case it runs the compaction it always ran after `false`.

- *Which read.* `uncompactedWorkoutIDs()` is the store's own definition of "a log is still there", unreadable
  rows included. `envelopes(for:)` leaves unreadable rows out and `highestSeq` asks about one device.
- *A log still listed* after `true` means the repository dropped another store's. The host logs a fault, because
  no composition of the app pairs stores so, and compacts.
- *A look that fails* is logged at error level and answered by the compaction too. Compacting a log that is gone
  does nothing, so the end is still only complete once the log is known to be gone: either the look said so or
  the compaction succeeded. The alternative, throwing the read's error, would make `finish` throw for a workout
  that is in history whenever one read failed after the commit. As built it takes the look **and** the
  compaction failing, one after the other, right after a save that succeeded
  (`finish_theLookAndTheCompactionFail_theEndWaits`): the end then waits as any other, and the retry saves again
  and ends it.
- *What the fix does not do.* It does not tie a repository to an event store. A pairing of two stores is still
  only found out at the first finish, by the fault in the log.

#### The cost of the host's look

One read of the event store per save of a finished workout: at `finish`, at its retry, and for each finished log
a recovery pass saves. No write, unless the log is still listed or the look failed, and then one compaction.

- Over GRDB it is `SELECT DISTINCT workout_id FROM workout_event`, on the table's index, in a read of its own.
  After a save that dropped the log the table holds only the logs that are kept: usually none.
- Measured in the nightly timing test, which now times the look after each save
  (`RecordReplayPerformanceTests.finishWithProgramUpdatesAndTheLog_underBudget`), by hand on the Mac host, Debug, a
  file database of 20,000 sets with a kept log of 200 events beside the one dropped: **p95 80 µs, median 56 µs**,
  against p95 11.1 ms and median 10.5 ms for the save before it. Under one per cent of the finish
  (`fix1/attachments/finish-save.txt`).
- That test now holds the save and the look together to the save's budget of 50 ms.
- Call for call, a finish over one database is now `unreadableCount`, `append`, `unreadableCount`, `materialize`,
  `uncompactedWorkoutIDs` (`finish_oneDatabase_looksOnceAfterTheSave` pins the list).

#### The failure table, as it now stands

Rows changed in this round are in bold; the others are as in the slice's section above.

| Step that fails | Memory | Store | Caller | Subscribers | Retry | Relaunch |
|---|---|---|---|---|---|---|
| append, any event; an append that stored and then threw; the clock | as in S2 | | | | | |
| the save, after `.finished` is stored: one transaction | `live` as before the finish; the end pending; clock and `seq` advanced | the log whole, with its `finished`; no history row, no miss, no program change | the store's error | nothing; `current()` still the workout | `finish`: saves and drops in one transaction, looks, publishes once, returns the state ended at the first date. `apply`, `discard`: complete it, then `noLiveWorkout`. `start`: `workoutInProgress`. Foreground: the step, no haptic | saved by the step; nothing live meanwhile |
| the save that stored and then threw (a store that lies) | the same | the workout in history, the log gone | the store's error | nothing; `current()` still the workout | `finish`: saves again (no change), looks, publishes once | nothing live, nothing to do |
| **the look after the save** (`finish_theLookFails_theHostCompacts`) | nothing pending | the workout in history; the log gone, or still listed | **nothing is thrown:** the host compacts, and `finish` returns | the ending update, once | — | — |
| **the look, and then the compaction** (`finish_theLookAndTheCompactionFail_theEndWaits`) | `live` as before the finish; the end pending | the workout in history; over one database the log is gone and the host does not know it | the compaction's error | nothing; `current()` still the workout | `finish`: saves again (no change), looks, publishes once | over one database nothing is left; otherwise saved again, compacted |
| **`compact` after the save, where the host's own event store still lists the log:** the repository holds no log (`false`), or holds another store's (`true`, and the look finds the log; `finish_repositoryAnswersForAnotherStore_theHostDropsItsOwnLog`, the tester's `HostMixedStoresAdversarialTests`) | the same | the log, and the history row with its misses and program changes | the store's error | nothing | saves again, compacts, publishes once | saved again, compacted |
| `compact`, after `.discarded`; a read during recovery | as in S2 | | | | | |
| a save during recovery | the other logs dealt with, **in start order**; the live one resumed | that log kept whole, and nothing of its save | the step throws; a protocol call does not | — | the next foreground | the next launch |

"Saves again" changes nothing as long as the program was not edited in between (S3-SF2).

- **`finish` over the database:** stores `finished`; one transaction; one read; the ending update. Nothing is
  thrown after the transaction unless that read and the compaction that answers it both fail.
- **`discard`, a second `finish`, the launch step:** as in the slice's section.

#### The recovery table, as it now stands

| Stored when the app died | The step | Afterwards |
|---|---|---|
| nothing, or a `started` that never reached the store | nothing | no workout |
| a live log | resumes it: no haptic, no effect run | `current()` is the workout |
| `finished` stored, not saved | one transaction: saves, with the misses from the program as stored now and the program updates, and drops the log; **then looks** | in history; no live workout |
| saved, and the log still there | saves again and drops the log; **where the repository answered for another store's log, the look finds it and the host compacts** | the same; the program as the save leaves it (S3-SF2) |
| `discarded` stored, not compacted | compacts | nothing in history, no program changed |
| a log that replays to nothing | keeps it and logs a notice | no workout |
| a log with rows this version cannot read | live: resumes from what it reads; ended: keeps it | a workout, or none |
| a save that throws | keeps the log whole; nothing is saved; records the step as failed; carries on with the other logs | retried on the next foreground |

**Order (new).** A pass reads every log before it completes any, so a read that fails leaves nothing completed.
The ended logs are then completed in the order their workouts started, then by id, whatever order the store
lists them in: of two finished workouts that swapped one slot, the program keeps the later one's exercise
(`recovery_twoFinishedLogs_areSavedInTheOrderTheyStarted`, with the later log listed first and last).

#### Sanctioned test edits (for the tester's audit)

`git diff f1427aa -- 'LedgerKit/Tests/*/Adversarial'` shows four files and these lines only. Line numbers are the
files' now.

| File | Line | Old | New |
|---|---|---|---|
| `Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift` | 7 | `func materialize(_ workout: WorkoutState, slotUpdates: [Slot]) async throws {` | `func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog _: Bool) async throws -> Bool {` |
| | 16 | (no line) | `return false`, after the `write { … }` block |
| `Tests/LedgerSyncTests/Adversarial/HostSiegeSabotageAdversarialSupport.swift` | 64-66 | `func materialize(_: WorkoutState, slotUpdates _: [Slot]) async throws {}` | `func materialize(_: WorkoutState, slotUpdates _: [Slot], droppingLog _: Bool) async throws -> Bool {`, `false`, `}` |
| `Tests/LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift` | 42-45 | `func materialize(_: WorkoutState, slotUpdates _: [Slot]) async throws {}` | the same three lines, and a blank line after them, which the formatter asks for after a body of more than one line (`blankLinesBetweenScopes`; checked on a copy) |
| `Tests/LedgerPersistenceTests/Adversarial/LinkedSaveLogAdversarialTests.swift` (`OldWrapper`, **not named by the review**) | 128 | `func materialize(_ workout: WorkoutState, slotUpdates: [Slot]) async throws {` | `func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog _: Bool) async throws -> Bool {` |
| | 130 | (no line) | `return false` |

- **`SiegeWorkoutRepository` is not edited.** It already implements the three-argument form
  (`HostSiegeStoresAdversarialSupport.swift:81`); its two-argument method is now an ordinary method, which its
  own unlinked path calls.
- **`HistoryModel`, `SabotagedWorkoutRepository`, `BriefWorkoutRepository`** each save as before (or not at all)
  and answer `false`: none holds a log.
- **`OldWrapper`, for the tester.** It was written to show what the default did for "a wrapper written before
  S3". There is no default now, and such a wrapper no longer compiles, which is S3-SF1's point. With the edit it
  is a wrapper that does not pass `droppingLog` on, and its test
  (`save_throughAWrapperOfBeforeS3_keepsTheLogAndSaysSo`) passes on both stores and still shows something true: a
  wrapper that saves through the two-argument call keeps the log, says so, and loses no program change. Left as
  they were, and no longer exact: the comment at `:124` ("inherits the new one's default"; it could read "it
  saves through the two-argument call and answers that the log is still there") and the test's name. I did not
  touch either.
- **The tester's two failing tests pass unedited:** `finish_eventStoreElsewhere_dropsItsLog` and
  `relaunch_afterAFinish_findsNoLogToSaveAgain`, four pairings each, on both pools.
- No other tester file is changed, and no tester test fails.

Tests of my own that changed: the six `waitUntilHeld()` callers (`try`); `LocalWorkoutSessionActorProgramTests`
(S3-SF5); `LinkedSaveDifferentialTests` (its own thirty seeds); the timing test (the look);
`LocalWorkoutSessionActorPerformanceTests` (the lane's one name); `SeparateWorkoutRepository` (item 1).

New tests: `LocalWorkoutSessionActorSaveTests`: `finish_oneDatabase_looksOnceAfterTheSave`,
`finish_repositoryAnswersForAnotherStore_theHostDropsItsOwnLog`, `finish_theLookFails_theHostCompacts`,
`finish_theLookAndTheCompactionFail_theEndWaits`, `probe_waitForACallThatNeverComes_endsOnCancellation`;
`LocalWorkoutSessionActorProgramTests.recovery_twoFinishedLogs_areSavedInTheOrderTheyStarted` (× 2); the contract
clause `laterSaveSetsTheSlotBack` (× 2 stores).

#### Nits

| Nit | Taken | What | Where |
|---|---|---|---|
| S3-N1 | yes | The differential builds its own thirty seeds; the nightly lane runs every seed of the lane and never fewer than the thirty | `Tests/LedgerPersistenceTests/LinkedSaveDifferentialTests.swift:20-28`, `:64` |
| S3-N2 | **in part** | `hostSeeds` is the longer of the lane's seeds and the fixed twenty. The Sync target reads the lane by one name (`TestLane.isNightly`; the inline read is gone). Testing-strategy §1 and §6 say how a matrix is cut by lane. **Not taken: one name across targets.** The tester's `SessionLane` uses `TestLane.isNightly` (`Tests/LedgerSyncTests/Adversarial/SessionLaneAdversarialSupport.swift:10`), and tester files of Persistence and Design use `TestLane.runsSlowTests`: either rename edits a tester's file | `Tests/LedgerSyncTests/WorkoutSessionClientContractTests.swift:24-30`; `LocalWorkoutSessionActorPerformanceTests.swift:15`; `docs/testing-strategy.md` §1, §6 |
| S3-N3 | yes | The repository's `init` says which queue its answer is about, and that a host looks in its own event store all the same | `GRDB:22-26` |
| S3-N4 | yes | One rule for "the exercise is stored", `ProgramRows.holdsExercise(_:in:)`, used by a program save and by the program updates. An ad-hoc workout returns before the loop, with one notice | `Sources/LedgerPersistence/Records/ProgramRows.swift:87`, `:94-99`; `GRDB:210-216`, `:238` |
| S3-N5 | yes | item 6 above | |
| S3-N6 | yes | "A host whose stores are one database saves in one transaction"; "the call that saves it does not throw once it is in history"; "`discard` saves the workout, with its program changes". The notes' sentence on a deleted custom exercise was wrong and is corrected in place | `Protocol:64-69`, `:97-99`; this file, the inputs for S8 |

#### Mutants of this round

`fix1/mutants-fix1.py` (logs `fix1/mutants.log`, `fix1/mutants2.log`): each applied alone, the named suites run,
the file put back and compared byte for byte. **Thirteen of thirteen are seen, one of them by a hang.**

| Mutant | Seen by |
|---|---|
| R1 the host takes the repository's word: no look | 6 tests: mine and the tester's two |
| R2 a look that fails is taken for a log that is gone | `finish_theLookFails_theHostCompacts`, `finish_theLookAndTheCompactionFail_theEndWaits` |
| R3 a log that is still listed is taken for gone | mine and the tester's two |
| R4 recovery completes ended logs in the store's order; R5 latest first | `recovery_twoFinishedLogs_areSavedInTheOrderTheyStarted` alone |
| H1 the host compacts after every save | 7 tests, in 11 s |
| H2 the host never compacts after a save | 37 tests, **in 70 s**: `finish_publishesAfterTheSave` waits to its time limit and then fails with `NeverHeld`. In the first round this mutant hung the run for good |
| H3 the host saves without dropping the log | 11 tests |
| G5 the exercise is not checked; G5b the shared rule asks for a live row; G11 the answer is always no; G14 an ad-hoc workout's updates reach a program | 1 to 4 tests each |
| **R6 the probe's wait ignores cancellation** | **a hang**, which is the fault it puts back: the probe's own test never returns. The script stopped it after 420 s |

**My first version of the probe's test hung under H1, H3 and G11.** It held `.compact` and then called `finish`
on a host that must not compact; a host that did compact parked there for good. The test now uses a bare probe
and no host (`Tests/LedgerSyncTests/LocalWorkoutSessionActorSaveTests.swift:31-43`). The general weakness stays: a held call that does
come, in a test that then fails before its `release()`, still waits for ever. Open question below.

#### Host runs, lint, Release build

On the final tree. `env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file
--skip-build --filter '^(LedgerSyncTests|LedgerDomainTests|LedgerAppKitTests|LedgerPersistenceTests|LedgerDependenciesTests)\.'`,
once as it is and once with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` (`fix1/final-default.log`,
`fix1/final-onethread.log`):

| Target | Default pool | One thread |
|---|---|---|
| LedgerSyncTests | 276 tests in 48 suites, passed (13 known issues, S1's) | the same |
| LedgerPersistenceTests | 495 tests in 113 suites, passed (1 known issue) | the same |
| LedgerDomainTests | 838 tests in 138 suites, passed | the same |
| LedgerDependenciesTests | 63 tests in 11 suites, passed (17 known issues) | the same |
| LedgerAppKitTests | 66 tests in 16 suites, passed | the same |
| Exit | **0** | **0** |

At `f1427aa` the Sync target had 270 tests, with the tester's two failing on purpose; six are new.

| Command | Exit | Result |
|---|---|---|
| The filter above, default pool | 0 | the table |
| The same, one thread | 0 | the table: nothing fails there in the PR lane |
| `LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=200 swift test … --filter '^LedgerSyncTests\.\|LinkedSave\|InMemoryContractTests\|WorkoutRepositoryLinkedTests'`, default pool | 0 | 276 and 53 tests passed, the full matrices |
| The same, one thread | **1** | three tests fail, below |
| `stress.py 20 'LocalWorkoutSessionActor\|WorkoutSessionConcurrentScriptTests\|HostMixedStoresAdversarialTests\|HostLinkedSaveAdversarialTests\|HostNeverLostAdversarialTests\|HostRecovery\|HostEndFailure\|HostProgramUpdate'`: the host's own suites and the tester's save, siege and recovery suites, 123 tests in 18 suites | 0 | 20 of 20 green, 109 s |
| The same with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` | 0 | 20 of 20 green, 188 s |
| `LEDGER_TEST_LANE=nightly swift test … --filter RecordReplayPerformanceTests`, once | 0 | the look's cost, above |
| `scripts/check.sh --lint-only` | **0** | format, `swiftlint --strict`, package graph, pins, script tests. No new suppression |
| `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file` | **0** | no warning; no symbol of `InMemoryStores`, `InMemoryWorkoutEventStore`, `InMemoryWorkoutRepository`, `InMemoryProgramRepository`, `FakeWorkoutSessionClient`, `SplitMix64`, `FakeLinkBus` or `Fixtures` in a Release object; `Release/LedgerFakes.o` is 1,176 bytes, as before |
| `scripts/check.sh` (full gate) | not run | the orchestrator's |

**The nightly lane on one thread: three tests fail, in every such run I made (one).**

- `SessionContractBiteAdversarialTests.racyClient_isRejectedByThisSuitesOverlapChecks` and
  `SessionContractRoundTwoAdversarialTests`' test of the same name: the two cases the tester's finding F10-S3-2
  names (`found != nil`), and nine more cases of the same two tests that met their one-minute time limit. On one
  thread a test waits for every other test of the run, and the whole Sync target took 65 s there with the
  nightly matrices.
- `LocalWorkoutSessionActorPerformanceTests.apply_withItsAppend_isUnderBudget` (S2's timing test): over its
  budget while the rest of the target ran on the same one thread. Alone it passes: p95 116 µs.
- None of them checks anything this round changed. I did not run the same at `f1427aa`, which needs a checkout,
  so that they fail there too is not shown.

#### Code lines

`count-lines.py` as before (`git diff -U0`, blank and whole-line comment lines excluded):

| | Against `95ac9b8` (the slice) | This round, against `f1427aa` |
|---|---|---|
| Product | **+100 −20** (was +70 −7) | +45 −28 |
| `LedgerFakes` | +74 −36 | +0 −4 |
| Test support | +433 −118 | +193 −124 (113 of each are the wrappers moved to `ProbedStores.swift`) |
| Tests, the testers' included | +2,782 −108 | +197 −35 |

Product by file, this round: `Recovery` +29 −10 (the look, the order), `GRDB` +9 −10, `ProgramRows.swift` +4 −1,
`Repositories` +2 −6, `UnimplementedStores.swift` +1 −1. The slice is now ten lines over the brief's "about 50 to
90"; the look and the order are what took it there.

#### Open questions

1. **A held store call in a test that fails before its `release()` still waits for ever** (`StoreProbe.hold`,
   and the tester's `Siege.hold` alike). S3-SF4 closed the wait for a call that never comes, not this.
   Recommendation: a `withHeld(_:during:)` on the probe that releases on every way out of its body, when the
   next test needs a held call.
2. **A look that fails is answered by a compaction, not thrown.** Recommendation: keep. If the reviewer would
   rather have every store error reach the caller, it is two lines, and `finish` then throws for a saved
   workout on one failed read.
3. **The lane check has two names across targets** (S3-N2). Recommendation: the chore that moves S1's two
   one-thread cases can rename one of them, since it edits tester files anyway.
4. **`OldWrapper`'s comment and test name** are the tester's to reword (above).
5. **Product lines are at 100.** Recommendation: accept; nothing was compressed, and what was added is the
   ruling's.

#### Not verified

- **The full gate, anything on a simulator or a watch, coverage.** Not run in this round. The orchestrator runs
  the gate.
- **Criterion 9's figure after this round.** Six host tests are new and none is a matrix; I did not measure
  again.
- **The three nightly, one-thread failures at `f1427aa`** (above), and the nightly lane's 2,000 seeds.
- **The look's cost on a simulator or a phone.** 80 µs is the Mac's.
- **The probe's wait under a real time limit** is shown by mutant H2 (70 s, then a failure); the probe's own
  test cancels its waiter by hand.
- Nothing odd in shared state. No helper process is left running. I interrupted my own mutant run once, and
  checked afterwards that every mutated file was back, by its diff.

### S3 — orchestrator's close (2026-10-05)

- The orchestrator's full gate on the fix round's tree exited 0. The tester's two tests for F10-S3-1 pass unedited,
  which was the finding's closing condition. **G2 is closed; G3 approved.**
- The edits to the testers' conforming types were read by the orchestrator line by line: each is the new signature
  answering `false`, nothing else (four files; a fifth type, `OldWrapper`, for the same reason).
- Not in this slice, queued: S3-SF3 and the ADR-004 wording (one amendment for Pete); S3-N2's name across targets;
  the three tests that fail in the nightly lane on one thread (S1's two overlap tests, S2's timing test).

## Slice S4 — the cover and the header (G1 implementer, 2026-10-08)

Built on `d61a3c4` (`main` `1d16e28` plus the specification), in the worktree `F10-s4`, on `feat/F10-s4-cover`.
Nothing is committed and no PR is open. **This section is written as the work goes; "The runs" at its end says
what was run and what was not.**

### The lifecycle table

Two objects, with one job each. `WorkoutLauncher` (public; the app's root holds one for its life) owns *which
workout is showing*: its `phase` is one of `idle`, `working`, `cover`, `conflict(source)`, `failed(failure)`, so
the cover, the conflict dialog and a failure can never be up together. `WorkoutStore` (one per presentation of
the cover) owns *the workout on screen*: it follows `WorkoutSessionClient.updates()`, and holds the finish
dialog, the discard and the reason the cover closes (`exit`). Neither keeps a workout of its own: what is live is
always what the session says.

An intent is accepted by the launcher only while it is `idle`, `conflict` or `failed`; while it is `working` or
the cover is up, `start`, `resume` and the dialog's choices do nothing. Each row below is one test
("Criteria → tests").

| # | What happens | Launcher `phase` / store state afterwards | What the lifter sees | The session afterwards |
|---|---|---|---|---|
| L1 | `start(day)`, nothing live | `working` → `cover`; `StartWorkoutUseCase.start` ran once | the cover: the day's name, 0:00 counting, no segment done | that day's new workout, live |
| L2 | `start(day)`, that day's workout live (resume) | `working` → `cover`; the use case is **not** called (criterion 3) | the cover, with the workout as it stands and its real elapsed time | unchanged |
| L3 | `start(day)`, that day's workout live, and the day since deleted or emptied in the program | as L2 | as L2 | unchanged |
| L4 | `resume()`, a workout live | `working` → `cover`; no use case | the cover | unchanged |
| L5 | `resume()`, nothing live | `working` → `idle` | nothing | none |
| L6 | `start(other day)`, a workout live | `working` → `conflict(other day)`; the use case answered `.conflict` | "You have a workout in progress" with its three choices | unchanged: the first workout, live |
| L7 | conflict → "Resume it" | `working` → `cover` (as L4) | the cover, with the live workout | unchanged |
| L8 | conflict → "Discard and start new" | `working` → `cover`; the use case ran with `replacingLive`: built the new one, **then** discarded, **then** started | the cover, with the new workout at 0:00 | the new workout, live; the old one discarded, nothing of it in history |
| L9 | conflict → "Cancel" (or the dialog dismissed) | `idle` | the tabs | unchanged |
| L10 | conflict → "Discard and start new", the discard fails | `failed(.notReplaced(.liveKept))`; no `start` was made | "Couldn't start the new workout" / "Your workout in progress was kept." | the old workout, live |
| L11 | conflict → "Discard and start new", the discard succeeds and the start fails | `failed(.notReplaced(.nothingLive))` | "Couldn't start the new workout" / "Your workout in progress was discarded." | none |
| L12 | conflict → "Discard and start new", the new day cannot be built (emptied, deleted, block over) | `failed(.notReplaced(.liveKept))`; nothing was discarded | as L10 | the old workout, live |
| L13 | the live workout ends elsewhere while the conflict dialog shows, then "Discard and start new" | `cover` | the cover, with the new workout | the new workout, live |
| L14 | the live workout ends elsewhere while the conflict dialog shows, then "Resume it" | `idle` (as L5) | the tabs | none |
| L15 | `start(day)` refused: the day has no exercise / is not in the active program / its week is past the block / anything else | `failed(.notStarted(reason))`, one reason each | "Couldn't start this workout" and the reason's line | unchanged: none, or the other day's workout that was live |
| L16 | `resume()` and the session cannot be read | `failed(.notOpened)` | "Couldn't open this workout" / "Try again." | unknown to the app; nothing was changed |
| L17 | a second `start` or `resume` while one is `working`, or while the cover is up | unchanged; the second is dropped | nothing new | at most the one workout the first made |
| L18 | the view that runs the launcher's task goes away while it works | what the work reached: `cover` if the start went through, else `idle`; a cancellation is never shown as a failure | — | whatever the session completed: the host finishes a call in its own task |
| L19 | `start(day)`: the store took the write and its answer was lost, so the call threw | `cover`: the launcher reads the session after any failure, and the workout asked for is live | the cover | that day's workout, live |
| S1 | the cover opens on a live workout | store `loaded(workout)` | the header | unchanged |
| S2 | "Minimize" | `exit = .minimized`; launcher `idle`; route `.minimized` | the tabs | unchanged: live |
| S3 | "Finish" | `dialog = .finish` | "End workout?" with "Discard" and "Keep lifting" | unchanged |
| S4 | "Keep lifting" (or the dialog dismissed) | `dialog = nil` | the cover | unchanged |
| S5 | "Discard" | `isDiscarding`, then `exit = .discarded`; launcher `idle`; route `.discarded` | the header's buttons disabled, then the tabs | none; nothing in history |
| S6 | "Discard", and the session refuses it | `dialog = .discardFailed`, `isDiscarding` false | "Couldn't discard this workout" / "It's still in progress. Try again."; then the cover as before | the workout, live (a host keeps its end waiting and shows it live) |
| S7 | "Discard", and the workout had already ended (`noLiveWorkout`) | no failure; the stream's ending update closes the cover (S9 or S10) | the tabs | none |
| S8 | another change to the workout arrives (a set logged elsewhere) | `loaded(new state)`; a dialog that shows stays | the header redrawn | as published |
| S9 | the workout is discarded elsewhere, with or without a dialog showing | `dialog = nil`, `exit = .discarded` | the tabs | none |
| S10 | the workout is finished elsewhere, with or without a dialog showing | `dialog = nil`, `exit = .saved(id)`; the app selects Today | the tabs | none; the workout is in history |
| S11 | the cover opens and nothing is live (the stream's first element is nil) | `exit = .nothingToShow`: the cover closes and no route is sent | the tabs | none |
| S12 | the stream ends while the cover is up (no session bound; a host never ends one) | `failed` | "Couldn't open this workout" / "Close this screen and try again." with "Close" (which minimizes) | unchanged |
| S13 | the cover goes away (minimize, or the app's root is torn down) while a discard is running | no failure is shown or logged for the cancellation | — | the host completes the discard in its own task |
| S14 | haptics in an update | ignored in this slice; S6 plays them from the stream only, never from a call's return, so never twice | — | — |

After any request that threw, the launcher reads `session.current()` once more and lets that decide (L10 to L12,
L19): the error says a call failed, the session says what is live. A read that fails too gives
`.notReplaced(.unknown)`, whose line claims nothing ("Try again.").

### What landed

- **`FeatureWorkout`** (was a placeholder): `WorkoutRoute`; `WorkoutLauncher` with its state types
  (`WorkoutLaunch.swift`: phase, failure, action, request) and `View.workoutCover(_:onRoute:)` (`WorkoutCover.swift`);
  `WorkoutRoot`; `WorkoutStore`; `WorkoutPresentation` (+`Header`) and its models (`WorkoutModel.swift`);
  `Views/WorkoutScreen`, `Views/WorkoutHeader`, `Views/WorkoutTimeline`; `WorkoutCopy` and
  `Resources/Localizable.xcstrings` (27 keys); `Workout+Previews` (six states); `WorkoutLauncher+Sample` (Debug only).
- **`LedgerDomain`**: `WorkoutState.checkedCursor`.
- **`LedgerAppKit`**: `MainRoot` holds the launcher and applies the modifier in `body`; `Routes+Workout.swift`
  (`AppRouter.resolve(_: WorkoutRoute)`); the Debug menu's sheet passes the extra row and starts the sample once the
  sheet is down.
- **`LedgerDesign`**: `DebugMenu(actions:diagnostics:)` and `DebugMenu.Action`; the menu's preview shows one.
- **Registrations**: `Package.swift` (the target's `resources`, `snapshotTestTargets`), `coverage-thresholds.json`
  (`required`), `PreviewScan.registeredModules`, `ModuleCopyTests.exemptions` (the Debug-only sample file).
- **Tests**: twelve suites in `FeatureWorkoutTests`, `WorkoutRoutesTests` in `LedgerAppKitTests`, one test added to
  `WorkoutStateTests`, and one UI test in `Apps/LedgerUITests/Smoke.swift`.

### The cover's VoiceOver tree

Pinned by `WorkoutAccessibilityTests.tree_isExactlyTheTable`, for every preview state, at light `.large` and dark
`.accessibility3`. Read from `WorkoutScreen` itself, which holds no scroll view yet.

| # | Stop | Label | Value | Traits |
|---|---|---|---|---|
| 1 | Minimize | "Minimize" | | button (and not enabled while a discard runs) |
| 2 | the dot and the time, one element | "Elapsed time" | | none |
| 3 | Finish | "Finish" | | button (and not enabled while a discard runs) |
| 4 | the workout's name | "Upper A — Push focus" | | header, static text |
| 5 | the progress segments, one element | "Workout progress" | "Exercise 2 of 5" (empty when the cursor names no row) | none |

Loading has no stop. Failed reads: "Couldn't open this workout" (header), "Close this screen and try again.",
"Close" (button). The two dialogs and the two alerts are the system's, and are tested through state, not by tree.

### Decisions and deviations

1. **Two objects, not one** (see the table's first paragraph). The task's "the store ... the two dialogs" is read
   as: the store has the finish dialog and the alert of a discard that failed; the launcher has the conflict
   dialog and the alert of a start that failed. The conflict dialog shows with no cover up, so it cannot belong
   to an object that lives with the cover. Tests are split the same way (`WorkoutLauncher…Tests`,
   `WorkoutStore…Tests`), as the plan's test table has them.
2. **`WorkoutLauncher.start(_:)` is synchronous** (the rulings, `implementation-notes.md` "O11 accepted. O12–O14";
   the plan's surface at "S4 — cover and header" still says `async`). An accepted intent makes the next
   `request`; the modifier's `.task(id: launcher.request)` runs it. Same pattern as onboarding's save attempt.
3. **`WorkoutRoot` is internal**, where the plan lists it as public. The app never builds it: it only holds the
   launcher and applies the modifier. Its closure takes a `WorkoutExit`, which is a route or "nothing to show"
   (row S11), because a cover that found no workout has no route to send.
4. **`Text(timerInterval:)` is used**, by the specification's criterion 6, against the plan's older line
   ("`Text(timerInterval:)` … are not used", "Snapshots per slice"). It is written once, in `WorkoutTimeline`, with
   the timeline's `pauseTime`; `FeatureWorkoutSourceTests` pins both.
5. **The current segment wins over "done".** The S4 input says "done when every set is done, current when it holds
   the shown row"; the prototype colours by position (`Ledger v2.dc.html:578`). Here the exercise that holds the
   cursor is current whatever its sets, so the orange segment is always the exercise the spoken value names; a
   workout with every set done keeps one orange segment, as the prototype does.
6. **The workout's name is under the row, as an eyebrow.** Criterion 1 asks for the name; v2's header draws none
   (`:134-149`), v1 draws it as an eyebrow over the bars (`Ledger.dc.html:520`). It is a VoiceOver heading.
7. **"Minimize" has no chevron.** v2 draws "‹ Minimize" with a left chevron (`:137-139`). `PillButton` takes no
   icon, `LedgerIcon` has no left chevron, and `LedgerPressStyle` is internal to `LedgerDesign`, so a button of the
   feature's own could not press like the others. It is `PillButton(.ghost, flush: .leading)`. See open question 2.
8. **The finish dialog is the system's `confirmationDialog`** with "Discard" (destructive) and "Keep lifting"
   (cancel), and no line of sets and volume: S7 replaces it with the "End workout?" sheet, which has that line.
9. **A dialog's dismissal and its button's action are accepted in either order.** SwiftUI sets `isPresented` to
   false and calls the action, and the order is not documented. So "Discard", "Resume it" and "Discard and start
   new" do not depend on the dialog's flag still being up (`WorkoutStore.send`, `WorkoutLauncher.accept`), and a
   dismissal is only ever the cancelling choice.
10. **The sample row lives in `FeatureWorkout`** (`WorkoutLauncher+Sample.swift`, wholly `#if DEBUG`, exempt in
    `ModuleCopyTests` as `debugOnly`): its title is a literal, which `LedgerAppKit`'s audit would refuse in
    `MainRoot`, and `Fixtures` is `LedgerFakes`', which the feature already links. It starts **week 1** of the
    active program's first day, not the calendar's week: the seed program's block ends on 2026-10-11, after which
    a start by date would be refused. `MainRoot` starts it from the sheet's `onDismiss`, because a cover cannot
    go up over a sheet that is still there.
11. **`.saved` selects Today** (`Routes+Workout.swift`); `.minimized` and `.discarded` do nothing. Nothing in this
    slice emits `.saved` except a workout finished elsewhere.
12. **Header buttons are disabled while a discard runs**, Minimize included. A discard that hung would leave no
    exit; a host's discard is two store calls, so this was not given a way round.
13. **A `Date` cannot hold NaN on this SDK** (`Date(timeIntervalSinceReferenceDate: .nan)` traps in `Integers.swift`,
    measured on the Mac host), so `WorkoutTimeline` guards only a start outside `distantPast ... distantFuture`.
14. **`FeatureWorkoutTests` imports `LedgerSync`** for the real host over `ProbedStores` (the failure rows): it
    reaches it through `LedgerTestSupport`, with no new edge in `Package.swift`.

### The catalog's keys

The brief's, word for word (10): "Minimize", "Finish", "Exercise %lld of %lld", "You have a workout in progress",
"Resume it", "Discard and start new", "Cancel" (the brief gives it for the swap sheet; the conflict's third choice
uses it), "End workout?", "Discard", "Keep lifting".

**Texts the brief does not give, for the product owner's copy review** (17 keys; "Try again." is used in three
places):

| Text | When it shows |
|---|---|
| "Elapsed time" | spoken only: VoiceOver's name for the running time in the header |
| "Workout progress" | spoken only: VoiceOver's name for the progress bars; its value is "Exercise 2 of 5" |
| "OK" | the one button of every alert below |
| "Couldn't start this workout" | alert title: a start was refused and nothing changed |
| "This day has no exercises yet." | its message when the day has no exercise |
| "This day is no longer in your program." | its message when the day, or its program, is not the active program's |
| "Your program's block has ended." | its message when the week asked for is past the last week |
| "Nothing was changed. Try again." | its message for any other cause (a store or the session failed) |
| "Couldn't start the new workout" | alert title: "Discard and start new" did not end with the new workout live |
| "Your workout in progress was kept." | its message when the old workout is still live |
| "Your workout in progress was discarded." | its message when the old workout was discarded and the new one did not start |
| "Try again." | its message when the app cannot tell which; and the message of "Couldn't open this workout" as an alert |
| "Couldn't open this workout" | alert title when Resume cannot read the session; and the title on the cover when it loses the session |
| "Close this screen and try again." | under that title, on the cover |
| "Close" | the button under it; it closes the cover and leaves the session alone |
| "Couldn't discard this workout" | alert title, over the cover: "Discard" was refused |
| "It's still in progress. Try again." | its message |

### Inputs for S5

- **Where the body goes.** `Views/WorkoutScreen.swift`, the `.workout` case: the header stays pinned and
  `ScrollView { WorkoutPage(model: workout.page) }` goes under it; `WorkoutModel` gains `page`. The header's
  horizontal inset is the screen's (`WorkoutScreen.body`), so move that padding onto the header when the page
  takes its own. `Support/WorkoutParts.swift` (tests) then stacks the header and the page; trees and references
  come from it, and `WorkoutAccessibilityTests.screen` must switch to it once the screen holds a scroll view.
- **How the store grows.** `WorkoutStore.send` is the one switch; add the set intents to `WorkoutAction`. Work that
  awaits follows the discard's shape: the intent makes the next id, `WorkoutRoot` runs it from a `.task(id:)`. For
  a queue of taps (two quick "+"), one `.task` draining an `AsyncStream` of intents is the plan's pump; take
  `apply`'s return as the base for the next intent and leave `workout` to the stream.
- **Selection.** `WorkoutPresentation.header` reads `checkedCursor`; give it the shown row
  (`selectedSetID` or the cursor) as a parameter. `segments(of:current:)` already takes the index.
- **Haptics** are S6's, and belong in `WorkoutStore.follow()`'s loop (`update.haptics`), nowhere else.
- **`isBusy`** disables the header; the page's controls should read the same flag.
- The preview fixture `WorkoutPreview.logged(_:in:)` logs rows through the engine at the cursor; S5's states can
  be built with it.

### Inputs for F09 S5: how Today calls the launcher

`MainRoot` already holds `workout` (a `WorkoutLauncher`). In `Routes+Today.swift`:
`.startWorkout(program:weekIndex:day:)` → `workout.start(WorkoutSource(programID:weekIndex:dayTemplateID:))`;
`.resumeWorkout` → `workout.resume()`. Both are synchronous and return at once; a second tap while one is being
answered is dropped. Today need not check anything first: a live workout of the same day is shown as it is, even
if its day has since left the program; another day's asks; a refusal shows its own alert. Today keeps following
`workoutSession.updates()` for its card; the launcher tells it nothing. `onRoute` gives `.minimized`, `.discarded`
or `.saved(id)` after the cover has closed. The Debug row can go once Today starts workouts, or stay for a
database with no program.

### Criteria → tests

Suites are in `LedgerKit/Tests/FeatureWorkoutTests` unless another place is named. "Ln" and "Sn" are the rows of
the lifecycle table; each test's display name starts with its row.

| Criterion | Tests |
|---|---|
| 1 Start | `WorkoutLauncherTests.start_nothingLive_startsTheDayAndOpensTheCover` (L1); `WorkoutPresentationTests.header_justStarted_isWordForWord` (name, start, no segment done); `WorkoutSnapshotTests`; UI `Smoke.test_sampleWorkout_startsCountsMinimizesResumesDiscards` |
| 2 Resume | `WorkoutLauncherTests.start_sameDayLive_opensTheCoverWithoutTheUseCase` (L2), `resume_live_opensTheCover` (L4), `resume_nothingLive_staysIdle` (L5), `send_onlyActsOnItsOwnPhase` (minimize, then again); `WorkoutStoreTests.follow_live_showsTheSessionsWorkout` (S1), `minimize_closesAndKeepsTheWorkoutLive` (S2); the UI test. After a kill: the launcher only reads `session.current()`; recovery itself is S2's `WorkoutRelaunchTests`. Not driven on the simulator here ("Not verified") |
| 3 Resume never meets the start refusal | `WorkoutLauncherTests.start_sameDayLive_dayGoneFromTheProgram_stillOpens` (L3; deleted and emptied, with a control that the use case does refuse that day), and L2's check that the program store was never read |
| 4 Conflict | `WorkoutLauncherConflictTests` (L6 to L9, L13, L14: the order `discarded` then `started` is read from the fake's record); `WorkoutLauncherFailureTests.replace_discardFails_keepsTheOldWorkout_startsNothing` (L10), `replace_startFailsAfterTheDiscard_leavesNoneLive` (L11), `replace_dayCannotBeBuilt_discardsNothing` (L12); `WorkoutPresentationTests.dialogs_areTheBriefs` |
| 5 Finish, for now | `WorkoutStoreTests.finish_asks_keepLiftingReturns` (S3, S4); `WorkoutStoreDiscardTests` (S5 to S7, S13); the UI test |
| 6 Elapsed time | `FeatureWorkoutSourceTests.elapsedTime_isDrawnByTheTimelineAlone`; `WorkoutTimelineTests`; `WorkoutSnapshotTests.header_pastAnHour_matchesReference` ("1:01:05"); `PreviewTests.preview_showsItsState` (the three times through `ClockText`); the tree's stop 2 ("Elapsed time", no value) |
| 7 The store | `WorkoutStoreTests` (S1 to S4, S8 to S12), `WorkoutStoreDiscardTests`; no `Task {` and no sleep in the module: `FeatureWorkoutSourceTests.sources_neverCountTime` and review |
| 8 Presentation and copy | `WorkoutPresentationTests`, `WorkoutCopyTests`, `FeatureWorkoutSourceTests`; `LedgerAppKitTests/ModuleCopyTests` (the audit, and the built bundle resolves all 27 keys); the gate's catalog step |
| 9 The shell | `LedgerAppKitTests/WorkoutRoutesTests`; the UI test (the cover over the tabs, the Debug row); `WorkoutLauncherTests.startSample_noProgram_savesTheSeedProgramAndStarts`; the tester's `AppRootAdversarialTests.root_idleAndReady_readToVoiceOver` still reads "Today" alone |
| 10 Tests | this table; `WorkoutAccessibilityTests` (the tree, 44 pt targets, what each button sends) |
| 11 Wiring | `PreviewTests` (registry and render), `LedgerDesignTests`' rule that every module with a `#Preview` is registered, `ModuleCopyTests`, the catalog step |

Failure rows not named above: L15 `WorkoutLauncherRefusalTests.start_refused_saysWhy`,
`start_refused_whileAnotherIsLive_keepsIt`, `start_storeRefusesTheWrite_startsNothing`; L16
`sessionCannotBeRead_opensNothing`; L17 `WorkoutLauncherTests.secondRequest_whileWorkingOrCovered_isDropped` and
`WorkoutLauncherFailureTests.start_stillRunning_secondRunAndRequestDoNothing`; L18
`start_viewGoesAwayWhileItRuns_isNoFailure`, `request_cancelledBeforeItsAnswer_isIdle`; L19
`start_answerLost_opensTheWorkoutThatIsLive`; S8 `update_fromElsewhere_isShown`; S9, S10
`endedElsewhere_closesTheCover` (four cases); S11 `follow_nothingLive_closesWithNoRoute`; S12
`follow_streamEnds_fails`. S14 has no test of its own: the store has no haptics dependency, and S8's update
carries the engine's `.setLogged` haptic through a store built on test dependencies, where touching `haptics`
would fail the test.

The failure rows run on the real host (`LocalWorkoutSessionActor`) over `ProbedStores` on the in-memory stores:
the fake cannot refuse a write or hold a call. L11 holds the discard's `compact`, then fails the next `append`,
so the start is the call that fails; no test sleeps. Two doubles are the tests' own
(`Support/SessionDoubles.swift`): `EndedSession` (the key's stub: updates end, calls throw) and `GatedSession`
(the fake behind a gate that throws `CancellationError` to a cancelled caller).

Two more decisions, found on the simulator:

15. **The conflict's "Cancel" is not drawn.** From iOS 26 the system draws no button for a dialog's cancelling
    role; tapping outside the dialog cancels (seen on iOS 27.0, `screenshots/s4/conflict-dialog-*.png`). The
    choice exists and does what it says (L9); the lifter reaches it the platform's way. "Keep lifting" is in the
    brief's copy, so it is a plain button with no role, and is drawn (`finish-dialog-*.png`).
16. **Only the header's two buttons are disabled during a discard**, not the row: a disabled row made the elapsed
    time read "dimmed" to VoiceOver (found by the tree test).

### References added

Five, in `LedgerKit/Tests/FeatureWorkoutTests/__Snapshots__/WorkoutSnapshotTests/`, written by a run in the
library's default mode (each failed once, then passed), on the iPhone 17 simulator (iOS 27.0). Each was looked at.

| File | Shows |
|---|---|
| `header_matchesReferences.light-large.png` | "Minimize", the dot and "24:22", "Finish"; "UPPER A — PUSH FOCUS"; five segments: done, current (orange), three upcoming |
| `header_matchesReferences.light-xLarge.png` | the same, one text size up |
| `header_matchesReferences.dark-large.png` | the same on the dark ground |
| `header_matchesReferences.dark-xLarge.png` | the same, one text size up |
| `header_pastAnHour_matchesReference.dark-large.png` | "1:01:05"; three segments done, the fourth upcoming, the fifth current |

One more than the plan's four: nothing else can show what the timer text reads past an hour.

### Screenshots for the product owner

`tasks/features/F10-active-workout/screenshots/s4/`, light and dark of each: `cover-just-started`,
`cover-after-24-minutes`, `cover-past-an-hour` (the previews' states, drawn by a test at 402 × 874 with time
standing still; no status bar), `conflict-dialog` and `finish-dialog` (the running app on the simulator, from a UI
test's attachments). The conflict dialog cannot be reached in the app yet (the Debug row always asks for the same
day), so for those two shots only, the sample alternated between two days in a temporary build; that change and
the two temporary tests were removed, and the final runs below are of the tree without them.

### Code lines per file

Non-blank, non-comment lines of product code (tests, `LedgerTestSupport`, the catalog and docs left out). Counted
when the store and the launcher were done (947) and at the end (952). The plan said about 580; the orchestrator
was told at 947 and ruled: one pull request, nothing cut.

| File | Lines |
|---|---|
| `FeatureWorkout/WorkoutLauncher.swift` | 140 |
| `FeatureWorkout/WorkoutStore.swift` | 121 |
| `FeatureWorkout/WorkoutCopy.swift` | 105 |
| `FeatureWorkout/Workout+Previews.swift` (Debug) | 86 |
| `FeatureWorkout/WorkoutCover.swift` | 84 |
| `FeatureWorkout/WorkoutPresentation.swift` | 63 |
| `FeatureWorkout/WorkoutRoot.swift` | 52 |
| `FeatureWorkout/WorkoutLaunch.swift` | 43 |
| `FeatureWorkout/Views/WorkoutHeader.swift` | 43 |
| `FeatureWorkout/WorkoutModel.swift` | 42 |
| `FeatureWorkout/WorkoutPresentation+Header.swift` | 33 |
| `FeatureWorkout/WorkoutLauncher+Sample.swift` (Debug) | 30 |
| `FeatureWorkout/Views/WorkoutScreen.swift` | 23 |
| `FeatureWorkout/Views/WorkoutTimeline.swift` | 19 |
| `FeatureWorkout/WorkoutRoute.swift` | 6 |
| `LedgerAppKit/MainRoot.swift` | +22 (−2) |
| `LedgerAppKit/Routes+Workout.swift` | 11 |
| `LedgerDesign/Gallery/DebugMenu.swift` | +17 (−1) |
| `LedgerDesign/Components/Components+Previews.swift` | +4 (−1) |
| `LedgerDomain/Model/WorkoutState.swift` | +8 |
| `FeatureWorkout/FeatureWorkout.swift` (the placeholder, deleted) | −3 |
| **Total** | **952** |

Where the plan's estimate fell short: the failure states and their sixteen texts (types, presentation, copy:
about 150), the two system dialogs and two alerts with their bindings (`WorkoutCover`, `WorkoutRoot`: about 90
over a bare cover), and the previews' workout built through the engine (about 40).

### The runs

All on the final tree (the temporary screenshot code removed), 2026-10-08. Simulator runs went through the lock,
on iPhone 17 (iOS 27.0), `PR` plan, `build-for-testing` then `test-without-building -only-testing`.

| Run | Result |
|---|---|
| iOS `build-for-testing` (scheme Ledger, plan PR) | exit 0 |
| `scripts/check-string-catalogs.sh` (the gate's catalog step, after that build) | exit 0 |
| `FeatureWorkoutTests` (simulator) | 71 of 71 passed |
| `LedgerUITests/Smoke` | 2 of 2 passed; the new test takes 22 s |
| `LedgerAppKitTests` + `LedgerDesignTests` (simulator) | 544 results: 537 passed, 6 expected failures, 1 skipped, 0 failed (none of the seven is this slice's) |
| `swift test --filter FeatureWorkoutTests` (Mac host; before the last two view edits) | 66 tests passed (no snapshot is drawn there, the tree tests are iOS only) |
| `swift test --filter LedgerDomainTests` (Mac host) | 1,213 tests passed |
| `scripts/check.sh --lint-only` | exit 0 |

The gate's preview step is `PreviewTests` in each registered module: FeatureWorkout's (in the 71) and
LedgerDesign's and LedgerAppKit's (in the 544) passed. `LedgerSyncTests` was not run: `LedgerSync` was not touched.

### Not verified

- **The full gate**, watchOS, and the coverage gate (FeatureWorkout is now `required` at 70 %): the
  orchestrator's. `LedgerDesign` builds for watchOS too; the `DebugMenu` change was not built there.
- **Kill and relaunch with the cover** (criterion 2's last sentence) was not driven on the simulator. The
  launcher reads `session.current()` and S2's `WorkoutRelaunchTests` prove recovery; the two were not run together.
- **"Discard and start new" in the running app.** The conflict dialog and "Resume it" were driven once in the app
  (the temporary screenshot run); the replace path is proven by the launcher's tests only.
- **VoiceOver itself**, on a device: the tree is read through UIKit in a test process.
- **The alerts' look** (four failure alerts): system alerts, tested through state; none was screenshot.
- **Accessibility sizes above `.accessibility3`** for the header's row. At `.accessibility3` every element is
  inside the screen and every button is 44 pt (the tree suite); `.accessibility5` was not drawn.
- The host run of `FeatureWorkoutTests` was not repeated after the last two view edits (the buttons' `disabled`,
  "Keep lifting" without a role); the simulator run was.

### Open questions

1. **Should VoiceOver hear the elapsed time?** Today it hears "Elapsed time" and no number (F09 S4's ruling). A
   lifter who cannot see the header cannot learn how long they have trained. Recommendation: in S6, when the rest
   card needs spoken times anyway, give this element a value made at the moment it is asked for (a custom
   accessibility value from the injected date), and pin it with the timeline fixed.
2. **"Minimize" has no chevron** (decision 7). Recommendation: S6 already changes `PillButton` and re-records its
   gallery; add an optional leading icon and a left chevron there, then one line here.
3. **The conflict's "Cancel" is invisible on iOS 26 and later** (decision 15). Recommendation: accept the
   platform's way for the conflict; or, if Pete wants a visible third choice, make it a plain button as
   "Keep lifting" is.
4. **"Your workout in progress was kept." after a discard whose log could not be dropped.** A host stores the end,
   fails to drop the log, and goes on showing the workout live; the next call completes the discard (S1's
   protocol, "a waiting end"). The line is true of what the session shows and may stop being true a moment
   later. Recommendation: leave it until ADR-004's paragraph on telling readers that an end is waiting; the
   launcher then has something to read.
5. **Sixteen texts are mine** (the table above). Recommendation: Pete reads the table before S5 merges; each is one
   catalog key and one copy member.
6. **`.saved` selects Today.** Recommendation: keep until S7 decides what "Done" on the receipt does.
7. **The header at the largest text sizes** is one row whatever the size. Recommendation: S5, which draws the
   whole screen at `.accessibility3` and above, decides whether the row stacks.

## Slice S4 — fix round 1 (G1 implementer, 2026-10-08)

On `fcb9fa0` (the slice as `46d4103`, the tester's files and the review on top), in the worktree `F10-s4`. Nothing
is committed. Criteria 12 to 18 are the brief's "Plan amendments — slice S4 after round 1". **Written before the
long runs; "The runs" at the end says what was run.**

### What changed, per item

| Item | Change | Where |
|---|---|---|
| Criterion 14 (F10-S4-2) | The guard asks `timeIntervalSinceReferenceDate.isFinite` first: every comparison of a `Date` that is not a number holds, so the range was built from it and SwiftUI trapped when it formatted the timer. Such a start now counts from the far future and reads "0:00". | `Views/WorkoutTimeline.swift`; the tester's `elapsed_startNotANumber_readsZero`; my `WorkoutTimelineTests` now holds NaN and a signalling NaN |
| Criterion 13 (F10-S4-1) | "Done" is decided first: an exercise whose every set is done is done also when the cursor rests on it; of the others the cursor's is current. A workout with every set logged has no current segment. The spoken value still names the cursor's exercise. | `WorkoutPresentation+Header.swift`; the tester's `segments_allDone`; `WorkoutPresentationTests.segments_everySetLogged_areAllDone`, `segments_doneWinsOverCurrent_andAnEmptyExerciseIsNeverDone` |
| Criterion 12 (SF1, F10-S4-4) | "Cancel" has no cancel role, as "Keep lifting": the system draws it. A tap outside still cancels. | `WorkoutCover.swift`; UI `Smoke.test_sampleWorkout_anotherDay_cancelResumeAndReplace` (three buttons hittable, by label); screenshots retaken |
| Criterion 15 (F10-S4-3) | "Discard and start new" that is refused for a reason a lifter can act on (empty day, day gone, block ended), with the old workout still live, ends as `.notStarted(reason)`: the plain start's title and line. No new text. `.notReplaced` remains for a failure with no such reason. | `WorkoutLauncher.phase(afterFailing:_:)`; `WorkoutLauncherFailureTests.replace_dayCannotBeBuilt_discardsNothing_saysWhy`, `replace_weekPastTheBlock_discardsNothing_saysTheBlockEnded` |
| Criterion 16 (SF3) | New `Reason.unknown`: a start that failed for no nameable reason **and** whose session could not be read again says "Couldn't start this workout / Try again." "Nothing was changed. Try again." is said only when the session was read and shows it. No new text ("Try again." exists). | `WorkoutLaunch.swift`, `WorkoutLauncher.swift`, `WorkoutPresentation.swift`; `WorkoutLauncherRefusalTests.sessionCannotBeRead_opensNothing`; the alert table's new row |
| Criterion 17 (SF2) | The UI test reads the time as text: the system's timer draws a static text inside the element VoiceOver knows as "Elapsed time" (the tester's F10-S4-6). It asserts at most 2 s on the clock when the cover is first read, then a later reading, then a still later one after Minimize and back. Minimize and Discard are each followed by `today.isHittable`, not `exists`. **Not exactly "0:00"**: by the time XCUITest can read the cover its first second may have passed; that a start reads "0:00" is the reference's. | `Apps/LedgerUITests/Smoke.swift` |
| Criterion 17 (SF4) | A third list, `unstructured` (`Task{`, `Task(`, `Task.detached`, `Task.init`, `Task<`), and `sources_startNoTaskOfTheirOwn`. | `FeatureWorkoutSourceTests.swift` |
| Criterion 17 (SF5) | "The current exercise's place in the workout, counted from 1, then the number of exercises", in the copy file and the catalog, word for word. | `WorkoutCopy.swift`, `Localizable.xcstrings` |
| Criterion 18 (F10-S4-5) | `WorkoutLauncher.startSample(day:)` (0 by default) and a second Debug row, "Start another day's sample workout" (`debug.menu.startOtherSampleWorkout`), which asks for the active program's second day. `DebugMenu.Action.sampleWorkouts(_:)` gives `MainRoot` both rows. One UI test takes Cancel, Resume it and Discard and start new in turn. It is in `Smoke`, so it runs in the PR lane: the plan selects that class only, and a test plan is not mine to edit. | `WorkoutLauncher+Sample.swift`, `WorkoutLaunch.swift`, `WorkoutLauncher.swift`, `MainRoot.swift`; `WorkoutLauncherTests.startSample_otherDay_conflictsWithTheFirst` |

Decision 5 of the slice's notes ("the current segment wins over done") is reversed by criterion 13. Decision 13
("a `Date` cannot hold NaN on this SDK") was wrong: my probe's output was lost in the crash it caused, and the trap
was SwiftUI's, as the tester's crash report shows. Decision 15 (the conflict's Cancel is not drawn) is superseded
by criterion 12. Open question 5 said sixteen texts; the table has seventeen (S4-N8).

### The reviewer's nits

| Nit | Done or declined |
|---|---|
| N1 a stale store on a fast re-present | **Not changed.** I could not observe it: the only way to ask for the cover again in the app is through the Debug sheet, which takes seconds. The two UI tests re-present the cover five times through that sheet and each new cover answers (Minimize works on it). F09 S5's "Resume" straight after "Minimize" is the test that would show it; the `.id(launcher.request?.number)` insurance is one line if it does. |
| N2 `onRoute`'s sentence | Done: the doc says it is told as the cover starts to go down, and that a route must not present anything in that turn. |
| N3 (a) a resume whose second read finds the workout | Done: it opens the cover (`resume_firstReadFails_secondFindsTheWorkout_opensTheCover`). (b) "Resume it" after the workout ended elsewhere stays silent: right for a phone alone; F15's list. |
| N4 a replacement that cannot be built does not say why | Done by criterion 15. The two-device case ("was kept" of a workout a third device replaced) is declined here: it needs the replaced workout's id carried through the dialog; F15's list. |
| N5 the dot's orange | Done: `LedgerColor.accentText`, the orange of the current segment. The two light references changed. The raw `5` stays (a shape's size; not a token). |
| N6 the plan's stale surface | Done: a note under the plan's block ("Inputs the implementer needs › S4"). |
| N7 a store per evaluation | Done as a sentence on `WorkoutStore`: making one does nothing, and must stay so. |
| N8 sixteen or seventeen | Seventeen. Corrected above. |
| N9 the loading cover has no way out | **Declined for S4.** It would add a state to the pinned tree and a control that, on the app's host, is never drawn: the launcher has awaited `current()` before the cover goes up. S5 must not make loading longer; if it ever can be, the failed screen's "Close" is the control to reuse. |
| N10 the alert's title goes empty as it dismisses | **Not changed, and not observed.** No failure alert can be raised in the running app from the Debug rows (a refused start needs an emptied day or a failing store). What would settle it: F09 S5 starting an emptied day, or a Debug row that fails. The fix, if seen, is to keep the last failure's model until the next request. |
| N11 three things written twice | Declined until a third use (the reviewer's own advice). |
| `/code-review`: the comment on a cancelled request | Done: it now says "on a host that completes each call in a task of its own, as the app's does". |

### New and changed texts

No new catalog key. One comment changed (SF5). One new Debug-only literal, not in the catalog: the row
"Start another day's sample workout".

For the product owner, what the fix round changes in when a text shows:

| Text | Now also shows when | No longer shows when |
|---|---|---|
| "Couldn't start this workout" with "This day has no exercises yet." / "This day is no longer in your program." / "Your program's block has ended." | "Discard and start new" was refused for that reason; the workout in progress is untouched | |
| "Couldn't start the new workout" / "Your workout in progress was kept." | | the refusal has one of those three reasons |
| "Couldn't start this workout" / "Try again." (a new pairing of two existing texts) | a start failed for no nameable reason and the app could not read the session afterwards | |
| "Nothing was changed. Try again." | | the app could not read the session afterwards |
| "Cancel" | drawn as the conflict dialog's third button | |

### The tester's tests that now fail, by design

Each pins the old line for a replacement that cannot be built; criterion 15 changes it. Not edited.

| Test | It expects | It now gets |
|---|---|---|
| `WorkoutConflictAdversarialTests` "L14: a new day that cannot be built leaves the old workout live, with no discard" (two cases: fake, host; `WorkoutConflictAdversarialTests.swift:126`) | "Couldn't start the new workout / Your workout in progress was kept. / OK" | "Couldn't start this workout" with the reason's line (see the run for the exact text) |
| `WorkoutConflictAdversarialTests` "A day past the block's end asked over a live workout: the dialog shows, and replacing discards nothing" (`+Changed.swift:139`) | `phase == .failed(.notReplaced(.liveKept))` | `.failed(.notStarted(.blockEnded))` |

In the L14 row above, the text it now gets is "Couldn't start this workout / This day has no exercises yet. / OK"
(read from the run).

### References and screenshots

Two references re-recorded, by deleting them and running `WorkoutSnapshotTests` once in the library's default mode
(it failed once and wrote them; the next run passed). Cause: the header's dot is now `accentText` (S4-N5). Both
were looked at: the dot is the darker orange of the current segment; nothing else moved.

| File | Shows |
|---|---|
| `header_matchesReferences.light-large.png` | as before, with the dot in the current segment's orange |
| `header_matchesReferences.light-xLarge.png` | the same, one text size up |

The old references still passed with the new dot (five points of colour are inside the suite's precision), so
they were re-recorded on purpose, for the stated cause, and not to turn a red test green. The three dark
references are unchanged: in dark the two oranges are one.

`screenshots/s4/conflict-dialog-light.png` and `conflict-dialog-dark.png` were retaken from the new UI test's
attachment on the final build (the dark one with the simulator's appearance set to dark for that one run, then
set back to light): three buttons, "Resume it", "Discard and start new" in red, "Cancel". No temporary code was
needed this time. **Not retaken:** the three `cover-*-light.png`, which still show the dot in the brighter orange.

### Code lines per file

965 in total (952 before this round; the limit is 1,000). Counted before the round and once after criterion 18,
not after each item as asked: items 1 to 5 were written in one pass, and the count was taken when 18 was in.

| File | Lines | Change |
|---|---|---|
| `FeatureWorkout/WorkoutLauncher.swift` | 144 | +4 |
| `FeatureWorkout/WorkoutStore.swift` | 121 | |
| `FeatureWorkout/WorkoutCopy.swift` | 105 | |
| `FeatureWorkout/Workout+Previews.swift` (Debug) | 86 | |
| `FeatureWorkout/WorkoutCover.swift` | 84 | |
| `FeatureWorkout/WorkoutPresentation.swift` | 64 | +1 |
| `FeatureWorkout/WorkoutRoot.swift` | 52 | |
| `FeatureWorkout/WorkoutLaunch.swift` | 44 | +1 |
| `FeatureWorkout/Views/WorkoutHeader.swift` | 43 | |
| `FeatureWorkout/WorkoutModel.swift` | 42 | |
| `FeatureWorkout/WorkoutLauncher+Sample.swift` (Debug) | 38 | +8 |
| `FeatureWorkout/WorkoutPresentation+Header.swift` | 33 | |
| `FeatureWorkout/Views/WorkoutScreen.swift` | 23 | |
| `FeatureWorkout/Views/WorkoutTimeline.swift` | 20 | +1 |
| `FeatureWorkout/WorkoutRoute.swift` | 6 | |
| `LedgerAppKit/MainRoot.swift` | +20 | −2 |
| `LedgerAppKit/Routes+Workout.swift` | 11 | |
| `LedgerDesign/Gallery/DebugMenu.swift` | +17 | |
| `LedgerDesign/Components/Components+Previews.swift` | +4 | |
| `LedgerDomain/Model/WorkoutState.swift` | +8 | |
| **Total** | **965** | **+13** |

### The runs

On the final tree, 2026-10-08, simulator runs through the lock on iPhone 17 (iOS 27.0), `PR` plan.

| Run | Result |
|---|---|
| iOS `build-for-testing` | exit 0 |
| `scripts/check-string-catalogs.sh` after that build | exit 0 |
| `FeatureWorkoutTests` (mine and the tester's) | 156 results: 154 passed, 2 failed. The two are the tester's pins in the table above (`replace_newDayEmptied_keepsTheOldWorkout`, both cases; `replace_weekPastTheBlock_keepsTheOldWorkout`), and no other. The tester's `segments_allDone` and `elapsed_startNotANumber_readsZero` pass, unedited; the process no longer traps |
| `LedgerUITests/Smoke` | 3 of 3 passed: launch 6 s, the cover 22 s, the conflict's three choices 32 s |
| `LedgerAppKitTests` + `LedgerDesignTests` | 544 results: 537 passed, 6 expected failures, 1 skipped, 0 failed |
| `swift test --filter FeatureWorkoutTests` (Mac host; before the wrong test of mine was removed) | 142 tests; the failures were the tester's two pins and that one test |
| `scripts/check.sh --lint-only` | exit 0 |

### Not verified

- The full gate, watchOS and the coverage gate: the orchestrator's. The PR lane's UI step grows by about 55 s
  with the two workout tests in `Smoke`.
- The tester's nightly UI test `WorkoutAdversarial` was not run after this round (it is not in the `PR` plan); it
  taps "debug.menu.startSampleWorkout", which is unchanged.
- N1 and N10 were not observed either way (reasons in the table).
- `LedgerDomainTests` and the Mac-host run were not repeated on the final tree; `LedgerDomain` was not touched in
  this round.
- A failure alert in the running app, kill and relaunch with the cover (F15), VoiceOver on a device, text sizes
  above `.accessibility3`: as before.
- The first reading of the clock in the UI test is asserted as at most 2 s, not as exactly "0:00" (criterion 17's
  words): see the item's row.

### Fix round 2 (G1 implementer, 2026-10-08): criterion 19

On fix round 1 plus the tester's uncommitted round 2. Nothing committed.

- **(a) F10-S4-7.** A replacement refused for a reason (empty day, day gone, block ended) says that reason whatever
  the session shows or fails to show afterwards: `.replace where reason == .other` is now the only path to
  `.notReplaced` (`WorkoutLauncher.phase(afterFailing:_:)`). Each such refusal is thrown before anything is
  discarded, so the reason needs no read.
- **(c) F10-S4-9.** `WorkoutPresentation.currentExercise(of:cursor:)`: the cursor's exercise while it has a set to
  log, otherwise the first exercise that has one; nil when every set is logged. The spoken value names the same
  exercise as the orange segment (with every set logged, the cursor's). Mine:
  `header_cursorOnAFinishedExercise_marksTheFirstUnfinished`.
- **(b) F10-S4-8: half done, and stopped for a ruling.** With (a), a workout finished elsewhere under the dialog is
  no longer called discarded when the replacement is refused for a reason (the tester's red test). What is **not**
  done: the neutral text for the remaining case (it ended elsewhere, and the new start then fails for no nameable
  reason), which still reads "Your workout in progress was discarded." Any new or reworded key fails the tester's
  green `WorkoutWordsAdversarialTests.catalog_holdsExactlyTheSlicesTexts` (27 keys, by name), and rewording the
  existing line also fails its pins of that line (`WorkoutConflictAdversarialTests.swift:66`, `:106`,
  `WorkoutRulingsAdversarialTests+Replace.swift:47`, `WorkoutWordsAdversarialTests.swift:45`, `:79`). Telling
  "ended elsewhere" from "this request discarded it" also needs a read of the session before the use case runs,
  which shifts the call counts the tester's fault tests skip by. Proposed, once ruled: reword the one line to
  "Your workout in progress has ended." (true of both cases, no extra read, no new key), with those pins updated
  by the tester.
- **One detail where the tester's pin and criterion 19 differ.** "While any set is not logged exactly one segment
  is current" is not held when the cursor names no row: then none is current and no value is spoken, as the
  tester's green `segments_cursorOutOfRange` and the round 1 tree expect. No session publishes such a cursor. Left
  as the tester has it.

The tester's three red tests pass unedited (`refusedReplacement_sessionUnreadable_stillSaysWhy`,
`refusedReplacement_afterFinishElsewhere_doesNotSayDiscarded`, `segments_anyOrder`).

**Lines:** 973 product lines (965 before; `WorkoutPresentation+Header.swift` 33 → 41). No catalog change.

**Runs.** Through the lock, iPhone 17 (iOS 27.0): build exit 0; catalog step exit 0; `FeatureWorkoutTests` 169 of
169 passed; `LedgerUITests/Smoke` 3 of 3. `scripts/check.sh --lint-only` exit 0. After the simulator run two of
my tests were moved, unchanged, into a new suite (`WorkoutPresentationDialogTests`; the old one was five lines
over the lint's type length): that move was run on the Mac host only (150 tests in 23 suites passed).
`LedgerAppKitTests`, `LedgerDesignTests` and the tester's nightly UI tests were not run in this round.

## Slice S5 — logging the sets of a solo exercise (G1 implementer, 2026-10-09)

Built on `fc8a38f` (`main` `0d4a156` plus the specification), in the worktree `F10-s5`, on
`feat/F10-s5-solo-logging`. Criteria 1 to 12 are the brief's "Plan amendments — slice S5". Paths are under
`LedgerKit/` unless they start with `Apps/` or `tasks/`. **"The runs" at the end says what was run and what was
not.**

### What landed

- **`Sources/FeatureWorkout`**
  - `WorkoutEdit.swift` (new): `WorkoutEdit` (the page's eight taps: select, log, un-log, step weight, step reps,
    repeat, add set, jump), `WorkoutSelection` (the row the lifter chose, where it is not the engine's cursor) and
    `WorkoutEditPlan.make`, a pure function from a tap, the workout, the selection, the time and a new set's id to
    the events to apply and the selection afterwards.
  - `WorkoutPageModel.swift` (new): `WorkoutPageModel`, `ExerciseCardModel`, `SetRowModel`, `SteppersModel`,
    `RemainingModel`. `WorkoutModel` gains `page`.
  - `WorkoutPresentation+Card.swift` (new): `shownExercise`, `activeSet`, `page`, `card`. `WorkoutPresentation.screen`
    takes `selection:` and `calendar:`; `header` takes `selection:` (defaulted) and names the shown exercise.
  - `WorkoutCopy+Card.swift` (new): 27 lookups and the module's `Locale.forCountedText`; the catalog has 54 keys
    (27 before).
  - `WorkoutStore.swift`: the pump (`pump()`, `drain()`, the queue), `selection`, the dialog `editFailed`.
    `WorkoutAction.swift` (new) holds `WorkoutAction` (now with `.edit`), `WorkoutExit`, `WorkoutStoreError` and
    `WorkoutDialog`, moved out of the store's file for the lint's file length; `WorkoutStore.Dialog` remains as a
    type alias.
  - `Views/WorkoutPage.swift`, `Views/ExerciseCard.swift` (with `FactLine`), `Views/SetRowList.swift`,
    `Views/RemainingList.swift` (new); `Views/WorkoutScreen.swift` puts the page in a scroll view under the pinned
    header; `WorkoutRoot.swift` runs the pump from a second `.task` and shows the alert of a refused change.
  - `Workout+Previews.swift`: two new states, "Logging a set" and "A drop set, in kilograms".
- **Tests** (`Tests/FeatureWorkoutTests`): `WorkoutEditPlanTests`, `WorkoutEditPlanMoveTests`,
  `WorkoutPresentationCardTests`, `WorkoutPresentationPageTests`, `WorkoutStorePumpTests`, `WorkoutStoreEditTests`,
  `WorkoutScreenTests`, `WorkoutPageLayoutTests` with `Support/WorkoutLayoutProbe.swift`,
  `WorkoutAccessibilityTrees.swift` (new); `WorkoutAccessibilityTests`, `WorkoutSnapshotTests`, `WorkoutCopyTests`,
  `PreviewTests`, `WorkoutPresentationTests`, `Support/WorkoutParts.swift` (changed); ten new references.
- **UI test**: `Apps/LedgerUITests/WorkoutLogging.swift` (new; nightly: the `PR` plan selects `Smoke` only).
- **Not touched**: `LedgerDomain`, `LedgerSync`, `LedgerDesign`, `LedgerAppKit` (the Debug rows needed nothing),
  `Package.swift`, the project file, the test plans, the coverage thresholds.

### The rules of the page (what the engine does not decide)

| Question | Rule | Where |
|---|---|---|
| Which exercise is on screen | the one the lifter chose (a row tapped, a stepper, a jump) while it is in the workout; otherwise S4's current exercise (the cursor's while it has a set to log, else the first that has one); with every set logged, the cursor's. The header's orange segment and "Exercise 2 of 5" name the same one | `WorkoutPresentation.shownExercise` |
| Which row is the shown row | the row chosen, else the cursor's row when it is in this exercise, else the exercise's first row; each only while it is not logged. A logged row is never the shown row (v2: `active = i === activeSet && !x.done`), so with every set logged there are no steppers | `activeSet` |
| When the choice ends | when a set is logged: the engine's cursor then says which row is next (rule 20). Un-logging moves nothing (rule 22). The choice lives with one presentation of the cover; after Minimize the engine's cursor decides, and a choice of a row that is not logged was also sent to the engine (`exerciseSelected`), so it survives | `WorkoutEditPlan` |
| A tap on a logged row's body | nothing (it cannot be the shown row; its check un-logs it) | `select` |
| A stepper on a logged row | nothing (it has no steppers on screen; a tap that was queued before the row was logged is dropped) | `step` |
| Weight and reps limits | `Weight.advanced(bySteps:of:)` with `WorkoutExercise.step` (the Domain's step for the equipment and unit, copied at build time, rule 16), held at zero; `Reps(clamping:)`. A step that would change nothing sends no event | `WorkoutEditPlan.make` |
| "+ Add set" on an exercise with no row | 0 × 8 (spec §3.7) | `repsOfAFirstSet` |
| "REMAINING" | the exercises after the shown one, whatever is logged in them (spec §3.7: "only later ones are listed"), each "{rows} × {reps of the first row}" (rule 26: the scheme follows an added set); with no card, every exercise | `page` |

### The pump

`send(.edit)` only appends to a queue and wakes the pump. `WorkoutRoot` runs `pump()` in a `.task`: it makes a
one-slot `AsyncStream<Void>` as its wake signal and calls `drain()` for each wake. `drain()` takes the taps oldest
first; each is planned on **the session's answer to the tap before it** (`ahead`), or on what the stream shows when
nothing is ahead, and its events are applied one by one. A tap stays at the front of the queue until it is done.

- The page draws what the stream publishes, never `ahead`. `ahead` is dropped when the stream shows that state, or
  when an answer is already what the stream shows (an event the engine ignored).
- Why not a stream of the taps themselves: an `AsyncStream` ends for good when its consumer's task is cancelled, so
  a cover whose view went away and came back would have a dead pump. With a queue and a signal, a tap made with no
  pump running waits for the next one (`pump_drainsAsTapsAreMade`).
- Why not `.task(id:)`, as the discard has: a new id cancels the call in flight.
- **A refused change drops the taps queued behind it.** They were made on a page that never came to be ("+", "+",
  check: logging at a weight the first "+" did not reach would be wrong). The alert says "Couldn't save that
  change" / "Try again." / "OK". This is the one case where a tap is lost; criterion 7's "none is lost" is read as
  holding while calls succeed. See open question 2.
- `noLiveWorkout` and a cancellation are no failures, as for the discard. A tap made while a discard runs, or
  after the cover began to close, is not queued; taps still queued when "Discard" is tapped are dropped.
- No unstructured task: the source test's `unstructured` list still passes.

### Decisions and deviations (every look the prototypes do not settle)

1. **No card behind the exercise.** v2 draws the exercise on the ground; v1 on a white card. v2 is followed.
2. **The TARGET line is v1's, drawn in v2's manner.** v2 has no target line; the criterion asks for one. It is a
   label and a value on one line, like "Last", with no pill and **no orange** (v1's "TARGET" is orange; criterion
   9 allows one accent). Both labels are `.label` in muted ink, both values `.caption` in secondary ink. At
   accessibility sizes the value goes under its label.
3. **The eyebrow "Exercise 2 of 5" is sentence case in muted ink** (v2), not `Eyebrow`'s capitals.
4. **Orange.** The card adds none of its own. What is orange on the page is `LedgerDesign.SetRow`'s: the shown
   row's number, its rule and its check's ring, and **the filled disc of every logged row** (v2: "orange fill when
   done"). So criterion 9's "the page's one accent" holds for what calls for a tap, and the logged discs are a
   second use of the colour, as v2 and the design system draw them. See open question 3.
5. **"REMAINING" has no small number before each name** (v2 draws "2", "3", …): `HairlineRow` has no leading
   column, and the header's segments place the exercise. Each row is one button, read "Incline DB Press, 3 × 11".
6. **No swap button, no rest panel, no plate line**: S8, S6 and F25. No dead control is drawn.
7. **"Repeat" is the outline `PillButton`** beside "Last"; without a last workout the line reads "No history yet"
   and the button is not drawn.
8. **"+ Add set" is the ghost `PillButton`, flush left** (v2: left-aligned text button), 44 pt high.
9. **While a discard runs the whole page is disabled with one modifier**, so VoiceOver reads every stop of it as
   dimmed, the texts too (the tree's table says so). The header disables its two buttons only, as in S4.
10. **The set label and the reps are plain digits** (`String(n)`), as the Domain writes the weight beside them; they
    are not catalog entries. A drop set's "D" is.
11. **A row's number counts the rows that are not drop sets**, so a set added after a drop set reads "4" after "D",
    not "5".
12. **Units are the workout's** (`WorkoutState.units`, snapshotted at build time), for the column, the target, the
    step and the spoken weight.
13. **`WorkoutPresentation.screen` gained `calendar:`**: "Last" is `LastPerformance.line(units:calendar:)`, whose day
    depends on the time zone, and an ambient calendar is forbidden. The store reads `@Dependency(\.calendar)`.
14. **A double tap on a check** logs once because the view sends `.log` for a row drawn open and `.unlog` for one
    drawn logged: a second tap made before the first was drawn finds the set logged and does nothing. A second tap
    made after the row was redrawn is an un-log, as in the prototype; no time-based guard exists or is wanted.
15. **Deviation from the plan's file list**: `SetRowList` and `RemainingList` exist as listed; `WorkoutPage`,
    `WorkoutEdit`, `WorkoutPageModel`, `WorkoutAction` and `WorkoutCopy+Card` are additional files (sizes and the
    lint's limits).

### What a day with a superset draws

The engine already runs rounds, so nothing logs wrongly; what is drawn is not yet a superset. Each member is drawn
as its own card ("Exercise 4 of 5", rows "1", "2", "3", its own target and "Last"). Logging A's set moves the
engine's cursor to B's (rule 20), so **the card switches to the other member after every set**, and the header's
current segment with it; the group's rest is the engine's (it starts after B). "Repeat", "+ Add set" and the
steppers act on the member shown. Not drawn: "Superset · block 2 of 4", "Round 2 of 3", the legend, "Rest 1:15
after B", the labels "A1"/"B1"/"AD". The Debug sample (Upper A) ends with such a pair: Lat Pulldown and Cable
Lateral Raise. S9 replaces the two cards with the block.

### The page's VoiceOver tree

Pinned by `WorkoutAccessibilityTests.tree_isExactlyTheTable` for the eight preview states at light `.large` and
dark `.accessibility3`, from `WorkoutParts` (the header over the page, no scroll view). After the header's five
stops (S4's table):

| # | Stop | Label | Value | Traits |
|---|---|---|---|---|
| 6 | the place | "Exercise 1 of 5" | | static text |
| 7 | the name | "Barbell Bench Press" | | header, static text |
| 8 | the target, one stop | "TARGET, 5 × 5 @ 200 lb · RPE 8" | | static text |
| 9 | the last workout, one stop | "Last, Sep 9 · 5×5 @ 195 lb" or "Last, No history yet" | | static text |
| 10 | Repeat (only with a last workout) | "Repeat" | | button |
| 11 | the column headings, one stop | "#, lb, reps" | | static text |
| per set | the row | "Set 1, 200 pounds, 5 reps" ("Drop set, 8.75 kilograms, 16 reps") | "Done", "Current set" or "Pending" | button |
| per set | its check | "Log set 1" / "Undo set 1" ("Log drop set" / "Undo drop set") | "Done" once logged | button, selected once logged |
| after the shown row | the weight stepper | "5 LB" | "200 pounds" | adjustable |
| after the shown row | the reps stepper | "1 REP" | "5 reps" | adjustable |
| | add | "+ Add set" | | button |
| | the list's heading | "REMAINING" | | header, static text |
| per remaining exercise | its row | "Incline DB Press, 3 × 11" | | button |

While a discard runs every stop of the page also carries "not enabled". The row and its check are the design
system's two stops (`SetRow`); the brief's older "Set 2, 185 pounds, 5 reps, not done" is read as that row with
its state as the value.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 1 the page | `WorkoutScreenTests` (one scroll view under the header; the header's tree and buttons in place with `outsideScrollViews: true`; the page scrolls at `.accessibility3`; loading and failed hold none); trees and references from `WorkoutParts`; UI `WorkoutLogging` |
| 2 the card | `WorkoutPresentationCardTests` (word for word; no history; the calendar's zone; rows; steppers; drop set; kilograms; RPE 8.5); `WorkoutCopyTests.cardsTexts_areWordForWord` |
| 3 logging | `WorkoutEditPlanTests.log_…`, `unlog_…`; `WorkoutStorePumpTests.doubleTapOnACheck_logsOnce`; `WorkoutStoreEditTests.log_sendsNoRestEvent`, `log_clearsTheChoice_unlogKeepsIt` |
| 4 steppers | `WorkoutEditPlanTests.stepWeight_movesByTheDomainsStep` (8 equipment and unit pairs), `stepWeight_neverUnderZero`, `stepReps_movesByOne_neverUnderOne`, `step_onTheShownRow_…`, `step_onAnotherRow_selectsItFirst`, `step_onAnotherExercise_…`, `step_onALoggedRow_…`; `WorkoutStorePumpTests.stepOnAnotherRow_selectsItFirst`; `WorkoutAccessibilityTests.steppers_adjustTheShownRow` |
| 5 repeat and add | `WorkoutEditPlanMoveTests.repeatLast_…`, `addSet_copiesTheLastRow`, `addSet_noRow_addsZeroByEight`; `WorkoutStoreEditTests.repeatLast_writesEverySet_keepsDoneFlags`, `addSet_appendsACopy_andTheSegmentWidens` |
| 6 remaining | `WorkoutPresentationPageTests.remaining_…`; `WorkoutEditPlanMoveTests.jump_…`; `mixedTaps_areAppliedInOrder` (the jump); the UI test |
| 7 in order, each once | `WorkoutStorePumpTests.twoQuickSteps_areTwoSteps`, `doubleTapOnACheck_logsOnce`, `mixedTaps_areAppliedInOrder`, `heldApply_laterTapsWaitTheirTurn` (the real host, an append held in the store), `pump_drainsAsTapsAreMade`; `FeatureWorkoutSourceTests.sources_startNoTaskOfTheirOwn` |
| 8 a failed apply | `WorkoutStoreEditTests.refusedApply_isShown_andThePageStays` (the real host, an append refused), `applyAfterTheWorkoutEnded_isNoFailure`, `busyOrClosing_tapsDoNothing`; `WorkoutAccessibilityTests.discarding_sendsNothing`; `WorkoutPresentationCardTests`… `page_busy_isNotEnabled` |
| 9 orange, labels, stops | the tree table; `buttons_sendTheirActions`, `steppers_adjustTheShownRow`; the references for the colour |
| 10 sizes and settings | `WorkoutPageLayoutTests` (cut, inside the phone, no overlap, 44 pt; five text sizes × 375 and 402 pt × Bold Text × right to left; a long-words page; the two self-checks); `controls_haveA44PointTarget`; the `.accessibility3` and Increase Contrast references |
| 11 words | `WorkoutCopyTests` (the card's texts, the spoken texts, `reps_takeTheCatalogsPluralForm` in nine locale cases, 54 keys); the gate's catalog step; the module audit |
| 12 pure and total | `WorkoutPresentationPageTests.page_noExercise_isEmpty`, `card_noSet_hasNoRow`, `page_cursorNamesNoRow_listsEveryExercise` (five cursors), `page_choiceNamesNothing_fallsBack`, `card_exerciseNotStored_…`; `WorkoutEditPlanMoveTests.edit_namingNothing_comesToNothing` (twelve edits, two workouts); `FeatureWorkoutSourceTests` |

**The cut-word check** (criterion 10; the idea of `ProgramViewsCutAdversarialTests`, which is not on `main`: read
from commit `6ea83da`). `WorkoutLayoutProbe.cut` measures a part by itself with all the width it wants and on the
page: narrower on the page and no taller means words were lost. It covers what this module lays out (the place,
the name, the two facts, "Repeat", "+ Add set", each remaining row); a part it cannot find on the page is reported,
not skipped. **Not covered**: the set rows' numerals and the steppers, which are `LedgerDesign`'s (a numeral too
long for its column shrinks to half size by design before it would be cut).

### Tests checked by breaking the code

Each mutant was applied to the product code, `swift test --filter FeatureWorkoutTests` run on the Mac host, and the
code restored; every one was caught.

| Mutant | Tests that failed |
|---|---|
| the next tap is planned on what the stream shows, not on the last answer | `twoQuickSteps_areTwoSteps`, `doubleTapOnACheck_logsOnce`, `mixedTaps_areAppliedInOrder` |
| a logged row can be logged again | `log_rowAlreadyLogged_comesToNothing`, `doubleTapOnACheck_logsOnce`, `heldApply_laterTapsWaitTheirTurn` |
| a stepper never selects its row | `step_onAnotherRow_selectsItFirst`, `step_onAnotherExercise_selectsItFirst`, `stepOnAnotherRow_selectsItFirst` (store) |
| a refusal keeps the taps behind it | `refusedApply_isShown_andThePageStays` |
| the weight is not held at zero | `stepWeight_neverUnderZero` |
| a count takes the lifter's plural rule | `reps_takeTheCatalogsPluralForm` |
| "REMAINING" lists the shown exercise too | five, among them `remaining_listsTheLaterExercises`, `remaining_lastExercise_isNil` |
| logging keeps the lifter's choice | `log_openRow_logsWhatTheRowReads`, `log_clearsTheChoice_unlogKeepsIt` |
| a failed change shows no alert | `refusedApply_isShown_andThePageStays` |

### Sanctioned edits to the tester's files

Ruled by the orchestrator on 2026-10-09 before any was made; this slice's tester audits them. All in
`Tests/FeatureWorkoutTests/Adversarial/`. `swiftformat` wrapped the lines that grew past 120 columns.

| # | File and test | Old | New |
|---|---|---|---|
| 1 | `WorkoutWordsAdversarialTests.catalog_holdsExactlyTheSlicesTexts` | `expected` ends `"It's still in progress. Try again."` | the same 27, then S5's 27 keys under a comment: `"TARGET"`, `"%lld × %lld @ %@ lb · RPE %@"`, `"%lld × %lld @ %@ kg · RPE %@"`, `"Last"`, `"No history yet"`, `"Repeat"`, `"#"`, `"reps"`, `"lb"`, `"kg"`, `"D"`, `"%@ LB"`, `"%@ KG"`, `"1 REP"`, `"+ Add set"`, `"REMAINING"`, `"%lld × %lld"`, `"Set %lld"`, `"Drop set"`, `"%@ pounds"`, `"%@ kilograms"`, `"%lld reps"`, `"Log set %lld"`, `"Undo set %lld"`, `"Log drop set"`, `"Undo drop set"`, `"Couldn't save that change"`. The test's name still says 27 |
| 2 | `WorkoutWordsAdversarialTests.forbidden` | `".formatted(",` | `".formatted()", ".formatted(.",` |
| 3 | `WorkoutCoverTreeAdversarialTests.screen(_:after:send:)` (used by `tree_liveWorkout`, `tree_fitsAtEverySize`, `tree_busy_buttonsAreDisabled`, `tree_activation`) | `WorkoutScreen(model: model, send: send)` | a `Group`: `WorkoutHeader(model: workout.header, send: send)` when the model is a workout, else the same `WorkoutScreen`; the environment and the 400 pt frame as before. Expectations unchanged |
| 3 | `WorkoutElapsedAdversarialTests.header_anyStart` | `WorkoutScreen(model: model) { _ in }` | `WorkoutHeader(model: header) { _ in }`, with `guard let header = model.drawnHeader` (recording an issue) before the loop. Expectations unchanged |
| 4 | `WorkoutPresentation.screen(…, locale: Fixtures.locale)` at **seven** call sites (I had counted six): `WorkoutCoverTreeAdversarialTests` 2, `WorkoutElapsedAdversarialTests` 1, `WorkoutHeaderAdversarialTests+Words` 4 | three arguments | `calendar: Fixtures.calendar` added |

**Edit 2, shown.** With a file planted in `Sources/FeatureWorkout` holding `moment.formatted()` (a `Date`) and
`count.formatted(.number)`, `sources_readNothingAmbient` failed with exactly
`["TmpPlanted.swift:5: .formatted()", "TmpPlanted.swift:9: .formatted(."]`; with the file removed it passed, over
sources that hold `Weight.formatted(in:)` six times. (`Date().formatted()` itself is also caught by the token
`Date()`.)

**The header in place** (the ruling's condition on edit 3): `WorkoutScreenTests.screen_headerInPlace_isItsTree`
reads the header's five stops from the real `WorkoutScreen`, above its scroll view, with
`outsideScrollViews: true`, for the six workout states at both appearances, and
`screen_headerButtons_sendTheirActions` activates them there.

### References

Ten new, recorded by the library's default mode on the `PR` plan's iPhone 17 (iOS 27.0): the first run wrote them
and failed, the next compared and passed. **No existing reference changed**: the five header references of S4 are
still drawn from the header alone (`WorkoutParts(headerOnly: true)`) and passed unre-recorded.

| File (`__Snapshots__/WorkoutSnapshotTests/`) | Shows |
|---|---|
| `cover_logging_matchesReferences.{light,dark}-{large,xLarge}.png` (4) | two rows logged, the shown row with its steppers, "Last" with "Repeat", "REMAINING" |
| `cover_logging_accessibility3_matchesReference.dark-accessibility3.png` | the same at the largest size of the matrix: the facts and the steppers stacked |
| `cover_logging_increasedContrast_matchesReference.light-large-increasedContrast.png` | the same with Increase Contrast |
| `cover_dropSet_matchesReferences.{light,dark}-large.png` (2) | the last exercise in kilograms with a drop set "D"; nothing remains |
| `cover_noHistory_matchesReferences.{light,dark}-large.png` (2) | "No history yet", no "Repeat" |

The plan listed nine (it had `ExerciseCard` alone at `.xLarge`; the whole cover is drawn instead, and one with
Increase Contrast is added for criterion 10). 744 kB in the folder, fifteen files.

### Screenshots for the product owner

`tasks/features/F10-active-workout/screenshots/s5/` (fifteen files). From the running app, the Debug sample
workout, taken by the UI test's attachments on the final build, light and then dark (the simulator's appearance
set to dark for one run and set back): `app-started-*`, `app-one-set-logged-*` (a logged row at 190 × 4 after two
"+" and one "−", the shown row with its steppers), `app-after-jump-*` (Lat Pulldown, reached from "REMAINING"),
`app-accessibility3-*` and `app-accessibility3-last-exercise-*` (the `AccessibilityXL` text size). The app's
screenshots were scaled to 1310 px high. Copies of five references: `reference-logging-{light,dark}.png`,
`reference-logging-accessibility3-dark.png`, `reference-drop-set-kg-light.png`, `reference-no-history-dark.png`.
"Repeat" is only in the references: the sample runs on a fresh database, where no exercise has a last workout.

### Every text not given by the brief

The brief's, word for word (15 keys): "TARGET", "%lld × %lld @ %@ lb · RPE %@", "Last", "No history yet", "Repeat",
"#", "lb", "kg", "reps", "D", "%@ LB", "%@ KG", "1 REP", "+ Add set", "REMAINING", "%lld × %lld" (16 with the last).

Mine, for the product owner's copy review (11 keys):

| Text | When it shows |
|---|---|
| "%lld × %lld @ %@ kg · RPE %@" | the target line in kilograms (the brief writes the pounds form only) |
| "Set %lld" | spoken only: the start of a row's name, "Set 2, 185 pounds, 5 reps" |
| "Drop set" | spoken only: the same for a drop set, which has no number |
| "%@ pounds" / "%@ kilograms" | spoken only: a row's weight, and the weight stepper's value |
| "%lld reps" (one: "%lld rep") | spoken only: a row's reps, and the reps stepper's value |
| "Log set %lld" / "Undo set %lld" | spoken only: a row's check (the brief's non-functional section and the S1 amendment give these words) |
| "Log drop set" / "Undo drop set" | spoken only: a drop set's check (`LedgerDesign`'s gallery uses the first) |
| "Couldn't save that change" | alert title: the session refused a tap's change. Its message is the existing "Try again.", its button the existing "OK" |

The spoken join ", " between a row's three parts is not a catalog entry.

### Product lines per file

877 in total (plan 485; the orchestrator ruled one pull request on 2026-10-09, with the split presentation +
store / views taken if a fix round passes about 1,000). Non-blank, non-comment lines, against `fc8a38f`.

| File | Lines | Change |
|---|---|---|
| `FeatureWorkout/WorkoutCopy+Card.swift` | 167 | new |
| `FeatureWorkout/WorkoutEdit.swift` | 162 | new |
| `FeatureWorkout/WorkoutPresentation+Card.swift` | 153 | new |
| `FeatureWorkout/WorkoutStore.swift` | 201 | +80 |
| `FeatureWorkout/Views/ExerciseCard.swift` | 62 | new |
| `FeatureWorkout/WorkoutPageModel.swift` | 56 | new |
| `FeatureWorkout/Workout+Previews.swift` (Debug) | 140 | +54 |
| `FeatureWorkout/Views/SetRowList.swift` | 35 | new |
| `FeatureWorkout/WorkoutAction.swift` | 21 | new (moved out of the store) |
| `FeatureWorkout/Views/RemainingList.swift` | 21 | new |
| `FeatureWorkout/Views/WorkoutPage.swift` | 21 | new |
| `FeatureWorkout/WorkoutPresentation.swift` | 85 | +21 |
| `FeatureWorkout/WorkoutRoot.swift` | 61 | +9 |
| `FeatureWorkout/Views/WorkoutScreen.swift` | 30 | +7 |
| `FeatureWorkout/WorkoutPresentation+Header.swift` | 48 | +7 |
| `FeatureWorkout/WorkoutModel.swift` | 43 | +1 |
| **Total** | | **+877** |

Where the overrun is: the copy file is 167 lines where the plan counted none (every key that carries a value needs
its own member with its locale and its translator's comment); the pump with the planning of each tap is about 240
where the plan had "handlers"; the previews are 54.

### Open questions

1. **A member of a superset is drawn as a solo card that switches after every set** (above). Recommendation:
   accept until S9; the alternative, drawing no rows for a superset day, would make the Debug sample's last two
   exercises impossible to log.
2. **A refused change drops the taps queued behind it.** Recommendation: keep. The other reading of "none is
   lost" would log a set at a weight the lifter did not see.
3. **The logged rows' discs are orange** (decision 4). Recommendation: keep v2's look; if "orange once" is meant
   strictly, the change is in `LedgerDesign.SetRowCheck`, not in this module.
4. **Eleven texts are mine** (the table). "1 pounds" is possible in speech for a weight of exactly one: the weight
   is a formatted text ("52.5"), which cannot pick a plural form. Recommendation: accept; no seed load is 1.
5. **The un-logged row does not become the shown row** (rule 22, the prototype). After un-logging, the lifter taps
   the row to bring the steppers to it. Recommendation: keep.
6. **An exercise before the shown one cannot be reached from the page** while a later one is shown and has sets
   left (spec: only later exercises are listed); it becomes the shown one again once the cursor's exercise is
   finished. Recommendation: put it to Pete with S9, where the legend adds another way to jump.
7. **`FeatureToday`'s counted texts** still take the lifter's plural rule (the brief's "separate chore"): not
   touched.

### Inputs for S6 (rest), S7 (finish), S9 (supersets)

- **S6.** The rest panel floats over the page (v2): put it in `WorkoutScreen`'s `.workout` case as an overlay or
  `safeAreaInset(edge: .bottom)` of the scroll view, and give `WorkoutPage` bottom room for it. The engine already
  starts the rest on a log (`WorkoutState.rest` is set in the store's state today; nothing draws it). "+30s" and
  "Skip rest" are two more `WorkoutEdit` cases whose plan is one event each; `restExtended` needs the tap's time,
  which `WorkoutEditPlan.make` is already handed as `now`. Haptics go in `WorkoutStore.follow()`'s loop, as S4
  said. The "next" line needs the shown row: `WorkoutPresentation.activeSet`.
- **S7.** `WorkoutDialog` is where the finish sheet's state goes; the save follows the discard's shape
  (`discardAttempt`, a `.task(id:)`), not the pump. Taps still queued when a save starts should be dropped, as
  `startDiscard()` does. The line "%lld of %lld sets logged · %@ lb moved" has two numbers: one is the count that
  picks the form, the other is passed as text (standards §7), and it takes `locale.forCountedText`, which is in
  `WorkoutCopy+Card.swift` as a private extension: move it to `WorkoutCopy.swift` when a second file needs it.
- **S9.** `WorkoutPresentation.page` is the one place that decides what a block draws: where
  `SupersetRounds.blocks(in:)` gives a block of more than one member, build the block's model in place of `card`.
  `shownExercise` should then name the block's current member for the header's segment. The plan of a tap needs no
  change (rows are named by exercise index and set id); "REMAINING" should list blocks, not members. Swap (S8)
  adds its button beside the title in `ExerciseCard`: the eleven whole-cover references change then, as the plan
  says.
- **The layout probe** (`Support/WorkoutLayoutProbe.swift`) takes any view and any list of parts: a new panel or
  sheet adds its parts and one test.
- **The UI test** `WorkoutLogging` leaves no workout running (it discards); S6 will see the rest panel over the
  rows it taps, and should skip the rest or tap through it.

### The runs

2026-10-09, on the final code (commit `c490067`; only this file and the screenshots were added after it).
Simulator runs through the lock, iPhone 17 (iOS 27.0) and Apple Watch Series 12 46 mm (watchOS 27.0).

| Run | Result |
|---|---|
| `scripts/check.sh --fast` | exit 0 in 122 s (lint 74 s; host Domain and Persistence tests 1,223 in 186 suites) |
| `swift test --filter FeatureWorkoutTests` (Mac host) | 209 tests in 29 suites passed (5 s). The snapshot, tree, layout and screen suites draw on iOS only |
| `FeatureWorkoutTests` on the simulator (`PR` plan, `-only-testing`) | 242 tests in 34 suites passed (54 s): mine and the tester's, with the four sanctioned edits |
| `LedgerUITests/WorkoutLogging` by itself (`Nightly` plan, `-only-testing`) | 2 of 2 passed, twice (light 50 s, dark 50 s): the logging flow 33 s, the accessibility-size order 17 s |
| `scripts/check.sh` (the full gate) | exit 0 in 827 s: lint 70 s, iOS build 10 s, catalogs (FeatureWorkout: 54 keys match the code), iOS tests 453 s, watchOS build 47 s, watchOS tests 243 s, coverage 2 s. FeatureWorkout 1,708 of 1,730 lines, 98.72 % (threshold 70 %) |
| The nine mutants, the planted `.formatted()` file | Mac host, each caught (tables above) |

Earlier red runs in this slice were of my tests, not of the code: a stop's traits while the page is disabled (the
texts are dimmed too; the table was corrected), two self-checks of the layout probe, the pinned header's place
(the reader's window is taller than the phone and centres the screen), and the UI test waiting for "Undo set 6"
after the last set, when the card has already moved to the next exercise.

### Not verified

- The rest of the `Nightly` plan (the tester's `WorkoutAdversarial` and `WorkoutConflictAdversarial` UI tests, the
  performance lanes) was not run; both tap identifiers this slice did not change, but both now meet a page under
  the header.
- CI: nothing is pushed.
- VoiceOver on a device, text sizes above the two the UI test and the references use (the layout check goes to
  `.accessibility5`), a refused change in the running app (no Debug row fails a store), kill and relaunch (F15).
- Right to left and Bold Text are measured (frames), not looked at: no reference draws them.
- "Repeat" in the running app: the sample has no history. It is covered by the store test and the references.

## Slice S5 — review, round 1 (G3 reviewer, 2026-10-09)

Reviewed `git diff main...f0318dd` (commits `c490067`, `f0318dd`) by reading only: nothing was built or run, so
every "met" below rests on the code as read and on the implementer's reported runs. Line numbers are those of the
files at `f0318dd`, under `LedgerKit/Sources/FeatureWorkout/` unless a path says otherwise. "Not checked" is at the
end.

**Verdict: approve with should-fix.** No blocking finding. S-1 and S-2 are defects a lifter would meet and each is
a few lines; S-3 is a product decision with a three-line cost; S-4 restores a check that a sanctioned edit
weakened. The pump is correct for what the session's contract promises and is close to the smallest shape that
can be.

### Blocking

None.

### Should fix

- **S-1. A jump to an exercise with nothing left to log holds the page there.** `WorkoutEdit.swift:184-186`
  sets `WorkoutSelection(exerciseIndex:, setID: nil)` and sends no event; `WorkoutPresentation+Card.swift:19-21`
  then shows that exercise for as long as the selection stands, and only a logged set clears it
  (`WorkoutEdit.swift:101`). "REMAINING" lists the later exercises whatever is logged in them
  (`WorkoutPresentation+Card.swift:54`). So: do the last exercise first (jump, log its sets; the page returns to
  exercise 1), then tap it in "REMAINING" again. The card shows it with every row done, no steppers, no
  "REMAINING", and a tap on a done row's body does nothing (`WorkoutEdit.swift:146`). The only ways back to the
  exercises that still have sets are to un-log and re-log a set, to add a set and log it, or to Minimize and
  reopen. `jump_nothingToLog_showsTheExercise` pins the selection; no test asks what the page then offers.
  **Proposed:** list in "REMAINING" only the later exercises that have a set to log, which is what criterion 6
  says ("the exercises still to do"). `jump`'s `nil` branch, the optional `WorkoutSelection.setID` and the
  "with every set logged" arm of `shownExercise`'s comment then go away: less code. Looking back at a finished
  exercise is the same question as open question 6 (an earlier exercise cannot be reached either) and belongs
  to Pete with S9.
- **S-2. The page keeps its scroll position when the shown exercise changes**, so the new exercise can appear
  with its name off screen. `Views/WorkoutScreen.swift:30-33` has no scroll position. Evidence:
  `screenshots/s5/app-accessibility3-last-exercise-{dark,light}.png` start at "TARGET 3 × 15 @ 12.5 lb": neither
  "Exercise 5 of 5" nor "Cable Lateral Raise" is on screen, and the pinned header names the day, not the
  exercise. The same happens when the last set of an exercise is logged from a scrolled page and the card moves
  on. The UI test passes because it reads the title's label, which exists off screen
  (`Apps/LedgerUITests/WorkoutLogging.swift:128`). **Proposed:** reset to the top when
  `page.card?.exerciseIndex` changes (`.scrollPosition` bound to the top, or `.id(exerciseIndex)` on the scroll
  view if VoiceOver focus survives it; try the first), and make the UI test assert
  `app.staticTexts["workout.card.title"].isHittable` after each jump.
- **S-3. An accidental second tap on a check un-logs the set** (decision 14). A person's double tap is 100 to
  300 ms apart; the row is redrawn as soon as the stream answers (a local write), so the second tap of a real
  double tap will usually land on a row already drawn done and be sent as `.unlog`. The "logs once" case
  (`doubleTapOnACheck_logsOnce`) covers only two taps inside one redraw. What the lifter then has: the set not
  logged, the cursor already on the next row (rule 22 moves nothing back), the rest still running from S6 on,
  and an empty ring one row up that is easy to miss. **Cost of a guard:** in `WorkoutEditPlan.unlog`
  (`WorkoutEdit.swift:105-109`), handed `now` as `log` is (`make` already has it), ignore an
  un-log within about 0.6 s after the set's `doneAt` (and only when `doneAt <= now`). Three lines and one test,
  pure, no timer, no sleep. **For the product owner to decide**; my recommendation is to add it, because the
  cost of a lost set is higher than that of a deliberate undo that must wait half a second.
- **S-4. Sanctioned edit 2 weakened the ambient-format check.**
  `Tests/FeatureWorkoutTests/Adversarial/WorkoutWordsAdversarialTests.swift:120` replaced `".formatted("` by
  `".formatted()"` and `".formatted(."`. The commonest ambient call, `date.formatted(date: .abbreviated, time:
  .omitted)`, matches neither, nor does `.formatted(style)` or `.formatted(Date.FormatStyle…)`. **Proposed:**
  put `".formatted("` back and blank the Domain's own call before the scan, as line 133 already does for
  `date.now`: `.replacingOccurrences(of: ".formatted(in:", with: "domainFormat")`. The other three edits lost
  nothing (below).
- **S-5. At accessibility sizes the two facts are grouped wrongly.** In `reference-logging-accessibility3-dark.png`
  and `app-accessibility3-*.png`, "Last" stands closer to the target's value above it than to its own value
  below. `Views/ExerciseCard.swift:25` and `:65` use the same `LedgerSpacing.xs` between the facts and inside
  one. **Proposed:** a larger gap between the two `FactLine`s than inside them at accessibility sizes
  (`LedgerSpacing.m` outside).
- **S-6. Three behaviours of the pump have no test.** (a) A change from elsewhere between two of the lifter's
  taps: the second must be planned on the newest workout (`follow()`'s `live == ahead` and `isShown`,
  `WorkoutStore.swift:170-173, 270, 291-296`); the mutant list has none for those lines. (b) A pump cancelled
  while a call waits: see N-2. (c) Whatever S-1 and S-2 become.

### Nits

- **N-1.** `WorkoutStore.swift:283-285`: a refused change sets `dialog = .editFailed` over an open finish dialog
  (taps keep draining under it). Harmless today; say in the comment that the refusal wins, or keep the finish
  dialog and show the refusal after it. S7 should decide with its sheet.
- **N-2.** `WorkoutStore.swift:249` empties the queue for any `false`, cancellation included (`:279-281`), while
  the type's comment (`:226-227`) and the notes say a tap with no pump waits for the next one. A pump cancelled
  mid-call drops the taps behind it silently. Either keep the queue on cancellation
  (`apply` returning a three-case result) or say so in the comment. Reaching it needs the view to go and return
  with the same store, which the cover does not do today.
- **N-3.** `leave()` (`WorkoutStore.swift:147`) drops queued taps on Minimize. Right for Discard; for Minimize it
  is a tap lost without a word (criterion 7). At a hand's speed the queue is empty by then (each apply is one
  local write), so accept, but list it beside the refusal as the second case where a tap can be lost.
- **N-4.** `WorkoutEdit.swift:70` clamps at zero itself while the doc comment (`:50-52`) says the engine holds it.
  Both do (`WorkoutEngine+Reduce.swift` `changeTarget`); the plan needs its own to see "would change nothing".
  Say that in the comment. Better home later: a Domain `Weight` helper that steps and floors.
- **N-5.** `WorkoutEdit.swift:141` `repsOfAFirstSet = 8` (spec §3.7) and "a new set copies the last row" (rule 26,
  `:131-137`) are product rules in the feature because `setAdded` takes a whole set. The watch will need the
  same two. Not for this slice (the engine is out of scope); record as an input for the watch's logging feature:
  move `WorkoutEditPlan`'s rule parts to the Domain when a second caller exists.
- **N-6.** `WorkoutEdit.swift:163-164`: the plan asks `WorkoutPresentation` which row is shown. It is the one
  place the rule lives, so it is right to share it; it reads oddly that the store's planning depends on the
  presentation. A neutral home (`WorkoutSelection` static functions) would cost nothing.
- **N-7.** `WorkoutPresentation.swift:12` and `WorkoutPresentation+Header.swift:17`: `selection` is defaulted to
  nil. A caller that forgets it compiles and draws the cursor's exercise. The only product caller passes it;
  drop the defaults when the tester's files are next touched.
- **N-8.** `WorkoutStore.swift:32`: `typealias Dialog = WorkoutDialog` exists for old call sites; rename them and
  drop it.
- **N-9.** `Views/ExerciseCard.swift:27, 51`: `ledgerHitTarget` on the TARGET line, which is not a control, and on
  the whole "Last" line. At the standard size it puts about 48 pt between "TARGET" and "Last" and makes the two
  facts read as unrelated lines (`app-started-*.png`); v2 sets them tight. Keep 44 pt for "Repeat" alone.
- **N-10.** "REMAINING" counts a drop set as a row: three sets and a drop read "4 × 16" beside a target of
  "3 × 16" (`WorkoutPresentation+Card.swift:60`). It follows rule 26's `sets.length`; mention to Pete.
- **N-11.** `WorkoutWordsAdversarialTests.catalog_holdsExactlyTheSlicesTexts`: its name still says 27 keys.
- **N-12.** A stale `ahead` is possible in theory: if the stream showed the answer and then a later change from
  elsewhere before the call's return resumed on the main actor, `isShown(answer)` is false and `ahead` stays old
  until the next answer. It needs the main actor to run two stream turns before one resumption, and the next
  plan would be wrong only for the same row. Accept; S-6 (a) would document the intended behaviour.

### Criteria

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | the page | met | `Views/WorkoutScreen.swift:26-33` (pinned header over `ScrollView { WorkoutPage }`); `Apps/LedgerUITests/WorkoutLogging.swift` logs sets. See S-2 |
| 2 | the card | met | `WorkoutPresentation+Card.swift:78-135`, strings final in the model; kg and lb; `WorkoutPresentationCardTests` |
| 3 | logging | met, with S-3 | `WorkoutEdit.swift:90-109`; no rest event sent (`log_sendsNoRestEvent`); nothing of rest drawn |
| 4 | steppers | met | `WorkoutEdit.swift:68-77, 154-175`; the step is `WorkoutExercise.step`, reps through `Reps(clamping:)`. N-4 |
| 5 | repeat and add | met | `WorkoutEdit.swift:113-138`; `repeatLast_writesEverySet_keepsDoneFlags`, `addSet_appendsACopy_andTheSegmentWidens` |
| 6 | remaining | partly | lists later exercises whether or not they are still to do (`WorkoutPresentation+Card.swift:54`); S-1. The superset report is given |
| 7 | in order, each once | partly | order and once: `WorkoutStore.swift:239-251, 264-272`; no unstructured task (`WorkoutRoot.swift:52-60`). "None is lost" does not hold on a refusal (accepted), on Minimize (N-3) or on a cancelled pump (N-2) |
| 8 | a failed apply | met | `WorkoutStore.swift:277-286`, `WorkoutRoot.swift:47-51`, `WorkoutPage.swift:26`; `refusedApply_isShown_andThePageStays` on the real host |
| 9 | orange once; labels; stops | partly | labels and stops as the tree table says (not run by me). Orange on the surface, by eye: the header's dot and current segment, the shown row's number, rule and ring, and every logged row's filled disc |
| 10 | sizes and settings | met as reported | `WorkoutPageLayoutTests` with a cut check that reports a part it cannot find. By eye nothing is cut or overlapping in the 15 images; S-5 |
| 11 | words | met | `WorkoutCopy+Card.swift`; 54 keys, each new one with a translator's comment, "%lld reps" with one/other; `forCountedText` on the one counted text |
| 12 | pure and total | met | no ambient read in the new files as read; `checkedCursor` and index guards at `WorkoutPresentation+Card.swift:30, 38`, `WorkoutEdit.swift:199` |

### The pump

- **Correct against the contract.** `WorkoutSessionClient.updates()` is unbounded and in order, and `apply`
  returns the state its update carries, so "plan on the last answer until the stream shows it" cannot miss.
  Each tap is taken from the front, planned when its turn comes on the newest workout (not the one the lifter
  saw), and removed when done. A row is named by set id, so a plan on a newer workout still means the same row,
  and `.log` logs what the row reads then.
- **Why not plan at tap time and apply events serially:** `setTargetChanged` carries an absolute weight, so two
  quick "+" planned on the drawn page would both say 205. Planning at the turn is needed while events are
  absolute. Why not show the answer directly and drop `ahead`: an older update still in the stream would draw
  the page backwards. So `ahead` earns its place. The queue and wake signal are about 25 lines; `isDraining`
  only matters for two overlapping pumps and is cheap. I would not ask for a smaller design.
- **Across events.** Restart: the queue survives, the new pump's first signal drains it (N-2 for a call in
  flight). Discard: queue emptied, taps refused while it runs, the call in flight is completed by the host.
  Finish dialog: taps keep draining under it (N-1). Minimize: queue dropped, store gone, the choice of row
  with it; the engine's cursor carries a choice of an open row. An update from elsewhere: shown as it comes;
  the next tap plans on it unless `ahead` is newer (N-12).
- **Isolation.** `@MainActor` store, value types `Sendable`, both dependencies injected, no `Task {}`.
- **263 lines:** about 80 added to the store and 162 of planning, of which the planning is a pure function with
  its own two test suites. Justified.

### A refused change drops the taps behind it

Right call. The taps behind were made on a page that assumed the refused one; applying them would log a weight
the lifter never saw. The alert ("Couldn't save that change" / "Try again." / "OK") is honest and claims nothing
about a first event of a two-event tap that may have gone through. Afterwards the page is what the stream says,
`ahead` is cleared, and the selection is unchanged, which `activeSet` reconciles with the cursor. Keep, and
reword criterion 7 in the brief to say so.

### A day with a superset

Nothing logs wrongly: every event names its row by set id and the engine runs the rounds and the group's rest.
Each member reads "Exercise n of m" with its own target, "Last" and rows; "REMAINING" under member A lists B.
What misleads is the card changing after every set with no word about why, which S-2 makes worse when the name
is scrolled away. With S-2 fixed it is acceptable on `main` for an app that is not released. S9 must come before
any release.

### Deviations and open questions

| Item | Judgement |
|---|---|
| Deviations 1, 2, 3, 5, 6, 7, 8 (the looks) | accept. 2 with N-9 |
| 4 orange | for Pete. Note: v2 draws the shown row's ring in 50 % ink, not orange (`x.done ? ORANGE : active ? 'rgba(244,242,237,.5)'`); the orange ring is `LedgerDesign.SetRow`'s, outside this slice |
| 9 the whole page disabled | accept |
| 10, 11, 12 digits, numbering after "D", the workout's units | accept |
| 13 `calendar:` | accept; required by "no ambient calendar" |
| 14 double tap | S-3 |
| 15 extra files | accept; each is under the lint's limits and has one job |
| Q1 superset as solo cards | accept until S9 |
| Q2 refusal drops the queue | accept |
| Q3 orange discs | for Pete; a change would be in `LedgerDesign` |
| Q4 eleven texts; "1 pounds" | accept. Also "1 kilograms". A fix needs a number, not a text, to pick a form; not worth it now |
| Q5 un-logged row is not the shown row | accept (rule 22) |
| Q6 earlier exercises unreachable | for Pete with S9; S-1 is its sharp end and should not wait |
| Q7 Today's counted texts | accept. Move `forCountedText` to a shared place (taking the bundle) with the Today chore, when the third module needs it; within this module to `WorkoutCopy.swift` in S7 as the notes say |

### The four sanctioned edits

1. The catalog's list: still an exact two-way set comparison, now of 54. No loss. N-11.
2. `forbidden`: weakened. S-4.
3. The tree and elapsed tests on the header alone: the same expectations on the same header view; the header
   in place in the real screen is covered by `WorkoutScreenTests.screen_headerInPlace_isItsTree` and
   `screen_headerButtons_sendTheirActions` (as the notes say; I read their names, not their bodies). The failed
   and loading states still go through `WorkoutScreen`. No loss.
4. `calendar:` at seven call sites: mechanical. No loss.

### Tests

- The plan's tests pin events exactly (`==` on the event list), so they cannot pass with a wrong weight, order or
  selection. The pump's tests wait on `Observations`, not on time; `heldApply_laterTapsWaitTheirTurn` and
  `refusedApply_isShown_andThePageStays` use the real host with a probed store. No sleep found in the new tests;
  the UI test waits on predicates with timeouts.
- Could pass with the code broken: `doubleTapOnACheck_logsOnce` says nothing about a tap after the redraw (S-3);
  nothing covers S-1's page, S-2's scroll, or S-6 (a) and (b).
- The UI test: sound. It taps the steppers by position (0.9 and 0.1 of the width), which right to left would
  swap; it runs left to right only. It reads off-screen labels as present (S-2).

### The look, by eye

Opened all fifteen images in `screenshots/s5/`: `app-started-{dark,light}`, `app-one-set-logged-{dark,light}`,
`app-after-jump-{dark,light}`, `app-accessibility3-{dark,light}`, `app-accessibility3-last-exercise-{dark,light}`,
`reference-logging-{dark,light}`, `reference-logging-accessibility3-dark`, `reference-drop-set-kg-light`,
`reference-no-history-dark`. The prototype was read as source (its set row's colours), not rendered.

- Nothing clipped, nothing overlapping. Logged rows are dimmed with a filled disc; the shown row is clear.
- "+ Add set" in muted ink reads as a caption more than a control at the standard size. It is v2's look; fine,
  but the weakest affordance on the page.
- Standard size: the facts are spread out (N-9). Accessibility size: the facts are misgrouped (S-5); the
  steppers stack well; "Sep 9 · 5×5 @ 195 lb" wraps beside "Repeat" without loss.
- After a jump at the accessibility size the exercise's name is off screen (S-2).
- Orange: see criterion 9.

### Simplicity

- S-1's fix removes a branch and an optional.
- N-6, N-7, N-8 are small removals.
- `WorkoutPresentation.Context` (two fields, one caller) could be two parameters; leave it if S6 adds a third.
- Nothing else I would cut. The copy file is long because standards §7 asks one member per key.

### Size

877 product lines, of which 167 are copy members and 54 previews; about 650 carry logic, in files of one job
each. Reviewable as one pull request and inside the agreed range for larger slices. The fixes above are about
+20 lines net (S-1 removes some). Split only if the fix round passes 1,000.

### For the product owner, in plain words

1. **A second tap on a check takes the set back.** Do you want the app to ignore an undo in the first half
   second after a set is logged? (S-3)
2. **Jumping to an exercise you already finished can leave you stuck on it** until you minimize. The proposed
   fix lists only exercises that still have sets. Going back to look at or correct a finished exercise, and
   going back to an earlier one at all, is not possible from this page: how should that work? (S-1, Q6)
3. **Orange.** It is on the header's dot and bar, on the shown row (number, line, ring) and on every logged
   row's disc. The prototype has the logged discs orange and the shown row's ring grey. Is this what you want?
4. **A superset day** switches the card between the two exercises after every set, with no superset label, until
   S9.
5. **"REMAINING" counts a drop set**: "4 × 16" for three sets and a drop. And VoiceOver says "1 pounds" for a
   weight of exactly one.
6. Look at `app-started-dark.png` (spacing of TARGET and Last) and `app-accessibility3-last-exercise-dark.png`
   (the name scrolled away).

### Not checked

- No build, test, lint or simulator run; no mutant re-run. Green claims are the implementer's.
- Read in full: the store, the plan, the action and model files, both presentation extensions, the root, the
  five views, the copy file, the pump and store-edit tests, the plan's move tests, the layout probe, the UI test,
  the four sanctioned diffs. Read by name or in part only: `WorkoutEditPlanTests`,
  `WorkoutPresentationCardTests`, `WorkoutPresentationPageTests`, `WorkoutPageLayoutTests`,
  `WorkoutScreenTests`, `WorkoutAccessibilityTests`/`Trees`, `WorkoutSnapshotTests`, `WorkoutCopyTests`,
  `Workout+Previews.swift`, `Support/WorkoutParts.swift`.
- The ten references under `__Snapshots__` beyond the five copied to `screenshots/s5/`. Right to left and Bold
  Text were not seen (no image draws them). VoiceOver was not heard.
- `LedgerDesign.SetRow` and `SetRowSteppers` were not read; the session host only for how it treats
  cancellation (`LocalWorkoutSessionActor.swift:124`, a task of its own).
- The tester's concurrent changes in the worktree were ignored.

## Slice S5 — adversarial testing, round 1 (G2 tester, 2026-10-09)

On `f0318dd`, in the worktree `F10-s5`. No product code was changed. New files carry `Adversarial` in their names;
three of the S4 tester's files were edited (below). The round was interrupted once by a network outage; the state
was read again from disk and every run listed under "The runs" was seen to its end afterwards. Paths are under
`LedgerKit/Tests/FeatureWorkoutTests/Adversarial/` unless they start with `Apps/`.

### What was attacked, and how

| # | Attack | Where | Result |
|---|---|---|---|
| 1 | The pump | `WorkoutPumpAdversarialSession.swift` (`PumpSession`: the real engine behind gates; every call can wait before the engine or after it, a numbered call is refused, the stream is kept behind the answers and let on one update at a time, another hand changes the workout in between; `PumpBench`), `WorkoutPumpAdversarialTests.swift`, `…+Lifecycle.swift` | 16 seeded storms of 36 taps each (every kind, one in eight naming a row the workout does not hold) come to the same events, the same workout and the same choice as the same taps made one at a time; a change from elsewhere while a call waits, behind a lagging stream, and with nothing behind; an answer that returns after the page showed it; a refusal in the middle; a refused discard; a workout ended elsewhere before the page heard; a pump cancelled while a call waits. **Findings 1, 2, 3** |
| 2 | The rules are the Domain's | `WorkoutRulesAdversarialLoggingTests.swift`, `WorkoutWalkAdversarialTests.swift` | the brief's table of steps written out, for 7 kinds of equipment × 2 units, against the event and the stepper's label; the floors through the engine (7.5 lb → 2.5 → 0, reps 2 → 1, five more taps send nothing); the workout's own step, not the equipment's of today; "+ Add set" after a drop set; "Repeat" over a drop set and a logged row, and without history; five solo exercises logged from the first check to the last by tapping only what the page shows (18 sets in rule 20's order, then no steppers, no list, no current segment); un-log after the end. All pass. **Finding 4** |
| 3 | The presentation | `WorkoutPageAdversarialTests.swift` | kilograms, twelve rows, a drop set as the fifth (rows "1"–"4", "D", "5"–"11"), RPE 8.5, every text character for character; the day of "Last" under four calendars with the machine's zone moved under it; reps 1, 2, 5, 21 and 0 under en, ja, ru, pl, fr, ar and cy; 400 seeded broken workouts (no exercise, no set, cursor and choice anywhere from −2 to 6) give a page that does not trap and does not contradict itself (one shown row at most, the steppers on it and never on a logged row, the header's words equal to the card's place, the list exactly the later exercises); every tap on 200 of them comes to a plan. All pass |
| 4 | A day with a superset | `WorkoutWalkAdversarialTests.swift` | Upper A's last two exercises walked round by round from the page: A1, B1, A2, B2, A3, B3; before every tap the card's place, name, target and rows, the header's words and current segment and the list name the same exercise, and every check logs the set its card showed at the weight its row read; a stepper, "+ Add set" and a jump to the second member change that member only. Nothing logs wrongly. What misleads is the reviewer's point and the implementer's question 1: the card changes after every set |
| 5 | The views | `WorkoutPageViewsAdversarialTests.swift` (simulator) | my own trees for two states no preview draws (every set logged; a cursor that names no row), both appearances; each stop sends its own tap once; busy: all seven controls dimmed, none sends; the set rows' numerals at five sizes × 375 and 402 pt × Bold × right to left ("187.5"/"12", "102.5"/"10", "315"/"5", "47.5"/"15": none needs less than half its size, so none is cut; the check is shown to see a cut); orange by pixels in three states × two appearances: only inside the shown row and the logged rows. **Finding 5** |
| 6 | The sanctioned edits | the S4 tester's files | below |
| 7 | The nightly UI tests | `Apps/LedgerUITests` | `WorkoutAdversarial` and `WorkoutConflictAdversarial` pass on this tree unchanged. New: `Apps/LedgerUITests/WorkoutLoggingAdversarial.swift`. **Findings 5, 6** |
| 8 | Mutation | 16 source changes | below |

### Findings

| # | Severity | What | Reproducing test (fails by design) |
|---|---|---|---|
| F10-S5-1 | bug, low to medium | **"Minimize" drops the taps that were still waiting**, without a word. `WorkoutStore.leave` empties the queue for every exit; the workout goes on after a Minimize, so a check tapped just before it is a set that is never logged. The store's own text says nothing is dropped but behind a refusal. It needs a call still under way when Minimize is tapped (a slow write), so it is rare; when it happens it is a lost set | `WorkoutPumpAdversarialTests.minimize_keepsTheTapsMadeBeforeIt` |
| F10-S5-2 | bug, latent | **A tap that waited for the next pump is planned on the workout as the cover last drew it.** When the cover's tasks start again the pump drains before the session's first update has arrived: the test's waiting check logs the set over the watch's log of it (300 lb × 1 becomes 185 × 5). No screen takes the cover's view away and brings it back with the same store today, so no lifter can reach it yet; the queue is kept across pumps for exactly that case, and it is the wrong thing to keep. Either drop the queue when a pump ends, or let a new pump wait for the stream's first update | `…pumpRestarted_plansOnTheNewestWorkout` (the same over 5 runs) |
| F10-S5-3 | bug, latent | **The kept answer (`ahead`) outlives a follow that starts again.** It is given up only when the stream shows that very workout; a new stream starts with the session's newest workout, and after a change from elsewhere the kept one is never shown. Every later tap is then planned on it: "+" on a row the page reads 300 lb sends 195. Same precondition as finding 2. One line: forget `ahead` when `follow()` starts | `…followRestarted_forgetsTheOldAnswer` |
| F10-S5-4 | bug, medium (the reviewer's S-1) | **A row of "REMAINING" can lead to a page with nothing to log and no way on.** The last exercise done first; the page returns to the first and still lists the last; a tap on it shows a card with every row done, no steppers and no list, with thirteen sets left | `WorkoutWalkAdversarialTests.jump_toAFinishedExercise_isNoDeadEnd` |
| F10-S5-5 | bug, medium (the reviewer's S-2) | **The page keeps its scroll position when the shown exercise changes.** Hosted: the real screen at `.accessibility3` scrolled 250 pt stays at 250 after a jump (and, rightly, after a change within the exercise). In the app at the `AccessibilityXL` size: after a tap on the last row of "REMAINING" the name's top is at y 114, the scroll view's at 219; neither the name nor "Exercise 5 of 5" can be touched | `WorkoutPageViewsAdversarialTests.scroll_returnsToTheTop_whenTheExerciseChanges` (PR lane); `Apps/…/WorkoutLoggingAdversarial.test_jumpFromRemaining_showsTheNewExercisesName` (nightly) |
| F10-S5-6 | question for the product owner (the reviewer's S-3, decision 14) | **A second touch on a check after the row was redrawn un-logs the set.** The system's double tap (`doubleTap()`) logs once in the running app: its second touch comes before the redraw, and that test passes. Two separate touches on the same spot 0.78 s apart leave the set not logged, with the shown row already on the next. Where between the two a person's accidental second touch falls was not measured; the reviewer proposes a guard of about 0.6 s | `Apps/…/WorkoutLoggingAdversarial.test_secondTouchOnTheSameCheck_doesNotLoseTheSet` (nightly) |

Notes, with no failing test:

- **N-a. A two-change tap is not stopped by Discard.** A stepper on a row that is not shown is two events; when
  "Discard" is tapped between them the second is still sent. With a host that takes its calls in order it lands
  before the discard or is answered `noLiveWorkout`; harmless.
- **N-b. A tap can be lost if a discard is refused while an older call is still out** (`queue.dropFirst()` after
  the queue was emptied and filled again). Not reachable on a session that takes its calls one at a time, as the
  protocol says a client does; `PumpSession` could show it, and I did not write it.
- **N-c. After a refusal of a tap's second change the lifter's earlier choice stands** while the engine's cursor
  has moved to the row the tap named. The next log names its own row, so nothing is logged wrongly.
- **N-d. Digits.** "Exercise 2 of 5" and "5 × 5" take the injected locale's digits (S4's ruling), the weight,
  the RPE, the row labels and the reps are plain digits, so under `ar_EG` one target line would mix both. Read
  in the code, not run. English is the only language shipped.
- **N-e. The list's "3 × 15" counts rows, drop sets included**, so an exercise prescribed 3 × 15 with a drop set
  reads "4 × 15" in "REMAINING" and "3 × 15 @ …" on its card. The notes say rule 26; the brief's "5 × 5" does not
  say which.

### The sanctioned edits

| # | Verdict | What I did |
|---|---|---|
| 1 catalog keys | not weaker: still exactly the 54 keys | nothing (the test's title still says 27) |
| 2 `forbidden` | **weaker**: `date.formatted(date:time:)`, `.formatted(style)` passed (the reviewer's S-4) | `WorkoutWordsAdversarialTests`: `".formatted("` is back; the scan blanks the Domain's `.formatted(in:` as it blanks `date.now` (`scanned(_:)`); new `scan_seesAmbientFormats` with seven lines, five caught and two passed. The module's sources pass |
| 3 the header alone | **weaker**: the header was drawn without the screen's insets, 32 pt wider than the cover draws it, so `tree_fitsAtEverySize` measured an easier layout, and four tests no longer met the real screen | `WorkoutCoverTreeAdversarialTests.screen(_:after:send:)` and `WorkoutElapsedAdversarialTests.header_anyStart` draw `WorkoutScreen` again and read it with `outsideScrollViews: true`: the pinned header in place. Expectations unchanged; all pass |
| 4 `calendar:` | not weaker | nothing |

### Mutation

Each change applied to the product code, `swift test --filter FeatureWorkoutTests` on the Mac host, the file
restored from a scratchpad copy. "Existing" is every test that was on the branch before this round.

| # | Mutant | Existing tests | This round's tests |
|---|---|---|---|
| M1 | the stream never clears the kept answer | **missed** | `changeElsewhere_shownBeforeTheNextTap` |
| M2 | every answer is kept, shown or not | **missed** | `answerAfterThePageShowedIt_isNotKept` (written for it) |
| M3 | "Discard" keeps the waiting taps | **missed** | `refusedDiscard_thePageAnswersAgain` (strengthened for it) |
| M4 | a workout ended elsewhere is shown as a failed change | **missed** | `endedElsewhere_beforeThePageHeard` (written for it) |
| M5 | a cancelled call is shown as a failed change | **missed** | `pumpCancelled_whileACallWaits` |
| M6 | un-logging gives up the lifter's choice | caught (1) | – |
| M7 | "+ Add set" copies the first row | caught (1) | caught |
| M8 | "Repeat" takes the last workout's set count as reps | caught (2) | caught |
| M9 | a jump lands on the first row, logged or not | caught (2) | – |
| M10 | the shown row ignores the lifter's choice | caught (1) | – |
| M11 | a drop set takes a number | caught (1) | caught (2) |
| M12 | "REMAINING" counts the prescribed sets | caught (2) | – |
| M13 | the weight moves by the equipment's step of today | **missed** | `stepWeight_isTheWorkoutsOwnStep` |
| M14 | the header's current segment ignores the choice | caught (1) | – |
| M15 | a set is logged at the prescribed load | caught (2) | caught |
| M16 | a tap never changes the lifter's choice | caught (2) | – |

Six of sixteen were missed by the existing tests, five of them in `WorkoutStore`'s handling of `ahead`, of an end
and of a cancellation (the reviewer's S-6); all sixteen are caught now. M6, M9, M10, M12, M14 and M16 are caught
by the implementer's tests alone. No view was mutated: a view's mutant needs a simulator run each.

### Questions

1. Finding 6: is a guard wanted, and how long?
2. Finding 1: should the taps waiting at a Minimize be applied before the cover closes, or after it by a task
   that outlives the view (the source rule forbids one today)?
3. Findings 2 and 3 share one precondition that no screen meets yet. Fix now (two small changes), or record for
   the slice that first covers the cover?
4. N-e: rows or prescribed sets in "REMAINING"?

### What I did not attack

- VoiceOver on a device; Increase Contrast beyond the implementer's reference; text sizes between the five of
  the sweep; a watch.
- The stepper pills' two halves one by one: VoiceOver sees a pill as one stop, and the halves cannot be measured
  through it. `ledgerHitTarget` gives each a 44 pt minimum by construction, and the implementer's sweep holds the
  pills inside the phone and apart for "5 LB" and "1.25 KG".
- A numeral longer than five characters ("1247.5") at the accessibility sizes: `SetRow` would cut it; no load
  of the seed reaches it.
- The real host under the storms: `PumpSession` wraps the engine, not `LocalWorkoutSessionActor`. The
  implementer's `heldApply_laterTapsWaitTheirTurn` and `refusedApply_isShown_andThePageStays` run on the host.
- A refused change in the running app (no Debug row fails a store), kill and relaunch (F15).
- View mutants; `LedgerDesign`'s own components beyond what the page draws with them.
- The scroll test spins the run loop for 0.1 s to let SwiftUI settle; it is the one place this round reads a
  clock.

### The runs

On the final tests, product code as at `f0318dd`. Simulator runs through the lock, iPhone 17 (iOS 27.0).

| Run | Result |
|---|---|
| `scripts/check.sh --fast` | OK in 130 s (lint 76 s, host tests 54 s) |
| `swift test --filter FeatureWorkoutTests` (Mac host) | 240 tests in 33 suites; **4 tests fail, 5 issues**: findings 1, 2 (two issues), 3 and 4. Before this round: 209 in 29, all passing. The pump and walk suites repeated 5 times: the same 4 each time |
| `FeatureWorkoutTests` on the simulator (`PR` plan, `-only-testing`) | 280 tests in 39 suites; **5 tests fail, 6 issues**: the four above and finding 5's hosted test. The S4 tester's suites pass with sanctioned edits 2 and 3 restored |
| `LedgerUITests` `WorkoutAdversarial`, `WorkoutConflictAdversarial`, `WorkoutLogging` (`Nightly` plan) | 4 of 4 pass, the first two unchanged on this tree (33 s and 55 s) |
| `LedgerUITests/WorkoutLoggingAdversarial` (`Nightly` plan) | 3 tests; `test_doubleTapOnACheck_logsTheSetOnce` passes; **2 fail**: `test_jumpFromRemaining_showsTheNewExercisesName` (finding 5) and `test_secondTouchOnTheSameCheck_doesNotLoseTheSet` (finding 6) |
| 16 mutants (Mac host) | table above; every product file restored, `git status` shows none changed |

An earlier red run of mine was the test's, not the code's: the orange check compared the image's lines with
frames the reader had placed elsewhere in its window (a marker over the page now gives its top), and the second
touch of finding 6's test was first aimed at an element that no longer existed.
