# F03 — implementation notes

Branch `feat/F03-exercise-catalog` (from `main` at `1d80613`). Implementer pass: 2026-09-30.

## What was built

- **`LedgerDomain/Resources/exercises.json`**: the catalog, 214 exercises. Before this pass it was
  the placeholder `{"version":1,"exercises":[]}`. A `contributing` array at the top of the file tells
  editors never to regenerate an id, to bump the version and to append the SHA. The decoder
  ignores that array.
- **`LedgerDomain/Resources/catalog.version.sha`**: the append-only history of
  `<version> <sha256 of exercises.json>` lines (criterion 7). It holds one line so far: version 1.
- **`LedgerDomain/Catalog/ExerciseCatalog.swift`**:
  - `version` (1) and `seed()`, which decodes and checks the bundled file and throws on the first
    malformed entry;
  - internal `exercises(from:)`, `entries(from:)` and `resource(_:withExtension:)`, which the tests
    use;
  - the pattern-assignment rules and start-load conventions, as doc comments.
- **`LedgerDomain/Catalog/CatalogEntry.swift`**: the decoding DTO. `exercise()` runs the checks
  that need only one entry and maps the entry to an `Exercise`.
- **`LedgerDomain/Errors.swift`**: `CatalogError`, with one case per way a document can be
  malformed.
- **`LedgerTestSupport/Catalog/CatalogSeedFixture.swift`**: criterion 8's fixture for F05.
- **`LedgerKit/Package.swift`**: the new `.sha` file is declared as a copied resource.
- **Tests** in `LedgerDomainTests/Catalog/`: `ExerciseCatalogTests`, `CatalogEntryTests`,
  `CatalogSeedFixtureTests` and `ExerciseCatalogPerformanceTests` (nightly lane).

`Exercise` (F02) is unchanged, as the brief requires. The project file was not touched.

## Ids must never be regenerated

Every id is a random UUIDv4, generated once for this pass. Ids are stored in lifters' databases,
referenced by programs, workouts and other entries' `alternatives`, and compared by F05's seed. An
edit must never change, reuse or re-roll one. A new exercise gets a new `uuidgen` id.

Three things guard this:

- the note at the top of the JSON;
- the pinned ids of the 22 prototype entries in `ExerciseCatalogTests.prototypeEntries_matchSpecW0`;
- the SHA test (criterion 7), which fails on any change to the file.

The generator used for this pass stays in the session scratchpad. It is deliberately not
committed: a script that rebuilds the file invites re-rolled ids. From now on the JSON is edited
by hand.

## Decisions and deviations

1. **Prototype W0 versus beginner loads (a conflict inside the brief).** Criterion 2 requires the 22
   spec §6.2 entries to carry the prototype's `W0` exactly: bench 180, squat 250, deadlift 315,
   OHP 115. The non-functional section asks for conservative beginner loads: bench 95, squat 135,
   deadlift 135, OHP 65. Criterion 2 wins for those 22. Every other entry uses a conservative
   beginner load, so Barbell Bench Press starts at 180 lb while Incline Bench Press starts at 95 lb.
   **For Pete:** lowering the 22 is a one-line-each JSON change plus a brief amendment. Criterion 2
   pins them today.
2. **One kg rule for the whole catalog.** Criterion 2's rule applies to every entry: kg is the lb
   value converted and rounded to the kg step, with ties away from zero, as in `Weight.rounded`. A
   test enforces it for all 214 entries. **For Pete:** F02's 1.25 kg step for dumbbells and
   kettlebells cannot express real kettlebells. A 35 lb bell becomes 16.25 kg, and 16, 24 or 32 kg
   cannot be written at all. Dumbbells land on sizes such as 13.75 kg. The step is F02's
   `Equipment.defaultStep`, which is out of F03's scope. A per-equipment kg step, such as 4 kg for
   kettlebells, would need an F02 change and a catalog version bump.
3. **Load conventions** (also in the `ExerciseCatalog` doc comment):
   - dumbbell and kettlebell loads are per implement, as in the prototype ("2 × 70 lb");
   - landmine lifts (T-Bar Row, Meadows Row, Landmine Press, Landmine Rotation) count the plates
     only;
   - band loads are the band's rated resistance;
   - carries count lengths as reps.
4. **`loadKind`.** It has one value, `"bodyweight"`, and appears exactly when both start loads
   are 0. It is allowed only on bodyweight equipment. The loader enforces all of this:
   - 36 pure-bodyweight entries carry `loadKind`;
   - the 3 weighted ones (Weighted Dip +45 lb and Weighted Pull-Up +35 lb from the spec, and
     Weighted Chin-Up +25 lb) give the added load and omit it.

   Because the rule works both ways, a misspelt `loadKind` still fails. `Exercise` has no field
   for `loadKind`, so the marker ends at validation: bodyweight equipment with a zero start
   carries the same meaning.
5. **Aliases stay in the DTO.** `Exercise` has no aliases, and the brief forbids changing it. So
   aliases (312 of them) do one job: they block a second entry under another name. Criterion 4
   compares them ignoring case. If F12 wants alias search, `CatalogEntry.aliases` is there, and
   `CatalogEntry` could become public.
6. **Names.** The catalog uses standard gym names and spells out "Dumbbell". The two exceptions
   are spec names that criterion 2 fixes: "Incline DB Press" and "Incline DB Curl". Their
   spelled-out forms are aliases. The prototype's §6.3 swap-sheet names all resolve:
   - as names: Dumbbell Bench Press, Machine Incline Press, Seated Cable Row, Neutral-Grip
     Pulldown, Straight-Arm Pulldown, Machine Lateral Raise;
   - as aliases: Smith Machine Press, Incline Barbell Press, Single-Arm DB Row, DB Lateral Raise,
     Upright Row;
   - except Assisted Pull-Up, which is excluded (see below).
7. **Short names.** They are upper case like the prototype's `sh`, at most 14 characters, and
   unique across the catalog. A test enforces all three. The longest prototype `sh` is 9
   characters; the watch's exercise name is 20 pt text in 196 pt. All 22 prototype `sh` values
   are kept except one. **Deviation:** Incline DB Curl is `INC DB CURL`, not the prototype's
   `DB CURL`, so Dumbbell Curl can be `DB CURL` and an arm day never shows two identical labels.
   Prefixes follow the spec's abbreviations: DB, CB, MC, BW, plus KB and BAND.
8. **Alternatives follow criterion 3 over the prototype.** The §6.3 pairs are kept wherever they
   share a pattern. Three are dropped:
   - Low-to-High Cable Fly for Incline DB Press, because a fly is isolation and a press is not;
   - Straight-Arm Pulldown for Lat Pulldown, also isolation;
   - Assisted Pull-Up, which is excluded.

   Every entry has 2–5 alternatives, 615 in all. Most share the primary muscle. The exceptions
   are same-family swaps across muscles: deadlift ↔ trap-bar/sumo, dip ↔ machine dip, and
   farmer's ↔ suitcase carry. Beyond the brief, a test requires every **isolation** alternative
   to train the same primary muscle, because `isolation` spans curls to calf raises.
9. **Primary-muscle calls:**
   - Deadlift is hamstrings, per the spec's Library row (§3.8, "Barbell · hamstrings");
   - Sumo Deadlift, Trap Bar Deadlift and the power cleans are glutes;
   - traps (shrugs) count as back, because there is no traps group;
   - rear delts (face pulls, reverse flies, pull-aparts) count as shoulders;
   - Dumbbell Pullover is back, since it trains the lats and swaps with the pulldown and machine
     pullover.
10. **Where the checks run.** `seed()` runs every structural rule: decoding, text, muscles, steps,
    `loadKind`, alternatives, unique ids and names. So a bad edit fails at launch as well as in CI.
    The criterion tests then check the bundled data independently rather than trusting the
    loader. Every key is required except `loadKind`, so a misspelt key is never silently ignored.
    `JSONDecoder` reads `Decimal` from the JSON digits exactly: verified on Xcode 27 (3.133 stays
    3.133, while `Decimal(3.133 as Double)` does not). JSON numbers therefore keep ADR-007's
    exactness.
11. **Version history format and its limit.** `catalog.version.sha` is append-only. The test
    requires:
    - versions 1…n in order;
    - a distinct SHA per version;
    - the last version equal to `ExerciseCatalog.version`;
    - the last SHA equal to the file's.

    On a mismatch the failure message gives the exact line to append. **Limit:** someone who
    changes the JSON and overwrites the last line's SHA in place, without bumping, passes. A unit
    test cannot see git history. The diff shows the edit to review, and a CI check against the
    merge base would close the gap. That check is a suggested follow-up, not in F03.
