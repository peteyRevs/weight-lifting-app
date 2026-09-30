# F03 — implementation notes

Branch `feat/F03-exercise-catalog` (from `main` at `1d80613`).
- **Implementer pass:** 2026-09-30, committed as `d80602f`.
- **Fix round 1:** 2026-09-30, committed as `4d7cf28`. It applies Pete's and the orchestrator's
  decisions; see "Decisions (2026-09-30)" below.
- **Fix round 2:** 2026-09-30, uncommitted. It answers the review (`review.md`) and the adversarial
  round (`test-findings.md`); see "Fix round 2" below.

## What was built

- **`LedgerDomain/Resources/exercises.json`**: the catalog, 224 exercises. Before this pass it was
  the placeholder `{"version":1,"exercises":[]}`. A `contributing` array at the top of the file tells
  editors never to regenerate an id, to bump the version and to append the SHA. The decoder
  ignores that array.
- **`LedgerDomain/Resources/catalog.version.sha`**: the append-only history of
  `<version> <sha256 of exercises.json>` lines (criterion 7). It holds three lines: versions 1 and 2
  (the first pass and fix round 1, never merged) and version 3.
- **`LedgerDomain/Catalog/ExerciseCatalog.swift`**:
  - `version` (3) and `seed()`, which decodes and checks the bundled file and throws on the first
    malformed entry;
  - internal `exercises(from:)`, `entries(from:)` and `resource(_:withExtension:)`, which the tests
    use;
  - the pattern-assignment rules and the start-load policy table, as doc comments.
- **`LedgerDomain/Catalog/CatalogEntry.swift`**: the decoding DTO. `exercise()` runs the checks
  that need only one entry and maps the entry to an `Exercise`.
- **`LedgerDomain/Errors.swift`**: `CatalogError`, with one case per way a document can be
  malformed.
- **`LedgerTestSupport/Catalog/CatalogSeedFixture.swift`**: criterion 8's fixture for F05.
- **`LedgerKit/Package.swift`**: the new `.sha` file is declared as a copied resource.
- **Tests** in `LedgerDomainTests/Catalog/`: `ExerciseCatalogTests`, `CatalogEntryTests`,
  `CatalogSeedFixtureTests`, `ExerciseCatalogPerformanceTests` (nightly lane) and
  `StartLoadPolicy`, the policy as a test oracle.
