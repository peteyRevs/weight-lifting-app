# Ledger — Architecture

Native Swift lifting log for iPhone + Apple Watch. The watch owns the live
workout (sets, crown-adjusted weight, heart rate, rest haptics); the phone
owns setup, programming, and review; both share one event-sourced workout.

Read with: `docs/engineering-standards.md` (rules), `docs/product-spec.md`
(what to build), `docs/product-decisions.md` (assumed product answers),
`docs/adr/` (why), `docs/research/` (evidence, dated 2026-09-16).

---

## 1. Stack at a glance

| Layer | Choice | Evidence |
|---|---|---|
| Language | Swift 6.4 (Xcode 27.0), Swift 6 language mode, strict concurrency `complete` | R1 §1, R2 §6, R3 §4 |
| Toolchain | Xcode 27.0 (Pete, 2026-09-29, F32), locally and on the GitHub `xcode-27` runner, a public preview image; fallback `macos-26` with Xcode 26.6. The App Store requires the 27 SDKs from April 2027 | R1 §1.1, R3 §4, ADR-006 |
| Min OS | iOS 26.0 · watchOS 26.0 (iOS 26 on 86 % of recent iPhones; watchOS 27 drops Series 6–8 / SE 2 / Ultra 1) | R1 §1.2–1.3 |
| UI | SwiftUI everywhere; `@Observable` stores; MainActor default isolation in UI targets | R2 §6 |
| Persistence | GRDB.swift 7.11.x (SQLite) on phone **and** watch, CloudKit-shaped schema | R2 §1, ADR-002 |
| Live phone⇄watch | HealthKit workout mirroring data channel (watch primary) + WatchConnectivity fallback | R1 §2, ADR-005 |
| Non-live phone⇄watch | WatchConnectivity `updateApplicationContext` / `transferFile` / `transferUserInfo` | R1 §2.6 |
| Cross-device sync | CloudKit private DB via CKSyncEngine (M4) using Point-Free SQLiteData or a hand-rolled actor; **no health data in iCloud** | R2 §3, R1 §3.4 |
| HealthKit | `HKWorkoutSession` + `HKLiveWorkoutBuilder` on watch (`traditionalStrengthTraining`); phone mirrors; workouts saved with HR + active energy | R1 §3 |
| DI | swift-dependencies 1.17.x | R2 §4 |
| Charts | Swift Charts (iOS + watchOS) | R2 §5 |
| Live Activity | ActivityKit, started in `workoutSessionMirroringStartHandler`; `Text(timerInterval:)` for rest | R1 §4 |
| Project | Committed `Ledger.xcodeproj` using Xcode synchronized folders; app targets depend only on umbrella package products; build settings in `.xcconfig`. No generator (XcodeGen has an open watch-embed bug on Xcode 26) | R3 §1, ADR-003 |
| Tests | Swift Testing (unit/integration), swift-snapshot-testing 1.19.x (UI), XCUITest (critical flows + `performAccessibilityAudit`) | R3 §2 |
| CI/CD | GitHub Actions `xcode-27` (preview) for PR gates; Xcode Cloud for signing, TestFlight (main) and App Store (tags); release-please for versions/changelog | R3 §4–5, ADR-006 |

Third-party runtime dependencies are exactly two: **GRDB** and **swift-dependencies**.
Test-only: **swift-snapshot-testing**. Nothing else without an ADR.

---

## 2. Repository layout

