# F08 — implementation notes

Planning pass only (no code written, nothing built or run). Grounded in `main` at `a526874`; every "main has"
below was read in the worktree. Paths are from the repo root. The brief is `tasks/features/F08-onboarding.md`.

## Slice plan (planning agent, 2026-10-04)

Product code lines are non-blank, non-comment lines; tests, `LedgerTestSupport`, `LedgerSnapshotTesting`, docs and
string catalogs are excluded; `LedgerFakes` is counted separately. Slices are strictly sequential (no stacked PRs).

| Slice | Contents (files and types) | Criteria covered | Est. product lines | Depends on |
|---|---|---|---|---|
| **S1 — template generator** (`feat/F08-s1-templates`) | New folder `LedgerKit/Sources/LedgerDomain/Templates/`: `DaysPerWeek.swift` (`enum DaysPerWeek: Int`), `ProgramTemplates.swift` (public API: `program(...)`, `preview(days:)`, `startDate(containing:weekStart:calendar:)`, `weekCount`, `ProgramTemplateError`; the builder), `ProgramTemplates+Splits.swift` (the four splits: program name, weekdays, days with name / tag / preview line / slots with role, supersets, drop set), `ProgramTemplates+Prescriptions.swift` (role table × 4 goals; the spec §6.4 table for `both` × `four`). `LedgerKit/Sources/LedgerFakes/Fixtures/Fixtures+Templates.swift`: `Fixtures.defaultProgram(startDate:)` built by the generator over the bundled catalog (what F09 calls "the F08 default program"). Tests: `LedgerDomainTests/Templates/` (table, ranges, names, determinism, start date, session build), `LedgerDependenciesTests/FixturesTests` (+2), `LedgerPersistenceTests/TemplateProgramRoundTripTests` (GRDB). One bullet in `docs/architecture.md` §5. No existing Domain file is edited. | 6 (every column but load, see "Brief vs main"), 7, 9; the data half of 3, 8 and 11; DoD "ProgramTemplates 100 %", "every name resolves" | Domain ≈ 360; LedgerFakes ≈ 25 | `main`. Pete decisions 1, 3, 4 (defaults let it start). Orchestrator decisions O4–O7, O17. |
| **S2 — onboarding screen** (`feat/F08-s2-onboarding-ui`) | `LedgerKit/Sources/FeatureOnboarding/`: `OnboardingRoot.swift` (public view; owns the store and the `.task`s), `OnboardingStore.swift` (`@Observable @MainActor`), `OnboardingPresentation.swift` (`OnboardingStepModel` + pure `make`), `OnboardingStrings.swift`, `Views/OnboardingStepView.swift`, `Views/OnboardingOptionRow.swift`, `Views/ProgramPreviewList.swift`, `Onboarding+Previews.swift` (`OnboardingPreview` registry), `Resources/Localizable.xcstrings`. Deletes the placeholder `FeatureOnboarding.swift` and its test. Shared files: `Package.swift`, `scripts/coverage-thresholds.json`, `PreviewScan.swift` (exact lines in "Seams"). Tests in `FeatureOnboardingTests`: store, presentation, accessibility tree, snapshots (18 PNGs), preview registry, string catalog. **Not wired into the app yet**: the app still opens on Today, so the slice is safe to merge alone. | 2, 3, 10, 12; the store half of 1, 4, 5, 8 | FeatureOnboarding ≈ 480 (≈ 55 of it the preview registry). If the implementer's count passes ~600, split at the agreed seam: S2a store + presentation + strings (≈ 255), S2b views + previews + snapshots (≈ 235). | S1. The localization scaffolding (row L0). Pete decisions 2, 5. Orchestrator decisions O1–O3, O8–O10, O14. |
| **S3 — root gate and UI tests** (`feat/F08-s3-root-gate`) | `LedgerKit/Sources/LedgerAppKit/RootGate.swift` (new: `.loading / .onboarding / .main` from `ProgramRepository.observeActive()`), `AppRoot.swift` (the `.ready` branch and the `.task`), `LedgerAppKitTests/RootGateTests.swift`. UI tests: `Apps/LedgerUITests/Support/LaunchedApp.swift` (new helper), `Smoke.swift`, `DebugMenu.swift`, `LaunchPerformance.swift` (updated), `Onboarding.swift` (new, nightly). One line each in `docs/architecture.md` §4 and `docs/testing-strategy.md` §2.7. `AppComposition.swift` is not edited. | 1, and the root half of 4, 5, 11 (the words "Week 1 of 8" on Today are F09's) | LedgerAppKit ≈ 70 | S2. F09's tab-shell slice if it has merged (S3 then wraps the shell; otherwise it wraps `TodayPlaceholder`). Orchestrator decisions O11–O13. |
| **L0 — localization scaffolding** (shared, not an F08 slice unless assigned here) | `defaultLocalization: "en"` in `Package.swift`; `LedgerTestSupport/Localization/StringCatalogScan.swift` (reads a module's `Localizable.xcstrings` and its `String(localized:)` literals, as `PreviewScan` reads `#Preview`s) with its tests; a paragraph in `docs/engineering-standards.md` §7. | none (DoD "String Catalog contains every string") | 0 (≈ 60 lines of `LedgerTestSupport`, 1 manifest line) | Orchestrator decision O1. Recommended as its own small PR before any lane's first UI slice; otherwise it rides in S2 and the other lanes' UI slices rebase on S2. |

Total ≈ 935 product lines over three PRs.

### Corrected `ProgramTemplates` signatures (replaces the brief's "Domain changes" block)

**Superseded by "The API as built" under "Slice S1 — template generator" (rulings after G2 and G3): code against that one.**

```swift
// LedgerDomain/Templates/DaysPerWeek.swift — the generator's input only; Program.daysPerWeek stays Int?
public enum DaysPerWeek: Int, Codable, Sendable, CaseIterable { case three = 3, four, five, six }

// LedgerDomain/Templates/ProgramTemplates.swift
public enum ProgramTemplateError: Error, Equatable, Sendable {
    /// A template exercise is not in the catalog given (not seeded yet: product decision #28).
    case unknownExercise(String)
}

public enum ProgramTemplates {
    public static let weekCount = 8

    public struct DayPreview: Hashable, Sendable { public let name: String; public let tag: String; public let exercises: String }
    public struct Preview: Hashable, Sendable { public let programName: String; public let days: [DayPreview] }

    /// Step 3's list. Needs no catalog and no ids; the goal changes prescriptions, not names.
    public static func preview(days: DaysPerWeek) -> Preview

    /// Decision #18: the first day (on `weekStart`) of the week that holds `now`, in `calendar`'s time zone.
    public static func startDate(containing now: Date, weekStart: Weekday, calendar: Calendar) -> CivilDate?

    /// Deterministic: the same inputs and the same `newID` sequence give an equal Program.
    /// `newID` is called in a documented order: weeks 0…7, then each day (its id, then its slots in order).
    /// `catalog` is the stored exercises (`exerciseRepository.all()`); custom exercises are ignored.
    /// The program is active, 8 weeks, week 8 a deload; goal and days.rawValue are recorded.
    public static func program(
        goal: TrainingGoal, days: DaysPerWeek, units: Units, startDate: CivilDate,
        catalog: [Exercise], id: ProgramID, newID: () -> UUID
    ) throws -> Program
}
```

`TrainingGoal` is the type on main, with main's case names; the brief's names map as `stronger → .strength`,
`muscle → .hypertrophy`, `both → .both`, `consistent → .consistency`. `program` is plain `throws` so `Slot.init`
and `Program.init` propagate with `try` and no unreachable `catch` (the DoD asks for 100 % line coverage); its one
own throw, `unknownExercise`, is reachable with an empty catalog.

## Brief vs main

| The brief says | Main has (file:line) | The plan does |
|---|---|---|
| New `LedgerDomain/Programs/TrainingGoal.swift` with `TrainingGoal { stronger, muscle, both, consistent }` | `TrainingGoal { strength, hypertrophy, both, consistency }` already exists: `LedgerDomain/Model/Program.swift:4-6`. Its raw value is stored in `program.goal` (`LedgerPersistence/Migrations.swift:66`, `Records/ProgramRecords.swift:45`). There is no `Programs/` folder. | Keeps main's cases (a rename would change stored values and the schema fixture). The option labels map to them in `OnboardingPresentation`. |
| `Program.goal: TrainingGoal`, `Program.daysPerWeek: DaysPerWeek`; "adapt F02 with a migration if typed differently" | `goal: TrainingGoal?`, `daysPerWeek: Int?` (`Program.swift:20-21`); `days_per_week INTEGER` (`Migrations.swift:67`). No `DaysPerWeek` type anywhere. | No retyping, no migration. `DaysPerWeek` is new and only types the generator's input; the program stores `days.rawValue`. `Int?` stays right for a block the builder (F11) can later give any number of days. |
| `program(... startDate: Date ...) -> Program` | `Program.startDate: CivilDate` (`Program.swift:17`, ADR-007). `Program.init` and `Slot.init` throw (`Program.swift:33`, `Slot.swift:52`; errors in `LedgerDomain/Errors.swift:4-33`). | Signatures above. |
| `WeekCalendar.startOfWeek(containing: today, weekStart:)`; criterion 11 names `WeekCalendar.currentWeekIndex` | The API is the instance method `firstDayOfWeek(containing:) -> CivilDate?` (`Rules/WeekCalendar.swift:77`, whose comment names F08) and `weekIndex(for:)` (`:53`); a `WeekCalendar` needs a `startDate` to exist (`:36`). | `ProgramTemplates.startDate(containing:weekStart:calendar:)` wraps it (a throwaway calendar anchored on today), so `WeekCalendar.swift`, which F09 edits, is untouched. Tests use `weekIndex(for:)`. |
| "Start load = `exercise.defaultStartLoad` rounded to the unit's step"; criterion 6 "every slot equals spec §6.4", whose load column is 180 / 250 / 315 lb | Product decision #21 (2026-09-30, after the brief) replaced the prototype's loads for "every catalog exercise, the 22 prototype ones included": Bench is 45 lb / 20 kg, Deadlift 95 lb / 40 kg (`LedgerDomain/Resources/exercises.json`). Every catalog load is already a multiple of its unit's step (`Catalog/CatalogEntry.swift:47-52`). `Exercise.startLoad(in:)` is `Model/Exercise.swift:71`. | `slot.startLoad = exercise.startLoad(in: units)`, copied into the slot (decision #24: "programs copy loads into their slots"); `slot.step = nil`. Criterion 6 is asserted for every §6.4 column **except load and step**; load is asserted equal to the catalog's. |
| "Every name must resolve in the F03 catalog" | 224 exercises. All 22 full names in the 3 / 5 / 6-day lists and in §6.4 resolve exactly (checked by script). The brief's 4-day role line uses shorthand that does not: Bench → Barbell Bench Press, Incline DB → Incline DB Press, CS Row → Chest-Supported Row, Pulldown → Lat Pulldown, Lateral → Cable Lateral Raise, Squat → Back Squat, RDL → Romanian Deadlift, Calf → Standing Calf Raise, OHP → Overhead Press, Row → Barbell Row, Curl → Barbell Curl, Leg Curl → Seated Leg Curl. **Trap:** "Pull-Up" does resolve, to the wrong exercise (the unweighted "Pull-Up", start load 0); §6.4 means "Weighted Pull-Up". Short names are no help either: `PULL-UP` is the weighted one's short name. | Templates use the full §6.4 names and match on `name` exactly, among non-custom exercises. A Domain test pins every template name to the bundled catalog. |
| Fixture in `LedgerTestSupport/Fixtures/ProgramFixtures.swift`: `Program.fourDayDefault(startDate:)` | Fixtures live in `LedgerFakes` (ADR-008). `Fixtures.seedProgram()` already exists (`LedgerFakes/Fixtures/Fixtures+Program.swift:139`). | Adds `Fixtures.defaultProgram(startDate:)` in LedgerFakes; leaves `seedProgram()` alone (F05 and F07 suites assert its numbers). See "What F09 can use" below. |
| `Apps/Ledger/Sources/RootView.swift`: one branch, "no active program → OnboardingRoot, else tabs" | `Apps/Ledger/` holds only `LedgerApp.swift`. The root is `LedgerAppKit/AppRoot.swift:24-38`; `.ready` shows `TodayPlaceholder` (`:27`). No `TabView` exists in the repo. | S3: `RootGate` plus a switch in the `.ready` branch. |
| `FeatureOnboarding/Resources/Localizable.xcstrings`; "no literals in `Text(...)`" | No `.xcstrings` in the repo; no `defaultLocalization` in `Package.swift`; no lint rule about string literals (`.swiftlint.yml`). Components take `String` and draw it verbatim (`PrimaryButton.swift:17`, `PillButton.swift:16`, `HairlineRow.swift:17-22`, `ProgressSegments.swift:36`); LedgerDesign's own words use `String(localized:bundle: .module)` (`SetRow.swift:146`). | The pattern in O1. |
| `Views/StepProgressBars.swift` | `ProgressSegments` exists and is one VoiceOver element with a label and a value (`LedgerDesign/Components/ProgressSegments.swift:27-55`). | Reuses it (three segments, `.current` up to the step, `.upcoming` after). 3 pt gaps instead of the prototype's 5. |
| `OnboardingRoute.swift` | — | No route: onboarding's only exit is the saved active program, which the root observes (O3). |
| Body copy "This sets how your loads progress week to week." | The prototype still says "…how Ledger progresses…" (`design/prototype/Ledger v2.dc.html:416`). | The brief's wording (shipped copy never names the product). |
| Criterion 4: "`startDate` = start of the current week per `settings.weekStart`" | `Settings.default.weekStart` is `.monday` (`Model/Settings.swift:46`). The comment above it says the app seeds it from the locale on first launch (`:37-39`, decision #15); nothing on main does (`Weekday.first(of:)` is called only in tests). Units default to `.lb` the same way. | Reads the stored settings. Whether first launch should follow the iPhone's region is Pete decision 5. |
| Criterion 8: "units = kg (set before onboarding via F14 fixture)" | `Fixtures.settingsKg` (`LedgerFakes/Fixtures/Fixtures.swift:69`), `InMemoryStores.Seed(settings:)` (`InMemoryStores.swift:25-39`). | Uses those. |
| Criterion 10 and "Inputs from F07": catch the save's `unknownExercise` | `RepositoryError.unknownExercise` (`Protocols/RepositoryError.swift:43`); `InMemoryStores.Seed.empty` (`InMemoryStores.swift:48`); the fake refuses as GRDB does (`InMemoryProgramRepository.swift:112-114`). | Any failure of "read settings, read catalog, generate, save" shows the retry and is logged; with an unseeded catalog the generator's `unknownExercise` comes first. Tested on `.inMemoryStores(seed: .empty)`. |
| `preview(goal:days:)` | — | `preview(days:)`: no goal changes a name or a line. |
| "`ProgramTemplates.program` < 5 ms" | Decoding the catalog alone has a 20 ms budget (`LedgerDomainTests/Catalog/ExerciseCatalogPerformanceTests.swift`). | The generator takes the catalog as a parameter and never decodes it. A nightly timing test, like the catalog's. |
| "`ProgramTemplates` at 100 % line coverage" | The gate is per module: `LedgerDomain` 95 (`scripts/coverage-thresholds.json`). | The reviewer reads the file's coverage; the design has no unreachable branch. |
| Test names `test_…`; snapshots "× {default, XL type}" | Convention is `subject_condition_expectation` with a sentence in `@Test("…")` (`docs/testing-strategy.md` §6); the matrix is light / dark × `.large`, `.xLarge`, `.accessibility3` (§2.5; `assertLedgerSnapshot`, `LedgerSnapshotTesting/LedgerSnapshot.swift:73`). | Renamed; matrix in "Test plan changes". |
| "UI (LedgerUITests): F15 flow" | Three UI tests on main look for `today.title` after a fresh launch (`Apps/LedgerUITests/Smoke.swift:15`, `DebugMenu.swift:16`, `LaunchPerformance.swift:20`); `-LEDGER_UITEST` gives a new empty database (`AppComposition.swift:165-167`). | S3 fixes them. |
| DoD "Screenshots … at default and AX5" | The snapshot matrix tops out at `.accessibility3`. | AX5 screenshots are taken by hand for the S2 PR. |

### What F09 can use before F08 merges

`Fixtures.seedProgram()` (`LedgerFakes/Fixtures/Fixtures+Program.swift:139`) equals spec §6.4 field by field: the
16 slots' exercise, sets, reps, `repsHi` (reps + 2), RPE, rest, progression and load (the prototype's pounds), the
supersets on Upper A slot 5 and Lower A slot 4, the drop set on Upper B slot 4, weeks 1–7 Mon / Wed / Fri / Sat and
week 8 Mon / Wed / Fri as a deload, name "Upper / Lower", goal `.both`, 4 days, active (`FixturesTests` pins most of
it). It differs from what F08 generates in three ways only:

| | `Fixtures.seedProgram()` | F08's default (`Fixtures.defaultProgram()`, after S1) |
|---|---|---|
| Start loads | the prototype's (Bench 180 lb) | the catalog's (Bench 45 lb / 20 kg, decision #21) |
| Start date | 2026-08-17 (`Fixtures.now` is in week 5) | first day of the current week (2026-09-14 for `Fixtures.now`) |
| Ids | `Fixtures.uuid(200…)`, `(300…)` | from the injected sequence |

So F09 can start today on `var program = try Fixtures.seedProgram(); program.startDate = CivilDate(year: 2026,
month: 9, day: 14)` (`startDate` is a `var`): same days, schedule, sets, rests and time estimates. Anything that
asserts a load ("5 × 5 @ 180") should say which fixture it means and move to `Fixtures.defaultProgram()` after S1.

## Seams with F09, F10 and later features

Shared files and exactly what F08 changes in each:

| File | F08's change | Slice | Others |
|---|---|---|---|
| `LedgerKit/Package.swift` | `defaultLocalization: "en"` after `name:` (`:73`), once for all lanes; `FeatureOnboarding` target (`:125`) gains `resources: [.process("Resources")]`; `snapshotTestTargets` (`:67`) gains `"FeatureOnboarding"`. **No new edge**, so `LedgerKit/package-graph.expected.txt` does not change for F08 (the checker prints dependencies only). | L0 / S2 | F09 and F10 add the same two things for their targets, on other lines. |
| `scripts/coverage-thresholds.json` | `"required"` (`:15`) gains `"FeatureOnboarding"`. Needed: the gate fails a module that has coverage and is not listed (`scripts/coverage-gate.sh:106-107`). No threshold changes (`Feature*` is 70). | S2 | F09 adds `FeatureToday`, F10 `FeatureWorkout`, on the same one-line array: a certain conflict, trivial to resolve. Whoever lands first could put the array one name per line. |
| `LedgerTestSupport/Previews/PreviewScan.swift:9` | `registeredModules` gains `"FeatureOnboarding"` (else `LedgerDesignTests/PreviewTests.swift:42` fails). | S2 | Same line for every lane. |
| `LedgerTestSupport/Localization/StringCatalogScan.swift` | New, shared by all features. | L0 | One implementation, one owner (O1). |
| `LedgerFakes/Fixtures/` | New file `Fixtures+Templates.swift`; existing fixtures untouched. | S1 | F10 adds its own files. |
| `LedgerDomain/` | New folder `Templates/` only. | S1 | F09 edits `Rules/WeekCalendar.swift`; F10 adds the session client. No overlap, but all three are Domain public-API additions, so the workflow rule serializes their merges. |
| `LedgerAppKit/AppRoot.swift` | `@State private var gate = RootGate()` beside `:9`; the `.task(id: scenePhase)` at `:19-21` also follows the active program after `resume`; the `.ready` case at `:26-32` becomes a switch on `gate.destination`, with today's content moved unchanged into `.main`. | S3 | F09's shell replaces what `.main` shows (`TodayPlaceholder` at `:27`). F10's full-screen cover should hang on the `.main` content, not around the gate. |
| `LedgerAppKit/AppComposition.swift` | None. The gate reads `composition.stores?.programs` (`:61`), as Diagnostics reads the composition's own stores; the retry hook calls the existing `resume(in:)` (`:96`). | — | F10 binds its key in `bind` (`:128-136`). |
| `Apps/LedgerUITests/*` | A helper that reaches Today by tapping "Skip setup"; the three existing tests use it; one new `Onboarding` test. | S3 | F09 must keep `today.title` and the Debug long press on it (`TodayPlaceholder.swift:15,17`), or change the helper. F15 later replaces the helper's body with its seeded launch mode. |
| `docs/` | architecture §5 (S1), §4 and testing-strategy §2.7 (S3), standards §7 (L0). | | |

Other seams:

- **F09's "No program" card is unreachable once S3 merges.** F08 (criterion 1) and F14 (criterion 6) both send
  "no active program" to onboarding, and nothing in M1 deletes a program any other way. F09's criterion 8 and its
  `.setUpProgram` route then describe a state the lifter never sees. F08 needs nothing from them; the orchestrator
  may keep the card as a defensive state or drop it.
- **F09 criterion 1** asks for "five preview rows" on Lower A; §6.4 gives Lower A four slots.
- **F14 "Delete all data"** recreates the database. The gate follows the stores it was given; F14 must make the root
  follow the new ones (re-run the `.task`).
- **F11** edits what F08 generates: slots have an explicit `startLoad` and `step == nil`.
- **F15** owns the seeded launch mode and the accessibility audit; F08 only keeps the existing UI tests green.
- **Found while reading, not F08's:** `DatabaseUnavailableView` says "Ledger tries again…" (`AppRoot.swift:46`),
  against the naming rule; `LedgerAppKit`'s strings have no catalog yet.

**Proposed merge order.** (1) L0, F08-S1 and the other lanes' Domain slices, built in parallel, merged one at a
time (disjoint files). (2) F09's tab shell and F08-S2, in either order. (3) F08-S3 after both, rebased on the
shell. F15 needs S3.

## Decisions for Pete

1. **Lower B and "abs".** The setup screen in the design describes Lower B as "Deadlift, front squat, hamstring,
   abs", but the Lower B day in the design has three exercises and no abs work.
   - *Option A (fix the words):* step 3 reads "Lower B · Hinge focus — Deadlift, front squat, leg curl". The day
     stays Deadlift, Front Squat, Seated Leg Curl.
   - *Option B (fix the workout):* add an abs exercise as a fourth, for example Hanging Leg Raise 3 × 12, and step 3
     reads "Deadlift, front squat, leg curl, abs". Every lifter's Lower B gets about five minutes longer, and the
     sample program the other screens are tested against changes.
   - **Recommendation: A.** Default if you say nothing: A.
2. **Step 3: a list, or something you tap?** The design shows the four training days each with a tick, "Upper A"
   ticked. Tapping moves the tick and changes nothing.
   - *Option A:* a plain list with no ticks: "this is the program you are getting".
   - *Option B:* keep the ticks. Then a tap has to mean something, for example "start with this day", which nobody
     has specified.
   - **Recommendation: A.** Default: A.
3. **The 3-, 5- and 6-day programs, and what a goal changes, were written by us, not taken from your design.** Only
   the 4-day Upper / Lower program is yours. Example: "3 days" gives Full Body A (Squat, Bench, Pulldown, Laterals,
   Curl), B (Bench, RDL, Row, Leg Press, Pushdown) and C (Deadlift, Overhead Press, Pull-up, Leg Curl, Rear Delt) on
   Monday, Wednesday and Friday. "Build muscle" turns Bench 5 × 5 into 4 sets of 8 to 10. The full lists are in the
   brief under "Templates" and "Role table".
   - *Option A:* ship them as sensible defaults; lifters can edit them in the program builder.
   - *Option B:* you review the lists first, and S1 waits.
   - **Recommendation: A**, and read the lists when convenient: changing one later is a small data-only change.
     Default: A.
4. **Setting up late in the week.** As already decided (#18), a block is dated from the first day of the week you
   set it up in. With weeks starting Monday: set up on a Saturday and week 1 has already lost Monday, Wednesday and
   Friday, so Today offers Saturday's Lower B and the week shows 0 of 4 done. Set up on a Sunday and Today says rest
   day; the next morning it is already "Week 2 of 8", and week 1 counts as a skipped week (loads hold, and they
   will be marked "HELD" once F24 ships).
   - *Option A:* keep it.
   - *Option B:* when no training day is left this week, date the block from next week. Today then needs a new
     "starts Monday" state (F09).
   - **Recommendation: A for now**, revisited with F24. Default: A.
5. **Pounds or kilograms, and the first day of the week, on first launch.** Today everyone starts in pounds with
   weeks starting Monday. Decision #15 says the week should follow the iPhone's region (Sunday in the US), but no
   code does that yet; no decision covers units. Settings (F14) arrives later, and onboarding copies start weights
   into the program in whatever unit is set at that moment.
   - A lifter in Germany today sees "Upper / Lower, 8 weeks, pounds" and Bench at 45 lb. With region defaults:
     "…kilograms" and Bench at 20 kg.
   - A lifter in the US, under decision #15 as written, would see weeks run Sunday to Saturday; the design draws
     Monday to Sunday.
   - *Option A:* the region decides both (kilograms outside the US; Sunday-first weeks in the US).
   - *Option B:* the region decides units only; weeks start Monday for everyone, changeable in Settings. This
     amends decision #15.
   - *Option C:* nothing now: pounds and Monday for everyone until Settings ships.
   - **Recommendation: B.** Default: C (what the app does today). A or B adds about 12 lines to S2.

What you do **not** need to look at: the names of the goal values in code; which module each file lives in; how
strings, previews and snapshots are organised; the UI-test changes. Three behaviours follow decisions you already
made or the brief as written, listed so nothing surprises you: start weights are the catalog's beginner defaults
(decision #21: Bench starts at 45 lb, Deadlift at 95 lb); "Skip setup" always gives the 4-day "Both" program, even
if a goal was already picked; steps 2 and 3 get a small "Back" button, which the design does not draw.

## Decisions for the orchestrator

- **O1 — Localization pattern for all three lanes.** One `Resources/Localizable.xcstrings` per module, written by
  hand as JSON, keys being the English copy (`"%@, %lld weeks, %@. Editable any time."`). One `<Feature>Strings.swift`
  per module is the only file that calls `String(localized: "…", bundle: .module, comment: "…")`; views, stores and
  LedgerDesign components pass `String`. `defaultLocalization: "en"` in the manifest. A shared `StringCatalogScan`
  test helper fails a module whose catalog and `String(localized:)` literals differ, or that has a `Text("…")`
  literal. No generated symbols (the host `swift build` would not generate them). *Why:* components already take
  `String` (architecture §11); literal `String(localized:)` calls are what Xcode itself extracts, so opening the
  project should not rewrite the catalog; agents cannot rely on Xcode's build-time extraction; and without a
  mechanical check a missing entry is invisible in English. Land the shared part once (row L0).
- **O2 — Store pattern.** `@Observable @MainActor final class <Screen>Store`, dependencies as
  `@ObservationIgnored @Dependency`, created inside the root view. Intents are synchronous and only change state;
  async work is an `async` method the view runs from `.task` or `.task(id:)` (onboarding: a tap bumps
  `saveAttempt`, and `.task(id: store.saveAttempt)` runs `save()`). Display values come from a pure
  `<Screen>Presentation.make(...)`. No `Task { }` in a store or a view. *Why:* standards §3–4 forbid tasks that
  outlive the view; tests call the `async` method directly, with no sleeps. F10, with an intent per tap, would use
  the same rule with one long-lived `.task` draining an intent stream.
- **O3 — Routing.** A feature root takes a closure for the exits the app must resolve and never presents another
  feature. Onboarding has none: the root follows `ProgramRepository.observeActive()`, so saving the program is the
  navigation, and "Delete all data" (F14) or a synced program (F28) flips it the same way. Recommend **no**
  `OnboardingRoute` (a deviation from architecture §12's "each feature exposes a Route"). *Why:* a second signal
  for the same transition can disagree with the first.
- **O4 — Keep `TrainingGoal`'s cases and `Program.daysPerWeek: Int?`;** add `DaysPerWeek` for the generator only.
  *Why:* stored raw values; no migration.
- **O5 — Templates name exercises by exact catalog name among non-custom exercises;** the store passes
  `exerciseRepository.all()`. *Why:* the brief's criterion, readable tables, no optional UUID parsing in Domain;
  a Domain test pins the names to the bundled catalog, so a rename fails a PR, not a launch. (Alternative: by id,
  as `Fixtures.CatalogID` does.)
- **O6 — Start loads are the catalog's, copied into the slot; `step` is nil.** Amend criterion 6 to "every §6.4
  column except load and step". *Why:* decisions #21 and #24 are later than the brief.
- **O7 — Program names, day names, tags and preview lines are English data in Domain,** like `exercises.json`, not
  String Catalog entries; the catalog holds the screen's own copy. *Why:* day names are stored in the program and
  edited by the lifter; the preview line belongs to the day it describes.
- **O8 — Pin criterion 12's VoiceOver tree before the tester starts.** Each option is one button, label
  "{label}, {sub}", with the `.isSelected` trait when picked and no accessibility value; iOS speaks "selected" and
  never speaks its absence, so drop "not selected". The progress bars are one element with label "Step 1 of 3" and
  an empty value. *Why:* F06's lesson; `PillButton` marks selection the same way (`PillButton.swift:34`).
- **O9 — A "Back" ghost pill above the progress bars on steps 2 and 3.** *Why:* criterion 2 needs a way back and
  the prototype has none. One string the brief does not list.
- **O10 — 18 snapshot references, not the brief's 20 or the full matrix's 30.** *Why:* the repo's matrix adds
  `.accessibility3`; 18 keeps the PR under the "more than 20 PNGs needs its own PR" line (testing-strategy §2.5).
- **O11 — Existing UI tests reach Today by tapping "Skip setup"** through one helper; no seed launch argument now.
  *Why:* F15 owns the seeded test mode, and the tap is the real first-run path. Cost: launch time "to Today with a
  program" stays unmeasured until F15.
- **O12 — The gate shows nothing (ground colour) until the launch's first `resume` has returned,** then follows
  the active program. *Why:* seeding and settings run after the first frame; a fast "Skip setup" (a UI test)
  would otherwise race the seed. Cost on a normal launch: a version check and one settings read.
- **O13 — "Retry" re-runs the launch's seed step before saving again** (`OnboardingRoot(prepareRetry:)`, wired in
  S3 to `composition.resume(in: .active)`). *Why:* decision #28's retry cannot succeed otherwise until the app is
  backgrounded and reopened. About six lines.
- **O14 — Body copy uses `.bodyLight` (13.5 pt), option labels `.body` (15 pt); no new LedgerDesign role.** *Why:*
  the prototype's 15.5 / 300 and 16 / 500 have no role, and adding one reopens F06's type tests. Orange also
  appears three times on this screen (bars, tick, button) against decision #17's "once"; the brief's criteria ask
  for exactly that.
- **O15 — Decision #15's locale week start is unimplemented on main** (`Settings.swift:37-39`). If Pete picks
  option C in decision 5, record it as an open follow-up (F14) rather than leaving the comment untrue.
- **O16 — S2's pre-agreed split** (store / views) if it passes ~600 lines.
- **O17 — Week 8 for the new splits keeps the full schedule** (deload changes load, sets and RPE, not days); the
  4-day drops Saturday for every goal, as §6.4 does. *Why:* the brief is silent for 3 / 5 / 6 days.

## Test plan changes

**Renamed and moved** (convention: no `test_` prefix, a sentence in `@Test`).

| Brief | Becomes | Target, slice |
|---|---|---|
| `test_templates_bothFourDay_matchesSpecSeedTable` | `program_bothFourDay_matchesSpec64_exceptLoad` (parameterized over the 16 rows) | LedgerDomainTests, S1 |
| `…_scheduleMatchesSeedIncludingWeek8` | `program_fourDay_scheduleMatchesSeed_includingWeek8` | S1 |
| `…_allGoalsAllDays_withinSpec71Ranges` | `program_everyGoalAndSplit_staysInsideSpec71` (16 pairs × lb, kg) | S1 |
| `…_allNamesResolveInCatalog` | `templates_everyExerciseName_isInTheBundledCatalog` | S1 |
| `…_lastWeekDeloadOnly`, `…_daysPerWeek_matchesScheduleCount` | `program_onlyWeek8IsADeload`, `program_weeks1to7_scheduleExactlyDaysPerWeek` | S1 |
| `…_kgStartLoads_multiplesOfKgStep` | `program_kilograms_startLoadsAreMultiplesOfTheStep` | S1 |
| `…_deterministic_sameIDsSameProgram` | `program_sameInputsAndIDs_isEqual` | S1 |
| `…_roleTable_appliedForStrongerFourDay` | `program_strengthFourDay_takesTheRoleTable` | S1 |
| `test_preview_fourDay_copyMatchesSpec67` | `preview_fourDay_matchesSpec67` (Lower B per Pete 1) | S1 |
| `test_programRepository_saveTemplate_roundTrips…` | `templateProgram_savedToGRDB_roundTripsEqual` (16 pairs, seeded catalog) in a new `TemplateProgramRoundTripTests` | LedgerPersistenceTests, S1 |
| `test_store_defaults_bothFourDayUpperA` | `defaults_areBothAndFourDays` (no "Upper A" pick: step 3 is a list) | FeatureOnboardingTests, S2 |
| `test_store_pickPersistsAcrossSteps` | `picks_surviveGoingBackAndForth` | S2 |
| `test_store_startTraining_savesActiveProgramAndRoutesToday` | `startTraining_savesOneActiveProgram_fromThePicks` (store, S2) and `savingAProgram_flipsToMain` (`RootGateTests`, S3) | S2, S3 |
| `test_store_skipSetup_savesFourDayDefault` | `skipSetup_savesTheDefault_whateverThePicks` | S2 |
| `test_store_startDate_isStartOfCurrentWeekPerSettings` | `startDate_isTheFirstDayOfTheWeek` in Domain (Mon and Sun starts, a late-evening instant in Los Angeles) and `save_usesTheSettingsWeekStart` in the store | S1, S2 |
| `test_store_bodyCopy_kgSaysKilograms` | `step3_kilograms_saysKilograms` (`OnboardingPresentationTests`) | S2 |
| `test_store_saveFailure_showsRetryAndDoesNotRoute` | `save_unseededCatalog_showsRetry_andSavesNothing` (`.inMemoryStores(seed: .empty)`) and `save_repositoryThrows_showsRetry` (a throwing double local to the test target) | S2 |
| `test_store_retry_afterFailureSucceeds` | `retry_onceTheCatalogIsSeeded_savesTheSamePicks` | S2 |
| Snapshot `OnboardingStepView` × 5 states | `OnboardingSnapshotTests`, matrix below | S2 |
| UI "F15 flow, first three steps" | `LedgerUITests/Onboarding.test_threeStepsGenerateProgram` (nightly) | S3 |

**Added.**

- S1, Domain: `program_unknownExercise_throws` (empty catalog; a custom exercise with a template's name is not
  used); `program_idsAreAllDistinct`; `program_recordsGoalDaysAndIsActive`; `program_everyDay_buildsASession`
  (`SessionBuilder.build` for every day of every pair, weeks 0 and 7); `preview_matchesTheGeneratedDays` (names
  and tags, every split); `startDate_outOfRange_isNil`; `ProgramTemplatesPerformanceTests` (nightly, median of 5
  under 5 ms). `FixturesTests`: `defaultProgram_isTheGenerators`, and
  `defaultProgram_differsFromSeedProgram_onlyInLoadsIdsAndStart` (guards the two fixtures F09 and F10 use against
  drifting apart).
- S2: `OnboardingPresentationTests` (each step's copy against spec §6.7; rows use " · "; exactly one option
  selected for every pick; six rows for six days); `save_twice_savesOneProgram`; `save_afterSuccess_doesNothing`;
  `OnboardingAccessibilityTests` (iOS, in a serialized suite, at `.large` and `.accessibility3`: the tree in O8,
  the title is a header, preview rows are not buttons, every button is at least 44 pt tall, the error is an
  element); `PreviewTests` (registry and render, as `LedgerAppKitTests/PreviewTests.swift`); `StringCatalogTests`.
- S3: `RootGateTests`: no program → `.onboarding`; a program → `.main`; saving flips to `.main`; deleting flips
  back; `.loading` before the first value; a stream that ends with no value (the program cannot be read) → `.main`,
  never onboarding; a cancelled follow leaves `.loading`. One on a real database: boot `Harness`, save a generated
  program through `composition.stores`, the gate reaches `.main`.

**Snapshot matrix (S2).** `OnboardingStepView` drawn from a model, phone only, at 402 pt and its own height.

| State | Cells | PNGs |
|---|---|---|
| Step 1, goal ("Both" picked) | light, dark × `.large`, `.xLarge`, `.accessibility3` | 6 |
| Step 2, days ("4 days" picked) | light, dark × `.large` | 2 |
| Step 3, 4-day preview | light, dark × `.large`, `.xLarge`, `.accessibility3` | 6 |
| Step 3, 6-day preview | dark × `.large`, `.accessibility3` | 2 |
| Step 3, save failed | light, dark × `.large` | 2 |
| **Total** | | **18** |

Measured on main: 124 references, 4,308,969 bytes (mean 34.7 KB, median 19.0 KB). Comparable text sheets cost
77–102 bytes per pixel row: `hairlineList` (4 rows) is 22–26 KB at 295–307 px and 51–55 KB at 534 px
(`.accessibility3`); `emptyState` is 25–30 KB at 328–340 px and 59–63 KB at 599 px. An onboarding step is about
660 px tall at `.large` and about 1,500 px at `.accessibility3`, so roughly 52 KB, 57 KB and 150 KB a cell, and
190 KB for the six-day list at `.accessibility3`. **Estimate: 18 PNGs ≈ 1.5 MB** (the brief's five states in the
full matrix would be 30 PNGs ≈ 2.6 MB).

**Existing tests that break, and the slice that fixes them.**

| Test on main | Breaks when | Fix |
|---|---|---|
| `FeatureOnboardingTests.module_name_matchesTarget` | S2 deletes the placeholder | Deleted in S2 |
| `LedgerDesignTests` `everyModuleWithPreviews_isRegistered` (`PreviewTests.swift:42`) | S2 adds the first `#Preview` to FeatureOnboarding | `registeredModules` in S2 |
| Coverage gate | S2 gives FeatureOnboarding coverage | `"required"` in S2 |
| `LedgerUITests/Smoke.test_launchesToToday` (PR lane) | S3: a fresh database now opens on onboarding | S3: becomes `test_freshInstall_skipsSetupToToday` (asserts `onboarding.title`, taps `onboarding.skip`, then `today.title`). Same class, so the PR plan's `selectedTests: ["Smoke"]` needs no edit. |
| `LedgerUITests/DebugMenu.test_diagnostics_showsTheSeededCatalog` (nightly) | S3 | S3: launches through the helper; also asserts `debug.diagnostics.rows.program` = 1, `program_week` = 8, `slot` = 16 (criteria 4 and 5 on the real database) |
| `LedgerUITests/LaunchPerformance.test_launchToFirstFrame` (nightly) | S3: it never fails, but silently loses its in-app figure | S3: the report step skips setup first |

Unaffected: both `LedgerWatchUITests` (the watch root is not touched), `LedgerTests/SmokeTests` (boots nothing),
every `LedgerAppKitTests` suite (`TodayPlaceholder` stays until F09). S1 breaks nothing.

UI-test identifiers (strings, as F07's): `onboarding.title`, `onboarding.progress`, `onboarding.option.<n>`,
`onboarding.preview.<n>`, `onboarding.cta`, `onboarding.skip`, `onboarding.back`, `onboarding.error`. Launch
argument: unchanged, `-LEDGER_UITEST 1`.

## Risks

Accessibility:

- **Selection.** `.isSelected` and an accessibility value "Selected" together make VoiceOver say it twice; the
  criterion's "not selected" is never spoken by iOS. One tree, pinned by a test (O8).
- **`HairlineRow` has no selected state.** It puts its `Button` inside a `VStack` with the rule
  (`HairlineRow.swift:30-38`), so a trait added from outside is applied to the container; whether it reaches the
  button is not something to rely on. The option row is the feature's own button inside a `HairlineList`, with the
  trait on the button; the read-only preview rows can be `HairlineRow` as is.
- **Step changes.** After "Continue", VoiceOver focus stays on the button at the bottom unless it is moved to the
  new title (`@AccessibilityFocusState`). The save error appears without a focus change, so it must be announced.
  Neither is visible to a unit test: both go on the manual check list.
- **Dynamic Type.** The screen must scroll with the button and "Skip setup" pinned. At accessibility sizes the
  tick moves under the text, as `HairlineRow` does (`:42-44`), or "Stay consistent" and "5 days" subs truncate.
  Snapshots stop at `.accessibility3`; AX5 is by hand.
- **Faint track.** `ProgressSegments` asks for the count in words on screen because its track is below 3:1
  (`ProgressSegments.swift:23-26`). Onboarding shows no words; the orange bars carry the step at 3:1 and VoiceOver
  gets "Step 1 of 3". F15's audit may still flag it.

Performance (architecture §15; the brief's own budgets):

- Cold launch to Today under 600 ms: the gate adds one program read and waits for the first `resume`. On a
  first-ever launch that includes seeding 224 exercises. Measured only once F15 can launch with a program.
- The generator must not decode the catalog (20 ms budget of its own): it is passed in.
- Save and switch under 100 ms: one transaction of about 40 rows, then one observation.

Build and tooling:

- **String catalogs and `swift build`.** Not verified in this pass (nothing was built): the host build
  (`check.sh --fast`, F07's release build) is expected to copy an `.xcstrings` file without compiling it, in which
  case lookups return the key, which is the English copy, and tests still pass. L0 (or S2's G1) must prove that
  the host build and the Xcode build both accept the catalog and `defaultLocalization`, with no new warning.
- **Hand-written catalogs.** Xcode updates a catalog when someone builds in the IDE (Apple's string-catalog
  guide). Keys that match the code's literals should keep that to formatting; expect one normalising diff.
- **macOS host.** `swift test` builds every target, so FeatureOnboarding must compile for macOS: no UIKit.
- **Previews.** A `.task` inside a scroll view traps the preview smoke test (F07 S3 decision 6): previews and
  snapshots draw `OnboardingStepView` from a model; `OnboardingRoot` owns the `.task`s.

Behaviour:

- **Gate edge cases.** `observeActive()` ends without a value when the active program cannot be read
  (`GRDBProgramRepository.swift:86`, `Observation/ValueObservation+AsyncStream.swift:11-17`): show `.main`, never
  onboarding. But a `.task(id: scenePhase)` restart also ends the loop, and scene phase changes at launch: set
  `.main` only when the task was not cancelled.
- **Exactly one program.** A second save makes a second active program. The button is disabled while saving and
  after success, and `save()` ignores re-entry.
- **Size.** S2 is estimated at the 500-line target.
- **F09 landing its shell after S3** is fine (it replaces what `.main` shows); both lanes edit the same UI tests.

## Inputs the implementer needs

### S1 — template generator

Read: the brief's "Domain changes" (role table, exception, templates) and criteria 6–9, 11; this file's signatures
and "Brief vs main"; `docs/product-spec.md` §6.4, §6.7, §7.1, §7.2; `docs/product-decisions.md` #18, #21, #22, #24;
ADR-007. Prototype: `design/prototype/Ledger.dc.html` lines 837–841 (`mk`), 850–857 (`W0`), 873–896 (`DAYS`, the
double and fixed lists, superset and drop flags), 908–909 (the schedule); the `Program builder` markup at 92–165
adds nothing. `Ledger v2.dc.html` 415–437 for the preview lines.

Calls on main:

- `Program.init(id:name:startDate:weeks:days:goal:daysPerWeek:isActive:) throws(ProgramValidationError)` — `LedgerDomain/Model/Program.swift:24-33`
- `Week.init(id:index:isDeload:schedule:)`, `schedule: [Weekday: DayTemplateID]` — `Model/Week.swift:40-47`; `Weekday` — `:7-8`
- `DayTemplate.init(id:name:tag:slots:)` — `Model/DayTemplate.swift:12`
- `Slot.init(id:exerciseID:sets:reps:repsHi:rpe:restSeconds:progression:startLoad:step:isSupersetWithPrevious:dropSets:misses:) throws(SlotValidationError)` — `Model/Slot.swift:38-52` (`rpe` is a `Decimal`, rest is whole seconds)
- `Exercise.startLoad(in:)` — `Model/Exercise.swift:71`; `isCustom` — `:41`; `Equipment.defaultStep(in:)` — `:9`
- `WeekCalendar.init(startDate:weekStart:calendar:)`, `firstDayOfWeek(containing:)`, `weekIndex(for:)` — `Rules/WeekCalendar.swift:36, 77, 53`; `CivilDate.init?(_:in:)` — `Model/CivilDate.swift:30`
- `ProgramID`, `WeekID`, `DayTemplateID`, `SlotID` `init(_ rawValue: UUID)` — `Identifiers.swift:31-57`
- `ExerciseCatalog.seed()` — `Catalog/ExerciseCatalog.swift:78` (tests and the fixture only)
- `SessionBuilder.build(program:weekIndex:day:exercises:history:settings:id:device:now:)` — `Rules/SessionBuilder.swift:16`; `ProgressionRules.prescribe` — `Rules/ProgressionRules.swift:21`
- Fixture style: `LedgerFakes/Fixtures/Fixtures+Program.swift:139-165`, `Fixtures.uuid(_:)` — `Fixtures.swift:41`; its test — `LedgerDependenciesTests/FixturesTests.swift`
- GRDB round trip: `LedgerPersistenceTests/ProgramRepositoryTests.swift:29-43`; seed with `LedgerStores.seedCatalog()` — `LedgerPersistence/LedgerStores.swift:59`

Rules to keep: Domain imports Foundation only (`ModuleBoundaryTests`); files under 300 lines (lint); no force
unwraps. Role table with main's goal names: `.strength` P 5×5 (hi 7) RPE 8 180 s linear, S 4×6 (8) 8 150 linear,
A 3×8 (10) 8 90 linear; `.hypertrophy` P 4×8 (10) 8 120 double, S 3×10 (12) 8 90 double, A 3×12 (15) 9 60 double;
`.both` P 5×5 (7) 8 150 linear, S 3×8 (10) 8 120 linear, A 3×12 (14) 9 75 double; `.consistency` P 3×5 (7) 7 120
linear, S 3×8 (10) 7 90 fixed, A 2×12 (14) 7 60 fixed. `both` × `four` ignores the table and is §6.4 verbatim.

### S2 — onboarding screen

Read: the brief's "Copy", criteria 1–5, 8, 10, 12 and "Non-functional"; `docs/product-spec.md` §3.10 (Onboarding),
§6.7, §2.4; `docs/engineering-standards.md` §3, §4, §7, §8; `docs/testing-strategy.md` §2.5, §2.6;
`docs/architecture.md` §11–13; F07 notes S3 decision 6 and open question 3. Prototype:
`design/prototype/Ledger v2.dc.html` lines 44–64 (markup: 76 / 28 / 46 px padding, 2 px bars, title 600 38 px
wdth 98, body 300 15.5 px at 48 %, rows 17 px padding with a 19 px tick, orange pill, "Skip setup"), 415–437 (copy),
441 (default picks), 543–551 (bar colours, selected and unselected ink, next and skip).

Calls on main:

- Keys: `programRepository`, `exerciseRepository`, `settingsRepository` — `LedgerDependencies/Keys/StoreKeys.swift:13-41`; `logger` — `Keys/DeviceKeys.swift:51` (`LedgerLogger.log`, `LedgerLogger.swift:10`); the library's `date`, `uuid`, `calendar`, `locale`
- `ProgramRepository.save(_:)`, `ExerciseRepository.all()`, `SettingsRepository.load()` — `LedgerDomain/Protocols/Repositories.swift:32, 9, 91`
- Tests: `withTestDependencies(_:operation:)` (async) — `LedgerTestSupport/WithTestDependencies.swift:39-54`; `inMemoryStores(seed:)` — `:72`; fixed date, incrementing UUIDs, `Fixtures.calendar` — `:86-92`; `InMemoryStores.Seed` — `LedgerFakes/InMemoryStores.swift:15-59`; `InMemoryExerciseRepository.seedIfNeeded(_:version:)` — `LedgerFakes/InMemoryExerciseRepository.swift:59`; `Fixtures.now` (Wed 2026-09-16), `settingsKg` — `Fixtures/Fixtures.swift:34, 69`
- Design: `PrimaryButton(_:icon:action:)` — `PrimaryButton.swift:17`; `PillButton(_:style:action:)` with `.ghost` — `PillButton.swift:16`; `HairlineList`, `HairlineRule` — `HairlineList.swift:6, 22`; `HairlineRow(_:detail:)` — `HairlineRow.swift:60-63`; `ProgressSegments(_:label:value:)`, `ProgressSegment(length:state:)` — `ProgressSegments.swift:36, 14`; `LedgerIconView(.check, sizedAs:)` — `LedgerIcon.swift:58`; `.ledgerFont(_:)` — `Tokens/LedgerFont.swift:143` (`.display` `:81`, `.body`, `.bodyLight`, `.label` `:85-87`); `LedgerColor.ground, ink, inkSecondary, inkMuted, accentText` — `Tokens/LedgerColor.swift:18-46`; `LedgerSpacing`; `LedgerMotion.snappy`
- Snapshot and tree: `assertLedgerSnapshot(of:named:devices:themes:typeSizes:)` — `LedgerSnapshotTesting/LedgerSnapshot.swift:73`; `accessibilityElements(_:)` — `AccessibilityElements.swift:24`; `renderPreview(size:_:)` — `PreviewRendering.swift:15`; examples: `LedgerDesignTests/ComponentAccessibilityTests.swift`, `LedgerAppKitTests/PreviewTests.swift`, `LedgerAppKitTests/TodaySnapshotTests.swift`; tags and the serialized parent suite are per test target (`LedgerDesignTests/Support/Tags.swift`, `RenderingSuites.swift`)
- Registry: `LedgerAppKit/AppKit+Previews.swift`; `PreviewScan.registeredModules` — `LedgerTestSupport/Previews/PreviewScan.swift:9`

Shape: `OnboardingRoot(prepareRetry: @escaping () async -> Void = {})` is the only public type. The store holds
step, goal (default `.both`), days (default `.four`), units, and a phase (editing, saving, failed, saved). Look up
`@ObservationIgnored @Dependency` and dependency lifetimes in swift-dependencies' docs (context7) before writing
it. Strings: 31 (27 in the brief's "Copy", plus "Back", "pounds", "kilograms" and "Step %lld of %lld").

### S3 — root gate and UI tests

Read: this file's "Seams", O11–O13 and the gate risks; `docs/architecture.md` §4, §13–15;
`docs/testing-strategy.md` §2.7; F07 notes S3 "What landed" and decisions 1, 3, 9; brief criteria 1, 4, 5, 11.
Prototype: `design/prototype/Ledger v2.dc.html` label `Today`, lines 66–131, only as the screen the lifter lands
on (F09 builds it).

Calls on main:

- `AppRoot` — `LedgerAppKit/AppRoot.swift:7-39` (state `:9`, `.task` `:19-21`, `.ready` `:26-32`)
- `AppComposition.state`, `stores`, `resume(in:)` — `LedgerAppKit/AppComposition.swift:47, 61, 96`; `DatabaseLaunch.resume(isForeground:)` and its seed retry — `LedgerPersistence/DatabaseLaunch.swift:104-122`
- `ProgramRepository.observeActive()` — `Protocols/Repositories.swift:38`; GRDB's — `LedgerPersistence/Repositories/GRDBProgramRepository.swift:86`; the fake's — `LedgerFakes/InMemoryProgramRepository.swift:75`
- Test harness: `LedgerAppKitTests/Support/Harness.swift` (`booted()`)
- UI tests: `Apps/LedgerUITests/Smoke.swift:11-18`, `DebugMenu.swift:12-36`, `LaunchPerformance.swift:8-33`; `today.title` and the Debug long press — `LedgerAppKit/TodayPlaceholder.swift:15, 17`; Diagnostics row keys `debug.diagnostics.rows.<table>` — `LedgerAppKit/AppComposition+Diagnostics.swift:34-36`
- Plans: `TestPlans/PR.xctestplan` selects `Smoke` in `LedgerUITests`; `Nightly.xctestplan` runs every UI test. No plan edit is needed.

Manual checks for the S3 PR: a fresh simulator install opens on step 1 with no Today flash; "Start training" and
"Skip setup" both land on Today; relaunch opens on Today; VoiceOver reads the new title after "Continue".

## Orchestrator rulings (2026-10-04)

Pete approved the M1 opening lanes (F08, F09, F10 in parallel) on 2026-10-04. The plan above is accepted with the
rulings below. Where a ruling and the plan disagree, the ruling wins.

**Slices.** S1 templates (`feat/F08-s1-templates`) starts now. S2 (onboarding screen) waits for S1 and for F09 S1
(the tab shell, which also lands the localization scaffolding: there is no separate "L0" PR). S3 (root gate) waits
for S2 and F09 S1, and edits F09's `MainRoot.swift`, not `AppRoot`'s switch.

**The plan's decisions.**
- O1–O3: replaced by "M1 shared conventions" below. The copy file is `OnboardingCopy.swift`. No `OnboardingRoute`
  (accepted deviation from architecture §12: saving the active program is the navigation).
- O4 accepted: `TrainingGoal` keeps main's cases; `Program.daysPerWeek` stays `Int?`; `DaysPerWeek` types the
  generator's input only. No migration.
- O5 accepted: templates name exercises by exact catalog name among non-custom exercises; a Domain test pins every
  name to the bundled catalog. "Pull-Up" in the brief's role line means **Weighted Pull-Up**.
- O6 accepted: start load is the catalog's `startLoad(in:)`, copied into the slot; `step` is nil. Criterion 6 is
  amended in the brief.
- O7 accepted: program names, day names, tags and preview lines are English data in the Domain, not catalog entries.
- O8 accepted (S2): each option is one button, label "{label}, {sub}", `.isSelected` when picked, no value; the bars
  are one element, "Step 1 of 3". "not selected" is dropped from criterion 12.
- O9 accepted (S2): a "Back" ghost pill on steps 2 and 3. Pete is told.
- O10 accepted: 18 snapshot references. O11 accepted: the existing UI tests reach Today by tapping "Skip setup".
- O12, O13 accepted (S3). O14 accepted: `.bodyLight` and `.body`, no new type role.
- O15: follows Pete's decision 5. O16 accepted (S2's split seam). O17 accepted: week 8 of the 3, 5 and 6-day splits
  keeps the full schedule; the 4-day drops Saturday for every goal.

**Pete's decisions.** Asked on 2026-10-04; until he answers, the plan's defaults hold: (1) Lower B's copy is fixed,
not the workout; (2) step 3 is a read-only list; (3) our 3, 5 and 6-day programs ship as defaults (the S1 PR waits
for his answer before it merges); (4) decision #18 stands; (5) pounds and Monday for everyone (option C).

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

## Slice S1 — template generator (G1 implementer, 2026-10-04)

Branch `feat/F08-s1-templates`, on top of `8d5a991`. Not committed, no PR (the orchestrator commits). Built to the
product defaults in force: Lower B keeps three exercises; the 3-, 5- and 6-day templates and the role table are the
brief's; a block is dated from the first day of the current week.

### What landed

Product (`LedgerKit/Sources/`):

- `LedgerDomain/Templates/DaysPerWeek.swift`: `enum DaysPerWeek: Int` (`three = 3` … `six`).
- `LedgerDomain/Templates/ProgramTemplates.swift`: `ProgramTemplateError`, and `ProgramTemplates` with `weekCount`,
  `Request`, `DayPreview`, `Preview`, `preview(days:)`, `startDate(containing:weekStart:calendar:)`,
  `program(_:catalog:id:newID:)`, and the builder (one private function for a day, one for the weeks).
- `LedgerDomain/Templates/ProgramTemplates+Splits.swift`: the internal `Role`, `Lift`, `Day`, `Split`, and the four
  splits (`upperLower`, `fullBody`, `pushPullLegs`, `bodyPart`).
- `LedgerDomain/Templates/ProgramTemplates+Prescriptions.swift`: the internal `Scheme` and `RoleSchemes`, the role
  table (`schemes(for:)`), spec §6.4's rows (`specSeed`), and `Split.scheme(for:goal:)`, which picks between them.
- `LedgerFakes/Fixtures/Fixtures+Templates.swift`: `Fixtures.defaultProgramID`, `Fixtures.defaultProgram(startDate:)`.

Tests (`LedgerKit/Tests/`): `LedgerDomainTests/Templates/` (`ProgramTemplatesTests`, `…SeedTests`, `…SplitsTests`,
`…CatalogTests`, `…StartDateTests`, `…PerformanceTests`, `DaysPerWeekTests`, and the helpers `TemplateTesting`,
`TemplateOracle`, `TemplateOracle+Splits`); `LedgerDependenciesTests/FixturesTemplatesTests.swift`;
`LedgerPersistenceTests/TemplateProgramRoundTripTests.swift`. 49 tests, 409 parameterized cases.

Docs: one bullet in `docs/architecture.md` §5. No existing Swift file is edited; `project.pbxproj`, `Package.swift`,
the test plans and the thresholds are untouched.

The API as built:

```swift
public enum DaysPerWeek: Int, Codable, Sendable, CaseIterable { case three = 3, four, five, six }
public enum ProgramTemplateError: Error, Equatable, Sendable { case unknownExercise(String) }

public enum ProgramTemplates {
    public static let weekCount = 8
    public struct Request: Hashable, Sendable {          // var goal, days, units, startDate; public init
        public init(goal: TrainingGoal, days: DaysPerWeek, units: Units, startDate: CivilDate)
    }
    public struct DayPreview: Hashable, Sendable { public let name, tag, line: String }  // `line` was `exercises` until fix round 1
    public struct Preview: Hashable, Sendable { public let programName: String; public let days: [DayPreview] }

    public static func preview(days: DaysPerWeek) -> Preview
    public static func startDate(containing now: Date, weekStart: Weekday, calendar: Calendar) -> CivilDate?
    public static func program(_ request: Request, catalog: [Exercise], id: ProgramID, newID: () -> UUID) throws -> Program
}
```

**Id order** (pinned by `program_drawsIDs_weeksThenEachDayAndItsSlots`): `newID` is called once per week, weeks 0…7
in order, then for each day in order: once for the day, then once per slot in order. For the 4-day split that is 28
calls: weeks 1–8, Upper A 9 and its slots 10–14, Lower A 15 and 16–19, Upper B 20 and 21–24, Lower B 25 and 26–28.
The program's own id is the `id` argument.

### Decisions and deviations

1. **`program` takes a `Request`; the ruling's seven-parameter signature is not implemented as written.** SwiftLint's
   `function_parameter_count` is a default rule (`.swiftlint.yml` does not configure it; it warns from six
   parameters, and the gate runs `--strict`). The one function on `main` that exceeds it carries an inline
   suppression (`LedgerDomain/Rules/SessionBuilder.swift:16`), and this slice may add none. So the four plain values
   (goal, days, units, start date) are `ProgramTemplates.Request` (`Templates/ProgramTemplates.swift:25`;
   initializers are exempt from the rule), and what the store supplies stays as parameters: `program(_:catalog:id:
   newID:)` (`:93`). Inputs, output and id order are the ruling's. To go back to the flat signature: one
   `// swiftlint:disable:this function_parameter_count` and delete `Request` (about 12 lines).
2. **`startDate(containing:weekStart:calendar:)` anchors its throwaway `WeekCalendar` on the Unix epoch, not on
   today** (`ProgramTemplates.swift:71-74`). `firstDayOfWeek` reads the week start and the zone only
   (`Rules/WeekCalendar.swift:77-79`, `:106-109`); anchoring on today would mean unwrapping `CivilDate(now, in:)`
   first, a second `nil` path for nothing. The one `nil` left is a week whose first day is outside the years 1…9999.
3. **The §6.4 exception is data on the split, not a `days == .four` test.** `Split.seed` holds spec §6.4's rows by
   exercise name; `Split.scheme(for:goal:)` takes the seed row under `both` where the split has one, and the role
   table otherwise (`ProgramTemplates+Prescriptions.swift:46-51`). Only `upperLower` has a seed. Both branches are
   reachable; `specSeed_namesTheFourDaySplitsExercises` pins that the seed's keys are exactly that split's 16
   exercises, so a misspelt key cannot fall through to the role table unseen.
4. **The role table is a struct per goal, not one switch over (goal, role).** Twelve cases in one switch fail
   `cyclomatic_complexity` (10). `schemes(for:)` returns a `RoleSchemes`, read by role.
5. **Week 8's schedule** is `Split.deloadRestDays`: `[.saturday]` on the 4-day split, for every goal, and empty on
   the others (ruling O17) (`ProgramTemplates+Splits.swift:55`, `:84`; `ProgramTemplates.swift:150-157`).
   `daysPerWeek` stays 4 in that week: it records the pick.
6. **Catalog matching**: exact name among exercises with `isCustom == false`; of two such exercises with one name
   the first in the list given is used (`ProgramTemplates.swift:100`). The bundled catalog has no duplicate name
   (`CatalogError.duplicateName`); the rule only keeps the function total and deterministic on any list a store
   returns. Tests: `program_customExerciseWithATemplatesName_isIgnored`, `program_twoCatalogExercisesWithOneName_
   usesTheFirst`.
7. **When `unknownExercise` is thrown, some ids have been drawn** (the eight weeks' and the failing day's), because
   the documented order starts with the weeks. Harmless, and said in the doc comment. With an incrementing test
   generator, a retry after a failed attempt therefore starts at a later id. *No longer true after fix round 1
   (S1-N1): every exercise is looked up before the first id is drawn.*
8. **Preview lines.** Lower B is "Deadlift, front squat, leg curl" (decision 1, default A). Upper B keeps spec
   §6.7's "Weighted pull-up, OHP, row, curls". `preview_linesCountTheDaysLifts` checks that every line names one
   thing per slot, so no line promises what its day lacks. `DayPreview.name` keeps " — "; the " · " form is S2's.
9. **The fixture tests are a new file**, `LedgerDependenciesTests/FixturesTemplatesTests.swift` (5 tests), not two
   more tests in `FixturesTests`: that suite's body is 93 code lines and these add about 80, past
   `type_body_length` (150). `FixturesTests.swift` is unchanged.
10. **`Fixtures.defaultProgram` has an id of its own**, `Fixtures.defaultProgramID` (`uuid(9004)`), and child ids
    `uuid(1001)`…`uuid(1028)` in the generator's order, so a store never takes it and `seedProgram` for one
    program. Its default start comes from `ProgramTemplates.startDate` at `Fixtures.now` with the default week
    start: 2026-09-14. It is pounds only (the plan's signature).
11. **Plan test names.** `program_unknownExercise_throws` became three tests (`program_emptyCatalog_
    throwsUnknownExercise`, `program_missingExercise_throwsUnknownExercise`, `program_customExerciseWithATemplates
    Name_isIgnored`). Everything else in the plan's S1 list exists under its planned name. Added beyond the plan:
    the id-order test, the deload-schedule test, the weekday test, the duplicate-name test, the Weighted Pull-Up
    test, `preview_everySplit_isTheBriefs`, `preview_linesCountTheDaysLifts`, the start-date property test over
    all seven week starts, `DaysPerWeekTests`, and two more GRDB tests (stored catalog equals bundled catalog;
    unseeded catalog).
12. **The tests' oracle is a second copy of the brief** (`TemplateOracle`, `TemplateOracle+Splits`): the role table,
    the 16 rows of §6.4, and the "Templates" list with full catalog names. It reads nothing from `ProgramTemplates`,
    so changing a template means changing it in two places, on purpose.
13. **No unreachable branch in `ProgramTemplates*`**: the three files are at 100 % of lines, and on the host at
    100 % of regions. `Fixtures+Templates.swift` has one line no test reaches (`:27`, the `throw` for a start date
    that cannot be computed), as `seedProgram` has (`Fixtures+Program.swift:153`); see "Gate and coverage".
14. **Not done, on purpose:** no public initializer on `DayPreview` / `Preview` (the plan's signatures have none;
    S2 gets them from `preview(days:)`); no `units:` parameter on the fixture; no change to `WeekCalendar`,
    `Fixtures.seedProgram()` or any other existing file.

### Criteria → tests

Suites are in `LedgerDomainTests/Templates/` unless named. Case counts are parameterized arguments.

| Criterion (as amended) | Tests |
|---|---|
| 6: `both` × `four` equals spec §6.4 in every column but load and step | `ProgramTemplatesSeedTests.program_bothFourDay_matchesSpec64_exceptLoad` (16 rows, each in lb and kg: exercise, sets, reps, repsHi, RPE, rest, progression, superset, drop set, no misses; load equals the catalog's; step nil), `program_bothFourDay_hasTheTablesDaysAndRowCount`, `program_bothFourDay_benchStartsAtTheEmptyBar`; `ProgramTemplatesCatalogTests.specSeed_namesTheFourDaySplitsExercises` |
| 6: schedule equals the §6.4 seed, week 8's three days included | `ProgramTemplatesSeedTests.program_fourDay_scheduleMatchesSeed_includingWeek8` (4 goals) |
| 7: every slot value inside spec §7.1 | `ProgramTemplatesTests.program_everyGoalAndSplit_staysInsideSpec71` (16 pairs × lb, kg) |
| 7: every exercise name resolves in the catalog; "Weighted Pull-Up", not "Pull-Up" | `ProgramTemplatesCatalogTests.templates_everyExerciseName_isInTheBundledCatalog` (4 splits), `program_fourDay_pullUpIsTheWeightedOne` (lb, kg); `ProgramTemplatesSplitsTests.program_everyGoalAndSplit_isTheBriefsTemplate` (16) |
| 7: exactly `days` training days in weeks 1–7 | `ProgramTemplatesTests.program_weeks1to7_scheduleExactlyDaysPerWeek` (16), `ProgramTemplatesSplitsTests.program_schedule_isOnTheBriefsWeekdays` (4) |
| Week 8 a deload and the only one; its schedule (amendment 5) | `ProgramTemplatesTests.program_onlyWeek8IsADeload` (16), `program_deloadWeek_keepsItsDays_exceptTheFourDaySaturday` (16) |
| 9: determinism from the id sequence | `ProgramTemplatesTests.program_sameInputsAndIDs_isEqual` (32), `program_drawsIDs_weeksThenEachDayAndItsSlots`, `program_idsAreAllDistinct` (16) |
| 3, data half: the preview's days, names and lines | `ProgramTemplatesSplitsTests.preview_fourDay_matchesSpec67`, `preview_everySplit_isTheBriefs` (4), `preview_matchesTheGeneratedDays` (16), `preview_linesCountTheDaysLifts` |
| 8, data half: kg start loads are the catalog's, multiples of the kg step | `ProgramTemplatesCatalogTests.program_kilograms_startLoadsAreMultiplesOfTheStep` (16), `program_startLoads_areTheCatalogs` (32) |
| 11, data half (and 4's start date): Wednesday 2026-09-16 → start 2026-09-14, week index 0 | `ProgramTemplatesStartDateTests.startDate_criterion11_wednesdayIsInWeek1`, `startDate_isTheFirstDayOfTheWeek` (18 rows: Monday, Sunday, Saturday, Wednesday and Thursday starts; a week's first and last minute; a year boundary; Sunday evening in Los Angeles; Havana and Cairo, where DST skips midnight on the week's first day), `startDate_isOnTheWeekStart_atMostSixDaysBack` (7 week starts × 14 days), `startDate_ignoresTheCalendarsFirstWeekday`, `startDate_outOfRange_isNil` |
| Amendment 1: types | `DaysPerWeekTests` (2); `ProgramTemplatesTests.program_recordsGoalDaysAndIsActive` (32) |
| Amendment 4: `unknownExercise`; exact names among non-custom exercises | `ProgramTemplatesCatalogTests.program_emptyCatalog_throwsUnknownExercise` (4), `program_missingExercise_throwsUnknownExercise` (2), `program_customExerciseWithATemplatesName_isIgnored`, `program_twoCatalogExercisesWithOneName_usesTheFirst`; `LedgerPersistenceTests/TemplateProgramRoundTripTests.templateProgram_unseededCatalog_throwsUnknownExercise` |
| Role table; the 4-day split under other goals | `ProgramTemplatesSplitsTests.program_everySlot_takesItsRolesScheme_exceptTheSeed` (16), `program_supersetsAndDropSets_areTheFourDaySplitsOnly` (16); `ProgramTemplatesSeedTests.program_strengthFourDay_takesTheRoleTable`, `program_fourDay_everyGoal_keepsExercisesSupersetsAndDropSet` (4) |
| A generated day builds a session | `ProgramTemplatesTests.program_everyDay_buildsASession` (32: every day, weeks 1 and 8; set counts, drop set, week-1 load, every weight a whole number of steps) |
| GRDB round trip | `LedgerPersistenceTests/TemplateProgramRoundTripTests.templateProgram_savedToGRDB_roundTripsEqual` (32, over the catalog as stored; row counts and the `program` row), `templateProgram_storedCatalog_givesTheBundledCatalogsProgram` |
| Amendment 6: the fixture | `LedgerDependenciesTests/FixturesTemplatesTests`: `defaultProgram_isTheGenerators`, `defaultProgram_startDate_isTheOneGiven`, `defaultProgram_differsFromSeedProgram_onlyInLoadsIdsAndStart`, `defaultProgram_savesAndReadsBack`, `defaultProgram_inASeed_missesNoExercise` |
| Budget: `program` under 5 ms | `ProgramTemplatesPerformanceTests.program_sixDays_under5ms`, nightly lane only, as the catalog's. By hand on the host (Debug): median 0.13 ms |
| DoD: `ProgramTemplates` at 100 % of lines | "Gate and coverage" below |

**Do the tests bite?** Spot check, not a mutation campaign (that is the tester's). Seventeen source mutations in two
host runs, sources restored and compared byte for byte afterwards; each made at least one named test fail: a §6.4
rest value; a role-table rep range; the `isCustom` filter removed; `deloadRestDays` emptied; the Lower B line set
back to "hamstring, abs"; loads always in pounds; the week start ignored; ids drawn days-first; last duplicate wins;
"Pull-Up" for "Weighted Pull-Up"; the drop set removed; `isActive` false; a wrong `daysPerWeek`; the deload on
week 7; the seed used for every goal; the superset flag dropped; Friday moved to Thursday on the 5-day split.

### Code lines

Non-blank lines that are not whole-line comments. Every Swift file is new, so each is counted whole; apart from
them `git diff -U0 8d5a991` shows one added line in `docs/architecture.md` and this section.

| File | Product lines |
|---|--:|
| `LedgerDomain/Templates/DaysPerWeek.swift` | 4 |
| `LedgerDomain/Templates/ProgramTemplates.swift` | 98 |
| `LedgerDomain/Templates/ProgramTemplates+Splits.swift` | 190 |
| `LedgerDomain/Templates/ProgramTemplates+Prescriptions.swift` | 96 |
| **LedgerDomain** | **388** (plan ≈ 360, +8 %) |
| `LedgerFakes/Fixtures/Fixtures+Templates.swift` | **25** (plan ≈ 25) |

Tests: 1,049 lines in 12 files (3 of them helpers). Largest product file: `+Splits`, 233 lines with comments
(lint limit 300). No split proposed: the slice is under the 500-line target.

### Gate and coverage

- **Full gate:** `/usr/bin/python3 <scratchpad>/sim-lock.py scripts/check.sh` from the worktree root, started
  2026-10-04 17:50:34. **Exit status 0** (`GATE_EXIT=0`, read from the log, with `check.sh OK`), **671 s**, lock
  acquired after 0 s. Steps: tools 1 s, format 0 s, lint 69 s, iOS build 100 s, iOS tests 213 s, watchOS build 36 s,
  watchOS tests 248 s, coverage 2 s. "17 test targets ran and passed (PR)", "8 test targets ran and passed
  (PR-Watch)". Result bundles: iOS 1,672 tests, 0 failed (1,653 passed, 13 skipped, 6 expected failures); watchOS
  1,498, 0 failed (1,482 passed, 13 skipped, 3 expected failures). Every suite of this slice is in the iOS bundle;
  the Domain and GRDB ones are in the watchOS bundle too.
- **What the gate ran on:** the tree as it is now, minus this notes section, which was appended afterwards.
  `scripts/check.sh --lint-only` was run again on the final tree: see the last line of this section.
- **Warnings in the gate log:** three, all on `main` already (`LedgerDesignTests/PreviewTests.swift:90`,
  `PayloadVersionAdversarialTests.swift:29`, a `@Test` macro expansion in `SettingsDecodingAdversarialTests`).
  None in this slice's files.

| Module | Lines | Coverage | Threshold | `main` (F07 S3) |
|---|--:|--:|--:|--:|
| LedgerDomain | 2162 / 2180 | 99.17 % | 95 % | 2009 / 2027, 99.11 % |
| LedgerFakes | 1349 / 1365 | 98.82 % | 90 % | 1327 / 1342, 98.88 % |
| Overall | 8385 / 8512 | 98.50 % | 80 % | 8210 / 8336, 98.48 % |

File coverage, from `xcrun xccov view --report --json` on both result bundles (identical on iOS and watchOS for the
Domain files):

| File | Lines |
|---|--:|
| `ProgramTemplates.swift` | 100 / 100 |
| `ProgramTemplates+Splits.swift` | 22 / 22 |
| `ProgramTemplates+Prescriptions.swift` | 31 / 31 |
| `DaysPerWeek.swift` | no executable line |
| `Fixtures+Templates.swift` (iOS) | 22 / 23 |

LedgerDomain's 153 new lines are all covered. **LedgerFakes is 0.06 points lower than on `main`**: its one new
uncovered line is the fixture's `throw` (decision 13). Host `llvm-cov` over the Domain suites alone agrees on the
lines and adds regions: 24 / 24, 11 / 11, 19 / 19.

- **Release build:** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
  **exit 0** (100 s, no warning). `nm .build/out/Products/Release/LedgerFakes.o` lists 1 symbol and none of the
  fixtures' (Debug: 3,557, `defaultProgram` among them), so `LedgerFakes` is still empty in Release.
- **Host:** `scripts/check.sh --fast` exit 0 (Domain 811 tests, Persistence 452). `LedgerDependenciesTests` on the
  host: 56 tests pass.
- **Not verified:** the nightly lane (the performance test was run by hand on the host only, never on a simulator);
  CI (nothing was pushed); a device.
- **Final tree:** `scripts/check.sh --lint-only` after this section was written: exit 0.

### How to verify by hand

```sh
# The slice's suites on the host (about a minute after the first build):
swift test --package-path LedgerKit --only-use-versions-from-resolved-file \
  --filter 'ProgramTemplates|DaysPerWeekTests|FixturesTemplatesTests|TemplateProgramRoundTripTests'
# The nightly timing test:
LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --only-use-versions-from-resolved-file \
  --filter ProgramTemplatesPerformanceTests
# LedgerFakes out of Release:
(cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file)
# File coverage after a gate (prints "name covered/executable"):
xcrun xccov view --report --json .derivedData/Results/PR-iOS.xcresult \
  | jq -r '.targets[].files[] | select(.name | test("^ProgramTemplates[+.]|^Fixtures.Templates"))
           | "\(.name) \(.coveredLines)/\(.executableLines)"' | sort -u
```

Reading check: `ProgramTemplates+Splits.swift` beside the brief's "Templates" list, and
`ProgramTemplates+Prescriptions.swift` beside the role table and spec §6.4. The tests' own copy is
`LedgerDomainTests/Templates/TemplateOracle*.swift`.

### Open questions

1. **`Request` or the flat signature?** (decision 1). *Recommendation:* keep `Request`; it costs S2 one line and
   keeps the repo at one parameter-count suppression.
2. **LedgerFakes' coverage is 0.06 points lower** because of one defensive `throw` (decision 13). *Recommendation:*
   accept; the alternative is a silent fallback date in a fixture, which is worse.
3. **Week 8 on the 4-day split has three sessions while `daysPerWeek` is 4.** F09's "n of 4 sessions" must count
   the week's schedule, not `daysPerWeek`, or the deload week reads "3 of 4" at best. *Recommendation:* F09 uses
   `week.schedule.count`; noted here because F08 generates the data.
4. **`Fixtures.history(weeks:)` and `seedSession()` are built from `seedProgram`.** They name its days, slots and
   loads and do not fit `defaultProgram`. *Recommendation:* F09 and F10 keep `seedProgram` wherever a test needs
   history, and use `defaultProgram` where it needs "what onboarding saved"; a `history(of:)` variant belongs to
   whichever slice first needs one.
5. **Templates name exercises, so a future catalog rename needs both edited together.** A Domain test fails the PR
   if they drift. On a device, onboarding reads the stored catalog, which a launch refreshes before the gate shows
   onboarding (S3, O12); if that refresh failed, a renamed exercise is `unknownExercise` until the retry seeds.
   *Recommendation:* nothing now (decision #28 covers it); matching by id (O5's alternative) would remove the case
   if it ever matters.
6. **Pete's decisions 1, 3 and 4 are still open.** This slice is the defaults. Each is a data-only change here:
   an abs slot is one `Lift` line, one preview line and one oracle line; a changed 3-, 5- or 6-day list likewise;
   decision 4 would change `startDate` only. The S1 PR waits for decision 3 (rulings).
7. **The fixture is pounds only.** *Recommendation:* add `units:` when a second caller needs kilograms; until then
   a kg program is four lines with `ProgramTemplates.program`.

### Inputs for S2

- **The call.**
  ```swift
  let request = ProgramTemplates.Request(goal: goal, days: days, units: settings.units, startDate: start)
  let program = try ProgramTemplates.program(request, catalog: exercises, id: ProgramID(uuid()), newID: { uuid() })
  ```
  `exercises` is `exerciseRepository.all()`. `start` is `ProgramTemplates.startDate(containing: date.now, weekStart:
  settings.weekStart, calendar: calendar)`, an optional: `nil` only for a date outside the years 1…9999, which the
  store should treat as a failed save (the retry state), not unwrap.
- **Failures.** With an unseeded catalog the generator throws `ProgramTemplateError.unknownExercise(name)` before
  anything is saved; `RepositoryError.unknownExercise` from `save` is then a second line of defence. `program` is
  plain `throws`. A call that throws `unknownExercise` has not called `newID` (fix round 1). In the call above the
  program's own id is the store's `uuid()`, drawn before the generator runs, so each attempt still costs that one.
- **Step 3.** `ProgramTemplates.preview(days:)` gives `programName` and one `DayPreview` per day (`name`, `tag`,
  `line`; `line` was `exercises` until fix round 1). Names keep " — "; criterion 3's " · " is the presentation's
  replacement. There is no public
  initializer: build models from `preview(days:)`. Longest strings for layout: "Full Body C — Deadlift focus",
  "Row, pull-up, pulldown, chest-supported row"; six rows for six days. The preview needs no catalog, so step 3
  can draw before the catalog is read.
- **Skip setup** is `Request(goal: .both, days: .four, …)`; `ProgramTemplates` has no "default" of its own.
- **Tests.** `Fixtures.defaultProgram()` is what a skip saves at `Fixtures.now` in pounds, except for ids: the
  store's come from the `uuid` dependency (the program's id first, then the generator's order), the fixture's are
  `defaultProgramID` and `uuid(1001…)`. Either generate the expectation with the same sequence, or compare
  `seedProgram`-style field by field as `FixturesTemplatesTests.defaultProgram_differsFromSeedProgram_
  onlyInLoadsIdsAndStart` does. A store seeded for a save: `InMemoryStores.Seed(catalog: ExerciseCatalog.seed(),
  settings: Fixtures.settingsKg)`; kg loads are the catalog's (Bench 20 kg).
- **Rows written by a save** (for S3's Diagnostics assertions): `program` 1, `program_week` 8, `day_template` 4,
  `slot` 16, `slot_miss` 0 for the default; 3 / 15, 5 / 24 and 6 / 24 days / slots for the other splits.

### S1 — orchestrator rulings after G2 and G3 (2026-10-04)

- **G2 closed in round 1** (no bug; 79 tests of the tester's own, committed `1031136`). **G3 approved**: 0 Blocking,
  1 Should fix, 4 nits (`review.md`).
- **`ProgramTemplates.program(_ request: Request, catalog:id:newID:)` is the accepted signature** (the implementer's
  decision 1; review S1-N4). The flat seven-parameter form in "Corrected `ProgramTemplates` signatures" above was the
  plan's; it is superseded by "The API as built". S2 codes against `Request`.
- Fix round 1 takes all five review items: S1-SF1 (the async fixture suite gets its time limit), S1-N1 (resolve every
  lift before drawing an id, so a failed generation draws nothing), S1-N2 (a template day carries its weekday; the
  schedule is built from the days), S1-N3 (`DayPreview.exercises` becomes `DayPreview.line`, the internal
  `Day.exercises` becomes `Day.preview`), S1-N4 (this entry, and a pointer on the old signature block).
- The tester's F8-S1-1 and the review's two role-table observations (linear accessories under `strength`; two days
  that never change under `consistency`) are with Pete as part of his decision 3. They are data-only changes if he
  wants them; the S1 PR waits for that answer.
- The review's note on changing units after onboarding (a slot keeps its stored load, so 45 lb reads 20.41 kg) goes
  to F14's brief as an input.

### S1 fix round 1 (G1 implementer, 2026-10-04)

On top of `1031136`, uncommitted. The five review items and the F14 input; no template's content, no role table
entry and no expected value in any test changed. Paths are under `LedgerKit/`.

**What changed, per item**

| Item | Change | Where |
|---|---|---|
| S1-SF1 | `.timeLimit(.minutes(1))` on the fixture suite. I checked the 17 suites this slice added (9 mine, 8 the tester's) for async tests: five have them, this one included. `TemplateProgramRoundTripTests` and the tester's `FixturesTemplatesAdversarialTests` already had one minute; the tester's `TemplateProgramStoreAdversarialTests` has two minutes, left as the tester set it; the tester's `TemplatesDeterminismAdversarialTests` (one async test, `concurrentCalls_giveTheSameBlocks`) had none and now has one minute | `Tests/LedgerDependenciesTests/FixturesTemplatesTests.swift:9`; `Tests/LedgerDomainTests/Templates/Adversarial/TemplatesDeterminismAdversarialTests.swift:7` |
| S1-N1 | Every lift of the split finds its catalog exercise before the first id is drawn (`resolved`, through the new private `lifts(of:in:)`); the ids are then drawn in the documented order, unchanged. A call that throws `unknownExercise` has not called `newID`; the doc comment says so and the caveat is gone. New test `program_unknownExercise_drawsNoID` (4 splits): each exercise of the split is removed from the catalog in turn, the error names it and no id is drawn; the same id source then writes the usual block. Notes: decision 7 marked, "Inputs for S2" corrected (the store's own `ProgramID(uuid())` is still drawn by the caller before the call) | `Sources/LedgerDomain/Templates/ProgramTemplates.swift:102-103`, `:134-147`, doc `:90-93`; `Tests/LedgerDomainTests/Templates/ProgramTemplatesCatalogTests.swift:84` |
| S1-N2 | A template day carries its weekday (`Day.weekday`, `Day(_:tag:on:lifts:preview:)`), `Split.weekdays` is gone, and the schedule is filled in the loop that writes each day template (`training[day.weekday] = dayID`), with no `zip`. `Split` has an explicit `init(name:deloadRestDays:days:seed:)`, so `deloadRestDays` and `seed` are `let`. `weeks` now takes the schedule and the rest days | `Sources/LedgerDomain/Templates/ProgramTemplates+Splits.swift:37`, `:42`, `:56`, `:61`, `:63`, and the 18 `Day(…)` calls; `ProgramTemplates.swift:106-121`, `:175-185` |
| S1-N3 | Public `DayPreview.exercises` is `DayPreview.line`; internal `Day.exercises` is `Day.preview`. My own tests follow; the tester's are under "Sanctioned test edits". "The API as built" and "Inputs for S2" above now say `line` | `ProgramTemplates.swift:48`, `:65`; `ProgramTemplates+Splits.swift:40`; `Tests/LedgerDomainTests/Templates/ProgramTemplatesSplitsTests.swift:68`, `:89`, `:106-107` |
| S1-N4 | One line at the top of "Corrected `ProgramTemplates` signatures" pointing to "The API as built" | this file, line 22 |
| F14 input | New last section `## Inputs from F08 (2026-10-04, S1)`, three lines | `tasks/features/F14-settings.md` |

**Two things a reader should know about S1-N2.**
- With a weekday in it, the one-line day header passes 120 columns for three days ("Full Body A / B / C"), so the
  preview line moved behind the lifts it abbreviates: `Day("…", tag: "FC", on: .friday, lifts: […], preview: "…")`.
  Same two lines of overhead per day as before; nothing else in the tables moved.
- A day can no longer be written without a weekday. Two days on one weekday can still be written: the later one
  takes the weekday and the earlier is never scheduled. `program_weeks1to7_scheduleExactlyDaysPerWeek` and the
  tester's `program_schedule_matchesTheBrief` fail on that; nothing in the types prevents it.

**Sanctioned test edits** (the tester's files; `git diff 1031136 -- LedgerKit/Tests/**/Adversarial` shows exactly
these four lines, and no expected value among them):

| File (`Tests/LedgerDomainTests/Templates/Adversarial/`) | Line | Edit |
|---|--:|---|
| `TemplatesDeterminismAdversarialTests.swift` | 7 | `@Suite(…, .tags(.domain, .property))` gains `, .timeLimit(.minutes(1))` (S1-SF1) |
| `TemplatesTableAdversarialTests.swift` | 162 | `preview.days.map(\.exercises)` → `preview.days.map(\.line)` |
| `TemplatesTableAdversarialTests.swift` | 168 | `$0.exercises` → `$0.line` |
| `TemplatesTableAdversarialTests.swift` | 197 | `day.exercises` → `day.line`, three times on the line |

**Are the generated programs the same as before?** By the tests, unedited: for all 32 (goal, days, units) the
tester's `program_everySlot_matchesTheBrief`, `program_schedule_matchesTheBrief`, `program_header_recordsThePicks`
and `sameInputs_giveEqualPrograms`, its `ids_areDrawnInTheDocumentedOrder` (the 16 in pounds), and my
`program_startLoads_areTheCatalogs`, `program_sameInputsAndIDs_isEqual`, `program_drawsIDs_weeksThenEachDayAnd
ItsSlots` and the GRDB round trip. Between them they pin every field of a `Program`. I did **not** dump the old and
new output and compare them byte for byte: that needs the old sources built again.

**Spot check of the new behaviour** (two mutations in one host run, sources restored and compared byte for byte):
the lookup moved after the week ids makes `program_unknownExercise_drawsNoID` fail (82 issues over the 4 splits);
"Legs — Hinge focus" moved to Sunday makes four tests fail, two of mine and two of the tester's.

**Product lines now** (non-blank, not whole-line comments):

| File | Now | At `fd8e747` |
|---|--:|--:|
| `DaysPerWeek.swift` | 4 | 4 |
| `ProgramTemplates.swift` | 121 | 98 |
| `ProgramTemplates+Splits.swift` | 193 | 190 |
| `ProgramTemplates+Prescriptions.swift` | 96 | 96 |
| **LedgerDomain** | **414** (plan ≈ 360, +15 %) | 388 |
| `LedgerFakes/Fixtures/Fixtures+Templates.swift` | 25 | 25 |

The 23 lines in `ProgramTemplates.swift` are the lookup function, the slot function split from the loop, and the
wider `weeks` signature. `+Splits` is 238 lines with comments (lint limit 300).

**Coverage.** `ProgramTemplates*`, from `xcrun xccov view --report --json` on both of the gate's result bundles
(iOS and watchOS agree):

| File | Lines |
|---|--:|
| `ProgramTemplates.swift` | 104 / 104 |
| `ProgramTemplates+Splits.swift` | 27 / 27 |
| `ProgramTemplates+Prescriptions.swift` | 31 / 31 |
| `Fixtures+Templates.swift` | 22 / 23 (unchanged: the fixture's `throw`) |

Host `llvm-cov` adds regions: 28 / 28, 10 / 10, 19 / 19. Modules: LedgerDomain 2171 / 2189 (99.17 %), LedgerFakes
1349 / 1365 (98.82 %), overall 8394 / 8521 (98.50 %).

**Gate.** `/usr/bin/python3 <scratchpad>/sim-lock.py scripts/check.sh` from the worktree root, started 2026-10-04
19:25:00: **exit status 0** (`GATE_EXIT=0` read from the log, with `check.sh OK`), **552 s**, lock acquired after
0 s. Lint 65 s, iOS build 24 s, iOS tests 234 s, watchOS build 20 s, watchOS tests 206 s, coverage 2 s. "17 test
targets ran and passed (PR)", "8 test targets ran and passed (PR-Watch)"; iOS 1,752 tests, 0 failed (1,733 passed,
13 skipped, 6 expected failures); watchOS 1,571, 0 failed (1,555 passed, 13 skipped, 3 expected failures). One
warning in the log, on `main` already (`PayloadVersionAdversarialTests.swift:29`). The gate ran on this tree minus
this section; no file under `LedgerKit`, `Apps`, `scripts` or `docs` changed after it started, and
`scripts/check.sh --lint-only` was run again once this section was written: exit 0.

**Release build.** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
**exit 0** (34 s, no warning). Release `LedgerFakes.o` still holds one symbol and none of the fixtures'.

**Host.** Domain 876 tests, Persistence 460, Dependencies 63: all pass, the tester's 79 among them.

**Not verified:** a byte-for-byte comparison of old and new output (above); the nightly lane, which now runs the
tester's determinism suite at 2,000 seeds under the new one-minute limit (the limit is per test case, and a case is
one seed) and the timing test; CI; a device.

## Slice S2 — orchestrator's brief (2026-10-05)

S2's specification is the brief's last section, "Plan amendments — slice S2". This branch,
`feat/F08-s2-onboarding-ui`, is S1's tip (`c685d65`, with `main` merged) plus F09 S1's tip merged in (`844a583`),
because S2 needs the localization rule and helper; it stays local until both are on `main`.

- The localization pattern is now `docs/engineering-standards.md` §7 as F09 S1 rewrote it: a catalog and
  `OnboardingCopy.swift`, nothing else to add; the gate's string-catalog step, `ModuleCopyTests` and the bundle
  check find the module by themselves. "L0" in the plan above no longer exists as a separate piece.
- `ProgramTemplates.program(_ request: Request, catalog:id:newID:)` and `DayPreview.line` are the API (S1's fix
  round); see "Inputs for S2" in S1's section.
- `ModuleCopyTests.exemptions`, `PreviewScan.registeredModules`, `Package.swift`'s `snapshotTestTargets` and
  `scripts/coverage-thresholds.json`'s `required` are the shared one-line files: add only `FeatureOnboarding`.
