# F14 — Settings, units, plates, export

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F07 |
| Branch | `feat/F14-settings` |
| Design refs | `design/prototype/Ledger.dc.html` → `Settings`; v2 visual system |
| Spec refs | `docs/product-spec.md` §3.3, §7.1 rule 3, §7.7 rule 38, §9 (Units, Export); `docs/product-decisions.md` #9, #10, #15, #19, #20 |

## Goal
Settings owns the few global preferences the whole app reads: units (lb/kg with correct steps everywhere), default rest, plate math with a per-unit bar/plate inventory, auto-rest, watch buzz, week start, an Apple Health status row, CSV export, and "Delete all data". The gear lives where the prototype's avatar was; there is no profile or account.

## User stories
- As a kg lifter, I flip one switch and every weight, step and plate calculation follows.
- As a lifter, I can export my whole log as CSV and share it.

## Scope
**In:** `FeatureSettings` screen + store, `Settings` persistence via `SettingsRepository`, plate inventory editor, CSV export via share sheet, Delete all data (confirm), About/version (read `CFBundleDisplayName` / `CFBundleShortVersionString` / `CFBundleVersion` from the bundle — never a hard-coded product name or version), Health row (status + open system Settings), Diagnostics entry (Debug).
**Out:** HealthKit authorization itself (F16 — the row shows "Not connected" until then), iCloud status (F28), notification preferences (F23).

## Touches
- `LedgerKit/Sources/FeatureSettings/{SettingsRoot,SettingsStore,PlateInventoryEditor,ExportService,DeleteAllData,SettingsRoute}.swift`
- `LedgerKit/Sources/LedgerDomain/Export/CSVExport.swift` (pure: `[WorkoutState] → String`)
- `LedgerKit/Tests/FeatureSettingsTests/**`, `LedgerKit/Tests/LedgerDomainTests/Export/CSVExportTests.swift`
- `LedgerKit/Sources/LedgerAppKit/Routes.swift`, Today's header gear button (coordinate with F09 — the button is F09's; the route is this brief's)

## Domain changes
```swift
public enum CSVExport { public static func render(workouts: [WorkoutState], exercises: [ExerciseID: Exercise], units: Units) -> String }
// columns: date,workout,tag,exercise,set,kind,weight_<lb|kg>,reps,done,e1rm_<unit>  — RFC 4180, header row, UTF-8, no health values
```
`Settings` (F02) gains nothing; `SettingsRepository.observe()` drives live updates.

