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