```
workout-app/
├── CLAUDE.md
├── Ledger.xcodeproj/               # committed; synchronized folders; rarely changes (ADR-003)
├── Config/                         # Base.xcconfig, Debug/Release, per-target xcconfig
├── .xcode-version                  # 27.0
├── mise.toml                       # pins swiftlint, swiftformat, lefthook
├── lefthook.yml                    # pre-commit: format + lint
├── .swiftlint.yml  .swiftformat
├── scripts/
│   ├── check.sh                    # lint + build + test; the local gate
│   ├── bootstrap.sh                # mise install, simulator runtimes, lefthook install
│   └── snapshots-update.sh
├── LedgerKit/                      # ONE local Swift package, many targets
│   ├── Package.swift
│   ├── Sources/
│   │   ├── LedgerAppKit/           # umbrella: iOS composition root (imports every iOS feature)
│   │   ├── LedgerWatchAppKit/      # umbrella: watch composition root
│   │   ├── LedgerDomain/           # models, WorkoutEngine, progression, 1RM, plate math, protocols, seed catalog JSON
│   │   ├── LedgerPersistence/      # GRDB schema, migrations, repositories, queries
│   │   ├── LedgerHealth/           # HealthKit adapter (watch session, phone mirror, save)
│   │   ├── LedgerSync/             # envelope transport (mirroring + WC), reconciliation, program push
│   │   ├── LedgerDesign/           # tokens, Archivo font loading, components; Resources/Archivo[wdth,wght].ttf
│   │   ├── LedgerActivityKit/      # ActivityAttributes shared by app + widget ext
│   │   ├── LedgerDependencies/     # swift-dependencies keys (§13) + Unimplemented stubs; nonisolated
│   │   ├── FeatureOnboarding/
│   │   ├── FeatureToday/
│   │   ├── FeatureWorkout/         # active workout, rest, swap, receipt
│   │   ├── FeatureProgram/         # builder, day editor, exercise picker
│   │   ├── FeatureLibrary/         # library, exercise detail/history
│   │   ├── FeatureHistory/         # workout list, workout detail
│   │   ├── FeatureSettings/
│   │   ├── WatchFeatureWorkout/    # all watch screens
│   │   ├── LedgerTestSupport/      # fakes, fixtures, builders, in-memory DB
│   │   └── LedgerSnapshotTesting/  # snapshot helpers + device/theme/type matrix (test-only)
│   └── Tests/                      # one test target per source target
├── Apps/
│   ├── Ledger/                     # iOS app shell: composition root, tabs, routes, Info.plist, entitlements
│   ├── LedgerWatch/                # watchOS app shell: composition root, WKApplicationDelegate
│   ├── LedgerWidgets/              # iOS widget + Live Activity extension
│   └── LedgerWatchWidgets/         # watch complications / Smart Stack
├── ci_scripts/ci_post_clone.sh     # Xcode Cloud bootstrap
├── release-please-config.json
├── .github/workflows/              # pr.yml (gates), nightly.yml (device-free long tests)
├── design/prototype/               # Claude Design exports (reference only)
├── docs/                           # this folder
└── tasks/                          # todo.md + feature briefs
```

---

## 3. Module map and dependency rules

```
                          ┌──────────────────┐
                          │   LedgerDomain   │  Foundation only
                          └────────▲─────────┘
        ┌──────────────┬───────────┼───────────┬──────────────┐
┌───────┴──────┐ ┌─────┴──────┐ ┌──┴───────┐ ┌─┴──────────┐ ┌─┴─────────────┐
│LedgerPersist.│ │LedgerHealth│ │LedgerSync│ │LedgerDesign│ │LedgerActivity │
│   (GRDB)     │ │ (HealthKit)│ │ (HK+WC)  │ │ (SwiftUI)  │ │Kit (ActivityK)│
└───────▲──────┘ └─────▲──────┘ └──▲───────┘ └─▲──────────┘ └─▲─────────────┘
        │              │           │           │              │
        │   Feature* → LedgerDomain, LedgerDesign, LedgerDependencies, LedgerTestSupport,
        │              swift-dependencies (+ LedgerActivityKit for FeatureWorkout's Live Activity)
        │              │           │           │              │
┌───────┴──────────────┴───────────┴───────────┴──────────────┴─────────────┐
│  App targets (Ledger, LedgerWatch, widgets): the composition root.        │
│  The only place live implementations are bound to Domain protocols.      │
└───────────────────────────────────────────────────────────────────────────┘
LedgerTestSupport / LedgerSnapshotTesting → depend on everything; imported by tests and previews only.
LedgerDependencies → depends on LedgerDomain (+ swift-dependencies); Features import it for `@Dependency` keys; the App shells bind live values.
```

`Package.swift` encodes exactly these edges. A feature that needs data calls a
protocol declared in `LedgerDomain` (e.g. `WorkoutRepository`), which the app
binds to `GRDBWorkoutRepository` via `swift-dependencies`.

`LedgerKit/package-graph.expected.txt` is the machine-readable copy of that
edge list; `scripts/check-package-graph.sh` fails the gate when `Package.swift`
and the table disagree, so an edge cannot be added quietly (F00).

**Open question (raised in F00, decide in F06/F07):** feature targets link
`LedgerTestSupport` so that `#Preview` bodies can use its fixtures. Because
`LedgerTestSupport` itself depends on Persistence, Health, Sync and Design,
this gives every feature a transitive link to the whole stack, which is exactly
what the rule above is meant to prevent. The alternative is a small
`LedgerPreviewFixtures` target that depends on `LedgerDomain` only. The edge is
kept for now because F00's target table specifies it, and the cost is invisible
while every module is a placeholder.

