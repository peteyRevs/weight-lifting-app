# F28 — iCloud sync (private database)

| | |
|---|---|
| Milestone | M4 |
| Status | proposed |
| Depends on | F27 (ADR-007) |
| Branch | `feat/F28-icloud-sync` |
| Design refs | Settings "iCloud" row (new; v2 hairline row style) |
| Spec refs | `docs/architecture.md` §7 (synced tables), §10, §16; ADR-002; R1 §3.4 (App Review 5.1.3(ii)) |

## Goal
A user's programs, workouts, custom exercises and settings follow them across iPhones and restore on a new phone, using the approach chosen in ADR-007, with no health data ever leaving the device and the watch untouched (it syncs through the phone).

## Scope
**In:** sync engine integration, record zone + table→record mapping for `exercise` (custom only), `program`, `program_week`, `day_template`, `slot`, `slot_miss`, `workout`, `workout_exercise`, `logged_set`, `settings`; soft-delete propagation; first-launch merge; account-change handling (sign-out clears cloud-derived data but keeps local); sync status row in Settings ("iCloud · Up to date / Syncing / Off / Error"); conflict tests; exclusions enforced by a test.
**Out:** sharing between users, watch CloudKit, health data (never).

## Touches
- `LedgerKit/Sources/LedgerCloud/**` (new target: depends on LedgerPersistence + the chosen library), `LedgerKit/Package.swift`
- `LedgerKit/Sources/LedgerDependencies/Keys/CloudSync.swift`, `LedgerKit/Sources/FeatureSettings/CloudStatusRow.swift`
- `Apps/Ledger/Ledger.entitlements` (iCloud container `iCloud.app.ledger`), `Ledger.xcodeproj` capability (human)
- Tests: `LedgerCloudTests` (fake CloudKit), device checklist in F20 addendum

## Domain changes
`SyncState` enum published to Settings; `Settings.iCloudEnabled: Bool` (default on when an account exists).

## Acceptance criteria
1. Given device A creates a program and finishes a workout, when device B (same Apple ID, fresh install) launches, then within 60 s B shows the program on Today and the workout in History with identical ids.
2. Given `workout_health`, `workout_event`, `device` tables, then a test asserts no record type maps to them and a CloudKit dashboard check (manual, F20) shows no such record types.
3. Given offline edits on both devices to different slots, then both converge with no duplicates; same-field conflicts resolve LWW by `updated_at`.
4. Given a workout deleted on A, then it disappears on B and its cascaded rows are removed.
5. Given iCloud signed out, then the app keeps working locally and the Settings row shows "Off"; signing back in resumes without duplicating rows.
6. Given a schema migration v002 (added in this brief for a new column), then sync tolerates old clients (additive only) — test with a record lacking the column.
7. Given the sync engine throws (quota, network), then the UI shows a non-blocking error state and retries with backoff; no data loss locally.

## Test plan
- Unit/integration (`LedgerCloudTests`): mapping round-trips per table, exclusion assertion, conflict resolution cases, first-launch merge with pre-existing local rows, sign-out/in transitions — all against the fake CloudKit from ADR-007 (or a recorded fixture layer if hand-rolled).
- Device (two iPhones or iPhone + simulator on one account): criteria 1, 2, 4, 5 recorded in `tasks/features/F28-icloud-sync/results-YYYY-MM-DD.md`.

## Non-functional
- Sync never blocks the main actor; initial import of 5,000 sets < 30 s.
- Privacy: nutrition label updated (F29) — "Fitness data linked to identity? No; synced via iCloud private database".

## Risks / unknowns
- CloudKit rate limits during initial import — batch by 400 records.

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F28-icloud-sync/{implementation-notes,test-findings,review}.md`
