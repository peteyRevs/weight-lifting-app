# F03 — adversarial test findings

Scope: branch `feat/F03-exercise-catalog` at `4d7cf28` (catalog v2, 214 exercises, conservative loads,
kettlebell step 5 lb / 2 kg). I wrote the tests from the brief (criterion 2 as amended 2026-09-30),
decisions #9, #21 and #22, spec §3.8, §4.3 and §6.1–§6.3, `LedgerWatch.dc.html` and `Ledger.dc.html`,
the F02 types and the doc comments of `ExerciseCatalog`, `CatalogEntry` and `CatalogError`. I read neither
the implementer's catalog tests nor `implementation-notes.md` before the first pass. After it I read the
notes' policy table (decision 1) only. A grep for "DB CURL" also showed the notes' short-name paragraph
(decisions 4 and 7).

## What was written

| File | Attacks |
|---|---|
| `LedgerKit/Tests/LedgerDomainTests/Adversarial/CatalogAdversarialSupport.swift` | Helpers: the bundled file (raw, `JSONSerialization`, decoded), strict text keys (NFKC plus case, diacritic and width folding, punctuation dropped), a step oracle restated from #9/#22, and a three-entry document builder for loader attacks |
| `…/Adversarial/CatalogDataAdversarialTests.swift` (13 tests) | Criterion 1: count, file order, nothing skipped, 214 as the Library promises. Ids: upper-case canonical v4, unique, alternatives canonical too. Exact key set per entry. No key written twice. Criterion 4 under strict folding across names and aliases. ASCII-only text with no stray whitespace. Short names unique, upper case, ≤ 14. Criteria 5 and 6. Enum raw values. ≥ 3 exercises per pattern. Secondary muscles distinct. Criterion 3. Isolation alternatives share the primary muscle |
| `…/Adversarial/CatalogLoadsAdversarialTests.swift` (6 tests) | Both units present, ≥ 0, multiples of the oracle's step. Bodyweight 0 exactly when `loadKind` says so (weighted variants excepted). **Every one of the 214 exercises against a policy oracle** restated from decision #21: equipment × {compound, isolation/core, small raise} plus the four named classes. The 22 spec §6.2 entries: name, prototype equipment, muscle family, policy lb and kg, formatted text, and `sh`. Exact decimals: each load equals its JSON digits, prints back as written, and survives a `Codable` round trip (15 lb = 6,803.88555 g) |
| `…/Adversarial/KettlebellStepAdversarialTests.swift` (7 tests) | Only kettlebells changed step (all 14 equipment × unit pairs). Linear and double progression one bell at a time. Deload × 0.85 onto a bell for 15 starts × 8 weeks, with the 17 kg tie going to 18. A drop set in a real `SessionBuilder` session in kg. Cross-unit conversion for 4–48 kg and 5–100 lb. Each catalog bell's lb and kg within one step. Weight and e1RM PRs one bell up, none at the same bell |
| `…/Adversarial/CatalogLoaderAdversarialTests.swift` (9 tests, 93 cases) | Criterion 1 through `ExerciseCatalog.exercises(from:)`: every key missing or null, mistyped fields, 10 bad enum spellings, 9 bad or duplicate UUIDs, 17 bad loads (negative, off-step, a hair off a step in exact decimals, overflow, kettlebell on the old steps, `loadKind` mismatches, a misspelt `loadKind`), 10 text faults, 8 alternative and muscle faults, 8 malformed documents, and a key written twice. Every case must throw a `CatalogError` |
| `…/Adversarial/CatalogVersionAdversarialTests.swift` (6 tests) | Criterion 7: the history's last line is `ExerciseCatalog.version` and the SHA-256 of the bundled file. Versions strictly rise. No SHA repeats. A one-byte edit changes the SHA. The 200 KB budget. Criterion 8: the fixture's base is the bundled catalog, the upgrade is +1 and append-only, the fixture names are new or clash only by case, and its ids are outside the catalog |
| `scripts/tests/adversarial/catalog-version-attack.adv.sh` (24 cases) | `check-catalog-version.sh` on real git histories: the first introduction (placeholder JSON at the base, and the JSON absent), version 0; after the merge, edits uncommitted and committed, whitespace-only edits, bumps, jumps, a lowered version; history lines edited, reordered, dropped or deleted, and comment-only changes; CI's detached merge commit against `origin/main`, both unbumped and bumped; depth-1 clones with and without `origin/main`; a trailing comment on the version line; a doc comment that quotes a version line. `run.sh` picks it up, so `check.sh` step 2 runs it |

## Results

Runs used the pinned simulators (iOS 27.0, watchOS 27.0), each through the simulator lock.