Isolation defaults per target (Swift 6.2+ `defaultIsolation`):

| Targets | Default isolation | Why |
|---|---|---|
| Feature*, WatchFeature*, App shells, LedgerDesign | `MainActor` | UI code; matches Apple DTS guidance (R2 §6) |
| LedgerDomain, LedgerPersistence, LedgerHealth, LedgerSync, LedgerActivityKit, LedgerDependencies | `nonisolated` | value types + actors; no implicit main-thread hops |
| App-hosted test targets (`LedgerTests`, `LedgerUITests`, `LedgerWatchTests`, `LedgerWatchUITests`) | `nonisolated` | `XCTestCase`'s overrides are nonisolated, so a MainActor default does not compile; tests mark `@MainActor` where they touch UI (Apple's 26.6 template pattern). Package test targets inherit their source target's setting. |

In the Xcode project this lives in `Config/Ledger.xcconfig` and
`Config/LedgerWatch.xcconfig`, not `Base.xcconfig`, so it reaches the app
targets only.

---

## 4. Runtime topology

### iPhone app (`Ledger`)
- `LedgerApp` (`@main`) builds the dependency graph once, opens the database,
  runs migrations, assigns `HKHealthStore.workoutSessionMirroringStartHandler`
  **synchronously at the top of launch** (R1 §2.5 gotcha 4), and registers the
  WatchConnectivity session delegate.
- Root view: `TabView` with four tabs (Today · Program · Library · History),
  each owning a `NavigationStack` keyed by that feature's `Route` enum.
- Active workout is presented as a full-screen cover over the tab root;
  "Minimize" dismisses the cover and Today shows "Resume · m:ss".
- Live Activity (rest + elapsed) is started inside the mirroring start
  handler (10 s budget) and updated sparsely (R1 §4.1).

### Watch app (`LedgerWatch`)
- `WKApplicationDelegate` handles `handle(_ workoutConfiguration:)`
  (phone-initiated start), `handleActiveWorkoutRecovery()`, and
  `applicationDidFinishLaunching` wiring.
- Single `NavigationStack`; screens map 1:1 to the prototype's watch modes
  (idle, ready, rest, list, end, summary) driven by `WorkoutState`.
- The watch is the **primary** HealthKit session and the **authoritative**
  device for live workout events (ADR-005). It can run an entire workout with
  the phone absent: its own GRDB store, its own event log, its own HealthKit
  save. Events reconcile when the phone reappears.

### Extensions
- `LedgerWidgets` (iOS): Live Activity UI (Lock Screen + Dynamic Island) using
  `LedgerActivityKit.WorkoutActivityAttributes`; a "Next session" widget.
- `LedgerWatchWidgets`: Smart Stack "Next session" + "Rest remaining" relevance.

---

## 5. Domain model (`LedgerDomain`)

Typed identifiers everywhere: `ExerciseID`, `ProgramID`, `WeekID`,
`DayTemplateID`, `SlotID`, `WorkoutID`, `WorkoutExerciseID`, `SetID`,
`DeviceID`. Each is `struct X: Hashable, Codable, Sendable { let rawValue: UUID }`.

Units:

```swift
public struct Weight: Hashable, Codable, Sendable, Comparable {   // exact grams, never Double (ADR-007)
    public let grams: Decimal                                   // .pounds(185) = 83,914.58845 g, not rounded
    public static func pounds(_ lb: Decimal) -> Weight
    public static func kilograms(_ kg: Decimal) -> Weight
    public func rounded(toStep step: Weight) -> Weight          // the only rounding, where a rule asks for it
}
public struct CivilDate: Hashable, Comparable, Codable, Sendable { public let year, month, day: Int }  // "YYYY-MM-DD"
public struct Reps: Hashable, Codable, Sendable { public let value: Int /* ≥ 1 */ }
public enum Units: String, Codable, Sendable { case lb, kg }
```

Entities (all `struct`, `Equatable`, `Sendable`, `Codable`):

