# F27 — CloudKit sync spike: SQLiteData vs hand-rolled CKSyncEngine

| | |
|---|---|
| Milestone | M4 |
| Status | proposed |
| Depends on | F05 |
| Branch | `spike/F27-cloudkit` (throwaway; never merged) |
| Design refs | none |
| Spec refs | `docs/architecture.md` §10; ADR-002; `docs/research/R2-data-architecture.md` §3 |

## Goal
Decide, with evidence, how Ledger syncs its GRDB store to the user's iCloud private database: Point-Free **SQLiteData 1.12.x** (GRDB-based CKSyncEngine wrapper, field-wise last-write-wins) versus a hand-rolled `SyncActor` following Apple's CKSyncEngine sample. Output is **ADR-007** with a recommendation and a prototype that syncs `program`/`slot` and `workout`/`logged_set` between two simulators (or simulator + device) on one iCloud account.

## Scope
**In:** both prototypes against the real v001 schema, timeboxed to 3 working days total; a comparison table; ADR-007 draft.
**Out:** production code, UI, watch.

## Touches
- `spike/` branch only. Deliverables merged to `main` via a docs-only PR: `docs/adr/ADR-007-icloud-sync-engine.md`, `docs/research/R4-cloudkit-spike.md`.

## Evaluation criteria (score each 1–5 with notes)
1. Schema fit: UUID text PKs, soft deletes, FK parent-before-child ordering, JSON columns, no UNIQUE.
2. Exclusions: can `workout_health`, `workout_event`, `device` be kept local trivially?
3. Conflict behaviour: field-wise LWW per row; deletes vs edits; `slot_miss` insert/delete churn.
4. First-launch merge on a second device with existing local data (no duplicates, ids preserved).
5. Testability: can sync be driven in unit tests with a fake CloudKit (SQLiteData ships one?) or must every test hit CloudKit?
6. Watch: confirm the watch stays excluded (syncs via phone, ADR-005) and nothing in the library forces CloudKit on watchOS.
7. Dependency risk: release cadence, Swift 6.3/Xcode 26.6 build, license, bus factor.
8. Effort to production for the winner (days) and the migration path if we swap later.

## Acceptance criteria
1. Given both prototypes, then each syncs a program edit and a finished workout across two devices within 30 s on Wi-Fi.
2. Given a concurrent edit to the same slot's `reps` on both devices while offline, then after sync both show the later `updated_at` value (LWW) and no crash.
3. Given ADR-007, then it contains the scored table, the recommendation, the rejected option's blocking issues, and the F28 plan deltas.

## Test plan
- Spike scripts and manual checklists recorded in `R4-cloudkit-spike.md` with timings.

## Definition of Done
- [ ] ADR-007 merged; `tasks/todo.md` F28 updated with the chosen approach.
- [ ] Spike branch deleted after the ADR merges.

---
_Filled in by agents during delivery:_ `F27-cloudkit-spike/{implementation-notes,review}.md`
