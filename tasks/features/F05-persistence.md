# F05 — Persistence: GRDB schema, repositories, stats, event store

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | F02, F04 |
| Branch | `feat/F05-persistence` |
| Design refs | none |
| Spec refs | ADR-002; `docs/architecture.md` §7; `docs/product-spec.md` §7.6–§7.7; `docs/research/R2-data-architecture.md` §1 |

## Goal
A CloudKit-shaped SQLite schema on both platforms, GRDB implementations of every Domain protocol, the stats SQL behind "what did I lift last time", and an event store for live workouts — all tested on in-memory databases with performance budgets.

## User stories
- As a lifter, my history is on my device forever and every screen loads instantly.
- As an engineer, I can seed 20 000 sets and every stats query returns in under 50 ms.

## Scope
**In:** schema v001, migrator, repositories, `StatsQueries`, `WorkoutEventStore`, materialization transaction, observation bridge, database factories, performance tests.
**Out:** CloudKit sync (F27/F28), HealthKit data capture (F16; this brief only creates the `workout_health` table), UI.

## Touches
- `LedgerKit/Sources/LedgerPersistence/{Database,Migrations,Records/*,Repositories/*,Stats/StatsQueries,Events/GRDBWorkoutEventStore,Observation/ValueObservation+AsyncStream}.swift`
- `LedgerKit/Tests/LedgerPersistenceTests/**`
- `LedgerKit/Sources/LedgerTestSupport/Persistence/{TestDatabase,Seeders}.swift`

## Domain changes
No Domain type changes. Schema (v001, all `TEXT` ids are UUID strings; `_at` columns are ISO-8601 UTC `TEXT`; `deleted_at` nullable):
> **ADR-007:** weights are exact (`Weight.grams: Decimal`) and `Program.startDate` is a `CivilDate`. Store weight and volume columns as integer counts of 10⁻⁷ g (exact for every hundredth of a pound), store `start_date` as `"YYYY-MM-DD"`, and choose an overflow-safe volume aggregate. See `docs/adr/ADR-007-exact-weights-and-civil-program-start.md`; column naming below is F05's to revise.