| Type | Key fields |
|---|---|
| `Exercise` | id, name, shortName, equipment (`barbell/dumbbell/cable/machine/bodyweight`), primaryMuscle, secondaryMuscles, movementPattern, defaultStartLoad, isCustom, curatedAlternatives: [ExerciseID] |
| `Program` | id, name, startDate (`CivilDate`, ADR-007), weeks: [Week], days: [DayTemplate], goal, daysPerWeek, isActive |
| `Week` | id, index, isDeload, schedule: [Weekday: DayTemplateID?] |
| `DayTemplate` | id, name, tag, slots: [Slot] |
| `Slot` | id, exercise, sets (1–12), reps (1–30), repsHi (2–40), rpe (5–10 by 0.5), rest (30–300 s by 15), progression (`linear/double/fixed`), startLoad, step?, isSupersetWithPrevious, dropSets (0/1), misses: Set<Int> |
| `Prescription` | load, sets, reps, rpe, rest, step, progression, isHeld, isDeload — computed by `ProgressionRules.prescribe(week:slot:)` per spec §7.2 |
| `WorkoutState` | id, source (program/week/day or ad-hoc), exercises: [WorkoutExercise], cursor (slot, set), rest: `RestTimer?` (`endsAt`, `total`), startedAt, finishedAt/discardedAt, phase (`idle/live/finished/discarded`) |
| `WorkoutExercise` | id, exercise snapshot (id, name, equipment, step, rest, rpe, isSupersetWithPrevious), target (sets, reps, load), sets: [LoggedSet], lastPerformance? |
| `LoggedSet` | id, weight, reps, kind (`working/drop/added/warmup`), doneAt? |
| `WorkoutSummary` | elapsed, doneSets, totalSets, volume, prs: [PersonalRecord], rows for the receipt |
| `PersonalRecord` | exercise, kind (`e1RM/weightAtReps`), value, previous |
| `Settings` | units, defaultRest, plateMath, autoRest, watchBuzz, weekStart, bar/plate inventory per unit |

Pure services in `LedgerDomain` (all unit-tested to ~100 %):