- **Fix round 1, outside the catalog:**
  - `Equipment.defaultStep(in:)` (F02): kettlebells step 5 lb / 2 kg;
  - `scripts/check-catalog-version.sh`, run by `check.sh` step 2, with the adversarial suite
    `scripts/tests/adversarial/catalog-version.adv.sh`;
  - two rows in `docs/product-decisions.md` (#21 and #22);
  - aligned step and load wording in the F02, F03, F08, F10, F11 and F14 briefs.

`Exercise`'s fields are unchanged, as the brief requires. The project file was not touched.

## Ids must never be regenerated

Every id is a random UUIDv4, generated once for this pass. Ids are stored in lifters' databases,
referenced by programs, workouts and other entries' `alternatives`, and compared by F05's seed. An
edit must never change, reuse or re-roll one. A new exercise gets a new `uuidgen` id.

Four things guard this:

- the note at the top of the JSON;
- the pinned ids of the 22 prototype entries in `ExerciseCatalogTests.prototypeEntries_usePolicyLoads`;
- the SHA test (criterion 7), which fails on any change to the file;
- `scripts/check-catalog-version.sh`. It fails a changed file unless the version rises above
  main's. Since fix round 2 (review S3) it also fails, whatever the version, when an id main has is
  gone, or when an entry main has now carries another id (a re-roll or a swap). Renaming an entry
  and keeping its id passes.

The generator used for this pass stays in the session scratchpad. It is deliberately not
committed: a script that rebuilds the file invites re-rolled ids. From now on the JSON is edited
by hand.

## Decisions (2026-09-30)

Pete decided the two product questions from the first pass; the orchestrator decided the rest.

1. **Conservative start loads for all 214, the 22 prototype entries included (Pete).** This
   amends criterion 2. The brief now reads "the 22 prototype entries exist with the policy's
   conservative loads", and the test is `prototypeEntries_usePolicyLoads`. It is decision #21 in
   `docs/product-decisions.md`. The policy, by equipment and movement class:

   | Equipment | Compound | Isolation and core | Small raises |
   |---|---|---|---|
   | Barbell (bar included) | 45 lb / 20 kg, the empty bar | 25 lb / 10 kg, an EZ or fixed bar | — |
   | Specialty bar, empty (fix round 2) | safety squat bar 65 lb / 30 kg; trap bar 55 lb / 25 kg | — | — |
   | Dumbbell (per hand) | 15 lb / 7.5 kg | 10 lb / 5 kg | 5 lb / 2.5 kg |
   | Cable (per stack) | 30 lb / 15 kg | 20 lb / 10 kg | 10 lb / 5 kg |
   | Machine | 40 lb / 20 kg | 20 lb / 10 kg | 10 lb / 5 kg |
   | Kettlebell (per bell) | 25 lb / 12 kg | — | — |
   | Band (rated resistance) | 20 lb / 10 kg | 10 lb / 5 kg | 5 lb / 2.5 kg |
   | Bodyweight | 0 | 0 | — |

   - **Class rules.** A class follows from the pattern: isolation and core patterns are
     "isolation", everything else is "compound". Four named classes override it:
     - **floor pulls:** Deadlift, Sumo Deadlift and Rack Pull take 95 lb / 40 kg, the bar with
       two small plates at pulling height (Trap Bar Deadlift moved to the specialty bars in fix
       round 2);
     - **specialty bars** (fix round 2, review S5): Safety Bar Squat 65 lb / 30 kg; Trap Bar
       Deadlift and Trap Bar Carry 55 lb / 25 kg, each bar's own empty weight;
     - **straight-bar isolation** (fix round 2, review N3): Barbell Shrug, Barbell Calf Raise and
       Behind-the-Back Wrist Curl take the empty bar, 45 lb / 20 kg, not the EZ bar;
     - **landmine:** T-Bar Row, Meadows Row, Landmine Press, Landmine Rotation and Landmine Squat
       take 10 lb / 5 kg of plates;
     - **kettlebell upper body, overhead, cleans and get-ups:** the press, row, floor press, clean,
       snatch, Turkish get-up and windmill take the lighter 15 lb / 8 kg bell (the clean named in
       #21 since fix round 2);
     - **weighted dips and pull-ups:** +10 lb / +5 kg.
   - **Small raises** are delt raises and flies, rotator-cuff rotations, triceps and glute
     kickbacks, cable hip abduction and adduction, and dumbbell wrist curls: 19 entries, listed
     in `StartLoadPolicy.small`.
   - **The kg rule.** Every value is a multiple of its equipment's step in that unit. The kg
     column is not a conversion: it is the same setup with kg equipment (a 20 kg bar, 2.5 kg
     dumbbells, 5 kg stack plates, and the 8, 12 and 16 kg bells beginners start on; the
     kettlebell step is 2 kg). It stays within 3.1 kg of the converted lb value; the largest gap
     is 95 lb against 40 kg.
   - **Tests.** `ExerciseCatalogTests.startLoads_followThePolicy` checks every exercise against
     the test oracle `StartLoadPolicy`. It also checks that every name the policy lists exists.
     It replaces the first pass's "kg is converted lb" test. The criterion 2 table was read off
     the policy by hand.
   - **Examples.** Bench 180 → 45 lb (82.5 → 20 kg); squat 250 → 45 lb; deadlift 315 → 95 lb
     (40 kg); Incline DB Press 50 → 15 lb (7.5 kg); Lat Pulldown 100 → 30 lb (15 kg); Weighted
     Dip +45 → +10 lb.
2. **Kettlebell step 5 lb / 2 kg (Pete), decision #22.**
   - **The change:** one new `switch` arm in `Equipment.defaultStep(in:)`, with a doc line.
   - **F02 tests that pinned the old value**, each updated with a one-line justification comment
     that cites decision #22:
     - `ExerciseTests.equipment_defaultStep` now excludes kettlebells, and the new
       `kettlebell_defaultStep` pins them;
     - `RepsRPERestAdversarialTests.defaultStep_perEquipmentAndUnit` has a kettlebell arm.
   - **The other users of the step** each got a kettlebell test:
     - linear progression adds one bell size (12 → 16 kg in two weeks; 25 → 35 lb);
     - a deload rounds to a real bell (26 kg × 0.85 = 22.1 → 22 kg; 60 lb × 0.85 = 51 → 50 lb):
       `ProgressionRulesTests.prescribe_kettlebell_usesBellSteps`;
     - `Exercise.startLoad(in:)`'s cross-unit rounding lands on bells (35 lb → 16 kg,
       12 kg → 25 lb): `ExerciseTests.kettlebell_startLoadFallback_landsOnABell`.

     Plate math takes a load and a plate inventory, never the equipment, and decision #10
     limits it to barbells, so kettlebells cannot reach it.
   - **Onboarding** rounds `defaultStartLoad` to `Equipment.defaultStep`, so it follows. The
     F08 brief's rounding text and criterion 8 now name the 2 kg step.
   - **Other briefs.** F02's, F10's, F11's and F14's step wording now carries the same
     exception, so no brief contradicts the code, and decision #9 points to #22.
   - **Catalog kettlebell loads** are now standard bells: 12 kg / 25 lb and 8 kg / 15 lb.
3. **The SHA gap is closed (orchestrator): `scripts/check-catalog-version.sh`**, run by
   `check.sh` step 2 after the pins check.
   - **The base** is the merge base of HEAD with `origin/main`, or with `main` when there is no
     `origin/main`. The working tree is compared, so uncommitted edits count. `pr.yml` checks
     out full history (`fetch-depth: 0`, pinned by WF47), so CI has `origin/main`. Xcode Cloud
     does not run `check.sh`.
   - **It fails (exit 1)** when:
     - `exercises.json` differs from the base and `ExerciseCatalog.version` is not above the
       base's;
     - the version fell;
     - a line the base has in `catalog.version.sha` was edited, dropped or deleted.
   - **It exits 2** when there is no base, or no shared history, with a message saying what to
     fetch, or when it cannot read a version. A base that predates `ExerciseCatalog.swift`
     (today's main) counts as version 0.
   - **Tests.** The adversarial suite `catalog-version.adv.sh` has 17 cases (CV01–CV17) on
     throwaway repositories, including CI's case: an `origin/main` ahead of a stale local
     `main` must win. Four mutants of the script were each caught:
     - trying `main` before `origin/main`;
     - `<` for `<=`;
     - a prefix test for the history;
     - no history check at all.

     The wiring suite gained a stub, the new id in the full-gate order (W02 and W04 inject a
     failure there) and W57 for `--lint-only`.
   - **The SHA file stays.** The script only proves that the version rose. The SHA file adds
     three things:
     - it binds each version to its exact content, which F05 can use to tell which catalog a
       database was seeded from;
     - its test fails in plain `swift test` and Xcode, where no git base is consulted, so the
       editor hears about a missing bump before CI;
     - its history makes the per-version record reviewable.

     To keep both consistent, the history is now append-only against main: a PR adds one line
     for its version and may rewrite that line until it merges. The script enforces it, and the
     file's header and the JSON's `contributing` note say so. The test's failure message covers
     both cases: raise and append, or rewrite your own line.
4. **Accepted as they were:** `INC DB CURL` for Incline DB Curl, and the exclusions of assisted
   machines and timed holds.
5. **The version is bumped to 2**, and `2 <sha>` is appended. Line 1 records the first pass's
   content, which never reached main.

## Fix round 2 (2026-09-30)

The orchestrator's decisions on `review.md` (0 Blocking, 5 Should fix, 11 Nit) and `test-findings.md`
(finding 1 open), all applied.

**Review should-fixes**

- **S1, the version test.**
  - `versionSha_matchesFile` now requires a non-empty history whose versions start at 1 or more and
    rise, with gaps allowed, as the script allows (CV05). An empty history no longer traps
    (`1 ... 0`); it fails with "catalog.version.sha has no version lines".
  - Every non-comment, non-blank line must read `<version> <64 hex>`, or the test fails naming it.
- **S2, the script's message.** It now prints the exact line to append, `N+1 <sha>`, computed from
  the file at its repository path. The old relative `shasum -a 256 exercises.json`, which failed
  from the root, is gone from the message, the JSON note and the history file's header. CV02
  checks the printed line.
- **S3, id stability.** `scripts/check-catalog-version.sh` reads `id → name` from main's file and
  from the working tree, with `jq`, which check.sh step 2 already uses for the pins check. It
  fails, whatever the version, when:
  - an id main has is gone: an entry deleted or re-rolled;
  - a name main has now carries another id: a re-roll, or two entries swapping ids.

  Renaming an entry while keeping its id passes. main's placeholder file (no entries) reads as
  nothing to protect. Adversarial cases CV18 (re-roll), CV19 (deletion), CV20 (swap) and CV21
  (rename plus addition passes) were each mutation-checked.
- **S4, additive upgrades.** The JSON note, `ExerciseCatalog.version`'s doc and the brief's
  criterion 7 now say that an install with the catalog receives new entries only, and its
  existing rows stay as they are (F05). A correction to an existing entry therefore reaches new
  installs only. The note says to prefer adding and never to delete.
- **S5, specialty bars.** Each starts at its own empty weight: Safety Bar Squat 65 lb / 30 kg,
  Trap Bar Deadlift and Trap Bar Carry 55 lb / 25 kg. The trap bar's raised handles make it
  pullable empty, so the trap-bar deadlift leaves the floor-pull class. This is in decision #21's
  row, the `ExerciseCatalog` table and both policy oracles. The catalog has no other specialty
  bar. The EZ bar already has its own cell (25 lb / 10 kg), and landmine lifts count plates.

**Adversarial finding 1 (a key written twice loads silently): the file scan is the guard.** The
catalog is static data bundled with the app. `seed()` only ever reads that one file, and the data
tests scan its text on every test run (`entries_noKeyWrittenTwice`). Making the loader reject a
repeated key would need a hand-written JSON tokenizer: neither `JSONDecoder` nor
`JSONSerialization` reports repeats. That is a lot of loader code to guard a file already
guarded. The red loader test is retargeted: `CatalogDataAdversarialTests.duplicateKey_caughtByTheFileScan`
takes the bundled text, writes Barbell Bench Press's `shortName` a second time, and asserts that
the scan (`CatalogScan.repeatedKeys`, extracted from the tester's scan into
`CatalogAdversarialSupport`) reports exactly that key, and nothing on the untouched file.
`CatalogEntry`'s doc comment says repeats and unknown keys are the scan's job.

**Spec and content**

- **The clean's bell:** decision #21's row and the `ExerciseCatalog` doc now name cleans among the
  light-bell work (test finding 2).
- **Short names** are the Program builder's day-chip label (spec §3.2 item 9: "chip row of up to 4
  short exercise names (`CATALOG.sh`)"). The watch shows the full name (§4.3 `exName`). Fixed in
  the JSON note, first-pass item 7 and the test, now `shortNames_fitTheDayChips` (test finding 5).
- **F10:** one line in its Risks. A swap onto a kettlebell or other stepped equipment re-targets
  the undone sets to the replacement's step and sizes, because F04 rule 27 keeps targets (test
  finding 3; the review's F10 carry-forward).
- **Hip adduction:** Machine Hip Adduction is in, with Cable Hip Adduction and Copenhagen
  Adduction (reps) as its swaps; each takes the policy's cell (machine isolation 20 lb / 10 kg,
  cable small 10 lb / 5 kg, bodyweight). They are filed under **glutes**, beside the abduction
  machines, because `MuscleGroup` has no adductors. The hip abduction machine was already in, as
  "Machine Hip Abduction" (alias "Hip Abduction Machine"). A second entry would have duplicated
  it, so none was added.
- **The version is bumped to 3**, and `3 <sha>` is appended.
- **Aliases** follow decision #23 (Pete, 2026-09-30; F05 S2 records it): search matches name and
  short name only. Aliases remain the uniqueness guard. The JSON note, `CatalogEntry`'s doc and
  first-pass item 5 say so; no doc here calls them searchable.
- **Power Clean and Pendlay Row** stay at the empty bar, as the orchestrator decided.

**Nits fixed**

- **N2:**
  - "4 kg bell sizes" now reads "the 8, 12 and 16 kg bells beginners start on; kettlebells then
    step 2 kg";
  - `Exercise.defaultStep`'s doc folds in the kettlebell exception;
  - `seed()`'s doc names the Foundation read error and `Bundle.module`'s trap;
  - "Three things guard this" is now "Four", and the list names the id guard.
- **N3:** straight-bar isolation from a rack (shrug, calf raise, behind-the-back wrist curl) starts
  at the empty bar (45 lb / 20 kg), not the EZ bar.
- **N5:**
  - Machine Glute Kickback is back, as Cable Glute Kickback's first swap;
  - Cable Side Bend is new, replacing Kettlebell Windmill as Dumbbell Side Bend's swap;
  - Box Squat is now one of Safety Bar Squat's swaps, so no entry is an orphan.
- **N6:** added Incline Push-Up (Push-Up's first swap), Seal Row, Landmine Squat (landmine plates),
  Bicycle Crunch and Dumbbell Squat, each with swaps pointing both ways.
- **N7 (part):** `clash` has its own short name, `ZERCHER SQ`.
- **N8:** `ExerciseCatalogTests` reads and decodes the file once per run: a cached `Result` of a
  `Sendable` struct.
- **N9:** the no-shared-history error adds "(or the clone is shallow: fetch with fetch-depth: 0)".
- **N11:** `CatalogEntry`'s doc says that unknown and repeated keys are not the loader's job.
- **Test finding 8 (part):** Captain's Chair Knee Raise no longer carries "… Leg Raise" aliases,
  which named a different movement.

**Nits skipped, with reasons**

- **N1, collapse the history to version 1:** the orchestrator asked for a bump. Lines 1 and 2
  record this branch's earlier content and cost nothing. Versions only need to rise, and the
  script keeps the lines frozen once merged.
- **N4, floor-start lifts at the empty bar:** accepted by the orchestrator for Power Clean and
  Pendlay Row. Stiff-Leg Deadlift follows the same reasoning: it is started from the hang or
  blocks, and the error is on the light side.
- **N5, Leg Extension's swaps** (Sissy Squat, Reverse Nordic): there is no other equipment-light
  quad isolation worth a catalog entry. A band leg extension is rare in gyms.
- **N7, alternatives for `added` and `clash`:** these are F05 seed inputs, and seeding checks no
  alternatives. Giving them catalog ids needs a name lookup or pinned ids in test support, and
  F05 decides how a skipped clash is handled (test finding 9).
- **N10, `WTD PULL-UP` / `WTD DIP`:** `PULL-UP` and `DIP` are the prototype's `sh` for two of the 22
  spec entries. Pete accepted exactly one `sh` deviation (`INC DB CURL`), so changing design copy
  is his call.
- **Test finding 8, straight-bar lifts:** fixed as N3. **Knee raise versus leg raise:** fixed
  above.

**The tester's committed suites**, updated where fix round 2 changed what they pin:

- `CatalogLoadsAdversarialTests.PolicyOracle` gained the specialty bars, straight-bar isolation,
  Landmine Squat and cable hip adduction;
- `CatalogDataAdversarialTests` drops the exact `== 214` count (F12's count is live) and hosts
  the retargeted finding 1 test;
- `CatalogLoaderAdversarialTests` loses `duplicateKey_throws`, with a pointer to the new test;
- `CatalogAdversarialSupport` gains `CatalogScan`.

The shell suite needed no change: its `Raise it to 3` check still matches the new message.

## Decisions and deviations (first pass; items 1, 2 and 11 superseded above)

1. ~~The prototype's W0 for the 22 entries and beginner loads elsewhere.~~ Superseded by decision
   #21: conservative loads for all.
2. ~~kg = lb converted, catalog-wide, and the kettlebell step problem.~~ Superseded by decisions #21
   (kg chosen in kg) and #22 (kettlebell step 5 lb / 2 kg).
3. **Load conventions** (also in the `ExerciseCatalog` doc comment):
   - dumbbell and kettlebell loads are per implement, as in the prototype ("2 × 70 lb");
   - landmine lifts (T-Bar Row, Meadows Row, Landmine Press, Landmine Rotation) count the plates
     only;
   - band loads are the band's rated resistance;
   - carries count lengths as reps.
4. **`loadKind`.** It has one value, `"bodyweight"`, and appears exactly when both start loads
   are 0. It is allowed only on bodyweight equipment. The loader enforces all of this:
   - 36 pure-bodyweight entries carry `loadKind`;
   - the 3 weighted ones (Weighted Dip, Weighted Pull-Up and Weighted Chin-Up, each +10 lb / +5 kg
     under decision #21) give the added load and omit it.

   Because the rule works both ways, a misspelt `loadKind` still fails. `Exercise` has no field
   for `loadKind`, so the marker ends at validation: bodyweight equipment with a zero start
   carries the same meaning.
5. **Aliases stay in the DTO.** `Exercise` has no aliases, and the brief forbids changing it. So
   aliases (319 of them) do one job: they block a second entry under another name. Criterion 4
   compares them ignoring case. Pete decided on 2026-09-30 (decision #23, recorded by F05 S2) that
   search matches name and short name only; aliases are neither stored nor searched.
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
   characters. A short name is the Program builder's day-chip label (spec §3.2, "chip row of up
   to 4 short exercise names"); the watch shows the full name (spec §4.3, `exName`). Fix round 2
   corrected the first pass, which called it the watch label. All 22 prototype `sh` values are
   kept except one. **Deviation:** Incline DB Curl is `INC DB CURL`, not the prototype's
   `DB CURL`, so Dumbbell Curl can be `DB CURL` and an arm day never shows two identical labels.
   Prefixes follow the spec's abbreviations: DB, CB, MC, BW, plus KB and BAND.
8. **Alternatives follow criterion 3 over the prototype.** The §6.3 pairs are kept wherever they
   share a pattern. Three are dropped:
   - Low-to-High Cable Fly for Incline DB Press, because a fly is isolation and a press is not;
   - Straight-Arm Pulldown for Lat Pulldown, also isolation;
   - Assisted Pull-Up, which is excluded.

   Every entry has 2–5 alternatives, 647 in all. Most share the primary muscle. The exceptions
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
11. **Version history format.** `catalog.version.sha` is append-only. The test requires:
    - versions 1…n in order;
    - a distinct SHA per version;
    - the last version equal to `ExerciseCatalog.version`;
    - the last SHA equal to the file's.

    ~~The first pass's limit, a last line overwritten in place without a bump,~~ is closed by
    `scripts/check-catalog-version.sh` (decision 3 above).
12. **The version lives in Swift only.** The JSON's own `"version"` key is gone, so the Swift
    constant is the single source of truth, and F05 can compare it without decoding. The
    placeholder on `main` was never seeded. Content started at version 1 and is now 2.
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
15. **Count.** The first pass shipped 214 entries to match the design's "Search 214 exercises".
    F12 shows a live count, so that number bought nothing (review N6), and fix round 2 added ten:
    224. Cut in the first pass and still out: Jump Squat (a plyometric), Band Lateral Raise,
    Bayesian Cable Curl, Decline Dumbbell Press and Underhand Barbell Row. Machine Glute Kickback
    came back in fix round 2.
16. **File order**: entries are grouped by primary muscle in `MuscleGroup` order, then sorted by
    name. `seed()` returns file order.
17. **Decode time.** The brief's budget is under 20 ms on iPhone. `ExerciseCatalogPerformanceTests`
    follows `ReplayPerformanceTests` and runs on the nightly lane only. The host median, debug
    build, was **3.5 ms** in the first pass. The file is now 114,561 bytes against a 200 KB budget;
    the criterion 1 test checks the size.

## Pattern-assignment rules

The authoritative text is the doc comment on `ExerciseCatalog`. A pattern is the swap family: a
swap only offers the same pattern (decision #13).

| Pattern | Rule | Count |
|---|---|---|
| `horizontalPush` | Presses in front of the torso: flat, incline and decline presses, push-ups and dips. Dips stand in for a bench press, not an overhead press. | 22 |
| `verticalPush` | Presses overhead: overhead presses, the landmine press, pike and handstand push-ups. | 11 |
| `horizontalPull` | Rows to the torso. | 14 |
| `verticalPull` | Pull-ups, chin-ups and pulldowns. | 10 |
| `squat` | Two-legged, knee-dominant lifts: squats (front squat included), leg presses and hack squats. | 16 |
| `lunge` | Single-leg, knee-dominant lifts: lunges, split squats, step-ups and pistols. | 11 |
| `hinge` | Hip-dominant lifts on one leg or two: deadlifts (RDL included), good mornings, hip thrusts, bridges, swings, cleans, back extensions and pull-throughs. | 27 |
| `carry` | Loaded walks; reps count lengths. | 5 |
| `core` | Trunk work that is not a carry: crunches, sit-ups, leg raises, rollouts, Pallof presses, chops, side bends and the Turkish get-up. | 24 |
| `isolation` | Single-joint accessories, plus the small-muscle accessories whose only sensible swaps are other accessories for the same muscle: face pulls, upright rows, shrugs, pullovers and straight-arm pulldowns. | 84 |

## Deliberately excluded

| Excluded | Why |
|---|---|
| Assisted pull-up and assisted dip machines | The load is assistance, so more weight is easier. `Weight` has no negative load, and progression would add assistance. |
| Timed holds: plank, side plank, wall sit, dead hang, hollow hold, L-sit | The log records reps, not time (spec §6.1 `LoggedSet`). Carries stay in, because the pattern exists and load is what progresses. |
| Copenhagen plank | A timed hold. The hip adduction machine is **in** since fix round 2, with Cable Hip Adduction and Copenhagen Adduction (reps) as its swaps. `MuscleGroup` has no adductors (F02), so the three are filed under glutes, beside the abduction machines; an `adductors` group would be an F02 change and Pete's call (review G5). |
| Neck work | There is no neck group. |
| Sled push and pull, medicine ball, plate-only moves (plate front raise, plate pinch), wrist roller, rings or suspension trainer, battle ropes | There is no equipment type for them. A lifter can add them as custom exercises (F12). |
| Snatch and clean & jerk | Competition lifts, left for a later version. Power Clean and Hang Power Clean are in, because strength programs use them. |
| Technique variants: paused, tempo, deficit, pin, board, Spoto and Larsen presses, Zercher squat | Log these under the base lift. Box Squat and Rack Pull are in, because gyms and programs treat them as separate lifts. Zercher Squat is the fixture's custom exercise. |
| Plyometrics: jump squat, box jump | Not loaded lifts. |

## Counts

Primary muscle (criterion 5: at least 10 each, core at least 8):

| chest | back | shoulders | quads | hamstrings | glutes | calves | biceps | triceps | forearms | core |
|---|---|---|---|---|---|---|---|---|---|---|
| 23 | 33 | 27 | 30 | 13 | 24 | 11 | 13 | 14 | 10 | 26 |

Equipment (criterion 6: the minimum is in brackets):

| barbell (30) | dumbbell (40) | cable (25) | machine (25) | bodyweight (25) | kettlebell (10) | band (8) |
|---|---|---|---|---|---|---|
| 43 | 44 | 32 | 37 | 42 | 15 | 11 |

Forearms (10) sits exactly at its minimum, so removing one forearm entry fails criterion 5. That
is intended: the test protects the floor.

## Acceptance criteria → tests

All paths are under `LedgerKit/Tests/LedgerDomainTests/Catalog/`. The testing strategy names tests
`subject_condition_expectation` without a `test` prefix (§6), so the brief's `test_…` names are
mapped below.

| # | Brief's test | Test |
|---|---|---|
| 1 | `test_seedDecodesAllEntries` | `ExerciseCatalogTests.seed_decodesAllEntries` (at least 200 entries, all decoded in order, none custom, file ≤ 200 KB). The "throws, never skips" half is `CatalogEntryTests`: `brokenEntry_throws` (21 cases, one per `CatalogError` path), `undecodableDocument_throwsUnreadable` (9 cases) and `missingResource_throws`. |
| 2 (amended) | `test_prototypeEntriesUsePolicyLoads` | `ExerciseCatalogTests.prototypeEntries_usePolicyLoads`: 22 cases, each with its spec equipment, its policy loads in lb and kg (read off the table by hand), and its pinned id. |
| 3 | `test_alternativesResolveSamePattern` | `ExerciseCatalogTests.alternatives_resolveToSamePattern`, plus `isolationAlternatives_trainTheSamePrimaryMuscle` |
| 4 | `test_noDuplicateNamesOrAliases` | `ExerciseCatalogTests.namesAndAliases_haveNoDuplicates` |
| 5 | `test_muscleCoverage` | `ExerciseCatalogTests.muscleCoverage_meetsMinimum` (11 cases) |
| 6 | `test_equipmentCoverage` | `ExerciseCatalogTests.equipmentCoverage_meetsMinimum` (7 cases) |
| 7 | `test_versionShaMatchesFile` | `ExerciseCatalogTests.versionSha_matchesFile`: versions rise, gaps allowed, as the script allows; an empty or malformed history fails cleanly. Plus `scripts/check-catalog-version.sh` against main (version, history and, since fix round 2, ids), tested by `catalog-version.adv.sh` (CV01–CV21) and the tester's `catalog-version-attack.adv.sh` (V01–V21), and wired into step 2 (check-wiring W02, W04, W57) |
| 8 | fixture only (the contract test is F05's) | `CatalogSeedFixtureTests.upgrade_isAdditive`, `custom_clashesOnlyWithClash` |
| — | `test_startLoadsAreMultiplesOfStep` | `ExerciseCatalogTests.startLoads_areMultiplesOfStep`, plus `startLoads_followThePolicy` (decision #21, all 224 entries against `StartLoadPolicy`) |
| — | (decision #22) | `ExerciseTests.kettlebell_defaultStep`, `kettlebell_startLoadFallback_landsOnABell`; `ProgressionRulesTests.prescribe_kettlebell_usesBellSteps`; `RepsRPERestAdversarialTests.defaultStep_perEquipmentAndUnit` |
| — | `test_idsAreStableUUIDs` | `ExerciseCatalogTests.ids_areStableUUIDs`: the raw file's ids are canonical upper-case UUIDv4 strings and unique. Stability across versions: the script's id guard (CV18–CV21), and the pinned prototype ids. |
| — | adversarial finding 1 | `CatalogDataAdversarialTests.duplicateKey_caughtByTheFileScan` (retargeted from the loader; see "Fix round 2") and `entries_noKeyWrittenTwice` |
| — | (beyond the brief) | `ExerciseCatalogTests.shortNames_fitTheDayChips`; `CatalogEntryTests.validEntry_mapsEveryField`, `bodyweightEntries_decode`; `ExerciseCatalogPerformanceTests.seed_under20ms` (nightly) |

**Mutation checks**, run on the host; each time the file was restored byte for byte, and its SHA
matches `catalog.version.sha`:

- Fix round 1: raising the bench from 45 to 50 lb failed exactly three tests: criterion 2, the
  policy and criterion 7. Criterion 7's message read: `exercises.json changed. If this branch has
  not raised ExerciseCatalog.version yet, raise it to 3 and append "3 f168992b…" …`.
- First pass: renaming one alias failed only criterion 7.
- First pass: a trailing space in a short name made `seed()` throw `invalidText`, so the whole
  suite failed in its `init()`.
- Fix round 1: the script's four mutants, listed under decision 3, each failed at least one CV
  case.
- Fix round 2: two mutants of the id guard (the check disabled; the re-roll rule removed) each
  failed CV18–CV20 or CV18 and CV20. A comments-only history and a malformed history line each
  failed `versionSha_matchesFile` with one clean issue ("catalog.version.sha has no version
  lines", "bad line: …"), where the first pass trapped.

## Size

The measure is lines that are neither blank nor comment-only, per engineering standards §10.
Comments are `//` and `///` in Swift and `#` in shell. Whole new files were counted with
`grep -v '^[[:space:]]*$' FILE | grep -v '^[[:space:]]*//' | wc -l` (`#` for shell). Edits to
existing files were counted over the `+` lines of `git diff -U0 1d80613 -- FILE`, with the same
filters. All figures are for the branch against `main`, after fix round 2.

| Kind | File | Lines |
|---|---|---|
| Code | `Catalog/ExerciseCatalog.swift` | 51 |
| Code | `Catalog/CatalogEntry.swift` | 57 |
| Code | `Errors.swift` (`CatalogError`, added) | 13 |
| Code | `Model/Exercise.swift` (kettlebell step: one arm changed, one added) | 2 |
| Code | `Package.swift` (one resource declaration) | 1 |
| Code | `scripts/check-catalog-version.sh` | 87 |
| Code | `scripts/check.sh` (the step 2 call) | 1 |
| Code (test support) | `LedgerTestSupport/Catalog/CatalogSeedFixture.swift` | 46 |
| **Code total** | | **258**, under the 500-line target |
| Tests | the five files in `LedgerDomainTests/Catalog/` | 498 (206 + 178 + 65 + 32 + 17) |
| Tests | kettlebell additions in `ExerciseTests`, `ProgressionRulesTests`, `RepsRPERestAdversarialTests` | 32 (14 + 10 + 8) |
| Tests | `catalog-version.adv.sh`, plus the `check-wiring.adv.sh` additions | 99 (93 + 6) |
| Tests | fix round 2's edits to the tester's suites (`git diff --stat HEAD`) | +56 −18 |
| Data | `exercises.json` (`wc -l`; 114,561 bytes) | 2,739 |
| Data | `catalog.version.sha` (`wc -l`) | 7 |

The JSON is pretty-printed one key per line, 12–13 lines per entry, and nothing is compressed.

## Gate

**Fix round 2** was run on the final tree through the shared simulator lock:
`sim-lock.py scripts/check.sh 2>&1 | tee …/scratchpad/f03-fix2.log` (2026-09-30).

| Check | Result |
|---|---|
| Full `scripts/check.sh` (format, lint, graph, pins, catalog version and ids, script tests, iOS `PR`, watchOS `PR-Watch`, coverage) | **OK**, 277 s |
| Step 2's catalog check | "exercise catalog changed since origin/main (1d80613): version 0 -> 3" |
| Script suites | `catalog-version.adv.sh` 21/21, `catalog-version-attack.adv.sh` 24/24, `check-wiring.adv.sh` 105/105 |
| iOS result bundle (`xcresulttool … PR-iOS.xcresult`) | **Passed**: 967 tests, 0 failed, 3 skipped (the nightly-lane suites), iPhone 17 (27.0). The tester's suites are included, and the finding 1 test is green. |
| watchOS result bundle (`… PR-watchOS.xcresult`) | **Passed**: 892 tests, 0 failed, 3 skipped, Apple Watch Series 12 (46 mm) (27.0) |
| Coverage gate | LedgerDomain **99.01 %** (1,817 / 1,835 lines; threshold 95 %); overall 98.12 % |
| Changed files (`xccov`, both platforms) | `ExerciseCatalog.swift` 46 / 46, `CatalogEntry.swift` 37 / 37, `Exercise.swift` 31 / 31 |
| `scripts/check.sh --fast` (before the full gate) | **OK**: 751 tests in 123 suites |

**Earlier rounds:**

- **Fix round 1** (`4d7cf28`): the full gate was OK in 267 s. iOS ran 926 tests and watchOS 851,
  none failed.
- **First pass** (`d80602f`): the full gate was OK in 317 s. iOS ran 923 tests and watchOS 848,
  none failed.

## How to verify by hand

1. Run `swift test --package-path LedgerKit --filter 'ExerciseCatalog|CatalogEntry|CatalogSeedFixture|ExerciseTests|ProgressionRules'`.
2. Run `shasum -a 256 LedgerKit/Sources/LedgerDomain/Resources/exercises.json`. It must equal the
   last line of `catalog.version.sha`.
3. Edit any character of `exercises.json` and rerun step 1. `versionSha_matchesFile` fails and
   names the line to append. `scripts/check-catalog-version.sh` still passes on this branch,
   because version 2 is above main's 0; on a branch off a main that already holds version 2, it
   would fail. Revert the edit.
3a. Run `bash scripts/tests/adversarial/catalog-version.adv.sh` (21 cases) and
    `bash scripts/tests/adversarial/catalog-version-attack.adv.sh` (24 cases): all `ok`.
3b. For the id guard, change one `"id"` in `exercises.json` to a fresh `uuidgen` value and run
    `scripts/check-catalog-version.sh`. On this branch it passes, because main has no ids yet;
    CV18 shows the failure on a branch off a main that has them. Revert the edit.
4. Recount from the file:
   `jq '.exercises | group_by(.primaryMuscle) | map({(.[0].primaryMuscle): length}) | add' LedgerKit/Sources/LedgerDomain/Resources/exercises.json`
   (use `.equipment` or `.pattern` for the other counts).
5. Time the decode with
   `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter ExerciseCatalogPerformanceTests`.
6. Read the appendix below. It is the catalog as a lifter would review it.

## Appendix: the catalog (version 3)

Generated from `exercises.json` version 3 for review; the JSON is the source of truth. Loads follow
decision #21's policy. "BW" means bodyweight, a zero start with `loadKind`; "+n" is added load. Patterns
are abbreviated: h-push, h-pull, v-push, v-pull.

#### Chest (23)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Barbell Bench Press | BENCH | barbell | h-push | triceps, shoulders | 45 / 20 | Dumbbell Bench Press; Smith Machine Bench Press; Weighted Dip; Machine Chest Press | Bench Press; Flat Bench Press |
| Barbell Floor Press | FLOOR PRESS | barbell | h-push | triceps, shoulders | 45 / 20 | Dumbbell Floor Press; Kettlebell Floor Press; Barbell Bench Press | Floor Press |
| Cable Chest Press | CB PRESS | cable | h-push | triceps, shoulders | 30 / 15 | Machine Chest Press; Dumbbell Bench Press; Push-Up | Standing Cable Chest Press; Standing Cable Press |
| Cable Crossover | CROSSOVER | cable | isolation | shoulders | 20 / 10 | Low-to-High Cable Fly; Pec Deck; Dumbbell Fly | Cable Fly; High-to-Low Cable Fly; Standing Cable Fly |
| Decline Bench Press | DEC BENCH | barbell | h-push | triceps, shoulders | 45 / 20 | Barbell Bench Press; Weighted Dip; Dip | Decline Barbell Bench Press |
| Decline Push-Up | DEC PUSH-UP | bodyweight | h-push | shoulders, triceps | BW | Push-Up; Dip; Incline DB Press | Feet-Elevated Push-Up |
| Dip | BW DIP | bodyweight | h-push | triceps, shoulders | BW | Weighted Dip; Push-Up; Machine Dip | Parallel Bar Dip; Chest Dip; Bar Dip |
| Dumbbell Bench Press | DB BENCH | dumbbell | h-push | triceps, shoulders | 15 / 7.5 | Barbell Bench Press; Machine Chest Press; Incline DB Press; Dumbbell Floor Press | DB Bench Press; Flat Dumbbell Press; Dumbbell Chest Press |
| Dumbbell Floor Press | DB FLOOR | dumbbell | h-push | triceps, shoulders | 15 / 7.5 | Barbell Floor Press; Kettlebell Floor Press; Dumbbell Bench Press | — |
| Dumbbell Fly | DB FLY | dumbbell | isolation | shoulders | 10 / 5 | Pec Deck; Cable Crossover; Incline Dumbbell Fly | Dumbbell Flye; Flat Dumbbell Fly |
| Incline Bench Press | INC BENCH | barbell | h-push | shoulders, triceps | 45 / 20 | Incline DB Press; Smith Machine Incline Press; Machine Incline Press | Incline Barbell Press; Incline Barbell Bench Press |
| Incline DB Press | INCLINE | dumbbell | h-push | shoulders, triceps | 15 / 7.5 | Incline Bench Press; Machine Incline Press; Smith Machine Incline Press; Dumbbell Bench Press | Incline Dumbbell Press; Incline Dumbbell Bench Press |
| Incline Dumbbell Fly | INC DB FLY | dumbbell | isolation | shoulders | 10 / 5 | Low-to-High Cable Fly; Dumbbell Fly; Pec Deck | Incline Dumbbell Flye; Incline DB Fly |
| Incline Push-Up | INC PUSH-UP | bodyweight | h-push | triceps, shoulders | BW | Push-Up; Machine Chest Press; Dumbbell Bench Press | Hands-Elevated Push-Up |
| Kettlebell Floor Press | KB FLOOR | kettlebell | h-push | triceps, shoulders | 15 / 8 | Dumbbell Floor Press; Barbell Floor Press; Push-Up | — |
| Low-to-High Cable Fly | FLY | cable | isolation | shoulders | 20 / 10 | Cable Crossover; Incline Dumbbell Fly; Pec Deck | Low Cable Fly; Low-to-High Cable Crossover |
| Machine Chest Press | CHEST PRESS | machine | h-push | triceps, shoulders | 40 / 20 | Barbell Bench Press; Dumbbell Bench Press; Smith Machine Bench Press; Cable Chest Press | Chest Press Machine; Seated Chest Press |
| Machine Incline Press | MC INCLINE | machine | h-push | shoulders, triceps | 40 / 20 | Incline DB Press; Incline Bench Press; Smith Machine Incline Press | Incline Chest Press Machine; Incline Machine Press |
| Pec Deck | PEC DECK | machine | isolation | shoulders | 20 / 10 | Cable Crossover; Dumbbell Fly; Low-to-High Cable Fly | Pec Deck Fly; Machine Fly; Butterfly |
| Push-Up | PUSH-UP | bodyweight | h-push | triceps, shoulders, core | BW | Incline Push-Up; Decline Push-Up; Dumbbell Bench Press; Cable Chest Press; Dip | Pushup; Press-Up |
| Smith Machine Bench Press | SMITH BENCH | machine | h-push | triceps, shoulders | 40 / 20 | Barbell Bench Press; Machine Chest Press; Dumbbell Bench Press | Smith Machine Press; Smith Bench Press |
| Smith Machine Incline Press | SMITH INCLINE | machine | h-push | shoulders, triceps | 40 / 20 | Incline Bench Press; Machine Incline Press; Incline DB Press | Smith Machine Incline Bench Press; Smith Incline Press |
| Weighted Dip | DIP | bodyweight | h-push | triceps, shoulders | +10 / +5 | Dip; Barbell Bench Press; Machine Dip; Decline Bench Press | Weighted Chest Dip; Weighted Parallel Bar Dip |

#### Back (33)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Back Extension | BACK EXT | bodyweight | hinge | glutes, hamstrings | BW | Machine Back Extension; Reverse Hyperextension; Good Morning | Hyperextension; 45-Degree Back Extension; Roman Chair Back Extension |
| Band Row | BAND ROW | band | h-pull | biceps, shoulders | 20 / 10 | Seated Cable Row; Inverted Row; Kettlebell Row | Seated Band Row; Resistance Band Row |
| Barbell Row | ROW | barbell | h-pull | biceps, shoulders | 45 / 20 | Seated Cable Row; Single-Arm Dumbbell Row; Chest-Supported Row; Pendlay Row | Bent-Over Row; Bent-Over Barbell Row |
| Barbell Shrug | SHRUG | barbell | isolation | forearms | 45 / 20 | Dumbbell Shrug; Cable Shrug | Shrug |
| Cable Shrug | CB SHRUG | cable | isolation | forearms | 20 / 10 | Barbell Shrug; Dumbbell Shrug | — |
| Chest-Supported Dumbbell Row | CS DB ROW | dumbbell | h-pull | biceps, shoulders | 15 / 7.5 | Chest-Supported Row; Single-Arm Dumbbell Row; Seated Cable Row; Seal Row | Incline Dumbbell Row; Prone Dumbbell Row |
| Chest-Supported Row | CS ROW | machine | h-pull | biceps, shoulders | 40 / 20 | Seated Cable Row; Single-Arm Dumbbell Row; Barbell Row; Chest-Supported Dumbbell Row | Machine Row; Seated Row Machine; Chest-Supported Machine Row |
| Chin-Up | CHIN-UP | bodyweight | v-pull | biceps | BW | Reverse-Grip Lat Pulldown; Pull-Up; Weighted Chin-Up; Neutral-Grip Pull-Up | Chinup; Underhand Pull-Up |
| Dumbbell Bent-Over Row | DB BO ROW | dumbbell | h-pull | biceps, shoulders | 15 / 7.5 | Barbell Row; Chest-Supported Dumbbell Row; Kettlebell Row | Bent-Over Dumbbell Row; Two-Arm Dumbbell Row |
| Dumbbell Pullover | DB PULLOVER | dumbbell | isolation | chest, triceps | 10 / 5 | Straight-Arm Pulldown; Machine Pullover | DB Pullover |
| Dumbbell Shrug | DB SHRUG | dumbbell | isolation | forearms | 10 / 5 | Barbell Shrug; Cable Shrug | — |
| Inverted Row | INV ROW | bodyweight | h-pull | biceps, shoulders | BW | Seated Cable Row; Band Row; Single-Arm Dumbbell Row | Bodyweight Row; Australian Pull-Up |
| Kettlebell Row | KB ROW | kettlebell | h-pull | biceps, shoulders | 15 / 8 | Single-Arm Dumbbell Row; Dumbbell Bent-Over Row; Band Row | Single-Arm Kettlebell Row |
| Lat Pulldown | PULLDOWN | cable | v-pull | biceps, shoulders | 30 / 15 | Neutral-Grip Pulldown; Pull-Up; Machine Pulldown; Single-Arm Lat Pulldown | Wide-Grip Lat Pulldown; Wide-Grip Pulldown |
| Machine Back Extension | MC BACK EXT | machine | hinge | glutes, hamstrings | 40 / 20 | Back Extension; Reverse Hyperextension; Good Morning | Back Extension Machine; Seated Back Extension |
| Machine Pulldown | MC PULLDOWN | machine | v-pull | biceps | 40 / 20 | Lat Pulldown; Neutral-Grip Pulldown; Pull-Up | Machine Lat Pulldown; Plate-Loaded Pulldown |
| Machine Pullover | MC PULLOVER | machine | isolation | chest, triceps | 20 / 10 | Dumbbell Pullover; Straight-Arm Pulldown | Pullover Machine |
| Meadows Row | MEADOWS | barbell | h-pull | biceps, shoulders | 10 / 5 | Single-Arm Dumbbell Row; T-Bar Row; Single-Arm Cable Row | — |
| Neutral-Grip Pull-Up | NG PULL-UP | bodyweight | v-pull | biceps | BW | Neutral-Grip Pulldown; Pull-Up; Chin-Up | Hammer-Grip Pull-Up; Parallel-Grip Pull-Up |
| Neutral-Grip Pulldown | NG PULLDOWN | cable | v-pull | biceps | 30 / 15 | Lat Pulldown; Neutral-Grip Pull-Up; Reverse-Grip Lat Pulldown | Close-Grip Lat Pulldown; Close-Grip Pulldown; V-Bar Pulldown |
| Pendlay Row | PENDLAY | barbell | h-pull | biceps, shoulders | 45 / 20 | Barbell Row; T-Bar Row; Dumbbell Bent-Over Row | — |
| Pull-Up | BW PULL-UP | bodyweight | v-pull | biceps, forearms | BW | Lat Pulldown; Weighted Pull-Up; Chin-Up; Neutral-Grip Pull-Up | Pullup; Overhand Pull-Up |
| Rack Pull | RACK PULL | barbell | hinge | glutes, hamstrings, forearms | 95 / 40 | Deadlift; Trap Bar Deadlift; Romanian Deadlift | Block Pull |
| Reverse-Grip Lat Pulldown | RG PULLDOWN | cable | v-pull | biceps | 30 / 15 | Chin-Up; Neutral-Grip Pulldown; Lat Pulldown | Underhand Lat Pulldown; Supinated Lat Pulldown |
| Seal Row | SEAL ROW | barbell | h-pull | biceps, shoulders | 45 / 20 | Chest-Supported Row; Chest-Supported Dumbbell Row; Barbell Row | Barbell Seal Row |
| Seated Cable Row | CABLE ROW | cable | h-pull | biceps, shoulders | 30 / 15 | Chest-Supported Row; Single-Arm Dumbbell Row; Barbell Row; Single-Arm Cable Row | Cable Row; Low Cable Row; Seated Row |
| Single-Arm Cable Row | SA CABLE ROW | cable | h-pull | biceps, shoulders | 30 / 15 | Seated Cable Row; Single-Arm Dumbbell Row; Meadows Row | One-Arm Cable Row |
| Single-Arm Dumbbell Row | DB ROW | dumbbell | h-pull | biceps, shoulders | 15 / 7.5 | Chest-Supported Row; Single-Arm Cable Row; Barbell Row; Kettlebell Row | Dumbbell Row; One-Arm Dumbbell Row; Single-Arm DB Row |
| Single-Arm Lat Pulldown | SA PULLDOWN | cable | v-pull | biceps | 30 / 15 | Lat Pulldown; Neutral-Grip Pulldown; Machine Pulldown | One-Arm Lat Pulldown; Single-Arm Cable Pulldown |
| Straight-Arm Pulldown | STRAIGHT ARM | cable | isolation | triceps, core | 20 / 10 | Dumbbell Pullover; Machine Pullover | Straight-Arm Lat Pulldown; Straight-Arm Cable Pulldown; Cable Pullover |
| T-Bar Row | T-BAR ROW | barbell | h-pull | biceps, shoulders | 10 / 5 | Barbell Row; Chest-Supported Row; Meadows Row | Landmine Row |
| Weighted Chin-Up | WTD CHIN-UP | bodyweight | v-pull | biceps | +10 / +5 | Chin-Up; Weighted Pull-Up; Reverse-Grip Lat Pulldown | Weighted Chinup |
| Weighted Pull-Up | PULL-UP | bodyweight | v-pull | biceps, forearms | +10 / +5 | Pull-Up; Lat Pulldown; Weighted Chin-Up; Machine Pulldown | Weighted Pullup |

#### Shoulders (27)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Arnold Press | ARNOLD | dumbbell | v-push | triceps | 15 / 7.5 | Seated Dumbbell Shoulder Press; Machine Shoulder Press; Kettlebell Overhead Press | Arnold Dumbbell Press |
| Band External Rotation | BAND EXT ROT | band | isolation | — | 5 / 2.5 | Cable External Rotation; Band Face Pull | Band Shoulder External Rotation |
| Band Face Pull | BAND FACE PULL | band | isolation | back | 10 / 5 | Face Pull; Band Pull-Apart; Cable Rear Delt Fly | — |
| Band Overhead Press | BAND OHP | band | v-push | triceps | 20 / 10 | Pike Push-Up; Seated Dumbbell Shoulder Press; Kettlebell Overhead Press | Band Shoulder Press |
| Band Pull-Apart | PULL-APART | band | isolation | back | 5 / 2.5 | Band Face Pull; Dumbbell Rear Delt Fly; Rear Delt Fly | Resistance Band Pull-Apart |
| Barbell Upright Row | UPRIGHT ROW | barbell | isolation | back, biceps | 25 / 10 | Cable Upright Row; Dumbbell Upright Row; Dumbbell Lateral Raise | Upright Row |
| Cable External Rotation | CB EXT ROT | cable | isolation | — | 10 / 5 | Band External Rotation; Face Pull | Cable Shoulder External Rotation |
| Cable Front Raise | CB FRONT | cable | isolation | chest | 10 / 5 | Dumbbell Front Raise; Cable Lateral Raise | — |
| Cable Lateral Raise | LATERAL | cable | isolation | — | 10 / 5 | Dumbbell Lateral Raise; Machine Lateral Raise; Cable Upright Row | Single-Arm Cable Lateral Raise |
| Cable Rear Delt Fly | CB REAR DELT | cable | isolation | back | 10 / 5 | Rear Delt Fly; Dumbbell Rear Delt Fly; Face Pull | Cable Reverse Fly; Reverse Cable Crossover |
| Cable Upright Row | CB UPRIGHT | cable | isolation | back, biceps | 20 / 10 | Barbell Upright Row; Cable Lateral Raise; Dumbbell Upright Row | Rope Upright Row |
| Dumbbell Front Raise | DB FRONT | dumbbell | isolation | chest | 5 / 2.5 | Cable Front Raise; Dumbbell Lateral Raise | Front Raise; Front Dumbbell Raise |
| Dumbbell Lateral Raise | DB LATERAL | dumbbell | isolation | — | 5 / 2.5 | Cable Lateral Raise; Machine Lateral Raise; Dumbbell Upright Row | DB Lateral Raise; Lateral Raise; Side Lateral Raise; Side Raise |
| Dumbbell Rear Delt Fly | DB REAR DELT | dumbbell | isolation | back | 5 / 2.5 | Rear Delt Fly; Cable Rear Delt Fly; Band Pull-Apart; Face Pull | Bent-Over Reverse Fly; Dumbbell Reverse Fly; Bent-Over Rear Delt Raise |
| Dumbbell Upright Row | DB UPRIGHT | dumbbell | isolation | back, biceps | 10 / 5 | Barbell Upright Row; Cable Upright Row; Dumbbell Lateral Raise | — |
| Face Pull | FACE PULL | cable | isolation | back | 20 / 10 | Band Face Pull; Rear Delt Fly; Cable Rear Delt Fly | Rope Face Pull; Cable Face Pull |
| Handstand Push-Up | HSPU | bodyweight | v-push | triceps | BW | Pike Push-Up; Overhead Press; Machine Shoulder Press | HSPU; Wall Handstand Push-Up |
| Kettlebell Overhead Press | KB PRESS | kettlebell | v-push | triceps, core | 15 / 8 | Seated Dumbbell Shoulder Press; Arnold Press; Landmine Press | Kettlebell Press; Single-Arm Kettlebell Press |
| Landmine Press | LANDMINE | barbell | v-push | chest, triceps | 10 / 5 | Overhead Press; Seated Dumbbell Shoulder Press; Kettlebell Overhead Press | Single-Arm Landmine Press; Landmine Shoulder Press |
| Machine Lateral Raise | MC LATERAL | machine | isolation | — | 10 / 5 | Cable Lateral Raise; Dumbbell Lateral Raise | Lateral Raise Machine |
| Machine Shoulder Press | MC OHP | machine | v-push | triceps | 40 / 20 | Seated Dumbbell Shoulder Press; Overhead Press; Smith Machine Overhead Press | Shoulder Press Machine; Seated Machine Shoulder Press |
| Overhead Press | OHP | barbell | v-push | triceps, core | 45 / 20 | Seated Dumbbell Shoulder Press; Machine Shoulder Press; Push Press; Landmine Press | OHP; Standing Overhead Press; Military Press; Strict Press; Barbell Overhead Press |
| Pike Push-Up | PIKE PUSH-UP | bodyweight | v-push | triceps | BW | Handstand Push-Up; Seated Dumbbell Shoulder Press; Band Overhead Press | Pike Pushup |
| Push Press | PUSH PRESS | barbell | v-push | triceps, quads | 45 / 20 | Overhead Press; Landmine Press; Seated Dumbbell Shoulder Press | — |
| Rear Delt Fly | REAR DELT | machine | isolation | back | 10 / 5 | Dumbbell Rear Delt Fly; Cable Rear Delt Fly; Face Pull | Reverse Pec Deck; Machine Rear Delt Fly; Reverse Fly Machine |
| Seated Dumbbell Shoulder Press | DB OHP | dumbbell | v-push | triceps | 15 / 7.5 | Overhead Press; Arnold Press; Machine Shoulder Press | Seated Dumbbell Press; Dumbbell Shoulder Press; Dumbbell Overhead Press; Seated DB Press |
| Smith Machine Overhead Press | SMITH OHP | machine | v-push | triceps | 40 / 20 | Overhead Press; Machine Shoulder Press; Seated Dumbbell Shoulder Press | Smith Machine Shoulder Press; Smith Shoulder Press |

#### Quads (30)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Back Squat | SQUAT | barbell | squat | glutes, hamstrings | 45 / 20 | Front Squat; Safety Bar Squat; Leg Press; Hack Squat; Smith Machine Squat | Barbell Back Squat; Squat; High-Bar Squat; Low-Bar Squat |
| Barbell Lunge | BB LUNGE | barbell | lunge | glutes, hamstrings | 45 / 20 | Dumbbell Lunge; Barbell Split Squat; Dumbbell Walking Lunge | Barbell Forward Lunge |
| Barbell Split Squat | BB SPLIT SQ | barbell | lunge | glutes | 45 / 20 | Dumbbell Split Squat; Dumbbell Bulgarian Split Squat; Barbell Lunge | — |
| Belt Squat | BELT SQUAT | machine | squat | glutes | 40 / 20 | Hack Squat; Leg Press; Goblet Squat; Landmine Squat | Belt Squat Machine |
| Bodyweight Lunge | BW LUNGE | bodyweight | lunge | glutes | BW | Dumbbell Lunge; Dumbbell Walking Lunge; Pistol Squat | Lunge; Forward Lunge |
| Bodyweight Squat | BW SQUAT | bodyweight | squat | glutes | BW | Goblet Squat; Kettlebell Goblet Squat | Air Squat |
| Box Squat | BOX SQUAT | barbell | squat | glutes, hamstrings | 45 / 20 | Back Squat; Safety Bar Squat; Belt Squat | Barbell Box Squat |
| Dumbbell Bulgarian Split Squat | BULGARIAN | dumbbell | lunge | glutes | 15 / 7.5 | Dumbbell Split Squat; Dumbbell Reverse Lunge; Barbell Split Squat | Bulgarian Split Squat; Rear-Foot-Elevated Split Squat; RFESS |
| Dumbbell Lunge | DB LUNGE | dumbbell | lunge | glutes | 15 / 7.5 | Dumbbell Reverse Lunge; Dumbbell Walking Lunge; Barbell Lunge | Dumbbell Forward Lunge |
| Dumbbell Reverse Lunge | DB REV LUNGE | dumbbell | lunge | glutes | 15 / 7.5 | Dumbbell Lunge; Kettlebell Reverse Lunge; Dumbbell Split Squat | Reverse Lunge |
| Dumbbell Split Squat | DB SPLIT SQ | dumbbell | lunge | glutes | 15 / 7.5 | Dumbbell Bulgarian Split Squat; Barbell Split Squat; Dumbbell Reverse Lunge | Split Squat |
| Dumbbell Squat | DB SQUAT | dumbbell | squat | glutes | 15 / 7.5 | Goblet Squat; Kettlebell Goblet Squat; Bodyweight Squat | — |
| Dumbbell Step-Up | STEP-UP | dumbbell | lunge | glutes | 15 / 7.5 | Dumbbell Reverse Lunge; Dumbbell Bulgarian Split Squat | Step-Up; Box Step-Up |
| Dumbbell Walking Lunge | WALK LUNGE | dumbbell | lunge | glutes | 15 / 7.5 | Dumbbell Lunge; Barbell Lunge; Bodyweight Lunge | Walking Lunge |
| Front Squat | FRONT SQ | barbell | squat | glutes, core | 45 / 20 | Back Squat; Goblet Squat; Hack Squat; Kettlebell Front Squat | Barbell Front Squat |
| Goblet Squat | GOBLET | dumbbell | squat | glutes, core | 15 / 7.5 | Kettlebell Goblet Squat; Dumbbell Squat; Front Squat; Leg Press | Dumbbell Goblet Squat |
| Hack Squat | HACK SQUAT | machine | squat | glutes | 40 / 20 | Leg Press; Pendulum Squat; Front Squat; Smith Machine Squat | Machine Hack Squat |
| Kettlebell Front Squat | KB FRONT SQ | kettlebell | squat | glutes, core | 25 / 12 | Front Squat; Kettlebell Goblet Squat; Goblet Squat | Double Kettlebell Front Squat |
| Kettlebell Goblet Squat | KB GOBLET | kettlebell | squat | glutes, core | 25 / 12 | Goblet Squat; Kettlebell Front Squat; Bodyweight Squat | — |
| Kettlebell Reverse Lunge | KB REV LUNGE | kettlebell | lunge | glutes | 25 / 12 | Dumbbell Reverse Lunge; Dumbbell Lunge; Bodyweight Lunge | — |
| Landmine Squat | LANDMINE SQ | barbell | squat | glutes, core | 10 / 5 | Goblet Squat; Belt Squat; Front Squat | — |
| Leg Extension | LEG EXT | machine | isolation | — | 20 / 10 | Sissy Squat; Reverse Nordic | Machine Leg Extension; Quad Extension |
| Leg Press | LEG PRESS | machine | squat | glutes | 40 / 20 | Hack Squat; Seated Leg Press; Back Squat; Pendulum Squat | 45-Degree Leg Press; Sled Leg Press |
| Pendulum Squat | PENDULUM | machine | squat | glutes | 40 / 20 | Hack Squat; Leg Press; Belt Squat | — |
| Pistol Squat | PISTOL | bodyweight | lunge | glutes, core | BW | Dumbbell Bulgarian Split Squat; Bodyweight Lunge; Dumbbell Step-Up | Single-Leg Squat |
| Reverse Nordic | REV NORDIC | bodyweight | isolation | — | BW | Sissy Squat; Leg Extension | Reverse Nordic Curl |
| Safety Bar Squat | SSB SQUAT | barbell | squat | glutes, back | 65 / 30 | Back Squat; Box Squat; Front Squat; Belt Squat | SSB Squat; Safety Squat Bar Squat |
| Seated Leg Press | MC LEG PRESS | machine | squat | glutes | 40 / 20 | Leg Press; Hack Squat; Belt Squat | Horizontal Leg Press |
| Sissy Squat | SISSY SQUAT | bodyweight | isolation | — | BW | Leg Extension; Reverse Nordic | — |
| Smith Machine Squat | SMITH SQUAT | machine | squat | glutes | 40 / 20 | Back Squat; Hack Squat; Leg Press | Smith Squat |

#### Hamstrings (13)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Good Morning | BAND GM | band | hinge | glutes, back | 20 / 10 | Good Morning; Band Pull-Through; Back Extension | — |
| Deadlift | DEADLIFT | barbell | hinge | glutes, back, forearms | 95 / 40 | Trap Bar Deadlift; Sumo Deadlift; Romanian Deadlift; Rack Pull | Conventional Deadlift; Barbell Deadlift |
| Dumbbell Romanian Deadlift | DB RDL | dumbbell | hinge | glutes, back | 15 / 7.5 | Romanian Deadlift; Single-Leg Romanian Deadlift; Kettlebell Deadlift | DB RDL; Dumbbell RDL |
| Glute-Ham Raise | GHR | bodyweight | isolation | glutes, calves | BW | Nordic Hamstring Curl; Lying Leg Curl; Seated Leg Curl | GHR; Glute Ham Raise |
| Good Morning | GOOD MORNING | barbell | hinge | glutes, back | 45 / 20 | Romanian Deadlift; Stiff-Leg Deadlift; Band Good Morning; Back Extension | Barbell Good Morning |
| Kettlebell Single-Leg Deadlift | KB SL RDL | kettlebell | hinge | glutes, core | 25 / 12 | Single-Leg Romanian Deadlift; Kettlebell Deadlift; Dumbbell Romanian Deadlift | Single-Leg Kettlebell Deadlift; Kettlebell Single-Leg RDL |
| Lying Leg Curl | LYING CURL | machine | isolation | calves | 20 / 10 | Seated Leg Curl; Standing Leg Curl; Nordic Hamstring Curl | Prone Leg Curl; Lying Hamstring Curl |
| Nordic Hamstring Curl | NORDIC | bodyweight | isolation | glutes, calves | BW | Glute-Ham Raise; Lying Leg Curl; Seated Leg Curl | Nordic Curl |
| Romanian Deadlift | RDL | barbell | hinge | glutes, back | 45 / 20 | Dumbbell Romanian Deadlift; Stiff-Leg Deadlift; Good Morning | RDL; Barbell RDL; Barbell Romanian Deadlift |
| Seated Leg Curl | LEG CURL | machine | isolation | calves | 20 / 10 | Lying Leg Curl; Standing Leg Curl; Nordic Hamstring Curl | Seated Hamstring Curl |
| Single-Leg Romanian Deadlift | SL RDL | dumbbell | hinge | glutes, core | 15 / 7.5 | Kettlebell Single-Leg Deadlift; Dumbbell Romanian Deadlift | Single-Leg RDL; Single-Leg Dumbbell RDL |
| Standing Leg Curl | ST LEG CURL | machine | isolation | calves | 20 / 10 | Seated Leg Curl; Lying Leg Curl | Standing Hamstring Curl |
| Stiff-Leg Deadlift | SLDL | barbell | hinge | glutes, back | 45 / 20 | Romanian Deadlift; Dumbbell Romanian Deadlift; Good Morning | Stiff-Legged Deadlift; SLDL |

#### Glutes (24)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Pull-Through | BAND PULL-THRU | band | hinge | hamstrings | 20 / 10 | Cable Pull-Through; Kettlebell Swing; Band Good Morning | — |
| Banded Lateral Walk | LATERAL WALK | band | isolation | — | 10 / 5 | Machine Hip Abduction; Cable Hip Abduction | Band Lateral Walk; Band Side Walk; Monster Walk |
| Barbell Glute Bridge | BB BRIDGE | barbell | hinge | hamstrings | 45 / 20 | Hip Thrust; Glute Bridge; Machine Hip Thrust | — |
| Cable Glute Kickback | GLUTE KICK | cable | isolation | hamstrings | 10 / 5 | Machine Glute Kickback; Cable Hip Abduction; Banded Lateral Walk | Glute Kickback |
| Cable Hip Abduction | CB ABDUCTION | cable | isolation | — | 10 / 5 | Machine Hip Abduction; Banded Lateral Walk; Cable Glute Kickback | Standing Cable Hip Abduction |
| Cable Hip Adduction | CB ADDUCTION | cable | isolation | — | 10 / 5 | Machine Hip Adduction; Copenhagen Adduction | Standing Cable Hip Adduction |
| Cable Pull-Through | PULL-THROUGH | cable | hinge | hamstrings | 30 / 15 | Band Pull-Through; Kettlebell Swing; Hip Thrust | — |
| Copenhagen Adduction | COPENHAGEN | bodyweight | isolation | core | BW | Machine Hip Adduction; Cable Hip Adduction | Copenhagen Hip Adduction |
| Glute Bridge | GLUTE BRIDGE | bodyweight | hinge | hamstrings | BW | Barbell Glute Bridge; Single-Leg Hip Thrust; Hip Thrust | Bodyweight Glute Bridge; Hip Bridge |
| Hang Power Clean | HANG CLEAN | barbell | hinge | hamstrings, quads, back | 45 / 20 | Power Clean; Kettlebell Clean | Hang Clean |
| Hip Thrust | HIP THRUST | barbell | hinge | hamstrings | 45 / 20 | Machine Hip Thrust; Barbell Glute Bridge; Single-Leg Hip Thrust | Barbell Hip Thrust |
| Kettlebell Clean | KB CLEAN | kettlebell | hinge | hamstrings, shoulders | 15 / 8 | Kettlebell Swing; Kettlebell Snatch; Hang Power Clean | — |
| Kettlebell Deadlift | KB DEADLIFT | kettlebell | hinge | hamstrings, quads | 25 / 12 | Kettlebell Swing; Dumbbell Romanian Deadlift; Trap Bar Deadlift | — |
| Kettlebell Snatch | KB SNATCH | kettlebell | hinge | shoulders, hamstrings | 15 / 8 | Kettlebell Swing; Kettlebell Clean | — |
| Kettlebell Swing | KB SWING | kettlebell | hinge | hamstrings, back | 25 / 12 | Cable Pull-Through; Kettlebell Deadlift; Band Pull-Through | Russian Kettlebell Swing; Two-Hand Kettlebell Swing |
| Machine Glute Kickback | MC GLUTE KICK | machine | isolation | hamstrings | 10 / 5 | Cable Glute Kickback; Machine Hip Abduction | Glute Kickback Machine |
| Machine Hip Abduction | HIP ABDUCT | machine | isolation | — | 20 / 10 | Cable Hip Abduction; Banded Lateral Walk | Hip Abduction Machine; Seated Hip Abduction; Abductor Machine |
| Machine Hip Adduction | HIP ADDUCT | machine | isolation | — | 20 / 10 | Cable Hip Adduction; Copenhagen Adduction | Hip Adduction Machine; Seated Hip Adduction; Adductor Machine |
| Machine Hip Thrust | MC HIP THRUST | machine | hinge | hamstrings | 40 / 20 | Hip Thrust; Barbell Glute Bridge; Glute Bridge | Hip Thrust Machine |
| Power Clean | POWER CLEAN | barbell | hinge | hamstrings, quads, back | 45 / 20 | Hang Power Clean; Kettlebell Clean | — |
| Reverse Hyperextension | REVERSE HYPER | machine | hinge | hamstrings, back | 40 / 20 | Back Extension; Machine Back Extension; Cable Pull-Through | Reverse Hyper |
| Single-Leg Hip Thrust | SL HIP THRUST | bodyweight | hinge | hamstrings | BW | Glute Bridge; Hip Thrust | — |
| Sumo Deadlift | SUMO | barbell | hinge | hamstrings, quads, back | 95 / 40 | Deadlift; Trap Bar Deadlift; Kettlebell Deadlift | Sumo Barbell Deadlift |
| Trap Bar Deadlift | TRAP BAR DL | barbell | hinge | quads, hamstrings, back | 55 / 25 | Deadlift; Sumo Deadlift; Rack Pull | Hex Bar Deadlift |

#### Calves (11)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Barbell Calf Raise | BB CALF | barbell | isolation | — | 45 / 20 | Smith Machine Calf Raise; Standing Calf Raise; Dumbbell Calf Raise | Standing Barbell Calf Raise |
| Bodyweight Calf Raise | BW CALF | bodyweight | isolation | — | BW | Single-Leg Calf Raise; Dumbbell Calf Raise | Calf Raise |
| Donkey Calf Raise | DONKEY CALF | machine | isolation | — | 20 / 10 | Standing Calf Raise; Leg Press Calf Raise | Donkey Calf Raise Machine |
| Dumbbell Calf Raise | DB CALF | dumbbell | isolation | — | 10 / 5 | Single-Leg Dumbbell Calf Raise; Barbell Calf Raise; Bodyweight Calf Raise | Standing Dumbbell Calf Raise |
| Leg Press Calf Raise | LP CALF | machine | isolation | — | 20 / 10 | Standing Calf Raise; Seated Calf Raise; Donkey Calf Raise | Calf Press; Leg Press Calf Press |
| Seated Calf Raise | SEATED CALF | machine | isolation | — | 20 / 10 | Standing Calf Raise; Seated Dumbbell Calf Raise; Leg Press Calf Raise | Seated Calf Raise Machine |
| Seated Dumbbell Calf Raise | SEATED DB CALF | dumbbell | isolation | — | 10 / 5 | Seated Calf Raise; Dumbbell Calf Raise | — |
| Single-Leg Calf Raise | SL CALF | bodyweight | isolation | — | BW | Bodyweight Calf Raise; Single-Leg Dumbbell Calf Raise | One-Leg Calf Raise |
| Single-Leg Dumbbell Calf Raise | SL DB CALF | dumbbell | isolation | — | 10 / 5 | Dumbbell Calf Raise; Single-Leg Calf Raise | — |
| Smith Machine Calf Raise | SMITH CALF | machine | isolation | — | 20 / 10 | Standing Calf Raise; Barbell Calf Raise; Dumbbell Calf Raise | Smith Calf Raise |
| Standing Calf Raise | CALF | machine | isolation | — | 20 / 10 | Seated Calf Raise; Leg Press Calf Raise; Smith Machine Calf Raise; Barbell Calf Raise | Standing Calf Raise Machine; Machine Calf Raise |

#### Biceps (13)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Curl | BAND CURL | band | isolation | forearms | 10 / 5 | Cable Curl; Dumbbell Curl | Resistance Band Curl; Band Biceps Curl |
| Barbell Curl | CURL | barbell | isolation | forearms | 25 / 10 | EZ-Bar Curl; Dumbbell Curl; Cable Curl | Standing Barbell Curl; Barbell Biceps Curl |
| Cable Curl | CABLE CURL | cable | isolation | forearms | 20 / 10 | Barbell Curl; EZ-Bar Curl; Band Curl | Cable Biceps Curl; Straight-Bar Cable Curl |
| Cable Hammer Curl | CB HAMMER | cable | isolation | forearms | 20 / 10 | Hammer Curl; Cable Curl | Rope Hammer Curl |
| Concentration Curl | CONC CURL | dumbbell | isolation | — | 10 / 5 | Dumbbell Preacher Curl; Spider Curl; Dumbbell Curl | Seated Concentration Curl |
| Dumbbell Curl | DB CURL | dumbbell | isolation | forearms | 10 / 5 | Barbell Curl; Incline DB Curl; Cable Curl; Hammer Curl | Dumbbell Biceps Curl; Standing Dumbbell Curl; Alternating Dumbbell Curl |
| Dumbbell Preacher Curl | DB PREACHER | dumbbell | isolation | — | 10 / 5 | Preacher Curl; Machine Preacher Curl; Concentration Curl | — |
| EZ-Bar Curl | EZ CURL | barbell | isolation | forearms | 25 / 10 | Barbell Curl; Cable Curl; Preacher Curl | EZ Bar Curl; EZ Curl |
| Hammer Curl | HAMMER CURL | dumbbell | isolation | forearms | 10 / 5 | Cable Hammer Curl; Dumbbell Curl; Incline DB Curl | Dumbbell Hammer Curl |
| Incline DB Curl | INC DB CURL | dumbbell | isolation | forearms | 10 / 5 | Dumbbell Curl; Cable Curl; Spider Curl | Incline Dumbbell Curl |
| Machine Preacher Curl | MC PREACHER | machine | isolation | — | 20 / 10 | Preacher Curl; Dumbbell Preacher Curl; Cable Curl | Preacher Curl Machine; Machine Biceps Curl; Machine Curl |
| Preacher Curl | PREACHER | barbell | isolation | forearms | 25 / 10 | Machine Preacher Curl; Dumbbell Preacher Curl; EZ-Bar Curl | EZ-Bar Preacher Curl; Barbell Preacher Curl |
| Spider Curl | SPIDER CURL | dumbbell | isolation | — | 10 / 5 | Dumbbell Preacher Curl; Concentration Curl; Incline DB Curl | Dumbbell Spider Curl |

#### Triceps (14)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Band Triceps Pushdown | BAND PUSHDOWN | band | isolation | — | 10 / 5 | Cable Triceps Pushdown; Rope Pushdown | Band Pushdown; Resistance Band Pushdown |
| Bench Dip | BENCH DIP | bodyweight | h-push | chest, shoulders | BW | Dip; Diamond Push-Up; Machine Dip | Triceps Bench Dip |
| Cable Triceps Kickback | CB KICKBACK | cable | isolation | — | 10 / 5 | Dumbbell Kickback; Cable Triceps Pushdown | — |
| Cable Triceps Pushdown | PUSHDOWN | cable | isolation | — | 20 / 10 | Rope Pushdown; Machine Triceps Extension; Band Triceps Pushdown | Triceps Pushdown; Cable Pushdown; Straight-Bar Pushdown |
| Close-Grip Bench Press | CG BENCH | barbell | h-push | chest, shoulders | 45 / 20 | Diamond Push-Up; Machine Dip; Barbell Floor Press | Close-Grip Barbell Bench Press; CGBP |
| Diamond Push-Up | DIAMOND | bodyweight | h-push | chest, shoulders | BW | Close-Grip Bench Press; Bench Dip; Push-Up | Close-Grip Push-Up; Triangle Push-Up |
| Dumbbell Kickback | KICKBACK | dumbbell | isolation | — | 5 / 2.5 | Cable Triceps Kickback; Cable Triceps Pushdown | Triceps Kickback; Dumbbell Triceps Kickback |
| Dumbbell Overhead Triceps Extension | DB OH EXT | dumbbell | isolation | — | 10 / 5 | Overhead Cable Extension; Skull Crusher; Dumbbell Skull Crusher | Overhead Dumbbell Extension; Dumbbell Overhead Extension; Seated Dumbbell Triceps Extension |
| Dumbbell Skull Crusher | DB SKULL | dumbbell | isolation | — | 10 / 5 | Skull Crusher; Dumbbell Overhead Triceps Extension | Lying Dumbbell Triceps Extension; Dumbbell Lying Triceps Extension |
| Machine Dip | MC DIP | machine | h-push | chest, shoulders | 40 / 20 | Dip; Weighted Dip; Close-Grip Bench Press | Seated Dip Machine; Triceps Dip Machine; Seated Dip |
| Machine Triceps Extension | MC TRI EXT | machine | isolation | — | 20 / 10 | Cable Triceps Pushdown; Overhead Cable Extension | Triceps Extension Machine |
| Overhead Cable Extension | OH EXT | cable | isolation | — | 20 / 10 | Dumbbell Overhead Triceps Extension; Rope Pushdown; Skull Crusher | Overhead Cable Triceps Extension; Cable Overhead Triceps Extension; Overhead Rope Extension |
| Rope Pushdown | ROPE PUSHDOWN | cable | isolation | — | 20 / 10 | Cable Triceps Pushdown; Overhead Cable Extension; Band Triceps Pushdown | Rope Triceps Pushdown; Cable Rope Pushdown |
| Skull Crusher | SKULLCRUSHER | barbell | isolation | — | 25 / 10 | Dumbbell Skull Crusher; Overhead Cable Extension; Cable Triceps Pushdown | EZ-Bar Skull Crusher; Lying Triceps Extension; Skullcrusher |

#### Forearms (10)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Barbell Wrist Curl | WRIST CURL | barbell | isolation | — | 25 / 10 | Dumbbell Wrist Curl; Behind-the-Back Wrist Curl | Wrist Curl; Seated Barbell Wrist Curl |
| Behind-the-Back Wrist Curl | BTB WRIST | barbell | isolation | — | 45 / 20 | Barbell Wrist Curl; Dumbbell Wrist Curl | Behind-the-Back Barbell Wrist Curl |
| Cable Reverse Curl | CB REV CURL | cable | isolation | biceps | 20 / 10 | Reverse Curl; Zottman Curl | Reverse-Grip Cable Curl |
| Dumbbell Farmer's Carry | FARMER CARRY | dumbbell | carry | back, core | 15 / 7.5 | Kettlebell Farmer's Carry; Trap Bar Carry; Suitcase Carry | Farmer's Carry; Farmer's Walk; Dumbbell Farmer's Walk |
| Dumbbell Reverse Wrist Curl | DB REV WRIST | dumbbell | isolation | — | 5 / 2.5 | Reverse Curl; Zottman Curl; Dumbbell Wrist Curl | Reverse Wrist Curl |
| Dumbbell Wrist Curl | DB WRIST | dumbbell | isolation | — | 5 / 2.5 | Barbell Wrist Curl; Dumbbell Reverse Wrist Curl | — |
| Kettlebell Farmer's Carry | KB CARRY | kettlebell | carry | back, core | 25 / 12 | Dumbbell Farmer's Carry; Kettlebell Front Rack Carry; Suitcase Carry | Kettlebell Farmer's Walk |
| Reverse Curl | REV CURL | barbell | isolation | biceps | 25 / 10 | Cable Reverse Curl; Zottman Curl; Dumbbell Reverse Wrist Curl | Reverse Barbell Curl; EZ-Bar Reverse Curl; Reverse-Grip Curl |
| Trap Bar Carry | TRAP CARRY | barbell | carry | back, core | 55 / 25 | Dumbbell Farmer's Carry; Kettlebell Farmer's Carry | Trap Bar Farmer's Carry; Trap Bar Walk |
| Zottman Curl | ZOTTMAN | dumbbell | isolation | biceps | 10 / 5 | Reverse Curl; Cable Reverse Curl | Dumbbell Zottman Curl |

#### Core (26)

| Exercise | Short | Equipment | Pattern | Secondary | Start lb / kg | Alternatives | Also called |
|---|---|---|---|---|---|---|---|
| Ab Wheel Rollout | AB WHEEL | bodyweight | core | back, shoulders | BW | Dead Bug; Hanging Leg Raise | Ab Rollout; Ab Wheel |
| Band Pallof Press | BAND PALLOF | band | core | — | 10 / 5 | Cable Pallof Press; Dead Bug | — |
| Bicycle Crunch | BICYCLE | bodyweight | core | — | BW | Crunch; Russian Twist; Dead Bug | — |
| Cable Crunch | CABLE CRUNCH | cable | core | — | 20 / 10 | Machine Crunch; Decline Sit-Up; Crunch | Kneeling Cable Crunch |
| Cable Pallof Press | PALLOF | cable | core | — | 20 / 10 | Band Pallof Press; Cable Woodchop; Dead Bug | Pallof Press |
| Cable Side Bend | CB SIDE BEND | cable | core | — | 20 / 10 | Dumbbell Side Bend; Cable Woodchop | Standing Cable Side Bend |
| Cable Woodchop | WOODCHOP | cable | core | shoulders | 20 / 10 | Cable Pallof Press; Landmine Rotation; Russian Twist | Cable Wood Chop; Woodchopper |
| Captain's Chair Knee Raise | CHAIR RAISE | bodyweight | core | — | BW | Hanging Knee Raise; Hanging Leg Raise; Reverse Crunch | Vertical Knee Raise |
| Crunch | CRUNCH | bodyweight | core | — | BW | Cable Crunch; Machine Crunch; Sit-Up | Abdominal Crunch; Floor Crunch |
| Dead Bug | DEAD BUG | bodyweight | core | — | BW | Ab Wheel Rollout; Cable Pallof Press; Band Pallof Press | — |
| Decline Sit-Up | DEC SIT-UP | bodyweight | core | — | BW | Sit-Up; Cable Crunch; Crunch | Decline Bench Sit-Up |
| Dumbbell Side Bend | SIDE BEND | dumbbell | core | — | 10 / 5 | Cable Side Bend; Cable Woodchop | Side Bend |
| Hanging Knee Raise | HANG KNEE | bodyweight | core | forearms | BW | Hanging Leg Raise; Captain's Chair Knee Raise; Reverse Crunch | — |
| Hanging Leg Raise | HANG LEG RAISE | bodyweight | core | forearms | BW | Hanging Knee Raise; Toes-to-Bar; Captain's Chair Knee Raise; Lying Leg Raise | — |
| Kettlebell Front Rack Carry | RACK CARRY | kettlebell | carry | shoulders | 25 / 12 | Kettlebell Farmer's Carry; Suitcase Carry | Front Rack Carry |
| Kettlebell Windmill | WINDMILL | kettlebell | core | shoulders, hamstrings | 15 / 8 | Turkish Get-Up; Dumbbell Side Bend | — |
| Landmine Rotation | LANDMINE ROT | barbell | core | shoulders | 10 / 5 | Cable Woodchop; Russian Twist | Landmine Twist; Landmine 180 |
| Lying Leg Raise | LEG RAISE | bodyweight | core | — | BW | Reverse Crunch; Hanging Leg Raise; V-Up | Floor Leg Raise |
| Machine Crunch | MC CRUNCH | machine | core | — | 20 / 10 | Cable Crunch; Crunch | Ab Crunch Machine; Abdominal Crunch Machine; Crunch Machine |
| Reverse Crunch | REV CRUNCH | bodyweight | core | — | BW | Hanging Knee Raise; Lying Leg Raise; Crunch | — |
| Russian Twist | RUSSIAN TWIST | bodyweight | core | — | BW | Cable Woodchop; Landmine Rotation; Bicycle Crunch | — |
| Sit-Up | SIT-UP | bodyweight | core | — | BW | Crunch; Decline Sit-Up; V-Up | Situp |
| Suitcase Carry | SUITCASE | dumbbell | carry | forearms | 15 / 7.5 | Dumbbell Farmer's Carry; Kettlebell Front Rack Carry; Kettlebell Farmer's Carry | Single-Arm Farmer's Carry |
| Toes-to-Bar | T2B | bodyweight | core | forearms | BW | Hanging Leg Raise; V-Up | T2B |
| Turkish Get-Up | GET-UP | kettlebell | core | shoulders, glutes | 15 / 8 | Kettlebell Windmill; Dead Bug | TGU; Kettlebell Get-Up |
| V-Up | V-UP | bodyweight | core | — | BW | Sit-Up; Toes-to-Bar; Lying Leg Raise | — |
