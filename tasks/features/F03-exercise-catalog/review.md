# F03 — Exercise catalog: review

- **Reviewer:** independent review agent, 2026-09-30.
- **Scope:** `git diff main...HEAD` at `4d7cf28` (commits `d80602f` and `4d7cf28`). The tester's two untracked
  files under `LedgerDomainTests/Adversarial/` are not part of this review.
- **Inputs:** the brief (criterion 2 amended, criterion 7 extended), `implementation-notes.md` including
  "Decisions (2026-09-30)" and the catalog appendix, product decisions #9, #12, #13, #21 and #22,
  `docs/engineering-standards.md`, `docs/subagent-workflow.md` "Reviewer", and the `/code-review` skill at
  level high (used as input only; how each of its findings was handled is listed at the end).

**Result: 0 Blocking, 5 Should fix, 11 Nit.** The loader, the kettlebell step change and the bundling are
correct. The version guard works on CI, but it has three gaps: its failure message disagrees with the
test, the test can crash, and nothing stops an id from being re-rolled. The content is sound; one start
load is below the weight of its own bar.

## What I ran and inspected

| Evidence | Result |
|---|---|
| `scripts/check-catalog-version.sh` in this worktree | exit 0, "exercise catalog changed since origin/main (1d80613): version 0 -> 2" |
| `bash scripts/tests/adversarial/catalog-version.adv.sh` | 17 passed, 0 failed |
| `xcresulttool … summary` on the recorded `.derivedData/Results/PR-iOS.xcresult` / `PR-watchOS.xcresult` | iOS: 926 tests, 923 passed, 0 failed, 3 skipped. watchOS: 851 tests, 848 passed, 0 failed, 3 skipped. Every `ExerciseCatalog`, `CatalogEntry` and `CatalogSeedFixture` case passed on both; the performance test was skipped (nightly lane only). |
| Built products: `LedgerKit_LedgerDomain.bundle` | Present in `Ledger.app`, in `LedgerWatch.app` and in `Ledger.app/Watch/LedgerWatch.app`. Each holds `exercises.json` and `catalog.version.sha`, and each `exercises.json` has HEAD's SHA-256 (`528e0325…`). |
| `.github/workflows/pr.yml` | The Check job checks out with `fetch-depth: 0` (pinned by WF47) and runs `check.sh --ios-only`, which runs step 2 and so this script |

The result bundles were written at 10:11 and 10:12, two minutes before `4d7cf28` was committed (10:14). The
bundled JSON's SHA and the test names match HEAD, so they reflect this catalog. G5's local `check.sh` on
the merge candidate reruns everything anyway. I ran no simulator and no `swift test`, because the tester's
gate is running.

---

## Blocking

None.

## Should fix

### S1 — `versionSha_matchesFile` crashes on an empty history, and its version rule contradicts the script

- **Where:** `LedgerKit/Tests/LedgerDomainTests/Catalog/ExerciseCatalogTests.swift:146`; `scripts/check-catalog-version.sh:61-64`; `scripts/tests/adversarial/catalog-version.adv.sh:52-53` (CV05).
- **Problem 1, the crash:** `Array(1 ... history.count)` traps ("Range requires lowerBound <= upperBound")
  when `catalog.version.sha` has only comment lines, for example after a bad merge. The trap kills the whole
  test process and loses every other result; the test should fail cleanly instead.
- **Problem 2, the contradiction:** the test requires the versions to be exactly 1, 2, 3 … with no gaps. The
  script accepts any rise ("Raise it to 3 or more"), and CV05 asserts that 1 → 3 passes. So a contributor who
  follows the script's advice and goes from 2 to 4 passes the script, then fails the test.