## Acceptance criteria
1. Given units switched lb → kg, when Today, Active workout, Library, History render, then weights show kg and steps are 2.5/1.25 (2 for kettlebells, decision #22) (verified through `Weight.formatted(in:)` and `Equipment.defaultStep(in:)` bindings; a UI test flips units and asserts a known set row).
2. Given "Default rest" stepped, then values stay within 30–300 s in 15 s steps and new slots (F11) pick it up.
3. Given "Plate math" on, then the bar and plate inventory editor is enabled with `PlateInventory.standard(units)` defaults; edits persist; F25 reads them.
4. Given the Health row before authorization, then it reads "Apple Health · Not connected" and tapping opens the system Settings app; after F16, "Connected".
5. Given "Export data · CSV", then a share sheet presents `ledger-export-YYYY-MM-DD.csv` whose content equals `CSVExport.render` output for all finished workouts.
6. Given "Delete all data" confirmed twice (alert + typed "DELETE"), then the database is recreated empty, the catalog re-seeded, settings reset, and the app returns to Onboarding.
7. Given "Week starts on" changed, then Today's week strip and History grouping change accordingly (observed).
8. Given VoiceOver, every toggle announces its label and state.

## Test plan
- Unit: `SettingsStoreTests` (each preference round-trips via the in-memory repository; range clamps), `CSVExportTests` (header, escaping of commas/quotes in names, kg vs lb columns, no HR columns, empty log → header only), `DeleteAllDataTests` (calls in order; routes to onboarding).
- Snapshot: `SettingsRoot` {lb, kg} × {light, dark} × {large, accessibility3}; `PlateInventoryEditor`.
- UI (nightly `Settings` suite): units flip criterion 1; export presents share sheet (assert the activity controller appears).

## Non-functional
- Export of 10,000 sets renders < 200 ms and streams to a temp file (no giant `String` in memory beyond 5 MB).
- Delete-all is atomic: close DB → delete file → reopen/migrate/seed.

## Risks / unknowns
- Share sheet automation in XCUITest is flaky — assert presentation only, tagged `.flakyProne` and nightly.

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_
- `F14-settings/implementation-notes.md`
- `F14-settings/test-findings.md`
- `F14-settings/review.md`

## Inputs from F05 (2026-09-30)
- `LedgerDatabase.open(at:protection:)` is synchronous: call it off the main actor. It took 4.6 ms on the
  watch simulator. Give the database a directory of its own, e.g. `Application Support/Database/ledger.sqlite`.
- A settings row this app cannot read makes `SettingsRepository.load()` throw, and `observe()` then ends
  without a value (review N2). The row may be in a later payload version (`unknownPayloadVersion`), hold a
  damaged column (`malformedColumn`) or invalid JSON (`DecodingError`). Fall back to `Settings.default` in
  memory, but never save it over the row: a later version, or the lifter, may still read it. Subscribe
  again after the lifter's next deliberate save.

## Inputs from F08 (2026-10-04, S1)
- A generated slot stores its start load in the unit of the day it was created, and `step == nil`, so after a unit
  change in Settings a stored 45 lb reads 20.41 kg and steps as 20.41, 22.91, 25.41. F14 must decide what a unit
  change does to stored start loads: convert and round to the new unit's step, or keep them exact.
- (2026-10-18, S2/S3; Pete's decision 5 = C) Decision #15, the week start from the iPhone's region on first
  launch, is unimplemented: nothing writes the settings before onboarding, so onboarding copies the stored
  units and week start (`Settings.default`: pounds and Monday) into the block it saves. F14 decides whether
  first launch reads the region for the week start (and the units), and what that does to a block saved before.

## Plan amendments (planner, 2026-10-28, against `main` @ 98b340d)

The planner's report, recorded as given. Where it and the brief above disagree, this section and the rulings after it win.

Paths are relative to `/Users/peterarevalo/Dev/workout-app/.claude/worktrees/F14-s1`, and `LedgerKit/` is left off source paths. Line numbers are as of 98b340d.

## 1. Corrections to the brief

**What already exists**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C1 | `Settings` persistence via `SettingsRepository` | It exists and is complete (F05): `load`, `save`, `observe`, over GRDB and in memory, pinned by `SettingsRepositoryContract`. **Nothing saves settings today**: onboarding, Today, the Program builder, the picker, the Library and the workout launcher only read them. F14 is the first writer | `Sources/LedgerDomain/Protocols/Repositories.swift:147-151`; `Sources/LedgerPersistence/Repositories/GRDBSettingsRepository.swift`; `Sources/LedgerFakes/InMemorySettingsRepository.swift`; grep of `save(` callers |
| C2 | Onboarding writes preferences | It does not. It reads the stored units for its step-3 sentence and copies the stored units and week start into the block it saves | `Sources/FeatureOnboarding/OnboardingStore.swift:109-118, 161-177` |
| C3 | `Routes.swift` and Today's header gear (coordinate with F09) | Both are done. `AppDestination.settings` exists and draws a `PlaceholderScreen("Settings", identifier: "settings.title")`. `TodayRoute.settings` is resolved, keeping one Settings on the stack. The gear is `TodayHeader`'s. F14 replaces only the placeholder in `AppTabs.screen(for:)`. It keeps `settings.title` on its title, because the nightly `Today.swift` UI test finds it there | `Sources/LedgerAppKit/Routes.swift:15-16`; `Routes+Today.swift:27-31`; `AppTabs.swift:61-62`; `Sources/FeatureToday/Views/TodayHeader.swift:33`; `Apps/LedgerUITests/Today.swift:90-94` |
| C4 | Module setup (`FeatureSettings`) | It is still a stub: `FeatureSettings.swift` and a placeholder test. The target has no `resources`. It is missing from `snapshotTestTargets`, from `required` in `scripts/coverage-thresholds.json` and from `PreviewScan.registeredModules`. It is already in both test plans. S1 adds it to each list, as F12 S1 did (F12 C22) | `Package.swift:159, 67-70`; `scripts/coverage-thresholds.json:15`; `Sources/LedgerTestSupport/Previews/PreviewScan.swift:9-12`; `TestPlans/PR.xctestplan:129` |
| C5 | Files `SettingsRoot, SettingsStore, PlateInventoryEditor, ExportService, DeleteAllData, SettingsRoute` | Follow the layout F12 shipped: `SettingsRoute`, `SettingsCopy*`, `SettingsAction`, `SettingsInput`, `SettingsModel`, `SettingsPresentation`, `SettingsStore(+Sources)`, `SettingsRoot`, `Views/*`, `Settings+Previews` | `Sources/FeatureLibrary/*` |

**Units, rest and week start**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C6 | Criterion 1: the Active workout turns to kg | A workout copies the unit (and `autoRest`) when it starts. **A live workout keeps its unit until it ends**; the switch takes effect from the next workout | `Sources/LedgerDomain/Rules/SessionBuilder.swift:45, 66-67`; `WorkoutState.swift:48` |
| C7 | Criterion 1: Today, the Library and History follow | Today, the Program builder, the Day editor, the picker and the Library already follow `settings.observe()` live. History is F13's. **For F14, criterion 1 is: a saved switch reaches every observer**, proved by a store test and the nightly UI test | `TodayStore.swift:56`; `LibraryStore+Sources.swift:36`; `DayEditorStore+Sources.swift:32`; `ProgramStore+Sources.swift:66` |
| C8 | Criterion 1: kg steps of 2.5 and 1.25 (2 for kettlebells) | Already true: `Equipment.defaultStep(in:)`. **What a switch does to weights already stored in the program is not settled** (F08's input above): Q1 | `Sources/LedgerDomain/Model/Exercise.swift:9-16`; `Slot.swift:27-30, 112-125` |
| C9 | Criterion 2: rest in 30–300 s, 15 s steps; new slots pick it up | Both exist: `RestDuration(clampingSeconds:)` and `.label`, and the picker passes `settings.defaultRest` to `DayEditing.newSlot`. F14 builds only the stepper | `Sources/LedgerDomain/Units/RestDuration.swift:27-50`; `Sources/FeatureProgram/ExercisePickerStore.swift:96-97` |
| C10 | Criterion 7: Today's strip and History grouping follow the week start | Today's strip and its stats weeks already read `settings.weekStart` live. Program weeks count from the block's first day whatever the week start (`ProgramStore+Sources` uses Monday on purpose), so a later change never moves a block. History grouping is F13's (coordination flag K3) | `Sources/FeatureToday/TodayPresentation.swift:126-131`; `TodayHistory.swift:35`; `Sources/FeatureProgram/ProgramStore+Sources.swift:41, 54` |
| C11 | Decision #15: the week start comes from the region | Not implemented: `Settings.default` is Monday and lb, and nothing writes settings before onboarding (F08, Pete's decision 5 = C, deferred to F14): Q2 | `Sources/LedgerDomain/Model/Settings.swift:36-49` |
| C12 | The three toggles act | `autoRest` is copied into a workout when it starts (C6). Nothing reads `watchBuzz` until F18 (M2), and nothing reads `plateMathEnabled` or `plateInventory` until F25 (M3). F14 proves that they persist and are observed; criterion 3's "F25 reads them" becomes an input for F25 | grep of the three fields |
| C13 | Criterion 3: `PlateInventory.standard(units)` | It exists, and `Settings.default` already holds both units' standard inventories. The type has no plate counts: each size comes in any number of pairs | `Sources/LedgerDomain/Model/PlateInventory.swift:3-25` |

**Health, About, Diagnostics**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C14 | Criterion 4: the Health row reads its status, and tapping opens Settings | `HealthStore` is an empty protocol. `authorization()` is F16's. `HealthAuthorization` lives in LedgerHealth, which a feature cannot import. Until F16 the row can only show a fixed "Not connected": Q4 | `Sources/LedgerDomain/Protocols/HealthStore.swift:5`; F16 brief:67-68, 125; `package-graph.expected.txt:9` |
| C15 | About reads the bundle | Under package tests `Bundle.main` is the test runner. `LedgerAppKit` builds an `AppAbout` value (display name, version, build) from `Bundle.main` and hands it to `SettingsRoot`, so tests pass their own. No product name or version appears in source | product-decisions, Naming |
| C16 | "Diagnostics entry (Debug)" | Diagnostics is a page of Debug's `DebugMenu`, raised by `MainRoot` from a long press on Today's title, and it reads `AppComposition`, which a feature cannot see. Settings gets a DEBUG-only row that emits `SettingsRoute.debugMenu`, and `MainRoot` raises the same sheet | `Sources/LedgerAppKit/MainRoot.swift:81-97`; `AppComposition+Diagnostics.swift` |
| C17 | The prototype's ACCOUNT section (Email, Apple Health, Export, Log out) | There are no accounts (decisions #2, #19): Email and Log out are dropped. The section holds Apple Health, Export and Delete all data under a "DATA" eyebrow | `design/prototype/Ledger.dc.html:1272-1277` |

**Export**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C18 | The file is `ledger-export-YYYY-MM-DD.csv` | The lifter sees the file's name in the share sheet and in Files, and shipped copy never contains the product name (Naming): Q5 | product-decisions, "Naming" |
| C19 | `render(workouts:exercises:units:)` | A workout already holds each exercise's name and equipment as logged, so `exercises` isn't needed. A date needs the lifter's calendar (decision #26: the day it started). The API becomes `CSVExport.header(units:)` and `CSVExport.lines(for: WorkoutState, units:calendar:)`, with `render` built from them, so a writer can stream workout by workout | `Sources/LedgerDomain/Model/WorkoutExercise.swift:15` |
| C20 | "all finished workouts" | There is no "all" read. `workouts(in: .distantPast ..< .distantFuture)` returns them newest first, deleted ones left out. The export writes them oldest first | `Repositories.swift:124-125`; `GRDBWorkoutRepository.swift:103-105` |
| C21 | 10,000 sets: under 200 ms, streamed, no String over 5 MB | At about 80 bytes a row, 10,000 sets come to about 0.8 MB and 20,000 to 1.6 MB. Streaming per workout to a `FileHandle` still keeps memory flat. Measured in the nightly `.performance` suite | estimate |

**Delete all data**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C22 | Criterion 6 and Non-functional: close the database, delete the file, reopen, migrate, seed | **This can't be done as written.** The stores are bound to the dependency keys once, process-wide (`prepareDependencies`). `DatabaseLaunch` opens once and keeps `stores`. Every open observation holds the queue. Decision #29 forbids launch code to delete the file. **Replace it with an in-place erase in one write transaction**: delete every row, then reseed the catalog in the same transaction. Flag A1 | `Sources/LedgerAppKit/AppComposition.swift:53-70`; `Sources/LedgerPersistence/DatabaseLaunch.swift:81-94` |
| C23 | Criterion 6: the app returns to Onboarding | Already wired. `RootGate` follows `observeActive()` and shows onboarding on nil. `MainRoot` then starts over with a new router. Both carry comments naming F14. No route is needed | `Sources/LedgerAppKit/RootGate.swift:8-10, 44-49`; `MainRoot.swift:59-71` |
| C24 | Criterion 6: settings reset | Removing the row makes `load()` return `Settings.default`, and observers emit it. With Q2 = A, the erase writes the regional defaults in the same transaction | `GRDBSettingsRepository.swift:56-60` |
| C25 | Criterion 6 says nothing about a live workout | The session host keeps a live workout in memory and in `workout_event`. Erasing the log under it would bring the workout back on its next event. Q3 | `Sources/LedgerSync/LocalWorkoutSessionActor.swift`; `WorkoutSessionClient.swift:30-33, 108-116` |
| C26 | What "everything" is | Tables: `exercise`, `program`, `program_week`, `day_template`, `slot`, `slot_miss`, `workout`, `workout_exercise`, `logged_set`, `personal_record`, `workout_health`, `workout_event`, `settings`, `device`. The erase hard-deletes every row of every table **but `device`**. `device` holds this install's id and a kind name ("iPhone"), nothing personal, and F19/F28 key on it. Soft-deleted rows go too | `Sources/LedgerPersistence/Migrations.swift:44-232`; `LocalDevice.swift:15-41` |

**Conventions**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C27 | `test_…` names; snapshot matrix | `subject_condition_expectation`, with no `test` prefix. The {lb, kg} × {light, dark} × {large, accessibility3} matrix is 8 references, under the 20-reference line | `docs/testing-strategy.md:438-443` |
| C28 | The prototype's orange toggle tracks | `LedgerToggleStyle` is ink-only (Pete's F11 decision 1). Settings has no primary action, so **no orange on Settings** (decision #17) | `Sources/LedgerDesign/Components/LedgerToggleStyle.swift:3-9` |
| C29 | AppTabs tests | `AppTabsTests.swift:76-105` uses `.settings` as its generic pushed destination and expects the labels to be exactly `["Settings"]`, the placeholder's. Real Settings reads many labels. These are sanctioned edits: assert the `settings.title` header instead | as cited |

## 2. Slices

Three sequential pull requests, each cut from `main` after the one before has merged. S2 and S3 both build on S1's store, copy and page, and both edit the same store and presentation, so **run them one after the other**.

- **How lines are counted:** as in F12: non-blank, non-comment Swift under `LedgerKit/Sources` and `Apps`. String catalogs, `LedgerTestSupport` and the UI-test targets are excluded. LedgerFakes and `*+Previews.swift` are counted.
- **Calibration:** F12 S1 planned 790 and landed at 933 net. The copy file, the store's sources and the previews ran over. The estimates below carry that margin.
- **Stop rule:** each slice stops and reports past about 950 lines.
- **Every PR description says it is over the 500-line target** and names the split it considered (standards §10:512-515).

### S1: the Settings screen and its preferences (about 885 lines)

**Scope**
- Module setup (C4).
- `SettingsCopy`, action, input, model, presentation, store, root and views.
- TRAINING: Units, Default rest, Week starts on, Plate math, Auto rest timer, Watch haptic at zero.
- DATA: the Apple Health row (fixed, per Q4).
- The About footer.
- The Debug row.
- Q2's regional defaults on first launch.
- `AppDestination.settings` drawing `SettingsRoot`.
- **Not in S1:** the "Bar and plates" row (S2) and the Export and Delete rows (S2, S3).

**Criteria owned**
- **1 (restated per C6–C8):** tapping KG saves `units = .kg` once. Today, the Library and the Program screens redraw in kg without navigating. A live workout keeps its unit. Q1's program conversion is S2's.
- **2:** "−" and "+" step the rest by 15 s within 30–300 s, and each step at a bound is switched off. A saved rest is what `ExercisePickerStore` gives a new slot (store test across the two stores over one in-memory repository).
- **4 (per Q4):** "Apple Health" with "Not connected".
- **7 (restated per C10):** a weekday picked under "Week starts on" is saved. Today's strip redraws starting on it. The block's program weeks don't move.
- **8:** every toggle reads its label, its subtitle and on or off (`LedgerToggleStyle` is already SwiftUI's switch to VoiceOver).

**New criteria**
- **N1. Saving:** each change is one `save` of the whole `Settings`, made from the latest value the store holds. Saves run one at a time, and a change made while one runs is saved next, folded with any others (the last value wins). The control shows the lifter's value at once and doesn't flicker back when `observe()` echoes an earlier save. A failed save shows "Couldn't save that change." and reverts the control to the stored value.
- **N2. Unreadable settings** (F05 input): when `observe()` ends without a value, or `load()` throws, the screen draws `Settings.default`. Nothing is saved until the lifter changes something. That first change saves the whole value (overwriting the unreadable row, as F05 allows), and the store then subscribes again.
- **N3. Regional defaults** (Q2 = A):
  - `Settings.regional(locale:calendar:)` gives:
    - units: lb where `locale.measurementSystem == .us`, kg everywhere else;
    - week start: `Weekday.first(of: calendar)`;
    - everything else as `.default`.
  - `SettingsRepository.seedIfAbsent(_:)` writes it only when there is no row. It is new on the protocol, with a contract clause run against GRDB and the in-memory store: an existing row, even an unreadable one, is never touched.
  - The iPhone's `loadSettings` launch step calls it before loading. The watch's never does (F19 supplies the watch's settings).
- **N4. Week start picker:** all seven weekdays, named by the lifter's locale (`Calendar.weekdaySymbols`), listed from the locale's first weekday. VoiceOver reads "Week starts on, Monday".
- **N5. Units control:** a two-option segmented control, "LB" and "KG". VoiceOver reads it as a group "Units", with the chosen option `.isSelected`. Its spoken names are "pounds" and "kilograms".
- **N6. About:** "{CFBundleDisplayName} {CFBundleShortVersionString} · build {CFBundleVersion}", from `AppAbout`. A missing key leaves its part out, and the line is never empty of words. A source test asserts that no literal product name or version appears in FeatureSettings.
- **N7. Debug row:** "Diagnostics" exists only in DEBUG builds and emits `.debugMenu`. `MainRoot` raises the Debug menu's sheet. A Release build compiles neither the row nor the case.
- **N8. The title:** the screen draws its own "Settings" header with identifier `settings.title`. The pushed screen keeps the navigation bar's back button.
- **N9. Conventions:** `FeatureSettingsSourceTests` enforces the F12 checks: every lookup lives in `SettingsCopy*.swift`; views import only SwiftUI and LedgerDesign; one scroll view per screen; no orange (C28).
- **N10. Text sizes:** at accessibility sizes, each row's control moves under its label (the `StepperField` and `HairlineRow` rule). The segmented control stays one line, at 44 pt per option.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Model/Settings.swift`: `regional(locale:calendar:)` | 15 |
| `LedgerDomain/Protocols/Repositories.swift`: `seedIfAbsent` | 3 |
| `LedgerPersistence/Repositories/GRDBSettingsRepository.swift`: `INSERT … ON CONFLICT DO NOTHING` | 15 |
| `LedgerFakes/InMemorySettingsRepository.swift`, `LedgerDependencies/…/UnimplementedStores.swift` | 11 |
| `LedgerPersistence/DatabaseLaunch.swift`: the regional value passed in, seeded in `loadSettings` | 15 |
| `LedgerAppKit/AppComposition.swift`: the environment's locale and calendar | 4 |
| `FeatureSettings/SettingsRoute.swift` | 10 |
| `SettingsCopy.swift`, `SettingsCopy+Names.swift`: rows, subtitles, units, weekdays, rest spoken, errors, About | 130 |
| `SettingsAction.swift`, `SettingsInput.swift`, `SettingsModel.swift` | 85 |
| `SettingsPresentation.swift` | 130 |
| `SettingsStore.swift`, `SettingsStore+Sources.swift` | 160 |
| `SettingsRoot.swift` | 40 |
| `Views/SettingsScreen.swift`, `SettingsPage.swift`, `SettingsSection.swift`, `UnitsRow.swift`, `WeekStartRow.swift`, `AboutFooter.swift` | 130 |
| `LedgerDesign/Components/SegmentedChoice.swift`, with its gallery entry (A5) | 50 |
| `Settings+Previews.swift` | 55 |
| `LedgerAppKit`: `AppTabs.swift`, `Routes+Settings.swift`, `MainRoot.swift`, `AppAbout.swift` | 35 |
| `Package.swift` (resources, `snapshotTestTargets`) | 2 |
| Placeholder `FeatureSettings.swift` and its test removed | −3 |
| **Total** | **about 885** |

**Tests**
- Domain: `SettingsRegionalTests`: en_US gives lb and Sunday; de_DE gives kg and Monday; en_GB gives kg and Monday; ar_AE gives the calendar's first weekday.
- Contract: `SettingsRepositoryContract` gains the `seedIfAbsent` clauses: no row, a stored row, and an unreadable row left as it is (GRDB only).
- Launch: `DatabaseLaunchTests` covers:
  - the phone seeds the regional value once;
  - the watch kind seeds nothing;
  - a seed failure is logged and the launch goes on with what `load` gives.
- Unit: `SettingsPresentationTests` covers rows in lb and kg, the rest label and its bounds, the weekday order per locale, About with missing keys, and the Health row. `SettingsCopyTests`.
- Store: `SettingsStoreTests` covers:
  - each preference round-trips;
  - N1's serial, folded saves;
  - a failure reverts;
  - N2's unreadable fallback and the subscription again after the first save;
  - the rest reaching a new slot through `ExercisePickerStore`;
  - Today's model redrawing on a week-start change (one in-memory repository shared by two stores).
- Hosted, through `TestSweep`: `SettingsRootTests`, `SettingsAccessibilityTests` (the toggles, the segmented group, the stepper as adjustable, the picker), `SettingsLayoutTests`.
- Snapshots: `SettingsSnapshotTests` {lb, kg} × {light, dark} × {large, accessibility3}: 8 references.
- App: `SettingsRouteMappingTests` (`.debugMenu` raises the sheet), and the sanctioned edits of `AppTabsTests` (C29).
- Source: `FeatureSettingsSourceTests` (N9, N6).
- Nightly UI: `Apps/LedgerUITests/Settings.swift`. Today → gear → KG → back: Today's tiles read "kg", and a Library PR reads kg. `Today.swift:90-94` stays green unchanged.

**Needs:** Q2, Q4 and Q7 answered or defaulted. Merge first.

### S2: units carry the program, the bar and plates, and CSV export (about 710 lines)

**Scope**
- Q1's program conversion when the units change.
- The "Bar and plates" row and its sheet.
- "Export data · CSV" through the share sheet.

**Criteria owned**
- **1, the program part (Q1 = A):** after lb → kg, each explicit start load in the active program is rounded to the nearest default step of its equipment in kg. 45 lb becomes 20 kg; 135 lb becomes 62.5 kg. Each explicit step is converted and rounded the same way, never below one default step. `nil` loads and steps stay `nil`. Past workouts are untouched.
- **3 (restated per C12, C13):** with Plate math on, "Bar and plates" opens a sheet for the current unit's inventory, starting from the stored one (`standard` by default). With Plate math off, the row is drawn disabled and reads "Turn on Plate math to edit". Edits persist through N1. The other unit's inventory is left alone. "Reset to standard" restores `PlateInventory.standard(units)`.
- **5 (restated per C18–C21, Q5):** the row presents the share sheet. The file is `{name per Q5}.csv`, and its bytes equal the UTF-8 encoding (N15) of `CSVExport.render` over every stored workout, oldest first, in the lifter's current unit.

**New criteria**
- **N11. Conversion order:**
  1. The settings are saved first.
  2. Then `ProgramRepository.update(active)` applies `UnitSwitch.convert`, which is pure and idempotent: a load already on the new unit's grid is unchanged.
  3. A failed conversion shows "Couldn't convert your program's weights." with "Try again", which runs the same conversion. No active program means no conversion.
  - `UnitSwitch` has 100% line coverage, and a property test checks that converting twice equals converting once.
- **N12. Plate editor:**
  - The bar is a `StepperField`: 0–100 lb in 2.5 lb steps, or 0–45 kg in 1.25 kg steps.
  - Plates are on/off toggles over a fixed list per unit:
    - lb: 55, 45, 35, 25, 15, 10, 5, 2.5, 1.25;
    - kg: 25, 20, 15, 10, 5, 2.5, 1.25, 0.5.
  - A stored size off that list (from a later version) is shown and kept.
  - With every plate off, the sheet says "No plates: no plate line will show".
  - The sheet uses `SheetChrome`, and "Done" saves.
- **N13. CSV shape:**
  - The columns are `date,time,workout,tag,exercise,set,kind,weight_<lb|kg>,reps,done,e1rm_<lb|kg>`.
  - `date` is the start day `YYYY-MM-DD` in the lifter's calendar (decision #26). `time` is `HH:mm`.
  - `set` counts from 1 within the exercise. `kind` is `working`, `warmup`, `drop` or `added`. `done` is `1` or `0`.
  - Weights are plain decimals with a `.` separator, no grouping, rounded to hundredths as `Weight.formatted(in:)` rounds.
  - `e1rm` is Brzycki for a done set of 12 reps or fewer, and empty otherwise.
  - No health columns (architecture §16).
  - The row separator is CRLF (RFC 4180), and a field holding a comma, a quote, CR or LF is quoted, with quotes doubled.
- **N14. Formula guard:** a text field that starts with `=`, `+`, `-`, `@`, a tab or a CR gets a leading `'` (OWASP CSV injection), so a custom exercise named "=HYPERLINK(…)" opens as text in a spreadsheet. Numbers are never prefixed.
- **N15. Encoding:** UTF-8 with a byte-order mark, so Excel reads "Développé" correctly. An empty log gives the header row only.
- **N16. The file:**
  - It is written under `temporaryDirectory/Export/`.
  - The directory is emptied before each export and when Settings goes away.
  - The write streams workout by workout to a `FileHandle`.
  - A failure is logged, and the share sheet reports it.
- **N17. Budgets** (nightly `.performance`): 10,000 sets render and write in under 200 ms, and peak memory added stays under 5 MB.
- **N18. Hosting** (flag A2): the row is a `ShareLink` over a `Transferable` whose `FileRepresentation(exportedContentType: .commaSeparatedText)` writes the file when the lifter picks a destination. FeatureSettings needs no UIKit.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Rules/UnitSwitch.swift` | 50 |
| `LedgerDomain/Export/CSVExport.swift` | 100 |
| `SettingsStore+Units.swift`: the conversion step and its retry | 45 |
| `Plates/PlatesInput.swift`, `PlatesModel.swift`, `PlatesPresentation.swift` | 110 |
| `SettingsStore+Plates.swift`: edit, reset, done | 60 |
| `Views/PlateInventorySheet.swift`, `PlateToggles.swift` (on `WrapLayout`) | 95 |
| `Export/ExportFile.swift`: the directory, the stream, the name | 70 |
| `Export/WorkoutExport.swift` (`Transferable`) and `Views/ExportRow.swift` | 40 |
| `SettingsCopy+Plates.swift`, `+Export`, the conversion error | 70 |
| `SettingsPresentation` (the plates and export rows) | 25 |
| `Plates+Previews.swift`, export preview | 45 |
| **Total** | **about 710** |

**Tests**
- Domain:
  - `UnitSwitchTests`: lb → kg and back, the 135 → 62.5 → 140 drift (Q1), kettlebells to 2 kg, explicit steps, nil fields, idempotence as a property.
  - `CSVExportTests`: the header per unit; escaping of commas, quotes and line breaks in names; N14 for each prefix character; kg and lb values; kinds; not done; e1RM above 12 reps; an empty log; dates across midnight and daylight saving (decision #26).
  - A round-trip property: random names, including emoji and RTL, written and then parsed by an RFC 4180 reader in LedgerTestSupport, give the same fields.
- Store:
  - Conversion: saved, then converted; a failure shows the line; retry converts; no program, no write.
  - Plates: toggle, bar bounds, reset, the other unit untouched, disabled while Plate math is off.
  - Export: the bytes over an in-memory history equal `render`; the directory is cleared.
- Hosted, through `TestSweep`: `PlateInventorySheetAccessibilityTests` and `LayoutTests`; the export row is a share link with the label "Export data, CSV".
- Snapshots: the sheet {lb, kg} × {light, dark} at `.large`, plus lb at `.accessibility3` light and dark: 6 references.
- Performance: `ExportPerformanceTests`, gated by `TestLane.runsSlowTests`.
- Nightly UI: `SettingsExport` checks that the activity sheet appears. It is tagged `.flakyProne` (brief risk).

**Needs:** S1; Q1, Q5 and Q6.

### S3: Delete all data (about 540 lines)

**Scope**
- A Domain `DataReset` protocol with its GRDB implementation, its fake, its stub and its key.
- The two-step confirmation.
- The erase.
- Cleaning up the export files.

**Criteria owned**
- **6 (restated per C22–C26, Q3):**
  1. "Delete all data" opens an alert. Its title is "Delete all data?", and its message names what goes and what stays (Q3). "Cancel" sits beside "Continue" (destructive role).
  2. "Continue" opens a sheet with a text field ("Type DELETE to confirm"). "Delete everything" is enabled only when the trimmed text equals the localized word, ignoring case.
  3. On confirm, `dataReset.eraseAll(restoring:)` runs once. It deletes every row of every table but `device`, reseeds the catalog and writes the regional settings, all in one write transaction.
  4. The gate then shows onboarding (C23).
  5. A failure deletes nothing, and the sheet says "Nothing was deleted. Try again."

**New criteria**
- **N19. A live workout** (Q3 = A): while `workoutSession.current()` is non-nil, the row reads "Finish or discard your workout first" and is disabled. The store follows `workoutSession.updates()`.
- **N20. Atomic:** a catalog that fails to load or insert inside the transaction rolls back the whole erase, and the row counts afterwards equal those before. The catalog JSON is parsed before the transaction opens.
- **N21. Gone from the disk:** after the commit, `PRAGMA wal_checkpoint(TRUNCATE)` and `VACUUM` run, off the main actor and best-effort (a failure is logged; the erase has already succeeded). A distinctive custom exercise name and workout name are then absent from the database file and from its `-wal`.
- **N22. What else goes:** the export directory (N16) is removed. Apple Health is not touched, and the alert's message says so.
- **N23. Once:** a second tap while the erase runs does nothing. A cancelled task either erases everything or nothing.
- **N24. Budget** (nightly `.performance`): erasing a 20,000-set history and reseeding takes under 1 s at p95 on the simulator, with `VACUUM` included.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Protocols/DataReset.swift`: the protocol, `eraseAll(restoring: Settings)` and its doc | 20 |
| `LedgerPersistence/Repositories/GRDBDataReset.swift`: the deletes in child-first order, the reseed, the settings row, the checkpoint and vacuum | 75 |
| `GRDBExerciseRepository.swift`: seeding moved into a `Database`-level function that both callers use | 15 |
| `LedgerStores.swift`: the `reset` member | 4 |
| `LedgerFakes/InMemoryDataReset.swift`, plus a `reset` on each in-memory store | 50 |
| `LedgerDependencies`: `dataReset` key and `UnimplementedDataReset` | 20 |
| `AppComposition.bind` | 2 |
| `DeleteAll/DeleteAllInput.swift`, `DeleteAllModel.swift`, `DeleteAllPresentation.swift` | 70 |
| `SettingsStore+DeleteAll.swift`: the steps, the typed word, the live check, once, the failure, the export cleanup | 110 |
| `Views/DeleteAllSheet.swift` (on `SheetChrome`, with a text field) and the alert | 90 |
| `SettingsCopy+DeleteAll.swift` | 45 |
| `DeleteAll+Previews.swift` | 30 |
| The regional settings passed to the erase | 10 |
| **Total** | **about 540** |

S3 sits under the 700-line band by its nature. Folding it into S2 would come to about 1,250. It stands alone so that the data-loss change has a review of its own.

**Tests**
- Contract: `DataResetContract` runs on both the in-memory stores and GRDB:
  - Over a seeded history (programs, workouts with records, a custom exercise, changed settings, a live log), `eraseAll` leaves:
    - each table empty but `device` and the catalog;
    - the catalog equal to `ExerciseCatalog.seed()`;
    - `load()` equal to the settings passed;
    - `observeActive` emitting nil;
    - `observeRecent` emitting `[]`;
    - the same `deviceID`.
  - A second erase is harmless.
- GRDB only:
  - N20: a catalog with a duplicate id throws, and every row count is unchanged;
  - N21: the file-bytes scan;
  - an erase made while an observation is open: that observation emits the empty state.
- Store: `DeleteAllStoreTests` covers:
  - Cancel at each step;
  - a typed word that doesn't match, then one in other case or with spaces;
  - a live workout disabling the row, which comes back when the workout ends;
  - a double tap erasing once;
  - a failure keeping the sheet;
  - a cancellation;
  - the export directory removed.
- App: `DeleteAllGateTests` (LedgerAppKitTests) runs a real composition on a temporary database. Erasing through the bound key turns `RootGate.destination` to `.onboarding`, and `MainRoot` makes a new router.
- Hosted, through `TestSweep`: `DeleteAllSheetAccessibilityTests` (one text field, the button dimmed until the word matches) and `LayoutTests`.
- Snapshots: the sheet {empty, typed, failed} × {light, dark} at `.large`, plus typed at `.accessibility3`: 7 references.
- Performance: `DataResetPerformanceTests` (N24), gated.
- Nightly UI: `SettingsDeleteAll`: gear, Delete all data, Continue, type DELETE, then onboarding appears; finishing onboarding shows an empty Today.
- The DoD's VoiceOver check on the simulator.

**Needs:** S1; Q3. S2's export directory for N22 (if S3 ran first, N22 would be a no-op).

## 3. Open questions for Pete

Each will be built to its recommended default until Pete answers.

1. **When you switch between pounds and kilograms, what happens to the weights already in your program?**
   - A: Ledger rounds each one to the nearest weight you can load in the new unit: a 45 lb bar becomes 20 kg, 135 lb becomes 62.5 kg. Switching back can land one step away (62.5 kg comes back as 140 lb, not 135).
   - B: The weights stay exactly as they were, so a 45 lb bar shows as 20.41 kg and goes up 22.91, 25.41.
   - Either way, finished workouts never change, and are shown in the new unit (225 lb shows as 102.06 kg). A workout in progress keeps its unit until you finish it.
   - Recommended: A.
2. **Should a new install pick units and the first day of the week from the iPhone's region?**
   - A: Yes, both. In the US that is pounds and weeks starting Sunday; in the UK and Germany, kilograms and Monday. You can change either in Settings.
   - B: Only the first day of the week; units start as pounds everywhere.
   - C: Neither: pounds and Monday for everyone.
   - In all cases, changing the first day of the week later doesn't move your program's weeks. It changes the week strip on Today, the "this week" numbers and how History groups workouts.
   - Recommended: A. It also means a kilogram lifter's first program is built in kilograms.
3. **Delete all data: what goes, and how do you confirm?**
   - What goes: every workout and set, your records, your programs, your custom exercises, your settings (back to the starting values), and any exported files still on the phone.
   - What stays: the built-in exercise list (restored fresh), and workouts already saved to Apple Health, which you delete in the Health app. The confirmation says this.
   - Confirming:
     - A: a warning, then typing DELETE (as the brief says).
     - B: a warning only.
     - Recommended: A.
   - A workout in progress:
     - A: Delete is unavailable until you finish or discard it.
     - B: Delete also throws it away.
     - Recommended: A.
4. **The Apple Health row, before the Health connection is built (it comes with the watch work).**
   - A: It shows "Not connected" and does nothing when tapped, until then.
   - B: Tapping it opens the iPhone's Settings page for the app, which won't mention Health until the connection exists.
   - Recommended: A.
5. **The exported file.**
   - Name:
     - A: "workouts-2026-10-28.csv".
     - B: the app's name, then "export 2026-10-28.csv", once the name is settled.
     - Recommended: A. The file name never needs to change if the app is renamed.
   - Weights:
     - A: all in your current unit, with the unit in the column title.
     - B: each workout in the unit it was logged in.
     - Recommended: A.
   - Sets:
     - A: every set, with a done column.
     - B: done sets only.
     - Recommended: A.
6. **What can you change about your bar and plates?**
   - A: The bar's weight, with − and +; and which plate sizes you own, switched on or off from a list of common sizes (pounds: 55 down to 1.25; kilograms: 25 down to 0.5). "Reset to standard" puts back the usual set. Pounds and kilograms each keep their own setup.
   - B: The same, and you can also type in any plate size.
   - Recommended: A.
7. **Show the toggles whose features come later?** "Watch haptic at zero" acts once the watch app exists (M2), and "Plate math" once plates appear on the set row (M3).
   - A: Show them now. Both are built before anyone outside the team installs the app.
   - B: Hide each until its feature is built.
   - Recommended: A.

## 4. Architecture flags

- **A1. Delete all data is an in-place erase, not a new file (C22).** This needs an orchestrator ruling.
  - New Domain API: `public protocol DataReset: Sendable { func eraseAll(restoring settings: Settings) async throws }`.
    - GRDB `GRDBDataReset` over the stores' queue.
    - An in-memory fake that resets the six in-memory stores.
    - An `Unimplemented` stub.
    - A `dataReset` dependency key, bound in `AppComposition.bind(_:into:)`.
    - `DataResetContract` in LedgerTestSupport.
  - `architecture.md` §13's key list gains `dataReset`, and §7 gains one paragraph on the erase. No migration and no ADR are needed: ADR-002's tables are unchanged, and the hard delete is local only.
  - **F28 must extend it to iCloud** (K6).
  - Alternatives considered:
    - Deleting and reopening the file would need the dependencies to be bound again and `DatabaseLaunch` to be reopened. `prepareDependencies` binds once, and decision #29 bars deleting the file.
    - `PRAGMA secure_delete` instead of `VACUUM` costs on every write forever.
- **A2. Share sheet: SwiftUI `ShareLink` with a lazy `FileRepresentation`, not a `UIActivityViewController` wrapper.**
  - It needs no UIKit in FeatureSettings and is one tap.
  - The cost: a failure is shown by the system sheet, not by our copy.
  - The alternative: write the file first ("Preparing…"), then present a `LedgerDesign` `ActivitySheet` (UIKit, about 30 lines). It is the fallback if hosted tests can't reach the share link.
  - Orchestrator ruling needed.
- **A3. `SettingsRepository.seedIfAbsent(_:)`** (S1, Q2 = A). It is a new protocol requirement with contract clauses. The F05 protocol is extended, not replaced. `DatabaseLaunch` takes an optional regional `Settings`: the phone passes one, the watch passes nil.
- **A4. A unit switch is two writes (N11), the settings then the program, not one transaction.**
  - Acceptable because the second write is idempotent and offered again on failure.
  - The alternative: a Persistence use case that saves both in one write. That means a new protocol for one call.
  - Orchestrator ruling needed if Q1 = A.
- **A5. LedgerDesign additions:** `SegmentedChoice` (S1; two or more string options, a group with `.isSelected` per option, 44 pt each). Each gets a gallery entry and snapshots.
  - `FilterChipRow` was considered: it is a scrolling multi-chip row, wrong for an inline two-way choice.
  - The week-start picker is a SwiftUI `Picker(.menu)` with the system's menu.
  - The alert uses the system's destructive red. LedgerDesign has no red token, and none is added.
- **A6. Module setup** (S1): `Package.swift` resources and `snapshotTestTargets`, `coverage-thresholds.json` `required`, `PreviewScan.registeredModules`. These are the same lines F13 adds FeatureHistory to (K1).
- **A7. Test plans and project file:** none needed.
  - `FeatureSettingsTests` is already in both plans.
  - The new UI tests go in `Apps/LedgerUITests` (a synchronized folder). The PR plan selects `Smoke` only.
  - The `.performance` suites gate themselves by trait.
- **A8. Sanctioned edits of others' tests, listed in the notes:**
  - `AppTabsTests.swift:76-105` (S1, C29).
  - `FeatureSettingsTests.swift`, the placeholder, removed (S1).
  - `DatabaseLaunchTests` for the new seed call (S1).
  - `ExerciseRepositoryContract` only if the seed refactor moves a clause (S3).

### Coordination flags with F13 and later features

- **K1. Shared shell lines (F13):**
  - `AppTabs.swift`: F13 replaces line 39's History placeholder, and F14 replaces lines 61-62.
  - `Routes.swift`: F13 adds a workout destination.
  - `MainRoot.tabs`: each adds its `onRoute`.
  - `AppTabsTests`.
  - The module lists in A6.
  - All are one-line edits. Whichever PR merges second takes the other's lines, with no design change.
- **K2. Units in History (F13):** F14 holds that finished workouts are shown in the lifter's current unit (Q1), as the Library does. F13's edit-sets steppers must choose between the current unit and the stored `workout.units`. That choice is F13's; this plan names it only so the two features agree.
- **K3. Week start in History (F13):** criterion 7's History grouping must follow `settings.observe()` live, as Today does. F14's UI test covers Today only.
- **K4. Delete all and F13's screens:** after an erase, `observeRecent` emits `[]`, and `MainRoot` swaps to onboarding with a new router, so an open workout detail is dropped with its stack. F13 needs nothing beyond handling an empty list. F13's per-workout delete is a soft delete; F14's erase also removes soft-deleted rows.
- **K5. F16:** the Health row becomes `healthStore.authorization()` ("Connected", "Not connected", "Off in Settings"), with a tap to Settings. The erase never touches HealthKit.
- **K6. F28 (critical):** "Delete all data" must also delete the iCloud zone's records. Otherwise sync restores everything. Until F28 there is nothing to delete there. F29's review notes describe both.
- **K7. F19:** the watch's cached program and settings must be cleared when the phone erases (push an empty context). In M2 a workout started on the watch can race N19's check, so F19 should refuse an erase while the session reports any device's live workout.
- **K8. F25:** it reads `plateMathEnabled` and `plateInventory[units]`, as stored by S1–S2.

## 5. Risks

- **R1. Erase cost and safety.**
  - Deleting about 20,000 sets with their cascades takes about 50–150 ms.
  - Reinserting the 224-entry catalog takes about 10–30 ms.
  - `VACUUM` on a file of about 10 MB takes about 100–300 ms, off the main actor.
  - N24's 1 s budget covers all of it.
  - The transaction defers foreign keys only where the delete order can't satisfy them: children are deleted first.
- **R2. A live workout racing the erase** (watch start in M2): handled on the phone by N19, and flagged to F19 (K7).
- **R3. Leftover export files hold the lifter's log:** N16 and N22 remove them; iOS purges `tmp` too.
- **R4. Share sheet automation:** hosted tests can't drive `ShareLink`'s sheet, so the transfer's writer is tested directly. The nightly UI test asserts presentation only and is `.flakyProne` (the brief's risk). A2's fallback stands if even presentation can't be found.
- **R5. The typed field in hosted tests:** the hosted reader's text-field gap is the queued chore. F12 S3's name field shows the workaround (tree read from the sheet's parts). The word is a catalog string, so translators localize "DELETE" and the store compares with the localized word.
- **R6. Unit round-trip drift (Q1 = A):** documented in Q1 and pinned by `UnitSwitchTests`. A lifter who flips back and forth loses at most one step per flip on each off-grid weight.
- **R7. Save races (N1):** rapid taps fold into serial saves. The echo of an older value from `observe()` must not overwrite the control: the store holds the value it is saving as pending until the observation reaches it. This is S1's most test-heavy part.
- **R8. Stale launch copy:** `DatabaseLaunch.settings` and `AppComposition.settings` keep the launch's value. No screen reads them at runtime (grep), so an erase or a change leaves them stale and harmless. The rule stays: features read `settingsRepository`.
- **R9. CI time.** F12's measured PR-sweep additions were 6.1, 4.0 and 1.1 s on a developer Mac, against estimates of 30–40 s.
  - Estimates for F14, on the Mac:
    - S1: 6–9 s (three hosted suites over a long page and 8 references).
    - S2: 3–5 s (the plate sheet, 6 references; CSV tests on the simulator's Domain suite, under 1 s).
    - S3: 3–5 s (the GRDB erase contract on a temporary file at about 1–2 s, and the sheet).
  - At the runner's 2–3×, that is roughly 25–55 s for all three, against a test step of 1,900–2,400 s under the 4,500 s deadline (`docs/ci-cd.md:132-136`). It fits.
  - Every new hosted sweep goes through `TestSweep.sizes(…)` or `TestSweep.subset`, and no sweep reads a swept list's count. Each slice measures its seconds and writes them in the notes.
- **R10. Slice size:** S1 is near the top of the band; store slices have overrun before (F12 S1 +143). Stop at about 950. The split point is S1a, the domain, persistence, launch, copy, presentation and store (about 460, nothing on screen), then S1b, the views, the LedgerDesign control, the previews and the app (about 425).
- **R11. CSV in spreadsheets:** N14's guard changes how a name that starts with "-" appears ("'-Band Pull-Apart"). This is the accepted cost of OWASP's rule. The BOM (N15) can show as a stray character in some plain-text tools; spreadsheets are the audience.

### Critical Files for Implementation
- `LedgerKit/Sources/LedgerDomain/Model/Settings.swift` and `LedgerKit/Sources/LedgerPersistence/Repositories/GRDBSettingsRepository.swift`
- `LedgerKit/Sources/LedgerPersistence/DatabaseLaunch.swift` and `LedgerKit/Sources/LedgerAppKit/AppComposition.swift`
- `LedgerKit/Sources/LedgerPersistence/Migrations.swift` (the tables the erase empties) and `Repositories/GRDBExerciseRepository.swift` (the seed)
- `LedgerKit/Sources/LedgerAppKit/AppTabs.swift`, `MainRoot.swift`, `RootGate.swift`
- `LedgerKit/Sources/FeatureLibrary/LibraryStore+Sources.swift` (the store pattern to mirror)
