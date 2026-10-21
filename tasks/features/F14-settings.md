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