- **Fix:** make the test's rule "non-empty and strictly increasing", which F05's "re-seed when the version
  rises" is all that needs:

  ```swift
  let versions = history.map(\.version)
  try #require(!versions.isEmpty, "catalog.version.sha has no version lines")
  #expect(versions.first! >= 1 && zip(versions, versions.dropFirst()).allSatisfy { $0 < $1 }, "versions rise")
  ```

  (`#require` the first element rather than force-unwrapping it, if lint objects.) This removes the trap and
  the disagreement in one edit, and CV05 can stay as it is. The other option is to make the script demand
  exactly `previous + 1`. That would also mean flipping CV05, and this PR's own 0 → 2 would fail unless N1
  is applied.

### S2 — The script's failure message sends the editor in the wrong direction

- **Where:** `scripts/check-catalog-version.sh:62-66`.
- **Problem 1:** "Raise it to N **or more**" contradicts the test (S1), unless S1 relaxes the test.
- **Problem 2:** "(shasum -a 256 exercises.json)" fails when run from the repo root, which is where the
  script runs, because the file is at `LedgerKit/Sources/LedgerDomain/Resources/exercises.json`.
- **Problem 3:** unlike the Swift test, the message does not print the line to append.
- **Fix:** compute the digest and print the exact line, in the style of the test's message:

  ```bash
  sha="$(shasum -a 256 "$JSON" | cut -d' ' -f1)"
  # error: $JSON differs from $base_ref ($short), but ExerciseCatalog.version is still $current.
  #        Set it to $((previous + 1)) in $SOURCE and end $HISTORY with the line:
  #        $((previous + 1)) $sha
  ```

  Add a check to CV02 that the output contains the digest line.

### S3 — Nothing stops an id from being removed or re-rolled

- **Where:** `scripts/check-catalog-version.sh` (after line 68); the claims in
  `ExerciseCatalog.swift:57-58`, `implementation-notes.md:47-52` and `exercises.json:4-5`.
- **Problem:** the brief's main risk is agents regenerating UUIDs. The notes say three (in fact four)
  things guard against it. But once the version is raised, which any deliberate edit does, the SHA test and
  the script both pass a file that re-rolled, reused or deleted an id. Only the 22 prototype ids are pinned.
  A re-rolled id orphans lifters' programs, history and `curatedAlternatives`.
- **Fix:** the script already has the base. Fail when an id that main has is missing from the working tree.
  `jq` is not a pinned tool; `grep` is enough, because the file has one `"id": "…"` key per entry (214
  matches today):

  ```bash
  ids() { grep -oE '"id": "[0-9A-F-]{36}"' | sort -u; }
  if base_json="$(git show "$base:$JSON" 2>/dev/null)"; then
      gone="$(comm -23 <(ids <<<"$base_json") <(ids <"$JSON"))"
      [[ -z "$gone" ]] || { printf 'error: ids main has are gone from %s (never remove or regenerate an id):\n%s\n' "$JSON" "$gone" >&2; exit 1; }
  fi
  ```

  Add two CV cases (an id is re-rolled; an entry is deleted) and correct the notes' "Three things guard
  this". main has no ids yet, so this protects from the first catalog PR after this one. It is about 6
  lines; land it here.

### S4 — The contributing note promises edits that an additive upgrade never delivers

- **Where:** `exercises.json:5` ("add entries, fix text, loads or alternatives"); `ExerciseCatalog.swift:57`
  ("Upgrades are additive"); `CatalogSeedFixture.swift:26-30`; F05 criterion 11.