| Run | Result |
|---|---|
| New Swift suites on the host (`swift test --filter`) | 41 tests, 93 parameterised loader cases. **1 fails:** `duplicateKey_throws` (finding 1) |
| `scripts/check.sh --fast` | Steps 0–2 green: format, lint (these files included), graph, pins, `check-catalog-version.sh`, and every script suite, including `catalog-version-attack.adv.sh` (24/24) and the implementer's `catalog-version.adv.sh` (17/17). Step 3 (`swift test`, host): 751 tests, **1 failed** (`duplicateKey_throws`) |
| `scripts/check.sh` (full) via the lock, log `scratchpad/f03-g2.log` | Steps 0–2 green. Step 3, iOS PR plan: 967 tests, 963 passed, 3 skipped, **1 failed** (`CatalogLoaderAdversarialTests.duplicateKey_throws`). `set -e` stops before step 4 (exit 65) |
| Steps 4 and 5 by hand, same `xcodebuild` lines as `check.sh`, via the lock (log `scratchpad/f03-g2-watch.log`) | watchOS PR-Watch: 892 tests, 888 passed, 3 skipped, **1 failed** (the same test). Coverage gate over both bundles: **98.12 %** overall, ✓ |

Every other test on both platforms is green, including the implementer's catalog suites. The one
failure is deliberate and left in place: it is the repro for finding 1.

## Findings

### 1. A key written twice in an entry loads silently; the first value wins — minor bug (criterion 1)

- **Test:** `CatalogLoaderAdversarialTests.duplicateKey_throws` (fails).
- **Repro:** an entry with `"name": "Alpha Press", "name": "Bravo Press"` loads as "Alpha Press" with no error.
  `JSONDecoder` and `JSONSerialization` both keep the first value. So a hand edit that re-adds
  `"alternatives": […]` or `"startLoad": {…}` at the end of an entry, instead of editing the existing
  key, is silently ignored. The SHA and version bump then ship the file as if the edit had landed.
  Criterion 1 says "no silent skipping".
- **Today's file is clean.** `CatalogDataAdversarialTests.entries_noKeyWrittenTwice` scans the raw text
  and passes.