12. **Version 1.** The JSON's own `"version"` key is gone, so the Swift constant is the single
    source of truth. F05 can compare it without decoding. The placeholder on `main` was never
    seeded, so content starts at version 1.
13. **The `.sha` file ships in the bundle** (about 300 bytes), so the test reads it the same way
    `seed()` reads the JSON. The alternative was a `#filePath` read of the source tree, which
    would be a second deliberate file-system read in the domain tests. The catalog tests read
    only the module's own resource bundle, as the product does.
14. **Criterion 8 ships as a fixture only.** `CatalogSeedFixture` provides:
    - `base()`: the bundled catalog at its version;
    - `upgrade()`: base plus `added` and `clash`, one version higher;
    - `custom`: the lifter's "Zercher Squat";
    - `clash`: "ZERCHER SQUAT", a catalog entry that matches `custom` only when case is ignored.

    Its doc comment spells out the scenario F05 criterion 11 asks for. `CatalogSeedFixtureTests`
    proves the fixture sets up those cases; the contract test is F05's.
15. **214 entries**, which matches the design's "Search 214 exercises". F12 shows the live count
    anyway. Six candidates were cut to get there: Jump Squat (a plyometric), Band Lateral Raise,
    Bayesian Cable Curl, Machine Glute Kickback, Decline Dumbbell Press and Underhand Barbell Row.
16. **File order**: entries are grouped by primary muscle in `MuscleGroup` order, then sorted by
    name. `seed()` returns file order.
17. **Decode time.** The brief's budget is under 20 ms on iPhone. `ExerciseCatalogPerformanceTests`
    follows `ReplayPerformanceTests` and runs on the nightly lane only. The host median, debug
    build, was **3.5 ms**. The file is 109,371 bytes against a 200 KB budget; the criterion 1
    test checks the size.

## Pattern-assignment rules