- **Problem:** F05 criterion 11 only inserts new entries on a higher version ("new entries are added and
  existing names are not duplicated"), and the fixture only models additions. A future PR that fixes a name,
  a wrong alternative or a pattern will bump the version and pass every gate. Existing installs will then
  never see the fix; only new installs will.
- **Fix, in F03:** make the note and the doc comment say what an upgrade does to existing rows. If the
  answer is "catalog rows are updated in place and custom rows are untouched", add a `modified` entry to
  `CatalogSeedFixture.upgrade()` (a base entry with a changed name or alternatives), assert it in
  `CatalogSeedFixtureTests`, and extend F05 criterion 11 to match.
- **The semantics** are F05's to decide (see G5).

### S5 — Safety Bar Squat starts below the weight of its own bar

- **Where:** `exercises.json:1287` (45 lb / 20 kg); the class assignment in `StartLoadPolicy.swift:56`.
- **Problem:** a safety squat bar weighs about 60–70 lb (25–32 kg). "The empty bar" in decision #21 means
  45 lb for a standard bar, but for an SSB no setup reaches 45 lb. The lifter must correct it, or the log
  records a load that never happened and progression starts from it.
- **Fix:** give specialty bars their own class, like `floorPulls`, set to the empty SSB: e.g. 65 lb /
  30 kg, both on step. This stays inside #21's "empty bar" principle.
- **Check at the same time:** Trap Bar Carry (`exercises.json:2292`, 45 lb / 20 kg). Trap bars are often
  45–65 lb, so 45 lb is only reachable with the lightest ones.

Content fixes are cheapest before merge: they rewrite this PR's own line in `catalog.version.sha`. After
merge, each one needs a version bump and a re-seed.

## Nit

- **N1 — `catalog.version.sha:5`, merge-time only.** Version 1 names content from `d80602f`, which the
  squash merge erases from main. Once merged, the line is frozen and points at content no commit on main
  has. The orchestrator chose version 2 knowingly. If you would rather main's history start clean,
  collapse the file to `1 528e…`, set `version = 1` and update the notes' "version 2" references. This is
  the last chance to do that.
- **N2 — Docs contradict the code.**
  - `ExerciseCatalog.swift:51-52` says "4 kg bell sizes", while `Exercise.swift:8` and #22 say the gap is
    2 kg. The notes repeat it in "The kg rule".
  - `Exercise.swift:7` still says "everything else 2.5 / 1.25"; fold the kettlebell exception into that
    line.
  - `ExerciseCatalog.swift:63` says `seed()` throws `CatalogError`, but `Data(contentsOf:)` (line 112) can
    throw a Cocoa error, and the generated `Bundle.module` traps if the whole bundle is missing.
    `missingResource` covers only a missing file inside the bundle. Say so.
  - `implementation-notes.md:47` says "Three things" and then lists four.
- **N3 — Barbell isolation lifts normally done on a standard bar from a rack.** Barbell Shrug
  (`exercises.json:317`), Barbell Calf Raise (`:1736`) and Behind-the-Back Wrist Curl (`:2208`) get the
  "EZ or fixed bar" 25 lb / 10 kg. In practice these use a 45 lb / 20 kg bar, which also puts shrugs at a
  sensible start. The error is on the light side, which is #21's direction, so either accept it or move
  them to the empty-bar cell.
- **N4 — Floor-start lifts outside the deadlift family sit at the empty bar.** Power Clean (`:1675`),
  Pendlay Row (`:524`) and Stiff-Leg Deadlift (`:1482`, deadlift family and usually pulled from the floor)
  are 45 lb / 20 kg. With iron plates, that bar is below pulling height, which is the floor-pull class's own
  rationale. Again the error is on the light side: accept it, or note in the class rules that these start
  from blocks or the hang.
- **N5 — Weak alternatives.**
  - Leg Extension (`:1225`) offers only Sissy Squat and Reverse Nordic, two harder bodyweight skills.
  - Cable Glute Kickback (`:1530`) offers two abduction movements. That is a different job for the glutes;
    Machine Glute Kickback was cut to reach 214.
  - Dumbbell Side Bend (`:2429`) offers Kettlebell Windmill, a mobility and skill lift.
  - Box Squat (`:1069`) is the only entry that no exercise lists as an alternative.
  - Fix: restore Machine Glute Kickback, and add a Cable Side Bend or a Band Leg Extension, or accept.
- **N6 — Missing staples.**
  - The most useful addition is Incline Push-Up, the standard beginner regression. Every alternative
    Push-Up has today is harder or needs equipment.
  - Also worth adding: Seal Row, Landmine Squat, Bicycle Crunch, Dumbbell Squat.
  - The six entries cut to reach exactly 214 (Decline Dumbbell Press, Underhand Barbell Row, Machine Glute
    Kickback …) bought nothing: F12's placeholder is a live count ("Search %lld exercises", F12 brief
    line 54).