```sql
CREATE TABLE exercise (id TEXT PRIMARY KEY, name TEXT NOT NULL, short_name TEXT NOT NULL, equipment TEXT NOT NULL,
  primary_muscle TEXT NOT NULL, secondary_muscles TEXT NOT NULL /* JSON array */, pattern TEXT NOT NULL,
  start_load_lb_grams INTEGER NOT NULL, start_load_kg_grams INTEGER NOT NULL, is_custom INTEGER NOT NULL DEFAULT 0,
  curated_alternatives TEXT NOT NULL /* JSON array of ids */, catalog_version INTEGER,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE program (id TEXT PRIMARY KEY, name TEXT NOT NULL, start_date TEXT NOT NULL, goal TEXT, days_per_week INTEGER,
  is_active INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE program_week (id TEXT PRIMARY KEY, program_id TEXT NOT NULL REFERENCES program(id) ON DELETE CASCADE,
  week_index INTEGER NOT NULL, is_deload INTEGER NOT NULL DEFAULT 0,
  mon TEXT, tue TEXT, wed TEXT, thu TEXT, fri TEXT, sat TEXT, sun TEXT /* day_template ids, nullable */,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE day_template (id TEXT PRIMARY KEY, program_id TEXT NOT NULL REFERENCES program(id) ON DELETE CASCADE,
  position INTEGER NOT NULL, name TEXT NOT NULL, tag TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE slot (id TEXT PRIMARY KEY, day_template_id TEXT NOT NULL REFERENCES day_template(id) ON DELETE CASCADE,
  position INTEGER NOT NULL, exercise_id TEXT NOT NULL REFERENCES exercise(id), sets INTEGER NOT NULL, reps INTEGER NOT NULL,
  reps_hi INTEGER NOT NULL, rpe_x2 INTEGER NOT NULL /* rpe*2 */, rest_seconds INTEGER NOT NULL, progression TEXT NOT NULL,
  start_load_grams INTEGER, step_grams INTEGER, is_superset_with_previous INTEGER NOT NULL DEFAULT 0, drop_sets INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE slot_miss (id TEXT PRIMARY KEY, slot_id TEXT NOT NULL REFERENCES slot(id) ON DELETE CASCADE, week_index INTEGER NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE workout (id TEXT PRIMARY KEY, program_id TEXT, week_index INTEGER, day_template_id TEXT, name TEXT NOT NULL, tag TEXT NOT NULL,
  is_deload INTEGER NOT NULL DEFAULT 0, started_at TEXT NOT NULL, ended_at TEXT, phase TEXT NOT NULL /* finished|discarded */,
  elapsed_seconds INTEGER NOT NULL, volume_gram_reps INTEGER NOT NULL, done_sets INTEGER NOT NULL, total_sets INTEGER NOT NULL,
  pr_count INTEGER NOT NULL DEFAULT 0, origin_device TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE workout_exercise (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE, position INTEGER NOT NULL,
  exercise_id TEXT NOT NULL, original_exercise_id TEXT NOT NULL, slot_id TEXT, name TEXT NOT NULL, equipment TEXT NOT NULL,
  step_grams INTEGER NOT NULL, rest_seconds INTEGER NOT NULL, rpe_x2 INTEGER NOT NULL, is_superset_with_previous INTEGER NOT NULL DEFAULT 0,
  target_sets INTEGER NOT NULL, target_reps INTEGER NOT NULL, target_load_grams INTEGER NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE logged_set (id TEXT PRIMARY KEY, workout_exercise_id TEXT NOT NULL REFERENCES workout_exercise(id) ON DELETE CASCADE, position INTEGER NOT NULL,
  weight_grams INTEGER NOT NULL, reps INTEGER NOT NULL, kind TEXT NOT NULL, done_at TEXT, e1rm_grams INTEGER /* precomputed Brzycki, NULL if reps > 12 or not done */,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);
CREATE TABLE workout_health (workout_id TEXT PRIMARY KEY REFERENCES workout(id) ON DELETE CASCADE, avg_heart_rate INTEGER, max_heart_rate INTEGER,
  active_energy_kcal REAL, hk_workout_uuid TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);           -- never synced
CREATE TABLE workout_event (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, device_id TEXT NOT NULL, seq INTEGER NOT NULL, wall_clock TEXT NOT NULL,
  payload BLOB NOT NULL /* JSON EventEnvelope */, created_at TEXT NOT NULL);                                        -- never synced
CREATE TABLE settings (id TEXT PRIMARY KEY /* always 'singleton' */, payload TEXT NOT NULL /* JSON Settings */, updated_at TEXT NOT NULL);
CREATE TABLE device (id TEXT PRIMARY KEY, kind TEXT NOT NULL /* phone|watch */, name TEXT NOT NULL, created_at TEXT NOT NULL);   -- never synced
CREATE INDEX idx_logged_set_wex ON logged_set(workout_exercise_id);
CREATE INDEX idx_wex_exercise_workout ON workout_exercise(exercise_id, workout_id);
CREATE INDEX idx_workout_ended ON workout(ended_at);
CREATE INDEX idx_event_workout_device_seq ON workout_event(workout_id, device_id, seq);
CREATE UNIQUE INDEX uidx_event_key ON workout_event(workout_id, device_id, seq);   -- allowed: local-only table
```
No `UNIQUE` on synced tables (ADR-002). `PRAGMA foreign_keys = ON`, `journal_mode = WAL`.

Public API of the module:
```swift
public enum LedgerDatabase {
    public static func open(at url: URL, protection: FileProtectionType = .completeUntilFirstUserAuthentication) throws -> DatabaseQueue   // migrates
    public static func inMemory() throws -> DatabaseQueue                                                                                 // migrates
    public static var migrator: DatabaseMigrator
}
public struct GRDBExerciseRepository: ExerciseRepository { public init(_ db: DatabaseQueue) }   // likewise GRDBProgramRepository, GRDBWorkoutRepository, GRDBSettingsRepository, GRDBStatsQueries, GRDBWorkoutEventStore
```