- **Fix, either:**
  - make the loader reject repeated keys (for example, count each entry's raw keys before decoding); or
  - accept the decoder's behaviour, keep the data-level scan as the guard, and delete the loader test.

### 2. Kettlebell Clean takes the light bell, but decision #21 does not name cleans — spec question

- **Test:** none fails. The policy oracle (`PolicyOracle.isLightBell`) now lists the clean, following the
  notes. The first pass flagged the clean at 15 lb / 8 kg against the 25 lb / 12 kg it expected.
- **The mismatch:** decision #21 and the table in `ExerciseCatalog.swift` both say "15 lb / 8 kg for
  upper-body, overhead and get-up work". The catalog files the clean as a hinge whose primary muscle is
  glutes. Only the notes' list names the clean.
- **Resolve, either:**
  - name cleans in decision #21 and in the doc comment; or
  - give the clean 25 lb / 12 kg, like the swing it is offered against.
- **Wording nit:** the doc comment's kg rationale says "4 kg bell sizes", but the kettlebell step is 2 kg
  (#22). The start loads sit on 4 kg competition sizes and progress in 2 kg. Say both.

### 3. A swap to or from a kettlebell can land on loads no bell has — spec question (F10 / rule 27)

- **Repro:**
  1. Take one of the 52 curated alternative links that cross between kettlebells and other equipment,
     for example Goblet Squat ↔ Kettlebell Goblet Squat, Single-Arm Dumbbell Row ↔ Kettlebell Row, or
     Dumbbell Farmer's Carry ↔ Kettlebell Farmer's Carry.
  2. Swap in a session where the replacement has no history.
- **What happens:** rule 27 (spec §7) and F04's `swap` keep the original sets, loads and step. F10's
  brief gives the undone sets the replacement's last-known load only "if any". A dumbbell goblet squat
  that progressed to 8.75 kg becomes an 8.75 kg kettlebell, and the store's 2 kg stepper then walks
  10.75, 12.75 kg and so on. That brings back the "16.25 kg, a bell nobody owns" problem that decision
  #22 fixed.
- **Suggestion:** when there is no last-known load, round the undone sets to the replacement's step, or
  use its default start load. Decide in F10.

### 4. Aliases never reach search — spec question (F05 / F12)

- `CatalogEntry.aliases` is decoded only to guard duplicates. `Exercise` has no aliases field, and F05's
  `exercise` table has no aliases column.
- So 312 authored aliases get no search hits. Examples: "Military Press" (Overhead Press), "Hex Bar
  Deadlift", "Hyperextension", "Bent-Over Row", "Butterfly", "Skullcrusher", "RFESS", "Australian
  Pull-Up".
- User story 1 is "I can find any common … exercise by name". Either carry the aliases into the seeded
  rows and search (F05 / F12), or record that they are dedupe-only.

### 5. The short name is called "the watch label", but the watch design shows the full name — spec question (F18)

- The JSON's contributing note caps `shortName` at 14 characters "(it is the watch label)".
- The watch design shows `exName`, the full name, in a 600 20 px slot 196 px wide (≈ 131 pt at 46 mm)
  (`LedgerWatch.dc.html`, spec §4.3). The prototype uses `sh` only for the Program builder's day chips
  (`CATALOG[x.c].sh`).
- 23 catalog names are 24 characters or longer, for example "Dumbbell Overhead Triceps Extension" (35).
  They will wrap to 2–3 lines on the watch.
- Either F18 and spec §4.3 adopt `shortName` for the watch, or the note should say "chip label". The
  14-character cap is the implementer's own choice either way. It is enforced (≤ 14, unique, upper case)
  and every short name fits it.

### 6. Specialty bars start below their own weight — content question

- Safety Bar Squat starts at 45 lb / 20 kg, but a safety squat bar weighs about 60–70 lb (27–32 kg)
  empty.
- Trap Bar Carry starts at 45 lb / 20 kg; trap bars weigh about 45–75 lb.
- The policy's "empty bar" assumes a standard bar, so these defaults cannot be set up. They are
  conservative, but the lifter must raise them in the first session. Consider the typical empty weight
  (for example 65 lb / 30 kg for the SSB).

### 7. Floor-start lifts at the empty bar — content question

- Power Clean and Pendlay Row start from the floor, and so does Stiff-Leg Deadlift in its common form.
  All three sit at 45 lb / 20 kg with no plates, so the bar starts about 4 in lower than with
  standard-diameter plates.
- The policy's floor-pull class (95 lb / 40 kg, "at pulling height") names only deadlift variants and
  rack pulls. Consider whether these three belong there. Bumper plates exist in 10 lb / 5 kg sizes.

### 8. Smaller content observations — content question (low)

- **Knee raise vs leg raise:** "Captain's Chair Leg Raise" is an alias of Captain's Chair **Knee** Raise,
  while Hanging Knee Raise and Hanging Leg Raise are separate entries.
- **Short names that point at the weighted variant:** the short names `PULL-UP` and `DIP` label the
  *weighted* variants, while "Pull-Up" and "Dip" are the names of the bodyweight entries (short names
  `BW PULL-UP` and `BW DIP`). This is inherited from spec §6.2, but a day chip reading "PULL-UP" means
  the weighted one.
- **An orphan:** Box Squat is the only exercise no other entry lists as an alternative, so no swap ever
  offers it.
- **Straight-bar lifts at the fixed-bar load:** Barbell Calf Raise and Barbell Shrug start at the
  isolation value, 25 lb / 10 kg ("an EZ or fixed bar"). Both are usually loaded on a straight bar.

### 9. The seed fixture's name-clash rule can leave dangling ids — spec question (F05 criterion 11)

- `CatalogSeedFixture.clash` encodes "a new catalog entry named like a custom exercise is not
  inserted". On that device the entry's catalog id then never exists.
- An upgrade that also lists it as another entry's alternative, or a future template that references
  it, would then point at a missing row.
- The fixture's `added` and `clash` also have no curated alternatives, so `upgrade()` is not a catalog
  `seed()` would accept. That is fine as an F05 input, but F05 should decide how a skipped clash is
  handled: rename it, or insert it and let the custom exercise keep its name.

## Attacked and held

- **Criterion 1:** `seed()` returns all 214 entries in file order. Every malformed shape throws a
  `CatalogError` (93 cases), except finding 1. Decoding uses exact decimals: `45.000000000000000000001` lb
  and `19.9999999999999999` kg are rejected, not rounded through `Double`, and `1e400` throws. (Beyond
  38 significant digits `Decimal` itself rounds: `45.0000000000000000000000000000000000001` reads as 45.
  That is out of reach for a hand-edited file.) `-0` reads as 0.
- **Ids:** all 214 are upper-case canonical v4 UUIDs, unique, and every alternative is written the same
  way. The loader also rejects braces, missing hyphens, short ids, trailing spaces and numbers.
  Lower-case ids decode to the same UUID; the data test enforces upper case.
- **Criterion 3:** every alternative resolves, shares the pattern, is not the exercise itself, and does
  not repeat; there are ≥ 2 each. Every isolation alternative trains the same primary muscle, as the
  pattern rules promise. Sampled swap lists read sensibly, and the spec §6.3 alts are there where the
  pattern allows (Assisted Pull-Up is excluded on purpose).
- **Criterion 4, stricter than the brief:** no two entries share a name or alias under NFKC plus case,
  diacritic and width folding with punctuation and spacing dropped ("Glute-Ham Raise" ≡ "Glute Ham
  Raise"). All text is plain ASCII, so no Cyrillic or full-width lookalike can hide, and there are no
  double or edge spaces.
  - **Note:** the loader itself only compares `lowercased()` and trims the edges. It would accept
    "Bench  Press" beside "Bench Press", a full-width twin, or an embedded tab. The data tests now guard
    the one file it loads.
- **Short names:** unique, upper case, 1–14 characters, ASCII. The 22 prototype `sh` values are kept
  except Incline DB Curl → `INC DB CURL`, a documented and accepted deviation (notes, decisions 4 and 7).
  The test pins it, and pins Dumbbell Curl = `DB CURL`.
- **Enums and counts:**
  - every raw value is an F02 case; all 11 muscles, 7 equipment types and 10 patterns are used; each
    pattern has ≥ 5 members;
  - criterion 5: back 32, quads 28, shoulders 27, core 24, chest 22, glutes 20, triceps 14,
    hamstrings 13, biceps 13, calves 11, forearms 10;
  - criterion 6: dumbbell 43, barbell 41, bodyweight 39, machine 35, cable 30, kettlebell 15, band 11.
- **Loads:**
  - every lb and kg value is a whole multiple of the step restated from #9/#22 (kettlebells 5 lb / 2 kg);
  - none is negative; bodyweight entries are 0/0 with `loadKind` exactly when zero; weighted dip,
    pull-up and chin-up are +10 lb / +5 kg; no non-bodyweight entry is 0;
  - **all 214 match an independent oracle of decision #21** (after finding 2's clean);
  - the 22 prototype entries carry the policy's loads (bench, squat, front squat, OHP and row 45/20;
    deadlift 95/40; RDL 45/20; Incline DB Press 15/7.5; Lat Pulldown 30/15; the weighted pair 10/5), with
    the prototype's equipment and muscle family;
  - each load equals its JSON digits exactly, formats back as written, and round-trips through `Codable`.
- **Kettlebell step (F02 change):**
  - no other equipment's step moved;
  - linear progression steps 12 → 14 → 16 kg and 25 → 30 → 35 lb; double progression moves one bell
    after the rep span;
  - deloads land on 2 kg multiples for 120 start × week combinations, and the tie rule sends 17 kg to 18;
  - a real `SessionBuilder` session in kg keeps step 2 kg, with its drop row 14 × 0.85 = 11.9 → 12 kg;
  - `startLoad(in:)` conversion lands on a bell for every size tried;
  - PR detection works on bells.
  - Plate math never sees kettlebells (it takes no equipment, and decision #10 limits it to barbells).
- **Criterion 7 (`catalog.version.sha`):** the last line is `2 528e0325…`, which is both
  `ExerciseCatalog.version` and the file's SHA-256. The versions rise and a one-byte edit changes the SHA.
- **Criterion 7 (`check-catalog-version.sh`)**, all 24 cases pass:
  - the first introduction passes, both with main's placeholder JSON (no `ExerciseCatalog.swift` at the
    base) and with the file absent;
  - version 0 fails;
  - a changed JSON at the same version fails, committed, uncommitted and whitespace-only alike, and the
    message names the version to raise to;
  - a bump with an appended line passes;
  - lowering the version, editing, reordering or dropping a merged history line, and deleting the file
    all fail; comment-only edits pass;
  - on a CI-style detached merge commit it compares with `origin/main` and fails unbumped / passes bumped;
  - depth-1 clones with no `main` or no shared history fail closed (exit 2), never open;
  - a trailing comment on the version line fails closed; a doc comment quoting a version line is ignored.
  - **Note:** locally the script prefers `origin/main` over `main`, so a stale `origin/main` compares
    against an older base. CI fetches full history, so the runner is authoritative.
- **Criterion 8:**
  - the fixture's base is the bundled catalog at `ExerciseCatalog.version`;
  - `upgrade()` is +1 and appends exactly `added` and `clash`;
  - "Zercher Squat" and "Cossack Squat" appear in no catalog name or alias, and `clash` differs from
    `custom` only by case;
  - the fixture ids are distinct and outside the catalog.
- **Non-functional:** the JSON is 109,196 bytes, under 200 KB. The contributing note explains the
  never-regenerate rule for ids.

## Verdict

**Ready once finding 1 is resolved; nothing blocks the catalog content.**

- The data holds up under every integrity attack in the brief and some stricter ones:
  - ids, criteria 1 and 3–6;
  - names and aliases under Unicode and punctuation folding;
  - short names;
  - steps, bodyweight and exact decimals;
  - all 214 loads against an independent oracle of decision #21, and the 22 prototype entries.
- The kettlebell step change behaves in progression, deload, drop sets, conversion and PRs, and touches
  no other equipment.
- The loader throws a `CatalogError` on every malformed shape tried except one: a key written twice
  (finding 1, minor). Fix it in the loader, or accept it and keep the data-level scan and drop the
  failing test.
- `check-catalog-version.sh` held on all 24 histories, including the first introduction, CI's detached
  merge commit and shallow clones, which fail closed.
- Findings 2–5 and 9 are spec questions for Pete or the owning briefs:
  - 2: the clean's bell class vs #21's wording;
  - 3: swaps onto a kettlebell;
  - 4: aliases never reach search;
  - 5: short name vs the watch label;
  - 9: the seed-clash rule.
- Findings 6–8 are low-stakes content questions.

# Round 2 — close-out

Scope: `feat/F03-exercise-catalog` at `f0b444e` (fix round 2: catalog version 3, 224 exercises). I read
this file's round 1, `review.md` (S1–S5), and two parts of `implementation-notes.md`: "Fix round 2" and
"Decisions (2026-09-30)". I attacked only what changed. Mutants ran in a throwaway copy of the
LedgerDomain target and its catalog suites (`scratchpad/f03-mut`), so the worktree's data was never
edited.

## Close-out

| Item | Asked | Fix round 2 | Checked this round | Status |
|---|---|---|---|---|
| **Finding 1:** a key written twice | Make the loader reject it, or keep the file scan and drop the loader test | Option 2. `duplicateKey_throws` is gone; `duplicateKey_caughtByTheFileScan` and `CatalogScan` were added | The scan read only the first key on each line, so a repeat on the same line passed every test. That is the form finding 1's own repro used (M12b, M12c). I fixed this in the tests during close-out (new finding R2-1). A repeat is now caught on its own line (M10), on the same line (H1, H2) and inside `startLoad` (H3) | **Resolved**, after R2-1 |
| **S1:** the version test traps and forbids gaps | Require a non-empty history that rises | The history must be non-empty, start at ≥ 1 and rise; gaps are allowed; each line must read `<n> <64 hex>` | M1–M8, below. An empty history now fails at `#require(history.last)` without a trap. A gap passes. The rest fail | **Resolved** |
| **S2:** the script's message | Print the exact line from the repo path | Done; CV02 checks it | Read. The message prints `N+1 <sha>` for `$JSON` at its repo path | **Resolved** |
| **S3:** ids unprotected | Fail when an id main has is gone | `jq` reads id → name from main and from the working tree. The script fails when an id is gone or a name main has now has another id. CV18–CV21 | I01–I13 and three script mutants, all killed. One blind spot is under Noted, item 1 | **Resolved** |
| **S4:** "additive" is undefined | Say what an upgrade does | The JSON note, `ExerciseCatalog.version`'s doc and brief criterion 7 now say: new entries only, existing rows untouched | Read. The three texts agree with F05 S2's seeding rule | **Resolved** |
| **S5:** Safety Bar Squat is below its bar | A specialty-bar class | The SSB starts at 65 lb / 30 kg. Trap Bar Deadlift and Trap Bar Carry start at 55 lb / 25 kg | See "Specialty bars" below | **Resolved** |
| **2:** the clean's bell | Name cleans in #21, or use the heavier bell | #21 and the doc name cleans; "4 kg bell sizes" is reworded | Read; three oracles agree | **Resolved** |
| **3:** a swap onto a kettlebell | Decide in F10 | A new line in F10's Risks: re-target to the new equipment's step and sizes (last-known load, else its start load) | Read | **Moved to F10** |
| **4:** aliases never searched | Carry them to search, or record that they only guard duplicates | Decision #23 (Pete): search covers name and short name; aliases are neither stored nor searched and remain a duplicate guard. The JSON note and `CatalogEntry`'s doc say so | Read. #23 is recorded in the F05-persistence worktree (F05 S2, not yet committed) | **Resolved by decision (#23, Pete)** |
| **5:** is the short name the watch label? | Adopt it on the watch, or call it a chip label | It is the Program builder's day-chip label (spec §3.2). The test is now `shortNames_fitTheDayChips` | Read | **Resolved** |
| **6:** specialty bars | Use their typical empty weight | Same fix as S5 | See S5 | **Resolved** |
| **7:** floor-start lifts at the empty bar | Consider the floor-pull class | The orchestrator kept Power Clean and Pendlay Row at the empty bar, and SLDL for the same reason (the error is on the light side) | — | **Resolved by decision (orchestrator)** |
| **8a:** knee raise vs leg raise | — | "… Leg Raise" aliases are dropped from Captain's Chair Knee Raise | Diff | **Resolved** |
| **8b:** `PULL-UP` / `DIP` short names | — | Kept: these are prototype `sh` values, and changing design copy is Pete's call (N10) | — | **Resolved by decision (left to Pete)** |
| **8c:** Box Squat orphaned | — | Box Squat is now one of Safety Bar Squat's swaps | None of the 224 is an orphan | **Resolved** |
| **8d:** straight-bar isolation on the EZ-bar value | — | Shrug, calf raise and behind-the-back wrist curl now start at 45 lb / 20 kg (N3) | Three oracles agree | **Resolved** |
| **9:** a seed clash can leave dangling ids | F05 decides | F05 S2's rule: "an entry is never skipped over a name"; it is inserted by its id beside the clash | `CatalogSeedFixture`'s doc still says `clash` "is not inserted" (Noted, item 7) | **Moved to F05** |

## Audit of the tests the fix round edited or retargeted

| Test | Change | Verdict |
|---|---|---|
| `CatalogLoaderAdversarialTests.duplicateKey_throws` | Deleted, with a pointer to the scan | **Accepted.** This was round 1's option 2: the app loads one bundled file, and every test run scans it. The scan it relies on had a gap (R2-1, now fixed). |
| `CatalogDataAdversarialTests.duplicateKey_caughtByTheFileScan` (new) | Doubles BENCH's `shortName` on a line of its own; asserts that the scan reports it and that the real file is clean | **Sound, but narrow.** It covered only the separate-line form. I added the same-line form (R2-1). |
| `CatalogDataAdversarialTests.entries_noKeyWrittenTwice` | Uses `CatalogScan` | **Sound after R2-1.** It fails closed if the layout changes: re-indenting the file to 4 spaces (M16b) breaks its entry count. |
| `CatalogDataAdversarialTests` count test | `== 214` dropped | **Accepted.** F12's count is live. The ≥ 200 floor (`seed_decodesAllEntries`) and "one exercise per raw entry, in order" remain. |
| `CatalogLoadsAdversarialTests.PolicyOracle` (my oracle, edited by the implementer) | Specialty-bar and straight-bar name lists, Landmine Squat, cable hip adduction | **Correct against #21's amended row, but name-keyed.** A new specialty-bar lift at 45 lb passed it (M13). I now derive specialty bars from the name ("Safety Bar", "SSB", "Trap Bar", "Hex Bar"), so H4 fails and H5 passes. I also refreshed two stale doc comments (adduction; #21 now names the clean). |
| `ExerciseCatalogTests.versionSha_matchesFile` | S1 rule and a strict line format | **Sound.** M0–M8 are below. It agrees with my round-1 `history_risesStrictly`, except that mine also rejects a leading zero. |
| `ExerciseCatalogTests.startLoads_followThePolicy` + `StartLoadPolicy` | The new classes; `named ⊆ names` also covers the new lists | **Sound, and fails closed.** A new SSB lift at the correct 65 / 30 fails it until its list grows (H5). One at 45 / 20 passes it (M13), which my oracle now catches. |
| `ExerciseCatalogTests.shortNames_fitTheDayChips` | Renamed from `…fitTheWatch` | Same assertions. **Sound.** |
| `ExerciseCatalogTests` cached `Loaded` (N8) | One decode per run, cached as a `Result`; a failure is kept as text | **Sound.** A broken file fails every test, each with the loader's error in its message (M10's output). |
| `CatalogSeedFixture.clash` | `shortName` → `ZERCHER SQ` | **Sound.** My fixture test compares names only. |
| `catalog-version.adv.sh` (implementer) | Entries are now `{id, name}` objects; CV02 checks the printed line; CV18–CV21 | **Sound.** I read each case, and my I-cases cover the same ground independently. |

**Version-test mutants** (M0–M8; the history is rewritten in the copy, and the SHA recomputed where the
case needs it):

| Mutant | Result |
|---|---|
| M0: unchanged | pass |
| M1: comment lines only | fails at `#require(history.last)`; no trap, and the other 31 tests run |
| M2: gap `1, 2, 4` with `version = 4` | pass (as CV05 and the script allow) |
| M3: order `2, 1, 3` | fails ("rise") |
| M4: CRLF on the last line | fails ("bad line") |
| M5: first version `0` | fails ("rise") |
| M6: a repeated SHA | fails ("own content") |
| M7: the last line is `2` while the code says `3` | fails ("current version") |
| M8: an indented `  # note` line | fails ("bad line"); the script also reads it as an entry line, so the two agree |

## New findings

### R2-1. The file scan missed a key repeated on the same line — minor; fixed in close-out (test-only)

- **Where:** `CatalogScan.entryKeys` (`CatalogAdversarialSupport.swift`). It took only the *first*
  `"key":` of each line.
- **Repro, before the fix:**
  - `"shortName": "SSB SQUAT", "shortName": "SSB",` (M12b) passed every catalog test.
  - `"alternatives": [a, b, c], "alternatives": [a]` on Trap Bar Carry (M12c) passed as well.
  - In each case the decoder kept the first value and said nothing, which is finding 1 exactly (its repro
    used this same-line form).
- **Fix:** the scan now counts every `"key":` in an entry's block. A same-line assertion is added to
  `duplicateKey_caughtByTheFileScan`. H1–H3 are now caught; the real file stays clean (H0).
- **Before this fix,** a repeat inside `startLoad`'s one-line object was already caught by the
  exact-digits test and the policy oracles (M11, M11b).
- **Status:** fixed in the worktree, uncommitted. The orchestrator commits it with this round.

No other new defect.

## Noted, not blocking

1. **The id guard is keyed by name, so it misses an id reused in place.** Two cases pass the script:
   - G1: an entry renamed into a different exercise with its id kept ("Row" → "Nordic Curl");
   - G2: two entries that are both renamed and swap ids.

   The gap is narrow in practice. Every one of the 224 entries is some other entry's alternative, so the
   loader's same-pattern check fails any reuse that changes the pattern (and, for isolation, the primary
   muscle). What can get through is a same-pattern "rename".

   To close it, also fail when an id main has changes `equipment` or `pattern`.