- **N7 — `CatalogSeedFixture.swift:58-67`.**
  - `clash` also reuses `custom`'s shortName `ZERCHER`. F05's schema has no unique `short_name`, so there
    is no false pass today. Still, give `clash` a distinct shortName (e.g. `ZERCHER SQ`) so the case
    isolates the name rule.
  - `added` and `clash` have no alternatives, so the "upgraded catalog" is one `exercises(from:)` would
    reject. Give each two ids from the base catalog.
- **N8 — `ExerciseCatalogTests.swift:16-20`.** `init()` reads the file and decodes it twice, and Swift
  Testing builds about 48 instances (the parameterized cases), so that is roughly 96 decodes per run. Load
  once into a `static let` (e.g. a `Result`) and read from it.
- **N9 — `check-catalog-version.sh:32-34`.** "Shares no history" is also what a shallow clone produces. Add
  "(or the clone is shallow: fetch with fetch-depth: 0)", as the first message already does.
- **N10 — Short names.** Weighted Pull-Up is `PULL-UP` and Weighted Dip is `DIP`, while the unweighted ones
  are `BW PULL-UP` / `BW DIP`, and Weighted Chin-Up is `WTD CHIN-UP` (`exercises.json:536, 657`). The
  prototype set these, so the plain label now marks the weighted variant, which is inconsistent with
  `WTD CHIN-UP`. Accept, or use `WTD PULL-UP` / `WTD DIP`.
- **N11 — `CatalogEntry` ignores unknown keys.** A misspelt required key fails, as documented. An extra key,
  say `"step": 2` added by an editor who expects a per-exercise step, is silently dropped. This is fine as
  long as the doc comment at `CatalogEntry.swift:5-6` does not suggest otherwise.

---

## Focus areas

### Loader correctness

- **Correct.** `seed()` throws and never skips anything.
  - Decoding is all or nothing (`entries(from:)`), and every required key is required.
  - Ids and names (with aliases, ignoring case) are checked before any entry is mapped.
  - `CatalogEntry.exercise()` rejects blank or untrimmed text, a primary muscle repeated as secondary,
    repeated secondaries, a load that is negative or off the step (in each unit), a mismatch between
    `loadKind` and the zero load, and alternatives that are fewer than 2, include the exercise itself or
    repeat.
  - The cross-entry pass rejects unknown alternatives and alternatives with another pattern.
  - `Dictionary(uniqueKeysWithValues:)` at line 84 is safe, because ids were proven unique first.
- **The DTO → `Exercise` mapping is exact.** `validEntry_mapsEveryField` compares the whole value,
  including `isCustom == false`, the order of `curatedAlternatives` and both units of `defaultStartLoad`.
  `seed()` returns entries in file order, which is tested.
- **Errors carry the entry's id,** and `unreadable` carries the decoder's coding path.
- **No `try?` anywhere.**

### The F02 kettlebell step change (#22)

Every consumer of `Equipment.defaultStep(in:)` or the resolved step is consistent:

| Consumer | Follows #22? | Evidence |
|---|---|---|
| `ProgressionRules.prescribe` (linear, double) | yes: `slot.step ?? defaultStep` | `prescribe_kettlebell_usesBellSteps`: 12 → 16 kg, 25 → 35 lb |
| Deload `× 0.85` rounding | yes | same test: 26 kg → 22 kg, 60 lb → 50 lb |
| `SessionBuilder` drop set (`p.step`) | yes, through `Prescription.step` | not tested separately; same path |
| `Exercise.startLoad(in:)` cross-unit fallback | yes | `kettlebell_startLoadFallback_landsOnABell` |
| `CatalogEntry` step validation | yes | the catalog's 8 / 12 kg and 15 / 25 lb pass |
| `EventBuilders` (test support) | yes | reads `defaultStep` |
| Plate math | n/a | barbell only (decision #10); takes no equipment |
| Onboarding (F08, not built) | brief updated | F08 rounding text and criterion 8 |
| Stepper, builder, settings (F10, F11, F14, not built) | briefs updated | each names the kettlebell exception |
| Persisted `Slot.step` | n/a | F05 is not built; `Slot.step == nil` resolves at read time |

One interaction is outside F03 (see carry-forward): a swap keeps the old exercise's step.

### Version guard (SHA file plus `scripts/check-catalog-version.sh`)

- **Correct on CI.**
  - For `pull_request`, `actions/checkout` with `fetch-depth: 0` creates `origin/main` and checks out the
    merge commit, so the merge base is main's tip and the merged tree is compared with main.
  - A stale local `main` loses to `origin/main` (CV16, CV17).
  - Nightly and release runs on main compare HEAD with itself and pass.
  - Xcode Cloud does not run `check.sh`.
- **Blob comparison is right,** including uncommitted edits (`git hash-object` on the working tree).
- **The history check is exact:** the lines main has must stay unchanged and first, and comments may
  change (CV11–CV15).
- **Gaps:**
  - S1: the test and the script disagree.
  - S2: the message.
  - S3: ids are not protected.
- **Residual risk to know about:** two catalog PRs in flight at once, both at version N. The second is
  caught by the textual conflict on the last line of `catalog.version.sha` (both append `N …`), not by the
  script. That is still a hard stop, and G5's local `check.sh` on the rebased candidate catches it too.

### Content (read as a strength coach)

- **Taxonomy is sound.** The pattern rules are defensible and written down: front squat is a squat, the
  RDL is a hinge, and a dip stands in for the bench.
- **Primary muscles are defensible:** Deadlift → hamstrings (the spec's call), traps → back, rear delts →
  shoulders.
- **Alternatives are mostly excellent.** The isolation same-muscle rule prevents nonsense swaps.
- **Loads:** nothing is too heavy for a beginner, and all 214 match #21, checked by an oracle test.
- **Findings:**
  - S5: loads below the implement's own weight.
  - N3 and N4: light-side class edges.
  - N5: weak alternatives.
  - N6: missing staples.
  - G5: the hip adduction machine is excluded.

### Resource bundling

- **Works on both platforms.** `Bundle.module` for LedgerDomain resolves through `Bundle.main.resourceURL`,
  and Xcode embeds `LedgerKit_LedgerDomain.bundle` in `Ledger.app`, in `LedgerWatch.app` and in the watch
  app inside the iOS app. All three hold both files, with HEAD's JSON.
- **The catalog suites passed on the iOS and watchOS simulators,** including the SHA test, which proves
  that `catalog.version.sha` is bundled as well.
- **Shipping the 496-byte `.sha` file is justified:** §9 forbids unit tests from reading the source tree,
  so `#filePath` would be worse (implementation note 13).

### Test quality

- **Strong overall.** The tests assert behaviour, use no sleeps and no time, and are parameterized where it
  helps.
- `CatalogEntryTests` has one case per `CatalogError` path (21), plus 9 undecodable documents.
- `StartLoadPolicy` is an independent oracle, and it proves that every name it lists exists.
- The 22 prototype ids are pinned.
- The shell suite (CV01–CV17) runs on throwaway repositories, including CI's `origin/main` case, and was
  mutation-tested four ways.
- **Weaknesses:** S1 (the trap), N8 (repeated decodes), no id-stability test beyond the 22 (S3), and no
  kettlebell drop-set case (acceptable, since it shares the deload's path).

## Seven review points

| # | Point | Verdict |
|---|---|---|
| 1 | Module boundaries | OK. LedgerDomain imports Foundation only. CryptoKit is imported only in the test target. LedgerTestSupport → LedgerDomain. |
| 2 | Concurrency | OK. Everything new is `Sendable`, with no global mutable state. `Bundle.module` is `static nonisolated let`, and the test globals are immutable. |
| 3 | Error handling | OK. Typed `CatalogError` carries the id, nothing is swallowed, no `try?`. Doc caveat in N2. |
| 4 | Design fidelity | n/a (no UI). A test enforces the watch rules for short names (upper case, ≤ 14, unique). |
| 5 | Accessibility | n/a (no UI). See the F18 carry-forward. |
| 6 | Test quality | Good; S1, N7, N8. |
| 7 | Brief compliance | Met; table below. |

## Brief compliance

| Criterion | Evidence | Status |
|---|---|---|
| 1. ≥ 200; throws on any malformed entry | `seed_decodesAllEntries` (214; file order; none custom; ≤ 200 KB); `CatalogEntryTests.brokenEntry_throws` (21), `undecodableDocument_throwsUnreadable` (9), `missingResource_throws` | Met |
| 2 (amended). The 22 spec entries with policy loads | `prototypeEntries_usePolicyLoads` (22 cases: name, equipment, lb, kg, pinned id); `startLoads_followThePolicy` for all 214 | Met |
| 3. Alternatives exist, share the pattern, not self, ≥ 2 | `alternatives_resolveToSamePattern`; enforced again in `seed()`; `isolationAlternatives_trainTheSamePrimaryMuscle` goes beyond the brief | Met |
| 4. No duplicate names or aliases, ignoring case | `namesAndAliases_haveNoDuplicates`; enforced in `seed()` | Met |
| 5. Muscle coverage (≥ 10, core ≥ 8) | `muscleCoverage_meetsMinimum` (11 cases); forearms sit at exactly 10 | Met |
| 6. Equipment coverage | `equipmentCoverage_meetsMinimum` (7 cases): 41 / 43 / 30 / 35 / 39 / 15 / 11 | Met |
| 7 (extended). The version rises with any change | `versionSha_matchesFile`; `check-catalog-version.sh` in step 2; CV01–CV17; wiring W02, W04, W57 | Met; S1–S3 |
| 8. The seed fixture | `CatalogSeedFixture` + `upgrade_isAdditive`, `custom_clashesOnlyWithClash` (contract in F05) | Met; N7, S4 |
| Rules: step multiples, the `loadKind` rule, stable UUIDs | `startLoads_areMultiplesOfStep`, the `loadKindMismatch` cases, `ids_areStableUUIDs` | Met |
| Non-functional: < 20 ms, ≤ 200 KB | 109,196 bytes (tested); `seed_under20ms` runs nightly (3.5 ms on the host, first pass) | Met (the timing is not from an iPhone) |
| DoD: §6.2 names resolve; notes list the pattern rules and exclusions | criterion 2 test; `implementation-notes.md` | Met |
| Standards §12: check.sh, coverage | recorded bundles green on both platforms; LedgerDomain 99.01 % | Met; the adversarial pass and CI are pending |

PR size: 239 code lines, under the 500 target.

## How the `/code-review` findings were handled

| # | Finding | Disposition |
|---|---|---|
| 1 | `1 ... 0` traps | Confirmed → S1 |
| 2 | The script allows gaps; the test forbids them | Confirmed → S1, S2 |
| 3 | A distinct SHA per version blocks a byte-exact revert | Dismissed. Returning to an older version's exact bytes means deleting the entries added since, which additive upgrades forbid. |
| 4 | Nothing enforces "never remove or regenerate an id" | Confirmed → S3 |
| 5 | "4 kg bell sizes" contradicts #22 | Confirmed → N2 |
| 6 | The fixture's shortName clash and missing alternatives | Kept as N7. F05 has no unique `short_name`, so there is no false pass today. |
| 7 | `.sha` shipped in the app bundle | Dismissed: 496 bytes, and the alternative breaks §9 |
| 8 | The suite decodes about 96 times | Confirmed → N8 |
| 9 | `seed()` is not cached | Dismissed for F03: `version` is public, so F05/F07 compare before decoding. Their call. |
| 10 | History line 1 was never merged | Kept as N1 (the orchestrator's choice; flagged as irreversible after merge) |

## Carry-forward notes (not findings against F03)

- **F10, swap and step.** `WorkoutEngine+Reduce.swift:142` keeps the step (and the equipment) on a swap,
  and 28 kettlebell alternatives cross equipment. After #22, a dumbbell → kettlebell swap keeps
  2.5 lb / 1.25 kg, and the reverse keeps 5 lb / 2 kg. F10's store already keeps `[ExerciseID: Exercise]`
  "for names/steps". Make criterion 5 say that the step comes from the **replacement's** equipment.
- **F18.** 14-character labels (`SEATED DB CALF`, `HANG LEG RAISE`, `BAND PULL-THRU`, `BAND FACE PULL`) at
  20 pt in 196 pt need a snapshot check. Abbreviations (`T2B`, `HSPU`, `GHR`, `SLDL`) need the full name as
  their VoiceOver label.
- **F05.**
  - There is no alias column, and search is by prefix, so "RDL", "Military Press" and "Hex Bar" will not
    find anything (see G5).
  - Upgrade semantics: S4.
- **Bands** step 2.5 lb / 1.25 kg, but bands come in discrete resistances. This is the same class of
  problem #22 fixed for kettlebells. It is not in this PR.

## G5: product decisions Pete has not made

**Already Pete's:** #21 (the load policy), #22 (the kettlebell step), `INC DB CURL`, and the exclusions of
assisted machines and timed holds.

**Not yet decided:**

1. **Should aliases be searchable?** The 312 aliases are validated, then dropped at the loader, because
   `Exercise` has no aliases field. F05's schema has no column for them and F12 searches names by prefix,
   so lifters searching "RDL", "Military Press" or "Skullcrusher" will find nothing. Making them searchable
   needs `Exercise.aliases` (an F02 public-type change) and an F05 column. **Decide before F05's `v001`
   migration lands,** because migrations are append-only. This is Pete's call.
2. **The hip adduction machine (and the Copenhagen plank) are excluded** because `MuscleGroup` has no
   adductors. That is a staple machine missing from the Library, and it is not among the exclusions Pete
   accepted. The options are:
   - accept the exclusion;
   - add `adductors` (an F02 enum change; serialized);
   - file it under glutes.

   This is Pete's call.
3. **Upgrade semantics for existing catalog rows (S4).** Do catalog fixes reach existing installs? This
   belongs in F05's brief, which the orchestrator can decide. It decides whether any future catalog fix
   reaches current users, so show Pete if unsure.

**Not new decisions:**

- The S5 fix stays inside #21 ("the empty bar").
- Trimming to exactly 214 is FYI only (F12's count is live).

**Process note.** This PR adds rows #21 and #22 to `docs/product-decisions.md`. They record Pete's own calls
from today, but G5 stops for Pete on any PR that carries a product decision. Confirm with Pete that the two
rows say what he decided, or show them to him, before merging.

## Verdict

**Approve: G3 passes with zero Blocking findings.**

- **Before merge:** S1–S3 (small; they make the version and id guards trustworthy from the next catalog PR
  on) and S4's wording.
- **S5 and the content nits:** fix now, because before merge they only rewrite this PR's own line in
  `catalog.version.sha`; after merge each needs a version bump.
- **N1:** decide now or never.