## Acceptance criteria
1. Given an empty database, when `LedgerDatabase.inMemory()` runs, then all tables and indexes exist and `PRAGMA foreign_keys` is on (`test_v001SchemaMatchesExpectedDDL` compares `sqlite_master` against a committed fixture).
2. Given a program with 8 weeks × 4 days saved via `GRDBProgramRepository.save`, when loaded, then it round-trips `Equatable`-equal including `misses`.
3. Given a finished `WorkoutState` with 5 exercises, when `materialize` runs, then `workout`, `workout_exercise`, `logged_set` (with `e1rm_grams` computed), PRs and `slot_miss` rows are written in **one** transaction; a failure injected mid-way leaves no rows.
4. Given 34 sessions of bench, when `lastPerformance(exerciseID:)` runs, then it returns the most recent finished workout's working sets as (date, sets, reps, load) per spec rule 14.
5. Given sets across 10 ISO weeks, when `e1RMByWeek(lastWeeks: 8)` runs, then each week's value is the max `e1rm_grams` of done sets in that week and weeks with no sets are absent.
6. Given workouts in two consecutive weeks, when `weeklyVolume(in:)` runs for each, then values equal Σ weight×reps of done sets (drop/added included), and the Today delta can be computed from the two.
7. Given a live workout's envelopes appended twice (duplicate keys), when read back, then each key appears once and `highestSeq` is correct per device.
8. Given `compact(workout:)` after materialization, then `workout_event` rows for that workout are gone and `liveWorkoutIDs()` excludes it.
9. Given 20 000 logged sets across 400 workouts, when each `StatsQueries` method runs, then p95 < 50 ms on the iOS simulator (`StatsQueriesPerformanceTests`, `.slow`, nightly).
10. Given `observeRecent(limit: 10)`, when a workout is materialized, then the `AsyncStream` emits the new list within one event-loop turn.
11. Given the seed catalog applied twice with the same version, then the `exercise` row count is unchanged and custom rows survive; with a higher version, new entries are added and existing names are not duplicated.
12. Given a future migration `v002` added in a test, when migrating a database created at v001 with data, then data survives (scaffold `MigrationCompatibilityTests` iterating over committed `fixtures/db-v001.sqlite`).

## Test plan
- Integration (LedgerPersistenceTests): `SchemaTests`, `ExerciseRepositoryTests` (search by prefix/equipment/muscle, custom save, seed idempotence), `ProgramRepositoryTests`, `WorkoutRepositoryTests` (materialize atomicity, updateSets re-materializes `e1rm_grams`, delete cascades), `StatsQueriesTests` (criteria 4–6, PR history, sessions this week, recentlyLogged order), `WorkoutEventStoreTests` (7, 8), `ObservationTests` (10), `MigrationCompatibilityTests` (12), `StatsQueriesPerformanceTests` (9, `.slow`).
- Seeders in LedgerTestSupport: `Seeders.history(exercises:workouts:setsPerWorkout:rng:)`.
- Snapshot / UI: none.

## Non-functional
- All repository types are `struct` + `Sendable`; the `DatabaseQueue` is the actor boundary (GRDB serializes).
- watchOS: write transactions ≤ 10 ms typical; never hold a transaction across an `await`.
- File protection `completeUntilFirstUserAuthentication`; database in Application Support/`ledger.sqlite`.

## Risks / unknowns
- GRDB `DatabaseMigrator` on watchOS first launch time — measure; seed in a background task after first frame if > 300 ms.
- ISO week vs user `weekStart` — stats use `WeekCalendar` bounds passed in, not SQLite's `strftime('%W')`.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Coverage ≥ 90 %.
- [ ] `fixtures/db-v001.sqlite` committed for future migration tests.

---
_Filled in by agents during delivery:_
- `F05-persistence/implementation-notes.md`
- `F05-persistence/test-findings.md`
- `F05-persistence/review.md`