2. **The id guard can raise a false alarm.** Renaming an entry and giving its old name to a new entry is
   read as a re-roll (G3). This is conservative, and the message names both ids.
3. **The script lets a duplicated id on a new entry through (G4).** `seed()`'s `duplicateID` catches it on
   every test run (`CatalogEntryTests` "repeated id"; the loader adversarial "duplicate id"). The gate as a
   whole holds.
4. **The script fails open on a leading-zero version.** Bash reads `010` as octal 8 and errors on `08`.
   An arithmetic error evaluates as false, so for `08` the "fell" and "not raised" checks are both skipped
   (O2: exit 0, "version 1 -> 08"). A real fall still fails the Swift history test, because main's lines
   are frozen and versions must rise. Fix: `([1-9][0-9]*)` in `version_in`, or `10#$current`.
5. **Hip adduction is filed under glutes.** The data is consistent: the three adduction entries form a
   closed swap cluster and mix with no abduction entry. Adding an `adductors` group is still Pete's call
   (review G5 #2), as the notes say; show him at G5. On the day chips, `HIP ABDUCT` and `HIP ADDUCT` differ
   by one letter.
6. **Machine Glute Kickback's second swap is Machine Hip Abduction.** That is the "different job" N5
   criticised for Cable Glute Kickback. The ≥ 2 rule forces a second swap. Low.
7. **`CatalogSeedFixture`'s doc disagrees with F05 S2.** Step 3 says `clash` "is not inserted". F05 S2's
   rule says an entry is never skipped over a name. Align the doc when F05 S2 lands.
8. **Process at G5:**
   - #21 was edited in `product-decisions.md`; it is Pete's row (straight-bar isolation, specialty bars,
     the clean).
   - F03 cites #23, which exists only in the F05-persistence worktree. If F03 merges first, main cites a
     decision it does not have yet.
   - main is now at `1db1cf9` (F05 S1). It also touches `LedgerKit/Package.swift` and `F14-settings.md`.
     This gate ran on the unrebased branch; the G5 run on the rebased candidate is the one that counts.

