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
1. Given units switched lb → kg, when Today, Active workout, Library, History render, then weights show kg and steps are 2.5/1.25 (verified through `Weight.formatted(in:)` and `Equipment.defaultStep(in:)` bindings; a UI test flips units and asserts a known set row).
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