The authoritative text is the doc comment on `ExerciseCatalog`. A pattern is the swap family: a
swap only offers the same pattern (decision #13).

| Pattern | Rule | Count |
|---|---|---|
| `horizontalPush` | Presses in front of the torso: flat, incline and decline presses, push-ups and dips. Dips stand in for a bench press, not an overhead press. | 21 |
| `verticalPush` | Presses overhead: overhead presses, the landmine press, pike and handstand push-ups. | 11 |
| `horizontalPull` | Rows to the torso. | 13 |
| `verticalPull` | Pull-ups, chin-ups and pulldowns. | 10 |
| `squat` | Two-legged, knee-dominant lifts: squats (front squat included), leg presses and hack squats. | 14 |
| `lunge` | Single-leg, knee-dominant lifts: lunges, split squats, step-ups and pistols. | 11 |
| `hinge` | Hip-dominant lifts on one leg or two: deadlifts (RDL included), good mornings, hip thrusts, bridges, swings, cleans, back extensions and pull-throughs. | 27 |
| `carry` | Loaded walks; reps count lengths. | 5 |
| `core` | Trunk work that is not a carry: crunches, sit-ups, leg raises, rollouts, Pallof presses, chops, side bends and the Turkish get-up. | 22 |
| `isolation` | Single-joint accessories, plus the small-muscle accessories whose only sensible swaps are other accessories for the same muscle: face pulls, upright rows, shrugs, pullovers and straight-arm pulldowns. | 80 |

## Deliberately excluded

| Excluded | Why |
|---|---|
| Assisted pull-up and assisted dip machines | The load is assistance, so more weight is easier. `Weight` has no negative load, and progression would add assistance. |
| Timed holds: plank, side plank, wall sit, dead hang, hollow hold, L-sit | The log records reps, not time (spec §6.1 `LoggedSet`). Carries stay in, because the pattern exists and load is what progresses. |
| Hip adduction machine, Copenhagen plank | `MuscleGroup` has no adductors (F02). Adding them needs the group first. |
| Neck work | There is no neck group. |
| Sled push and pull, medicine ball, plate-only moves (plate front raise, plate pinch), wrist roller, rings or suspension trainer, battle ropes | There is no equipment type for them. A lifter can add them as custom exercises (F12). |
| Snatch and clean & jerk | Competition lifts, left for a later version. Power Clean and Hang Power Clean are in, because strength programs use them. |
| Technique variants: paused, tempo, deficit, pin, board, Spoto and Larsen presses, Zercher squat | Log these under the base lift. Box Squat and Rack Pull are in, because gyms and programs treat them as separate lifts. Zercher Squat is the fixture's custom exercise. |
| Plyometrics: jump squat, box jump | Not loaded lifts. |

## Counts

Primary muscle (criterion 5: at least 10 each, core at least 8):

| chest | back | shoulders | quads | hamstrings | glutes | calves | biceps | triceps | forearms | core |
|---|---|---|---|---|---|---|---|---|---|---|
| 22 | 32 | 27 | 28 | 13 | 20 | 11 | 13 | 14 | 10 | 24 |

Equipment (criterion 6: the minimum is in brackets):

| barbell (30) | dumbbell (40) | cable (25) | machine (25) | bodyweight (25) | kettlebell (10) | band (8) |
|---|---|---|---|---|---|---|
| 41 | 43 | 30 | 35 | 39 | 15 | 11 |

Forearms (10) sits exactly at its minimum, so removing one forearm entry fails criterion 5. That
is intended: the test protects the floor.

## Acceptance criteria → tests

All paths are under `LedgerKit/Tests/LedgerDomainTests/Catalog/`. The testing strategy names tests
`subject_condition_expectation` without a `test` prefix (§6), so the brief's `test_…` names are
mapped below.

| # | Brief's test | Test |
|---|---|---|
| 1 | `test_seedDecodesAllEntries` | `ExerciseCatalogTests.seed_decodesAllEntries` (at least 200 entries, all decoded in order, none custom, file ≤ 200 KB). The "throws, never skips" half is `CatalogEntryTests`: `brokenEntry_throws` (21 cases, one per `CatalogError` path), `undecodableDocument_throwsUnreadable` (9 cases) and `missingResource_throws`. |
| 2 | `test_prototypeEntriesMatchSpecW0` | `ExerciseCatalogTests.prototypeEntries_matchSpecW0`: 22 cases, each with its lb W0, its hand-worked kg value, the kg rounding rule, and its pinned id. |
| 3 | `test_alternativesResolveSamePattern` | `ExerciseCatalogTests.alternatives_resolveToSamePattern`, plus `isolationAlternatives_trainTheSamePrimaryMuscle` |
| 4 | `test_noDuplicateNamesOrAliases` | `ExerciseCatalogTests.namesAndAliases_haveNoDuplicates` |
| 5 | `test_muscleCoverage` | `ExerciseCatalogTests.muscleCoverage_meetsMinimum` (11 cases) |
| 6 | `test_equipmentCoverage` | `ExerciseCatalogTests.equipmentCoverage_meetsMinimum` (7 cases) |
| 7 | `test_versionShaMatchesFile` | `ExerciseCatalogTests.versionSha_matchesFile` |
| 8 | fixture only (the contract test is F05's) | `CatalogSeedFixtureTests.upgrade_isAdditive`, `custom_clashesOnlyWithClash` |
| — | `test_startLoadsAreMultiplesOfStep` | `ExerciseCatalogTests.startLoads_areMultiplesOfStep`, plus `kilogramStartLoads_areConvertedPounds` (the kg rule for all 214; only bodyweight starts at zero) |
| — | `test_idsAreStableUUIDs` | `ExerciseCatalogTests.ids_areStableUUIDs`: the raw file's ids are canonical upper-case UUIDv4 strings and unique. Stability is also guarded by the pinned prototype ids and criterion 7. |
| — | (beyond the brief) | `ExerciseCatalogTests.shortNames_fitTheWatch`; `CatalogEntryTests.validEntry_mapsEveryField`, `bodyweightEntries_decode`; `ExerciseCatalogPerformanceTests.seed_under20ms` (nightly) |

**Mutation checks**, run on the host; each time the file was restored byte for byte, and its SHA
matches `catalog.version.sha`:

- Changing the bench's W0 from 180 to 185 lb failed exactly three tests: criterion 2, the kg rule
  and criterion 7.
- Renaming one alias failed only criterion 7, with the message
  `exercises.json changed: bump ExerciseCatalog.version to 2 and append "2 b533c96b…" to catalog.version.sha`.
- A trailing space in a short name made `seed()` throw `invalidText`, so the whole suite failed in
  its `init()`.

## Size

The measure is lines that are neither blank nor comment-only (`//` and `///`), per engineering
standards §10. It was counted with
`grep -v '^[[:space:]]*$' FILE | grep -v '^[[:space:]]*//' | wc -l`, and for `Errors.swift` over the
added lines of `git diff -U0`.

| Kind | File | Lines |
|---|---|---|
| Code | `Catalog/ExerciseCatalog.swift` | 51 |
| Code | `Catalog/CatalogEntry.swift` | 57 |
| Code | `Errors.swift` (`CatalogError`, added) | 13 |
| Code | `Package.swift` (one resource declaration; the diff is +2 −1 with its comment) | 1 |
| Code (test support) | `LedgerTestSupport/Catalog/CatalogSeedFixture.swift` | 46 |
| **Code total** | | **168**, under the 500-line target |
| Tests | the four files in `LedgerDomainTests/Catalog/` | 413 (186 + 178 + 32 + 17) |
| Data | `exercises.json` (`wc -l`; 109,371 bytes) | 2,616 |
| Data | `catalog.version.sha` (`wc -l`) | 4 |

The JSON is pretty-printed one key per line, 12–13 lines per entry, and nothing is compressed.

## Gate

Run on the final tree through the shared simulator lock:
`sim-lock.py scripts/check.sh 2>&1 | tee …/scratchpad/f03-check.log` (2026-09-30).

| Check | Result |
|---|---|
| Full `scripts/check.sh` (format, lint, package graph and pins, script tests, iOS `PR` plan, watchOS `PR-Watch` plan, coverage) | **OK**, 317 s |
| iOS result bundle (`xcresulttool … PR-iOS.xcresult`) | **Passed**: 923 tests, 0 failed, 3 skipped (the nightly-lane suites), iPhone 17 (27.0) |
| watchOS result bundle (`… PR-watchOS.xcresult`) | **Passed**: 848 tests, 0 failed, 3 skipped, Apple Watch Series 12 (46 mm) (27.0) |
| Coverage gate | LedgerDomain **99.01 %** (1,816 / 1,834 lines; threshold 95 %); overall 98.12 % |
| New files (`xccov`, both platforms) | `ExerciseCatalog.swift` 46 / 46, `CatalogEntry.swift` 37 / 37, `CatalogSeedFixture.swift` 7 / 7 |
| `scripts/check.sh --fast` (while iterating) | **OK**: 707 tests in 118 suites |

`CatalogEntryTests.swift` itself is at 141 / 143 lines. The two uncovered lines are the
`Issue.record` branch, which runs only when a test fails.

## How to verify by hand

1. Run `swift test --package-path LedgerKit --filter 'ExerciseCatalog|CatalogEntry|CatalogSeedFixture'`.
2. Run `shasum -a 256 LedgerKit/Sources/LedgerDomain/Resources/exercises.json`. It must equal the
   last line of `catalog.version.sha`.
3. Edit any character of `exercises.json` and rerun step 1. `versionSha_matchesFile` fails and
   names the line to append. Revert the edit.
4. Recount from the file:
   `jq '.exercises | group_by(.primaryMuscle) | map({(.[0].primaryMuscle): length}) | add' LedgerKit/Sources/LedgerDomain/Resources/exercises.json`
   (use `.equipment` or `.pattern` for the other counts).
5. Time the decode with
   `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter ExerciseCatalogPerformanceTests`.
6. Read the appendix below. It is the catalog as a lifter would review it.

## Appendix: the catalog (version 1)

This appendix was generated from `exercises.json` version 1 for review. The JSON is the source of
truth. "BW" means bodyweight, a zero start with `loadKind`, and "+n" is added load. Patterns are
abbreviated: h-push, h-pull, v-push, v-pull.

#### Chest (22)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Barbell Bench Press | BENCH | barbell | h-push | triceps, shoulders | 180 / 82.5 | Dumbbell Bench Press; Smith Machine Bench Press; Weighted Dip; Machine Chest Press | Bench Press; Flat Bench Press |
| Barbell Floor Press | FLOOR PRESS | barbell | h-push | triceps, shoulders | 95 / 42.5 | Dumbbell Floor Press; Kettlebell Floor Press; Barbell Bench Press | Floor Press |
| Cable Chest Press | CB PRESS | cable | h-push | triceps, shoulders | 30 / 13.75 | Machine Chest Press; Dumbbell Bench Press; Push-Up | Standing Cable Chest Press; Standing Cable Press |
| Cable Crossover | CROSSOVER | cable | isolation | shoulders | 20 / 8.75 | Low-to-High Cable Fly; Pec Deck; Dumbbell Fly | Cable Fly; High-to-Low Cable Fly; Standing Cable Fly |
| Decline Bench Press | DEC BENCH | barbell | h-push | triceps, shoulders | 95 / 42.5 | Barbell Bench Press; Weighted Dip; Dip | Decline Barbell Bench Press |
| Decline Push-Up | DEC PUSH-UP | bodyweight | h-push | shoulders, triceps | BW | Push-Up; Dip; Incline DB Press | Feet-Elevated Push-Up |
| Dip | BW DIP | bodyweight | h-push | triceps, shoulders | BW | Weighted Dip; Push-Up; Machine Dip | Parallel Bar Dip; Chest Dip; Bar Dip |
| Dumbbell Bench Press | DB BENCH | dumbbell | h-push | triceps, shoulders | 30 / 13.75 | Barbell Bench Press; Machine Chest Press; Incline DB Press; Dumbbell Floor Press | DB Bench Press; Flat Dumbbell Press; Dumbbell Chest Press |
| Dumbbell Floor Press | DB FLOOR | dumbbell | h-push | triceps, shoulders | 30 / 13.75 | Barbell Floor Press; Kettlebell Floor Press; Dumbbell Bench Press | — |
| Dumbbell Fly | DB FLY | dumbbell | isolation | shoulders | 15 / 6.25 | Pec Deck; Cable Crossover; Incline Dumbbell Fly | Dumbbell Flye; Flat Dumbbell Fly |
| Incline Bench Press | INC BENCH | barbell | h-push | shoulders, triceps | 95 / 42.5 | Incline DB Press; Smith Machine Incline Press; Machine Incline Press | Incline Barbell Press; Incline Barbell Bench Press |
| Incline DB Press | INCLINE | dumbbell | h-push | shoulders, triceps | 50 / 22.5 | Incline Bench Press; Machine Incline Press; Smith Machine Incline Press; Dumbbell Bench Press | Incline Dumbbell Press; Incline Dumbbell Bench Press |
| Incline Dumbbell Fly | INC DB FLY | dumbbell | isolation | shoulders | 15 / 6.25 | Low-to-High Cable Fly; Dumbbell Fly; Pec Deck | Incline Dumbbell Flye; Incline DB Fly |
| Kettlebell Floor Press | KB FLOOR | kettlebell | h-push | triceps, shoulders | 25 / 11.25 | Dumbbell Floor Press; Barbell Floor Press; Push-Up | — |
| Low-to-High Cable Fly | FLY | cable | isolation | shoulders | 25 / 11.25 | Cable Crossover; Incline Dumbbell Fly; Pec Deck | Low Cable Fly; Low-to-High Cable Crossover |
| Machine Chest Press | CHEST PRESS | machine | h-push | triceps, shoulders | 50 / 22.5 | Barbell Bench Press; Dumbbell Bench Press; Smith Machine Bench Press; Cable Chest Press | Chest Press Machine; Seated Chest Press |
| Machine Incline Press | MC INCLINE | machine | h-push | shoulders, triceps | 50 / 22.5 | Incline DB Press; Incline Bench Press; Smith Machine Incline Press | Incline Chest Press Machine; Incline Machine Press |
| Pec Deck | PEC DECK | machine | isolation | shoulders | 50 / 22.5 | Cable Crossover; Dumbbell Fly; Low-to-High Cable Fly | Pec Deck Fly; Machine Fly; Butterfly |
| Push-Up | PUSH-UP | bodyweight | h-push | triceps, shoulders, core | BW | Decline Push-Up; Dumbbell Bench Press; Cable Chest Press; Dip | Pushup; Press-Up |
| Smith Machine Bench Press | SMITH BENCH | machine | h-push | triceps, shoulders | 65 / 30 | Barbell Bench Press; Machine Chest Press; Dumbbell Bench Press | Smith Machine Press; Smith Bench Press |
| Smith Machine Incline Press | SMITH INCLINE | machine | h-push | shoulders, triceps | 65 / 30 | Incline Bench Press; Machine Incline Press; Incline DB Press | Smith Machine Incline Bench Press; Smith Incline Press |
| Weighted Dip | DIP | bodyweight | h-push | triceps, shoulders | +45 / +20 | Dip; Barbell Bench Press; Machine Dip; Decline Bench Press | Weighted Chest Dip; Weighted Parallel Bar Dip |

#### Back (32)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Back Extension | BACK EXT | bodyweight | hinge | glutes, hamstrings | BW | Machine Back Extension; Reverse Hyperextension; Good Morning | Hyperextension; 45-Degree Back Extension; Roman Chair Back Extension |
| Band Row | BAND ROW | band | h-pull | biceps, shoulders | 20 / 8.75 | Seated Cable Row; Inverted Row; Kettlebell Row | Seated Band Row; Resistance Band Row |
| Barbell Row | ROW | barbell | h-pull | biceps, shoulders | 155 / 70 | Seated Cable Row; Single-Arm Dumbbell Row; Chest-Supported Row; Pendlay Row | Bent-Over Row; Bent-Over Barbell Row |
| Barbell Shrug | SHRUG | barbell | isolation | forearms | 95 / 42.5 | Dumbbell Shrug; Cable Shrug | Shrug |
| Cable Shrug | CB SHRUG | cable | isolation | forearms | 50 / 22.5 | Barbell Shrug; Dumbbell Shrug | — |
| Chest-Supported Dumbbell Row | CS DB ROW | dumbbell | h-pull | biceps, shoulders | 25 / 11.25 | Chest-Supported Row; Single-Arm Dumbbell Row; Seated Cable Row | Incline Dumbbell Row; Prone Dumbbell Row |
| Chest-Supported Row | CS ROW | machine | h-pull | biceps, shoulders | 65 / 30 | Seated Cable Row; Single-Arm Dumbbell Row; Barbell Row; Chest-Supported Dumbbell Row | Machine Row; Seated Row Machine; Chest-Supported Machine Row |
| Chin-Up | CHIN-UP | bodyweight | v-pull | biceps | BW | Reverse-Grip Lat Pulldown; Pull-Up; Weighted Chin-Up; Neutral-Grip Pull-Up | Chinup; Underhand Pull-Up |
| Dumbbell Bent-Over Row | DB BO ROW | dumbbell | h-pull | biceps, shoulders | 25 / 11.25 | Barbell Row; Chest-Supported Dumbbell Row; Kettlebell Row | Bent-Over Dumbbell Row; Two-Arm Dumbbell Row |
| Dumbbell Pullover | DB PULLOVER | dumbbell | isolation | chest, triceps | 25 / 11.25 | Straight-Arm Pulldown; Machine Pullover | DB Pullover |
| Dumbbell Shrug | DB SHRUG | dumbbell | isolation | forearms | 30 / 13.75 | Barbell Shrug; Cable Shrug | — |
| Inverted Row | INV ROW | bodyweight | h-pull | biceps, shoulders | BW | Seated Cable Row; Band Row; Single-Arm Dumbbell Row | Bodyweight Row; Australian Pull-Up |
| Kettlebell Row | KB ROW | kettlebell | h-pull | biceps, shoulders | 35 / 16.25 | Single-Arm Dumbbell Row; Dumbbell Bent-Over Row; Band Row | Single-Arm Kettlebell Row |
| Lat Pulldown | PULLDOWN | cable | v-pull | biceps, shoulders | 100 / 45 | Neutral-Grip Pulldown; Pull-Up; Machine Pulldown; Single-Arm Lat Pulldown | Wide-Grip Lat Pulldown; Wide-Grip Pulldown |
| Machine Back Extension | MC BACK EXT | machine | hinge | glutes, hamstrings | 50 / 22.5 | Back Extension; Reverse Hyperextension; Good Morning | Back Extension Machine; Seated Back Extension |
| Machine Pulldown | MC PULLDOWN | machine | v-pull | biceps | 70 / 31.25 | Lat Pulldown; Neutral-Grip Pulldown; Pull-Up | Machine Lat Pulldown; Plate-Loaded Pulldown |
| Machine Pullover | MC PULLOVER | machine | isolation | chest, triceps | 50 / 22.5 | Dumbbell Pullover; Straight-Arm Pulldown | Pullover Machine |
| Meadows Row | MEADOWS | barbell | h-pull | biceps, shoulders | 25 / 12.5 | Single-Arm Dumbbell Row; T-Bar Row; Single-Arm Cable Row | — |
| Neutral-Grip Pull-Up | NG PULL-UP | bodyweight | v-pull | biceps | BW | Neutral-Grip Pulldown; Pull-Up; Chin-Up | Hammer-Grip Pull-Up; Parallel-Grip Pull-Up |
| Neutral-Grip Pulldown | NG PULLDOWN | cable | v-pull | biceps | 70 / 31.25 | Lat Pulldown; Neutral-Grip Pull-Up; Reverse-Grip Lat Pulldown | Close-Grip Lat Pulldown; Close-Grip Pulldown; V-Bar Pulldown |
| Pendlay Row | PENDLAY | barbell | h-pull | biceps, shoulders | 95 / 42.5 | Barbell Row; T-Bar Row; Dumbbell Bent-Over Row | — |
| Pull-Up | BW PULL-UP | bodyweight | v-pull | biceps, forearms | BW | Lat Pulldown; Weighted Pull-Up; Chin-Up; Neutral-Grip Pull-Up | Pullup; Overhand Pull-Up |
| Rack Pull | RACK PULL | barbell | hinge | glutes, hamstrings, forearms | 135 / 60 | Deadlift; Trap Bar Deadlift; Romanian Deadlift | Block Pull |
| Reverse-Grip Lat Pulldown | RG PULLDOWN | cable | v-pull | biceps | 70 / 31.25 | Chin-Up; Neutral-Grip Pulldown; Lat Pulldown | Underhand Lat Pulldown; Supinated Lat Pulldown |
| Seated Cable Row | CABLE ROW | cable | h-pull | biceps, shoulders | 70 / 31.25 | Chest-Supported Row; Single-Arm Dumbbell Row; Barbell Row; Single-Arm Cable Row | Cable Row; Low Cable Row; Seated Row |
| Single-Arm Cable Row | SA CABLE ROW | cable | h-pull | biceps, shoulders | 30 / 13.75 | Seated Cable Row; Single-Arm Dumbbell Row; Meadows Row | One-Arm Cable Row |
| Single-Arm Dumbbell Row | DB ROW | dumbbell | h-pull | biceps, shoulders | 30 / 13.75 | Chest-Supported Row; Single-Arm Cable Row; Barbell Row; Kettlebell Row | Dumbbell Row; One-Arm Dumbbell Row; Single-Arm DB Row |
| Single-Arm Lat Pulldown | SA PULLDOWN | cable | v-pull | biceps | 30 / 13.75 | Lat Pulldown; Neutral-Grip Pulldown; Machine Pulldown | One-Arm Lat Pulldown; Single-Arm Cable Pulldown |
| Straight-Arm Pulldown | STRAIGHT ARM | cable | isolation | triceps, core | 30 / 13.75 | Dumbbell Pullover; Machine Pullover | Straight-Arm Lat Pulldown; Straight-Arm Cable Pulldown; Cable Pullover |
| T-Bar Row | T-BAR ROW | barbell | h-pull | biceps, shoulders | 45 / 20 | Barbell Row; Chest-Supported Row; Meadows Row | Landmine Row |
| Weighted Chin-Up | WTD CHIN-UP | bodyweight | v-pull | biceps | +25 / +11.25 | Chin-Up; Weighted Pull-Up; Reverse-Grip Lat Pulldown | Weighted Chinup |
| Weighted Pull-Up | PULL-UP | bodyweight | v-pull | biceps, forearms | +35 / +16.25 | Pull-Up; Lat Pulldown; Weighted Chin-Up; Machine Pulldown | Weighted Pullup |

#### Shoulders (27)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Arnold Press | ARNOLD | dumbbell | v-push | triceps | 20 / 8.75 | Seated Dumbbell Shoulder Press; Machine Shoulder Press; Kettlebell Overhead Press | Arnold Dumbbell Press |
| Band External Rotation | BAND EXT ROT | band | isolation | — | 5 / 2.5 | Cable External Rotation; Band Face Pull | Band Shoulder External Rotation |
| Band Face Pull | BAND FACE PULL | band | isolation | back | 15 / 6.25 | Face Pull; Band Pull-Apart; Cable Rear Delt Fly | — |
| Band Overhead Press | BAND OHP | band | v-push | triceps | 20 / 8.75 | Pike Push-Up; Seated Dumbbell Shoulder Press; Kettlebell Overhead Press | Band Shoulder Press |
| Band Pull-Apart | PULL-APART | band | isolation | back | 15 / 6.25 | Band Face Pull; Dumbbell Rear Delt Fly; Rear Delt Fly | Resistance Band Pull-Apart |
| Barbell Upright Row | UPRIGHT ROW | barbell | isolation | back, biceps | 45 / 20 | Cable Upright Row; Dumbbell Upright Row; Dumbbell Lateral Raise | Upright Row |
| Cable External Rotation | CB EXT ROT | cable | isolation | — | 5 / 2.5 | Band External Rotation; Face Pull | Cable Shoulder External Rotation |
| Cable Front Raise | CB FRONT | cable | isolation | chest | 10 / 5 | Dumbbell Front Raise; Cable Lateral Raise | — |
| Cable Lateral Raise | LATERAL | cable | isolation | — | 12.5 / 6.25 | Dumbbell Lateral Raise; Machine Lateral Raise; Cable Upright Row | Single-Arm Cable Lateral Raise |
| Cable Rear Delt Fly | CB REAR DELT | cable | isolation | back | 10 / 5 | Rear Delt Fly; Dumbbell Rear Delt Fly; Face Pull | Cable Reverse Fly; Reverse Cable Crossover |
| Cable Upright Row | CB UPRIGHT | cable | isolation | back, biceps | 30 / 13.75 | Barbell Upright Row; Cable Lateral Raise; Dumbbell Upright Row | Rope Upright Row |
| Dumbbell Front Raise | DB FRONT | dumbbell | isolation | chest | 10 / 5 | Cable Front Raise; Dumbbell Lateral Raise | Front Raise; Front Dumbbell Raise |
| Dumbbell Lateral Raise | DB LATERAL | dumbbell | isolation | — | 10 / 5 | Cable Lateral Raise; Machine Lateral Raise; Dumbbell Upright Row | DB Lateral Raise; Lateral Raise; Side Lateral Raise; Side Raise |
| Dumbbell Rear Delt Fly | DB REAR DELT | dumbbell | isolation | back | 10 / 5 | Rear Delt Fly; Cable Rear Delt Fly; Band Pull-Apart; Face Pull | Bent-Over Reverse Fly; Dumbbell Reverse Fly; Bent-Over Rear Delt Raise |
| Dumbbell Upright Row | DB UPRIGHT | dumbbell | isolation | back, biceps | 15 / 6.25 | Barbell Upright Row; Cable Upright Row; Dumbbell Lateral Raise | — |
| Face Pull | FACE PULL | cable | isolation | back | 30 / 13.75 | Band Face Pull; Rear Delt Fly; Cable Rear Delt Fly | Rope Face Pull; Cable Face Pull |
| Handstand Push-Up | HSPU | bodyweight | v-push | triceps | BW | Pike Push-Up; Overhead Press; Machine Shoulder Press | HSPU; Wall Handstand Push-Up |
| Kettlebell Overhead Press | KB PRESS | kettlebell | v-push | triceps, core | 25 / 11.25 | Seated Dumbbell Shoulder Press; Arnold Press; Landmine Press | Kettlebell Press; Single-Arm Kettlebell Press |
| Landmine Press | LANDMINE | barbell | v-push | chest, triceps | 25 / 12.5 | Overhead Press; Seated Dumbbell Shoulder Press; Kettlebell Overhead Press | Single-Arm Landmine Press; Landmine Shoulder Press |
| Machine Lateral Raise | MC LATERAL | machine | isolation | — | 30 / 13.75 | Cable Lateral Raise; Dumbbell Lateral Raise | Lateral Raise Machine |
| Machine Shoulder Press | MC OHP | machine | v-push | triceps | 40 / 18.75 | Seated Dumbbell Shoulder Press; Overhead Press; Smith Machine Overhead Press | Shoulder Press Machine; Seated Machine Shoulder Press |
| Overhead Press | OHP | barbell | v-push | triceps, core | 115 / 52.5 | Seated Dumbbell Shoulder Press; Machine Shoulder Press; Push Press; Landmine Press | OHP; Standing Overhead Press; Military Press; Strict Press; Barbell Overhead Press |
| Pike Push-Up | PIKE PUSH-UP | bodyweight | v-push | triceps | BW | Handstand Push-Up; Seated Dumbbell Shoulder Press; Band Overhead Press | Pike Pushup |
| Push Press | PUSH PRESS | barbell | v-push | triceps, quads | 65 / 30 | Overhead Press; Landmine Press; Seated Dumbbell Shoulder Press | — |
| Rear Delt Fly | REAR DELT | machine | isolation | back | 50 / 22.5 | Dumbbell Rear Delt Fly; Cable Rear Delt Fly; Face Pull | Reverse Pec Deck; Machine Rear Delt Fly; Reverse Fly Machine |
| Seated Dumbbell Shoulder Press | DB OHP | dumbbell | v-push | triceps | 25 / 11.25 | Overhead Press; Arnold Press; Machine Shoulder Press | Seated Dumbbell Press; Dumbbell Shoulder Press; Dumbbell Overhead Press; Seated DB Press |
| Smith Machine Overhead Press | SMITH OHP | machine | v-push | triceps | 45 / 20 | Overhead Press; Machine Shoulder Press; Seated Dumbbell Shoulder Press | Smith Machine Shoulder Press; Smith Shoulder Press |

#### Quads (28)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Back Squat | SQUAT | barbell | squat | glutes, hamstrings | 250 / 112.5 | Front Squat; Safety Bar Squat; Leg Press; Hack Squat; Smith Machine Squat | Barbell Back Squat; Squat; High-Bar Squat; Low-Bar Squat |
| Barbell Lunge | BB LUNGE | barbell | lunge | glutes, hamstrings | 65 / 30 | Dumbbell Lunge; Barbell Split Squat; Dumbbell Walking Lunge | Barbell Forward Lunge |
| Barbell Split Squat | BB SPLIT SQ | barbell | lunge | glutes | 65 / 30 | Dumbbell Split Squat; Dumbbell Bulgarian Split Squat; Barbell Lunge | — |
| Belt Squat | BELT SQUAT | machine | squat | glutes | 90 / 41.25 | Hack Squat; Leg Press; Goblet Squat | Belt Squat Machine |
| Bodyweight Lunge | BW LUNGE | bodyweight | lunge | glutes | BW | Dumbbell Lunge; Dumbbell Walking Lunge; Pistol Squat | Lunge; Forward Lunge |
| Bodyweight Squat | BW SQUAT | bodyweight | squat | glutes | BW | Goblet Squat; Kettlebell Goblet Squat | Air Squat |
| Box Squat | BOX SQUAT | barbell | squat | glutes, hamstrings | 95 / 42.5 | Back Squat; Safety Bar Squat; Belt Squat | Barbell Box Squat |
| Dumbbell Bulgarian Split Squat | BULGARIAN | dumbbell | lunge | glutes | 20 / 8.75 | Dumbbell Split Squat; Dumbbell Reverse Lunge; Barbell Split Squat | Bulgarian Split Squat; Rear-Foot-Elevated Split Squat; RFESS |
| Dumbbell Lunge | DB LUNGE | dumbbell | lunge | glutes | 20 / 8.75 | Dumbbell Reverse Lunge; Dumbbell Walking Lunge; Barbell Lunge | Dumbbell Forward Lunge |
| Dumbbell Reverse Lunge | DB REV LUNGE | dumbbell | lunge | glutes | 20 / 8.75 | Dumbbell Lunge; Kettlebell Reverse Lunge; Dumbbell Split Squat | Reverse Lunge |
| Dumbbell Split Squat | DB SPLIT SQ | dumbbell | lunge | glutes | 20 / 8.75 | Dumbbell Bulgarian Split Squat; Barbell Split Squat; Dumbbell Reverse Lunge | Split Squat |
| Dumbbell Step-Up | STEP-UP | dumbbell | lunge | glutes | 15 / 6.25 | Dumbbell Reverse Lunge; Dumbbell Bulgarian Split Squat | Step-Up; Box Step-Up |
| Dumbbell Walking Lunge | WALK LUNGE | dumbbell | lunge | glutes | 20 / 8.75 | Dumbbell Lunge; Barbell Lunge; Bodyweight Lunge | Walking Lunge |
| Front Squat | FRONT SQ | barbell | squat | glutes, core | 185 / 85 | Back Squat; Goblet Squat; Hack Squat; Kettlebell Front Squat | Barbell Front Squat |
| Goblet Squat | GOBLET | dumbbell | squat | glutes, core | 30 / 13.75 | Kettlebell Goblet Squat; Front Squat; Leg Press | Dumbbell Goblet Squat |
| Hack Squat | HACK SQUAT | machine | squat | glutes | 90 / 41.25 | Leg Press; Pendulum Squat; Front Squat; Smith Machine Squat | Machine Hack Squat |
| Kettlebell Front Squat | KB FRONT SQ | kettlebell | squat | glutes, core | 25 / 11.25 | Front Squat; Kettlebell Goblet Squat; Goblet Squat | Double Kettlebell Front Squat |
| Kettlebell Goblet Squat | KB GOBLET | kettlebell | squat | glutes, core | 35 / 16.25 | Goblet Squat; Kettlebell Front Squat; Bodyweight Squat | — |
| Kettlebell Reverse Lunge | KB REV LUNGE | kettlebell | lunge | glutes | 20 / 8.75 | Dumbbell Reverse Lunge; Dumbbell Lunge; Bodyweight Lunge | — |
| Leg Extension | LEG EXT | machine | isolation | — | 50 / 22.5 | Sissy Squat; Reverse Nordic | Machine Leg Extension; Quad Extension |
| Leg Press | LEG PRESS | machine | squat | glutes | 320 / 145 | Hack Squat; Seated Leg Press; Back Squat; Pendulum Squat | 45-Degree Leg Press; Sled Leg Press |
| Pendulum Squat | PENDULUM | machine | squat | glutes | 45 / 20 | Hack Squat; Leg Press; Belt Squat | — |
| Pistol Squat | PISTOL | bodyweight | lunge | glutes, core | BW | Dumbbell Bulgarian Split Squat; Bodyweight Lunge; Dumbbell Step-Up | Single-Leg Squat |
| Reverse Nordic | REV NORDIC | bodyweight | isolation | — | BW | Sissy Squat; Leg Extension | Reverse Nordic Curl |
| Safety Bar Squat | SSB SQUAT | barbell | squat | glutes, back | 95 / 42.5 | Back Squat; Front Squat; Belt Squat | SSB Squat; Safety Squat Bar Squat |
| Seated Leg Press | MC LEG PRESS | machine | squat | glutes | 90 / 41.25 | Leg Press; Hack Squat; Belt Squat | Horizontal Leg Press |
| Sissy Squat | SISSY SQUAT | bodyweight | isolation | — | BW | Leg Extension; Reverse Nordic | — |
| Smith Machine Squat | SMITH SQUAT | machine | squat | glutes | 65 / 30 | Back Squat; Hack Squat; Leg Press | Smith Squat |

#### Hamstrings (13)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Good Morning | BAND GM | band | hinge | glutes, back | 20 / 8.75 | Good Morning; Band Pull-Through; Back Extension | — |
| Deadlift | DEADLIFT | barbell | hinge | glutes, back, forearms | 315 / 142.5 | Trap Bar Deadlift; Sumo Deadlift; Romanian Deadlift; Rack Pull | Conventional Deadlift; Barbell Deadlift |
| Dumbbell Romanian Deadlift | DB RDL | dumbbell | hinge | glutes, back | 30 / 13.75 | Romanian Deadlift; Single-Leg Romanian Deadlift; Kettlebell Deadlift | DB RDL; Dumbbell RDL |
| Glute-Ham Raise | GHR | bodyweight | isolation | glutes, calves | BW | Nordic Hamstring Curl; Lying Leg Curl; Seated Leg Curl | GHR; Glute Ham Raise |
| Good Morning | GOOD MORNING | barbell | hinge | glutes, back | 45 / 20 | Romanian Deadlift; Stiff-Leg Deadlift; Band Good Morning; Back Extension | Barbell Good Morning |
| Kettlebell Single-Leg Deadlift | KB SL RDL | kettlebell | hinge | glutes, core | 25 / 11.25 | Single-Leg Romanian Deadlift; Kettlebell Deadlift; Dumbbell Romanian Deadlift | Single-Leg Kettlebell Deadlift; Kettlebell Single-Leg RDL |
| Lying Leg Curl | LYING CURL | machine | isolation | calves | 50 / 22.5 | Seated Leg Curl; Standing Leg Curl; Nordic Hamstring Curl | Prone Leg Curl; Lying Hamstring Curl |
| Nordic Hamstring Curl | NORDIC | bodyweight | isolation | glutes, calves | BW | Glute-Ham Raise; Lying Leg Curl; Seated Leg Curl | Nordic Curl |
| Romanian Deadlift | RDL | barbell | hinge | glutes, back | 205 / 92.5 | Dumbbell Romanian Deadlift; Stiff-Leg Deadlift; Good Morning | RDL; Barbell RDL; Barbell Romanian Deadlift |
| Seated Leg Curl | LEG CURL | machine | isolation | calves | 90 / 41.25 | Lying Leg Curl; Standing Leg Curl; Nordic Hamstring Curl | Seated Hamstring Curl |
| Single-Leg Romanian Deadlift | SL RDL | dumbbell | hinge | glutes, core | 20 / 8.75 | Kettlebell Single-Leg Deadlift; Dumbbell Romanian Deadlift | Single-Leg RDL; Single-Leg Dumbbell RDL |
| Standing Leg Curl | ST LEG CURL | machine | isolation | calves | 20 / 8.75 | Seated Leg Curl; Lying Leg Curl | Standing Hamstring Curl |
| Stiff-Leg Deadlift | SLDL | barbell | hinge | glutes, back | 95 / 42.5 | Romanian Deadlift; Dumbbell Romanian Deadlift; Good Morning | Stiff-Legged Deadlift; SLDL |

#### Glutes (20)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Pull-Through | BAND PULL-THRU | band | hinge | hamstrings | 20 / 8.75 | Cable Pull-Through; Kettlebell Swing; Band Good Morning | — |
| Banded Lateral Walk | LATERAL WALK | band | isolation | — | 10 / 5 | Machine Hip Abduction; Cable Hip Abduction | Band Lateral Walk; Band Side Walk; Monster Walk |
| Barbell Glute Bridge | BB BRIDGE | barbell | hinge | hamstrings | 95 / 42.5 | Hip Thrust; Glute Bridge; Machine Hip Thrust | — |
| Cable Glute Kickback | GLUTE KICK | cable | isolation | hamstrings | 15 / 6.25 | Cable Hip Abduction; Banded Lateral Walk | Glute Kickback |
| Cable Hip Abduction | CB ABDUCTION | cable | isolation | — | 10 / 5 | Machine Hip Abduction; Banded Lateral Walk; Cable Glute Kickback | Standing Cable Hip Abduction |
| Cable Pull-Through | PULL-THROUGH | cable | hinge | hamstrings | 40 / 18.75 | Band Pull-Through; Kettlebell Swing; Hip Thrust | — |
| Glute Bridge | GLUTE BRIDGE | bodyweight | hinge | hamstrings | BW | Barbell Glute Bridge; Single-Leg Hip Thrust; Hip Thrust | Bodyweight Glute Bridge; Hip Bridge |
| Hang Power Clean | HANG CLEAN | barbell | hinge | hamstrings, quads, back | 75 / 35 | Power Clean; Kettlebell Clean | Hang Clean |
| Hip Thrust | HIP THRUST | barbell | hinge | hamstrings | 95 / 42.5 | Machine Hip Thrust; Barbell Glute Bridge; Single-Leg Hip Thrust | Barbell Hip Thrust |
| Kettlebell Clean | KB CLEAN | kettlebell | hinge | hamstrings, shoulders | 25 / 11.25 | Kettlebell Swing; Kettlebell Snatch; Hang Power Clean | — |
| Kettlebell Deadlift | KB DEADLIFT | kettlebell | hinge | hamstrings, quads | 35 / 16.25 | Kettlebell Swing; Dumbbell Romanian Deadlift; Trap Bar Deadlift | — |
| Kettlebell Snatch | KB SNATCH | kettlebell | hinge | shoulders, hamstrings | 25 / 11.25 | Kettlebell Swing; Kettlebell Clean | — |
| Kettlebell Swing | KB SWING | kettlebell | hinge | hamstrings, back | 35 / 16.25 | Cable Pull-Through; Kettlebell Deadlift; Band Pull-Through | Russian Kettlebell Swing; Two-Hand Kettlebell Swing |
| Machine Hip Abduction | HIP ABDUCT | machine | isolation | — | 70 / 31.25 | Cable Hip Abduction; Banded Lateral Walk | Hip Abduction Machine; Seated Hip Abduction; Abductor Machine |
| Machine Hip Thrust | MC HIP THRUST | machine | hinge | hamstrings | 90 / 41.25 | Hip Thrust; Barbell Glute Bridge; Glute Bridge | Hip Thrust Machine |
| Power Clean | POWER CLEAN | barbell | hinge | hamstrings, quads, back | 95 / 42.5 | Hang Power Clean; Kettlebell Clean | — |
| Reverse Hyperextension | REVERSE HYPER | machine | hinge | hamstrings, back | 45 / 20 | Back Extension; Machine Back Extension; Cable Pull-Through | Reverse Hyper |
| Single-Leg Hip Thrust | SL HIP THRUST | bodyweight | hinge | hamstrings | BW | Glute Bridge; Hip Thrust | — |
| Sumo Deadlift | SUMO | barbell | hinge | hamstrings, quads, back | 135 / 60 | Deadlift; Trap Bar Deadlift; Kettlebell Deadlift | Sumo Barbell Deadlift |
| Trap Bar Deadlift | TRAP BAR DL | barbell | hinge | quads, hamstrings, back | 135 / 60 | Deadlift; Sumo Deadlift; Rack Pull | Hex Bar Deadlift |

#### Calves (11)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Barbell Calf Raise | BB CALF | barbell | isolation | — | 95 / 42.5 | Smith Machine Calf Raise; Standing Calf Raise; Dumbbell Calf Raise | Standing Barbell Calf Raise |
| Bodyweight Calf Raise | BW CALF | bodyweight | isolation | — | BW | Single-Leg Calf Raise; Dumbbell Calf Raise | Calf Raise |
| Donkey Calf Raise | DONKEY CALF | machine | isolation | — | 90 / 41.25 | Standing Calf Raise; Leg Press Calf Raise | Donkey Calf Raise Machine |
| Dumbbell Calf Raise | DB CALF | dumbbell | isolation | — | 25 / 11.25 | Single-Leg Dumbbell Calf Raise; Barbell Calf Raise; Bodyweight Calf Raise | Standing Dumbbell Calf Raise |
| Leg Press Calf Raise | LP CALF | machine | isolation | — | 90 / 41.25 | Standing Calf Raise; Seated Calf Raise; Donkey Calf Raise | Calf Press; Leg Press Calf Press |
| Seated Calf Raise | SEATED CALF | machine | isolation | — | 45 / 20 | Standing Calf Raise; Seated Dumbbell Calf Raise; Leg Press Calf Raise | Seated Calf Raise Machine |
| Seated Dumbbell Calf Raise | SEATED DB CALF | dumbbell | isolation | — | 35 / 16.25 | Seated Calf Raise; Dumbbell Calf Raise | — |
| Single-Leg Calf Raise | SL CALF | bodyweight | isolation | — | BW | Bodyweight Calf Raise; Single-Leg Dumbbell Calf Raise | One-Leg Calf Raise |
| Single-Leg Dumbbell Calf Raise | SL DB CALF | dumbbell | isolation | — | 20 / 8.75 | Dumbbell Calf Raise; Single-Leg Calf Raise | — |
| Smith Machine Calf Raise | SMITH CALF | machine | isolation | — | 65 / 30 | Standing Calf Raise; Barbell Calf Raise; Dumbbell Calf Raise | Smith Calf Raise |
| Standing Calf Raise | CALF | machine | isolation | — | 160 / 72.5 | Seated Calf Raise; Leg Press Calf Raise; Smith Machine Calf Raise; Barbell Calf Raise | Standing Calf Raise Machine; Machine Calf Raise |

#### Biceps (13)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Curl | BAND CURL | band | isolation | forearms | 15 / 6.25 | Cable Curl; Dumbbell Curl | Resistance Band Curl; Band Biceps Curl |
| Barbell Curl | CURL | barbell | isolation | forearms | 75 / 35 | EZ-Bar Curl; Dumbbell Curl; Cable Curl | Standing Barbell Curl; Barbell Biceps Curl |
| Cable Curl | CABLE CURL | cable | isolation | forearms | 40 / 18.75 | Barbell Curl; EZ-Bar Curl; Band Curl | Cable Biceps Curl; Straight-Bar Cable Curl |
| Cable Hammer Curl | CB HAMMER | cable | isolation | forearms | 40 / 18.75 | Hammer Curl; Cable Curl | Rope Hammer Curl |
| Concentration Curl | CONC CURL | dumbbell | isolation | — | 20 / 8.75 | Dumbbell Preacher Curl; Spider Curl; Dumbbell Curl | Seated Concentration Curl |
| Dumbbell Curl | DB CURL | dumbbell | isolation | forearms | 20 / 8.75 | Barbell Curl; Incline DB Curl; Cable Curl; Hammer Curl | Dumbbell Biceps Curl; Standing Dumbbell Curl; Alternating Dumbbell Curl |
| Dumbbell Preacher Curl | DB PREACHER | dumbbell | isolation | — | 20 / 8.75 | Preacher Curl; Machine Preacher Curl; Concentration Curl | — |
| EZ-Bar Curl | EZ CURL | barbell | isolation | forearms | 45 / 20 | Barbell Curl; Cable Curl; Preacher Curl | EZ Bar Curl; EZ Curl |
| Hammer Curl | HAMMER CURL | dumbbell | isolation | forearms | 25 / 11.25 | Cable Hammer Curl; Dumbbell Curl; Incline DB Curl | Dumbbell Hammer Curl |
| Incline DB Curl | INC DB CURL | dumbbell | isolation | forearms | 30 / 13.75 | Dumbbell Curl; Cable Curl; Spider Curl | Incline Dumbbell Curl |
| Machine Preacher Curl | MC PREACHER | machine | isolation | — | 40 / 18.75 | Preacher Curl; Dumbbell Preacher Curl; Cable Curl | Preacher Curl Machine; Machine Biceps Curl; Machine Curl |
| Preacher Curl | PREACHER | barbell | isolation | forearms | 45 / 20 | Machine Preacher Curl; Dumbbell Preacher Curl; EZ-Bar Curl | EZ-Bar Preacher Curl; Barbell Preacher Curl |
| Spider Curl | SPIDER CURL | dumbbell | isolation | — | 20 / 8.75 | Dumbbell Preacher Curl; Concentration Curl; Incline DB Curl | Dumbbell Spider Curl |

#### Triceps (14)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Triceps Pushdown | BAND PUSHDOWN | band | isolation | — | 15 / 6.25 | Cable Triceps Pushdown; Rope Pushdown | Band Pushdown; Resistance Band Pushdown |
| Bench Dip | BENCH DIP | bodyweight | h-push | chest, shoulders | BW | Dip; Diamond Push-Up; Machine Dip | Triceps Bench Dip |
| Cable Triceps Kickback | CB KICKBACK | cable | isolation | — | 10 / 5 | Dumbbell Kickback; Cable Triceps Pushdown | — |
| Cable Triceps Pushdown | PUSHDOWN | cable | isolation | — | 60 / 27.5 | Rope Pushdown; Machine Triceps Extension; Band Triceps Pushdown | Triceps Pushdown; Cable Pushdown; Straight-Bar Pushdown |
| Close-Grip Bench Press | CG BENCH | barbell | h-push | chest, shoulders | 95 / 42.5 | Diamond Push-Up; Machine Dip; Barbell Floor Press | Close-Grip Barbell Bench Press; CGBP |
| Diamond Push-Up | DIAMOND | bodyweight | h-push | chest, shoulders | BW | Close-Grip Bench Press; Bench Dip; Push-Up | Close-Grip Push-Up; Triangle Push-Up |
| Dumbbell Kickback | KICKBACK | dumbbell | isolation | — | 10 / 5 | Cable Triceps Kickback; Cable Triceps Pushdown | Triceps Kickback; Dumbbell Triceps Kickback |
| Dumbbell Overhead Triceps Extension | DB OH EXT | dumbbell | isolation | — | 30 / 13.75 | Overhead Cable Extension; Skull Crusher; Dumbbell Skull Crusher | Overhead Dumbbell Extension; Dumbbell Overhead Extension; Seated Dumbbell Triceps Extension |
| Dumbbell Skull Crusher | DB SKULL | dumbbell | isolation | — | 15 / 6.25 | Skull Crusher; Dumbbell Overhead Triceps Extension | Lying Dumbbell Triceps Extension; Dumbbell Lying Triceps Extension |
| Machine Dip | MC DIP | machine | h-push | chest, shoulders | 70 / 31.25 | Dip; Weighted Dip; Close-Grip Bench Press | Seated Dip Machine; Triceps Dip Machine; Seated Dip |
| Machine Triceps Extension | MC TRI EXT | machine | isolation | — | 40 / 18.75 | Cable Triceps Pushdown; Overhead Cable Extension | Triceps Extension Machine |
| Overhead Cable Extension | OH EXT | cable | isolation | — | 45 / 20 | Dumbbell Overhead Triceps Extension; Rope Pushdown; Skull Crusher | Overhead Cable Triceps Extension; Cable Overhead Triceps Extension; Overhead Rope Extension |
| Rope Pushdown | ROPE PUSHDOWN | cable | isolation | — | 40 / 18.75 | Cable Triceps Pushdown; Overhead Cable Extension; Band Triceps Pushdown | Rope Triceps Pushdown; Cable Rope Pushdown |
| Skull Crusher | SKULLCRUSHER | barbell | isolation | — | 45 / 20 | Dumbbell Skull Crusher; Overhead Cable Extension; Cable Triceps Pushdown | EZ-Bar Skull Crusher; Lying Triceps Extension; Skullcrusher |

#### Forearms (10)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Barbell Wrist Curl | WRIST CURL | barbell | isolation | — | 45 / 20 | Dumbbell Wrist Curl; Behind-the-Back Wrist Curl | Wrist Curl; Seated Barbell Wrist Curl |
| Behind-the-Back Wrist Curl | BTB WRIST | barbell | isolation | — | 65 / 30 | Barbell Wrist Curl; Dumbbell Wrist Curl | Behind-the-Back Barbell Wrist Curl |
| Cable Reverse Curl | CB REV CURL | cable | isolation | biceps | 30 / 13.75 | Reverse Curl; Zottman Curl | Reverse-Grip Cable Curl |
| Dumbbell Farmer's Carry | FARMER CARRY | dumbbell | carry | back, core | 40 / 18.75 | Kettlebell Farmer's Carry; Trap Bar Carry; Suitcase Carry | Farmer's Carry; Farmer's Walk; Dumbbell Farmer's Walk |
| Dumbbell Reverse Wrist Curl | DB REV WRIST | dumbbell | isolation | — | 10 / 5 | Reverse Curl; Zottman Curl; Dumbbell Wrist Curl | Reverse Wrist Curl |
| Dumbbell Wrist Curl | DB WRIST | dumbbell | isolation | — | 15 / 6.25 | Barbell Wrist Curl; Dumbbell Reverse Wrist Curl | — |
| Kettlebell Farmer's Carry | KB CARRY | kettlebell | carry | back, core | 35 / 16.25 | Dumbbell Farmer's Carry; Kettlebell Front Rack Carry; Suitcase Carry | Kettlebell Farmer's Walk |
| Reverse Curl | REV CURL | barbell | isolation | biceps | 45 / 20 | Cable Reverse Curl; Zottman Curl; Dumbbell Reverse Wrist Curl | Reverse Barbell Curl; EZ-Bar Reverse Curl; Reverse-Grip Curl |
| Trap Bar Carry | TRAP CARRY | barbell | carry | back, core | 135 / 60 | Dumbbell Farmer's Carry; Kettlebell Farmer's Carry | Trap Bar Farmer's Carry; Trap Bar Walk |
| Zottman Curl | ZOTTMAN | dumbbell | isolation | biceps | 20 / 8.75 | Reverse Curl; Cable Reverse Curl | Dumbbell Zottman Curl |

#### Core (24)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Ab Wheel Rollout | AB WHEEL | bodyweight | core | back, shoulders | BW | Dead Bug; Hanging Leg Raise | Ab Rollout; Ab Wheel |
| Band Pallof Press | BAND PALLOF | band | core | — | 15 / 6.25 | Cable Pallof Press; Dead Bug | — |
| Cable Crunch | CABLE CRUNCH | cable | core | — | 50 / 22.5 | Machine Crunch; Decline Sit-Up; Crunch | Kneeling Cable Crunch |
| Cable Pallof Press | PALLOF | cable | core | — | 20 / 8.75 | Band Pallof Press; Cable Woodchop; Dead Bug | Pallof Press |
| Cable Woodchop | WOODCHOP | cable | core | shoulders | 20 / 8.75 | Cable Pallof Press; Landmine Rotation; Russian Twist | Cable Wood Chop; Woodchopper |
| Captain's Chair Knee Raise | CHAIR RAISE | bodyweight | core | — | BW | Hanging Knee Raise; Hanging Leg Raise; Reverse Crunch | Captain's Chair Leg Raise; Roman Chair Leg Raise; Vertical Knee Raise |
| Crunch | CRUNCH | bodyweight | core | — | BW | Cable Crunch; Machine Crunch; Sit-Up | Abdominal Crunch; Floor Crunch |
| Dead Bug | DEAD BUG | bodyweight | core | — | BW | Ab Wheel Rollout; Cable Pallof Press; Band Pallof Press | — |
| Decline Sit-Up | DEC SIT-UP | bodyweight | core | — | BW | Sit-Up; Cable Crunch; Crunch | Decline Bench Sit-Up |
| Dumbbell Side Bend | SIDE BEND | dumbbell | core | — | 25 / 11.25 | Kettlebell Windmill; Cable Woodchop | Side Bend |
| Hanging Knee Raise | HANG KNEE | bodyweight | core | forearms | BW | Hanging Leg Raise; Captain's Chair Knee Raise; Reverse Crunch | — |
| Hanging Leg Raise | HANG LEG RAISE | bodyweight | core | forearms | BW | Hanging Knee Raise; Toes-to-Bar; Captain's Chair Knee Raise; Lying Leg Raise | — |
| Kettlebell Front Rack Carry | RACK CARRY | kettlebell | carry | shoulders | 25 / 11.25 | Kettlebell Farmer's Carry; Suitcase Carry | Front Rack Carry |
| Kettlebell Windmill | WINDMILL | kettlebell | core | shoulders, hamstrings | 15 / 6.25 | Turkish Get-Up; Dumbbell Side Bend | — |
| Landmine Rotation | LANDMINE ROT | barbell | core | shoulders | 25 / 12.5 | Cable Woodchop; Russian Twist | Landmine Twist; Landmine 180 |
| Lying Leg Raise | LEG RAISE | bodyweight | core | — | BW | Reverse Crunch; Hanging Leg Raise; V-Up | Floor Leg Raise |
| Machine Crunch | MC CRUNCH | machine | core | — | 50 / 22.5 | Cable Crunch; Crunch | Ab Crunch Machine; Abdominal Crunch Machine; Crunch Machine |
| Reverse Crunch | REV CRUNCH | bodyweight | core | — | BW | Hanging Knee Raise; Lying Leg Raise; Crunch | — |
| Russian Twist | RUSSIAN TWIST | bodyweight | core | — | BW | Cable Woodchop; Landmine Rotation | — |
| Sit-Up | SIT-UP | bodyweight | core | — | BW | Crunch; Decline Sit-Up; V-Up | Situp |
| Suitcase Carry | SUITCASE | dumbbell | carry | forearms | 40 / 18.75 | Dumbbell Farmer's Carry; Kettlebell Front Rack Carry; Kettlebell Farmer's Carry | Single-Arm Farmer's Carry |
| Toes-to-Bar | T2B | bodyweight | core | forearms | BW | Hanging Leg Raise; V-Up | T2B |
| Turkish Get-Up | GET-UP | kettlebell | core | shoulders, glutes | 15 / 6.25 | Kettlebell Windmill; Dead Bug | TGU; Kettlebell Get-Up |
| V-Up | V-UP | bodyweight | core | — | BW | Sit-Up; Toes-to-Bar; Lying Leg Raise | — |