## Attacked and held

- **The id guard** (`catalog-version-attack.adv.sh` I01–I13, added this round; 39/39 in the suite). Each
  case uses the real JSON layout and UUIDs.
  - **First introduction:**
    - over main's actual placeholder `{"version":1,"exercises":[]}`, it passes (I01);
    - with no `exercises.json` at the base, it passes (I02).
  - **Removed, re-rolled or swapped, with the version raised:**
    - a re-roll fails and names both ids (I03);
    - a deletion fails (I04);
    - a swap fails and names both entries (I05);
    - an entry that takes another's id fails (I06);
    - an id re-spelt in lower case fails closed (I07).
  - **An unreadable or missing working file:**
    - an unreadable one exits 2 (I08);
    - a deleted one never passes (I09). Without the id block, I09 *passes*, so the block also covers this
      case.
  - **No false alarm:** reorders, renames and additions with every id kept pass (I10).
  - **CI checkouts:**
    - on CI's detached merge commit, a re-roll fails (I11);
    - a depth-2 checkout of the merge commit still finds main as the base and fails the re-roll (I12);
    - a depth-1 checkout fails closed with exit 2 (I13);
    - `pr.yml`'s Check job fetches with `fetch-depth: 0`.
  - **Script mutants, each killed:**
    - the id block removed (11 cases fail);
    - the re-roll-by-name rule dropped (I03b, I05, I05b fail);
    - the "gone" rule dropped (I04 fails).
