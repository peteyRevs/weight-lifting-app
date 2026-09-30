# F03 — Exercise catalog seed

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | F02 |
| Branch | `feat/F03-exercise-catalog` |
| Design refs | `design/prototype/Ledger.dc.html` → `Library`, `Day editor` (exercise picker sheet) |
| Spec refs | `docs/product-spec.md` §6.2 (22 prototype entries with W0 loads), §6.3 (alternatives), §3.8; `docs/product-decisions.md` #12 |

## Goal
Ship a curated, validated catalog of ~200 exercises so the Library's "Search 214 exercises" promise is real, every program template resolves, and swap suggestions have real alternatives. The catalog is data in `LedgerDomain`, loaded by `ExerciseCatalog.seed()`, seeded into the database on first launch and upgraded additively by version.

## User stories
- As a lifter, I can find any common barbell, dumbbell, cable, machine, bodyweight, kettlebell or band exercise by name, equipment or muscle.
- As a lifter, when I swap an exercise I am offered sensible alternatives with the same movement pattern.

## Scope
**In:** `exercises.json`, `ExerciseCatalog` loader + version, validation tests, per-equipment default steps and start loads in lb and kg, curated alternatives, short names.
**Out:** custom exercise UI (F12), seeding into GRDB (F05 provides `seedIfNeeded`; F07 calls it), images/videos, muscle diagrams.

## Touches
- `LedgerKit/Sources/LedgerDomain/Resources/exercises.json`
- `LedgerKit/Sources/LedgerDomain/Catalog/ExerciseCatalog.swift`
- `LedgerKit/Sources/LedgerDomain/Catalog/CatalogEntry.swift` (decoding DTO → `Exercise`)
- `LedgerKit/Tests/LedgerDomainTests/Catalog/ExerciseCatalogTests.swift`
- `LedgerKit/Package.swift` (add `resources: [.process("Resources")]` to `LedgerDomain` if F00 did not)

## Domain changes
```swift
public enum ExerciseCatalog {
    public static let version: Int            // bump on every content change; additive upgrades only
    public static func seed() throws -> [Exercise]
}
```
No changes to `Exercise` (F02). JSON schema (one object per exercise):
```json
{ "id": "1F1B0C2A-…", "name": "Barbell Bench Press", "shortName": "Bench", "equipment": "barbell",
  "primaryMuscle": "chest", "secondaryMuscles": ["triceps", "shoulders"], "pattern": "horizontalPush",
  "startLoad": { "lb": 95, "kg": 40 }, "alternatives": ["<id>", "<id>"], "aliases": ["Bench Press"] }
```
Rules: `id` is a stable UUID generated once and never regenerated (agents must not re-roll ids when editing); `startLoad` must be a multiple of the equipment's default step in that unit (`Equipment.defaultStep(in:)` from F02: lb barbell and kettlebell 5 / others 2.5; kg barbell 2.5 / kettlebell 2 / others 1.25 — kettlebell amended by decision #22, Pete 2026-09-30) and follow the conservative start-load policy (decision #21; its table is in `ExerciseCatalog.swift`, and its kg values are chosen in kg, not converted); bodyweight exercises use `startLoad` 0 with `"loadKind": "bodyweight"`; `alternatives` ≥ 2, same `pattern`, never self.

## Acceptance criteria
1. Given the bundled JSON, when `ExerciseCatalog.seed()` runs, then it returns ≥ 200 exercises and throws on any malformed entry (no silent skipping).
2. Given the 22 prototype entries in spec §6.2, when looked up by name, then each exists with the policy's conservative loads (Pete, 2026-09-30; decision #21). _Amended: it first required the prototype's `W0` in lb, with kg converted from it._
3. Given any exercise, when its alternatives are resolved, then every id exists, has the same `pattern`, and is not the exercise itself; at least two exist.
4. Given all names, when compared case-insensitively (including `aliases`), then there are no duplicates.
5. Given each `MuscleGroup`, when counting exercises whose `primaryMuscle` matches, then the count is ≥ 10 (core ≥ 8).
6. Given each `Equipment`, when counting, then barbell ≥ 30, dumbbell ≥ 40, cable ≥ 25, machine ≥ 25, bodyweight ≥ 25, kettlebell ≥ 10, band ≥ 8.
7. Given the `version` constant, when the JSON changes in a PR, then a test fails unless `version` was incremented (test compares a SHA-256 of the file against `catalog.version.sha` committed next to it). _Extended 2026-09-30: `scripts/check-catalog-version.sh` (check.sh step 2) also compares against the merge base with main, so the version must rise above main's and the SHA history's merged lines never change._
8. Given the seed is applied twice (F05 `seedIfNeeded`), then no duplicate rows are created and custom exercises are untouched (contract test lives in F05; this brief provides the fixture).

## Test plan
- Unit (LedgerDomainTests): `test_seedDecodesAllEntries`, `test_prototypeEntriesUsePolicyLoads` (parameterized over the 22 names → policy loads in lb and kg; was `test_prototypeEntriesMatchSpecW0`), `test_alternativesResolveSamePattern`, `test_noDuplicateNamesOrAliases`, `test_muscleCoverage`, `test_equipmentCoverage`, `test_startLoadsAreMultiplesOfStep`, `test_idsAreStableUUIDs` (regex + uniqueness), `test_versionShaMatchesFile`.
- Snapshot: none.
- UI: none (F12 covers search over the seeded table).

## Non-functional
- Decode time < 20 ms on iPhone; JSON ≤ 200 KB.
- Content is original work by the implementing agent (names, taxonomy, loads); do not copy from copyrighted exercise databases.
- Start loads are conservative, beginner-safe defaults from one policy by equipment and movement class, for all entries including the 22 prototype ones (Pete, 2026-09-30; decision #21): e.g. barbell compounds at the empty bar (45 lb / 20 kg), deadlift 95 lb / 40 kg, dumbbells 15 / 10 / 5 lb per hand, kettlebells 12 or 8 kg.

## Risks / unknowns
- Taxonomy disputes (e.g. RDL pattern = hinge; front squat = squat) — document the rule per pattern in `ExerciseCatalog.swift` doc comments.
- Agents regenerating UUIDs on edit — mitigated by criterion 7 and a `CONTRIBUTING` note at the top of the JSON.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `docs/product-spec.md` §6.2 names all resolve (test).
- [ ] `implementation-notes.md` lists the pattern-assignment rules and any exercise deliberately excluded.

---
_Filled in by agents during delivery:_
- `F03-exercise-catalog/implementation-notes.md`
- `F03-exercise-catalog/test-findings.md`
- `F03-exercise-catalog/review.md`