- `WorkoutEngine.reduce` — ADR-004.
- `ProgressionRules.prescribe` — linear / double / fixed / deload / held.
- `SessionBuilder.build(program:week:day:history:)` — spec §7.3 incl. drop sets and last-performance lines.
- `SupersetRounds` — display order A1 B1 A2 B2 … AD BD, "last of round" detection, group rest.
- `OneRepMax.brzycki(weight:reps:)` (r ≤ 12).
- `PersonalRecords.detect(finished:history:)`.
- `PlateMath.perSide(load:bar:plates:)`.
- `TimeEstimate.minutes(day:)` — one formula (decision #14).
- `WeekCalendar` — civil startDate → current week index, week boundaries (each the start of its own calendar day, ADR-007), off-schedule days.
- `MissTracking.update(slot:workout:)` — decision #5.

The seed exercise catalog ships as `Resources/exercises.json` inside
`LedgerDomain` with a decoding test that validates every entry (unique IDs,
known equipment/muscle enums, alternatives resolve).

---

## 6. The live workout: `WorkoutEngine` (ADR-004)

```swift
public enum WorkoutEngine {
    public static let longestRest: Duration                                            // 1 h
    public static func reduce(_ state: WorkoutState?, _ envelope: EventEnvelope)
        -> (WorkoutState?, [Effect])                                                   // own envelopes only
    public static func replay(_ log: [EventEnvelope]) -> WorkoutState?                 // sorted, deduped by (device, seq)
    public static func effects(from old: WorkoutState?, to new: WorkoutState?) -> [Effect]  // a rebuild's effects
    public static func summary(_ state: WorkoutState, prs: [PersonalRecord]) -> WorkoutSummary
}
public enum Effect: Hashable, Sendable {
    case haptic(Haptic)                 // .setLogged, .restOver, .personalRecord, .workoutFinished
    case scheduleRestNotification(endsAt: Date)
    case cancelRestNotification
    case updateLiveActivity
    case persist(EventEnvelope)         // before .transmit
    case transmit(EventEnvelope)
    case materialize(WorkoutState)      // F05 writes the rows and the receipt (summary)
    case discardLog
}
```

The shipped API is in `LedgerDomain/Engine` (with `WorkoutEventStore` in `LedgerDomain/Protocols`); the
rules are ADR-004's amendment (hybrid logical clock, the clock rule, malformed envelopes, the host loop).

- Both apps hold a `WorkoutSessionActor` (in `LedgerSync`) that owns the log,
  applies local intents (creating envelopes with its `DeviceID`, next `seq` and
  a hybrid-logical-clock `wallClock`), rebuilds by `replay` on received
  envelopes, and publishes `WorkoutState` as an `AsyncStream`.
- The rest timer is `RestTimer(endsAt: Date, total: Duration)`. Views render
  with `TimelineView`/`Text(timerInterval:)`; no tick events cross devices.
- On `finished`, `LedgerPersistence` materialises normalized rows and computes
  PRs and misses; the event log is compacted after that transaction commits.
- Recovery: on launch, each log in `WorkoutEventStore.uncompactedWorkoutIDs()`
  is replayed: live → resume, ended → materialise or drop; both apps also hook
  HealthKit recovery (`handleActiveWorkoutRecovery` / `shouldHandleActiveWorkoutRecovery`).

---

## 7. Persistence (`LedgerPersistence`, GRDB) — ADR-002

Principles: UUID primary keys everywhere; **no UNIQUE constraints** and only
additive migrations so the same schema can sync through CloudKit later
(R2 §1, §3); foreign keys on with `ON DELETE CASCADE` locally; sync applies
parents before children.

Tables (`snake_case`; all rows carry `created_at`, `updated_at`, and a
nullable `deleted_at` soft-delete for sync):

| Table | Purpose | Synced to iCloud (M4) |
|---|---|---|
| `exercise` | catalog + custom exercises | yes (custom only; seed is code) |
| `program`, `program_week`, `day_template`, `slot`, `slot_miss` | programming | yes |
| `workout`, `workout_exercise`, `logged_set` | finished history | yes |
| `workout_health` | avg/max HR, active energy, HealthKit workout UUID | **never** (App Review 5.1.3(ii), R1 §3.4) |
| `workout_event` | live event log (envelopes) | never; compacted after finish |
| `settings` | single-row preferences + plate inventory | yes |
| `device` | this device's `DeviceID`, name, last sync marks | never |

Indexes: `logged_set(workout_exercise_id)`, `workout_exercise(exercise_id, workout_id)`,
`workout(finished_at)`, `workout_event(workout_id, device_id, seq)`.

Repositories (protocols in Domain, GRDB implementations here):
`ExerciseRepository`, `ProgramRepository`, `WorkoutRepository`,
`WorkoutEventStore`, `SettingsRepository`, `StatsQueries` (last performance
per exercise, best set, e1RM by week, weekly volume + delta, sessions this
week, PR history). Every query has an integration test; the aggregate queries
have a performance test seeded with 20 000 sets (budget < 50 ms each on a
simulator).

Live reads: `ValueObservation` → `AsyncSequence` of Domain values; stores
consume them in `.task`.

File protection: `completeUntilFirstUserAuthentication`; the watch store lives
in the app container (R2 notes the historical 0xdead10cc suspend issue; we
close write transactions promptly and never hold the DB across suspension).

---

## 8. Phone ⇄ watch synchronisation (`LedgerSync`) — ADR-005

Two channels, two jobs:

**Live workout (events):** HealthKit workout mirroring data channel.
- Watch: `HKWorkoutSession` → `prepare()` → wait for `.prepared` →
  `startMirroringToCompanionDevice()` (DTS workaround for the 26.0.x regression,
  R1 §2.5) → `sendToRemoteWorkoutSession(data:)` per envelope, batched.
- Phone: `workoutSessionMirroringStartHandler` assigned at launch; keeps a
  strong reference to each mirrored session (handler may fire multiple times
  with new session objects on reconnect); receives `[Data]` batches;
  sends its own envelopes back on the same channel.
- Phone-initiated start: `HKHealthStore.startWatchApp(toHandle:)`.
- Latency-boost: while `WCSession.isReachable`, the same envelopes are also
  sent via `sendMessageData`; receivers dedupe by `(device, seq)`.
- Loss tolerance: every envelope is idempotent and ordered; on reconnect each
  side sends "your highest seq I have" and the peer replays the gap. If the
  mirroring send hangs (~5 % reports), a watchdog times out and falls back to
  WatchConnectivity; the watch never blocks logging on transport.

**Everything else (programs, settings, completed-workout pull-back):**
- `updateApplicationContext` — current program + next scheduled day (small, latest-wins).
- `transferFile` — full program JSON and history snapshots.
- `transferUserInfo` — ordered small records (a finished workout logged on the watch while the phone was away).

Reconciliation of a workout finished on both devices independently: same
`WorkoutID`, union of event logs, replay → one canonical workout. Property
tests cover shuffle/duplicate/partition scenarios.

---

## 9. HealthKit (`LedgerHealth`)

- Authorization requested lazily at first "Start workout", on the phone
  (which prompts for both devices). Both targets declare
  `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`
  (missing keys crash, R1 §3.3). HealthKit entitlement on both.
- Watch: `HKWorkoutConfiguration(activityType: .traditionalStrengthTraining, locationType: .indoor)`;
  `HKLiveWorkoutBuilder` with `HKLiveWorkoutDataSource` collects HR + active
  energy automatically; HR stream published to the UI; workout ended and saved
  with metadata (total volume, program/day names). Background mode
  `workout-processing`.
- Haptics pause HR sampling briefly (R1 §3.1) — acceptable; we play only on
  set-logged, rest-over, PR.
- Phone: mirrored session gives live HR for the phone UI; the phone never
  writes the HealthKit workout (the watch does). If a workout is logged purely
  on the phone with no watch (possible), the phone saves it via
  `HKWorkoutBuilder` without HR.
- Recovery: watch `handleActiveWorkoutRecovery()` →
  `recoverActiveWorkoutSession()`; iOS 26+ `shouldHandleActiveWorkoutRecovery`.
- Only one watch workout session may run; starting Ledger while Apple Workout
  is running ends ours with `errorAnotherWorkoutSessionStarted` — surfaced as
  a user-facing state.

`HealthStore` is a Domain protocol with a `LiveHealthStore` actor and a
`FakeHealthStore` in `LedgerTestSupport`; all logic that reacts to health
events is tested through the fake.

---

## 10. iCloud sync (M4)

CKSyncEngine against the private database. Preferred implementation:
Point-Free **SQLiteData** (GRDB-based, field-wise last-write-wins, watchOS 10+)
if it fits our schema; fallback is a hand-rolled `SyncActor` following Apple's
sample. Watch does **not** sync to CloudKit directly (unreliable background
sync, R2 §3); it syncs to the phone via §8, and the phone syncs to iCloud.
`workout_health`, `workout_event`, and `device` are excluded.

---

## 11. Design system (`LedgerDesign`)

Source of truth: `docs/product-spec.md` §8. Encoded as:

- `LedgerColor` — semantic tokens (`ground`, `surface`, `ink` at fixed alphas, `hairline`, `accent`, `accentText`, `watch…`) with light + dark values from §8.1–8.3, nudged where needed so every text token meets WCAG AA (F06 notes, decision 7). Adaptive colours are a dynamic `UIColor` on iOS, with stronger ink alphas under Increase Contrast; watchOS has one (dark) appearance. Accent usage rule: once per screen, on the primary action.
- `LedgerFont` — 21 roles (`display` … `numeralS`, `watch…`) with the v2 prototype's size, `wght`, `wdth`, line height and tracking. The Archivo variable font ships once, as a `LedgerDesign` resource; the apps' `UIAppFonts` point into that resource bundle (`LedgerKit_LedgerDesign.bundle/…`), and previews and package tests register it on first use (`FontRegistration`). Axes are set with a `CTFontDescriptor` carrying `kCTFontVariationAttribute` (`'wght'` 2003265652, `'wdth'` 2003072104), wrapped as `Font(ctFont)`. Views use `.ledgerFont(.role)`, which reads Dynamic Type and Bold Text from the environment (size on SwiftUI's custom-font curve for the role's text style; Bold Text = one weight step up) and applies tracking, case and `lineHeight`. The `Font` entry points take the text size explicitly (`LedgerFont.font(_:dynamicTypeSize:)`), because a Core Text instance cannot follow the environment by itself. Tabular figures for every numeral role; watch roles never go below 11 pt.
- `LedgerSpacing`, `LedgerRadius` (pill 999, card 26, sheet 28), `LedgerHairline`, `LedgerMotion` (`snappy`, `ledgerBuzz(trigger:)` with a Reduce Motion opacity variant).
- Components: `PrimaryButton`, `PillButton`, `HairlineList/Row`, `SetRow`
  (with steppers), `RestRing`, `WeekStrip`, `StatTile`, `ProgressSegments`,
  `Eyebrow`, `SwapSheet`, `TabBar` (native `TabView` tinted; the custom
  prototype bar is not replicated), watch variants where needed.
- Every component has snapshot tests: light + dark × 3 Dynamic Type sizes;
  watch components at 42 / 46 / 49 mm.

---

## 12. Feature modules

| Module | Screens (prototype labels) | Owns |
|---|---|---|
| FeatureOnboarding | Onboarding (3 steps) | goal/days choice → template program generation |
| FeatureToday | Today | week strip, up-next / logged / rest-day cards, stats, recent |
| FeatureWorkout | Active workout, Rest, Swap exercise, Session receipt | phone-side live workout UI over `WorkoutSessionActor` |
| FeatureProgram | Program builder, Day editor, Exercise library sheet | block/week/day/slot editing, progression preview |
| FeatureLibrary | Library, Exercise history | search/filter, exercise detail, e1RM chart, session log |
| FeatureHistory | Workout list, Workout detail (new per decision #11) | past workouts, edit/delete |
| FeatureSettings | Settings | units, rest, plate inventory, toggles, export CSV, Health status |
| WatchFeatureWorkout | Watch — before workout / set ready / rest timer / session list / end workout / summary | watch UI over the same `WorkoutSessionActor` |

Each feature exposes `public struct <Feature>Root: View` and `public enum
<Feature>Route`. The app shell maps routes across features.

---

## 13. Dependency injection keys (`swift-dependencies`)

`date`, `uuid`, `calendar`, `locale`, `continuousClock`, `exerciseRepository`,
`programRepository`, `workoutRepository`, `workoutEventStore`,
`settingsRepository`, `statsQueries`, `healthStore`, `liveWorkoutTransport`,
`companionTransport`, `haptics`, `notifications`, `liveActivities`, `logger`.
Each has `liveValue`, `testValue` (unimplemented → test failure), and where
useful `previewValue`. Stores never construct their dependencies.

---

## 14. Observability

- `os.Logger` subsystem `com.petearevalo.Ledger`, category per module; signposts around
  DB aggregates and sync round-trips.
- MetricKit for launch/hang/crash diagnostics at launch; no third-party crash
  SDK initially (keeps the privacy manifest trivial).
- A debug-only "Diagnostics" screen in Settings: sync state, event log size,
  HealthKit auth state.

## 15. Performance budgets

| Metric | Budget |
|---|---|
| Cold launch to Today (iPhone 15 class) | < 600 ms |
| Set logged → other device reflects (reachable) | < 1 s |
| Any stats query (20 k sets) | < 50 ms |
| Watch set-ready screen update on crown detent | next frame |
| App size (iOS) | < 15 MB |

## 16. Privacy & security

- No accounts, no analytics, no third-party SDKs at launch.
- Health data (HR, energy) stays in HealthKit and the local `workout_health`
  table; never leaves the device except to HealthKit.
- `PrivacyInfo.xcprivacy` declares required-reason APIs used (UserDefaults,
  file timestamps) — see R3.
- Export CSV contains only the user's log (no health values by default).

## 17. Known technical risks (tracked in `tasks/todo.md`)

1. HealthKit mirroring reliability on 26.x/27.0 (R1 §2.5) → mitigated by watch
   authority, idempotent envelopes, WC fallback, device-only test checklist.
2. Variable-font width axis on watchOS via CoreText — **closed by the F06 spike
   (2026-09-27): no fallback needed.** A `CTFontDescriptor` with
   `kCTFontVariationAttribute` renders `wdth` 62 / 88 / 100 / 112 / 125 as
   118 / 158 / 176 / 198 / 223 px wide ("0123456789", 30 pt, wght 700, 1×) on
   the watchOS 26.5 simulator, identical to iOS 26.5
   (`ArchivoFontTests.widthAxis_88versus112_rendersDifferentGlyphWidths`, with
   the rendered sheet committed as a snapshot on both platforms). Still to see
   on hardware: F20's device checklist; complications are unverified (R2 §6.2).
3. CKSyncEngine + GRDB integration surface (SQLiteData fit) → M4 spike before committing.
4. Xcode 27 is only on GitHub's `xcode-27` preview image (actions/runner-images#14404). F32 pins 27.0 locally, in CI and in Xcode Cloud (Pete, 2026-09-29); if the preview breaks, CI falls back to `macos-26` with 26.6 (ADR-006, amendment). The minimum OS stays 26, so any 27-only API is guarded with `#available` and feature-flagged.
5. Xcode synchronized folders keep `project.pbxproj` nearly frozen; the rare edits (new target, entitlement) are done in Xcode by a human and verified by CI (ADR-003).