- **Gap tolerance, test vs script:**
  - Both allow gaps (M2, CV05, V09).
  - Both reject a fall, a changed merged line and a malformed line.
  - The script never checks the last line against the code, but the test does (M7).
  - A pointless bump (the version raised without a JSON change) passes the script, but the test's
    distinct-SHA rule fails it.
- **Specialty bars:**
  - I searched every name and alias for safety, SSB, trap, hex, cambered, swiss, football, log, axle,
    yoke, Smith, EZ and landmine. Only Safety Bar Squat, Trap Bar Deadlift and Trap Bar Carry use a
    specialty bar.
  - Each starts at its bar's weight in both units (65 lb / 30 kg; 55 lb / 25 kg). The values are on step
    and within 0.52 kg of conversion.
  - Smith and belt-squat lifts are machines at 40 lb / 20 kg. EZ-bar lifts are at 25 lb / 10 kg.
  - Reverting the SSB to 45 / 20 (M14) fails both oracles. Trap Bar Carry at 55 lb / 20 kg (M15) fails
    both too.
- **The policy after the edits:** all 224 match the implementer's oracle and mine, and also a third
  restatement of #21's amended row, written in Python from the text alone (0 mismatches). The largest
  lb → kg gap is still Rack Pull's 3.09 kg.
- **The hip adduction entries:**
  - Machine Hip Adduction (machine isolation, 20 lb / 10 kg), Cable Hip Adduction (cable small raise,
    10 lb / 5 kg) and Copenhagen Adduction (bodyweight 0 / 0, `loadKind` bodyweight) each sit in their
    policy cell.
  - Each is an isolation lift with glutes as its primary muscle, and each lists the other two as swaps,
    both ways.
  - The abduction entries are unchanged.
- **Counts:**
  - glutes went from 20 to 24;
  - by muscle: chest 23, back 33, shoulders 27, quads 30, hamstrings 13, glutes 24, calves 11, biceps 13,
    triceps 14, forearms 10, core 26;
  - by equipment: barbell 43, dumbbell 44, cable 32, machine 37, bodyweight 42, kettlebell 15, band 11.

  All match the notes' tables and clear criteria 5 and 6.
- **Content of the 10 additions:**
  - Incline Push-Up, Seal Row, Dumbbell Squat, Landmine Squat, Bicycle Crunch, Cable Side Bend, Machine
    Glute Kickback and the three adduction entries are each in the right pattern and muscle, each at its
    policy load.
  - Each has ≥ 2 same-pattern swaps, and at least one entry lists it back.
  - No catalog entry was removed. The only other changes are the load classes, alternatives and one alias
    set described in the notes.
  - None of the 224 is an orphan. The short names are unique and ≤ 14 characters.
- **Duplicate keys:**
  - on their own line: M10 is caught, and its bogus first `alternatives` loads, which proves first-wins;
  - on the same line: caught since R2-1;
  - nested in `startLoad`: caught by the digits test (M11, M11b) and now by the scan (H3);
  - a layout change fails closed (M16b).

## Gate

One full run of `scripts/check.sh`, taken through the simulator lock (it waited for F06-slice3's run
first) and logged to `scratchpad/f03-closeout.log`. The worktree held R2-1 and my test edits. It exited
0 in 268 s and printed `check.sh OK`.

| Step | Result |
|---|---|
| 0–1 | tools and format ✓ |
| 2 | lint, graph and pins ✓. `check-catalog-version.sh`: "changed since origin/main (1d80613): version 0 -> 3". `catalog-version-attack.adv.sh` 39/39, `catalog-version.adv.sh` 21/21; every suite passed |
| 3 | iOS PR plan: 967 tests, 964 passed, 3 skipped, **0 failed** |
| 4 | watchOS PR-Watch: 892 tests, 889 passed, 3 skipped, **0 failed** |
| 5 | coverage: LedgerDomain 99.01 %, LedgerDesign 96.46 %, overall 98.12 % ✓ |

The edited tests pass on both platforms, by name in each result bundle:
`duplicateKey_caughtByTheFileScan`, `entries_noKeyWrittenTwice`, `startLoads_followPolicy`,
`startLoads_followThePolicy` and `versionSha_matchesFile`. The totals match round 1 (967 / 892): one
test was removed (`duplicateKey_throws`) and one added.

## Verdict

**G2 can close.**

- Finding 1 and S1–S5 are resolved.
- The spec and content questions are each resolved, resolved by decision (#23 on aliases, Pete; floor
  starts, the orchestrator; `PULL-UP` / `DIP`, left to Pete), or moved (3 → F10, 9 → F05).
- The one new defect, R2-1, was in my own scan. It is fixed in the tests and green in the full gate.
- Nothing under Noted blocks.

**Commit these with this round** (tests only; no product or data file changed):
- `LedgerKit/Tests/LedgerDomainTests/Adversarial/CatalogAdversarialSupport.swift`: R2-1, the scan;
- `…/Adversarial/CatalogDataAdversarialTests.swift`: R2-1, the same-line case;
- `…/Adversarial/CatalogLoadsAdversarialTests.swift`: the specialty-bar rule read from names, and two
  stale comments;
- `scripts/tests/adversarial/catalog-version-attack.adv.sh`: I01–I13, an `ADV_CHECK_CATALOG` override for
  mutation runs, and the script copied in under its own name.

**Show Pete at G5:**
- #21's amended row;
- filing adduction under glutes;
- F03 citing #23 before F05 S2 records it on main.
