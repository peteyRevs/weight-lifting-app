# F32 — Review

This is the reviewer pass on `chore/F32-xcode-27` at `950bba7`: one commit on `main` `e94b501`, 41 files,
reviewed as `git diff main...HEAD`. I am a fresh agent and did not write this code. Pete's decision of
2026-09-29 is a requirement, not a finding. It covers Xcode 27.0 now, CI on the `xcode-27` preview label and
criterion 3 deferred to his Xcode Cloud setup.

## Verdict

**Approve after the Should-fix items: 0 Blocking, 3 Should fix, 7 Nits.**

- **The migration is sound.**
  - Both regenerated Xcode files are exactly what Xcode 27 writes, and `project.pbxproj` is untouched.
  - The two lockfiles agree: `swift-issue-reporting` 2.1.1 at `75b000ce…` in each.
  - Pin enforcement works where it is wired in: a stale project lockfile fails cold, and the exact-key cache
    cannot mask it.
  - The 16 snapshots differ in font rendering only.
  - Product code is unchanged.
  - The scripts are correct under `/bin/bash` 3.2.
- **S1, the one real gap:** `LedgerKit/Package.resolved` is never checked on CI. A stale copy passes today.
- **S2, the fallback wording:** the fallback is written as a label-and-pin switch, but that switch alone
  fails. It has to be a revert, and later merges make a revert harder.
- **S3:** a stale "Series 11 / 26.5" comment on the snapshot suite.
- **Merge notes.**
  - Criterion 1 still needs the first `xcode-27` CI run (G4).
  - This PR amends ADR-006, so G5's text has the orchestrator show Pete before merging. The decision is his
    own, so this is a formality.
  - Also see N6.

## Checks run

| Check | Result |
|---|---|
| `/code-review` at level high | 10 candidates. None is Blocking once verified; the disposition of each is below. |
| All `scripts/tests/*.test.sh` under `/bin/bash` 3.2.57 (the only bash on this Mac) | All pass: check-wiring 73, sim-destination 25, workflows 56, check-test-results 18, ci-post-clone 14, coverage-gate 60 + 10, release-please 16, and the 4 lint-rules suites exit 0. |
| `scripts/check.sh --lint-only` on the real Xcode 27.0 | OK. Step 0 prints `Xcode 27.0 ✓`. WF01 (actionlint with `.github/actionlint.yaml`) passes. |
| `check-xcode-version.sh` edge cases (scratch copy) | Pin 26.6 on 27.0: exit 1 with the message. Pin ` 27.0 ` padded with blank lines: OK. Run from `/`: OK, so it does not depend on the working directory. `DEVELOPER_DIR` set to the Command Line Tools: xcode-select's own clear error, exit 1. |
| shellcheck 0.11.0 (pinned) | The production scripts are clean except the known F00 false positive, `check.sh:55` SC2154. The changed suites are clean at warning level. |
| New flags exist in Xcode 27 / SwiftPM 6.4 | `xcodebuild -help` lists `-collect-test-diagnostics on-failure\|never` and `-onlyUsePackageVersionsFromResolvedFile`. `swift test --help` lists `--only-use-versions-from-resolved-file`. |
| Lockfiles regenerate to themselves (a clean `git archive HEAD` copy in the scratchpad) | Cold strict `xcodebuild -resolvePackageDependencies`: exit 0. Non-strict `xcodebuild` resolve: no file changed. Non-strict `swift package resolve` in LedgerKit: no file changed. |
| Stale-pin matrix (same copy) | See "Pin enforcement" below. |
| Snapshots | I opened 4 pairs with Read and diffed them with a CoreGraphics script. The numbers match the notes' table exactly. |
| Runner images (actions/runner-images READMEs) | **macos-26** `20260907.0351.1`: Xcode 26.6 (17F113) is the default; iOS and watchOS 26.5 have iPhone 17 and Series 11 (46mm). **xcode-27** `20260921.0210.1`: Xcode 27.0 (27A266a) is the default at `Xcode_27.app`, linked as `Xcode_27.0.app` and `Xcode.app`. Its only runtimes are iOS 27.0 and watchOS 27.0, with iPhone 17 and Series 12 (46mm), as `xcode-27.json` models. |
| Not run | The full simulator gate, as instructed. For it I rely on the notes' `f32-check.log` (cold, 394 s) and `f32-ci-fresh.log` (421 s). |

## Acceptance criteria

| # | Status | Evidence |
|---|---|---|
| 1 | **Pending: G4** | `pr.yml:59` uses `xcode-27`, and `:66` selects `Xcode_27.0.app`, which the README lists. It needs a green first run. #14404 warns of queueing on the preview. `timeout-minutes` does not count time in the queue, so a job that sits queued points to the label, not the code. |
| 2 | Met (notes) | The notes record a cold full gate, green with 0 warnings, and a runner-shaped pass. I confirmed that `xcodebuild -version` 27.0 matches `.xcode-version` and that `--lint-only` is green. |
| 3 | **Deferred, as the brief says** | Brief lines 18–19 and 37. `docs/xcode-cloud/README.md` §6 carries the checklist item. |
| 4 | Met, with N6 | All 16 references are reviewed below. The criterion wants the justification *in the PR*. |
| 5 | Met | `git diff main...HEAD -- Apps LedgerKit/Sources LedgerKit/Package.swift Config TestPlans ci_scripts mise.toml` is empty. The only Swift edit drops a `try` in a test: `Round4StoreAdversarialTests.swift:57`, where the actor's `highestSeq` at `:97` does not throw. |

## Findings

### Blocking

None.

### Should fix

**S1. `LedgerKit/Package.resolved` is never validated on CI, so a stale one merges green.**
- **Where:**
  - `scripts/check-package-graph.sh:45` is where the check belongs.
  - `docs/ci-cd.md:16-20` overclaims the protection.
  - `.github/workflows/nightly.yml:75` absorbs any drift.
- **Evidence:**
  1. I left the project lockfile current and put main's `LedgerKit/Package.resolved` back.
  2. Cold, strict `xcodebuild -resolvePackageDependencies` exits **0**, and the stale file stays as it was.
  3. The reason: `xcodebuild` reads only the workspace lockfile.
  4. The only strict reader of LedgerKit's file is `swift test` in `--fast`, which CI never runs and which a
     warm `LedgerKit/.build` passes anyway (notes, stale-pin table).
  5. `check-package-graph.sh` uses `swift package describe`, and I checked that it does not resolve.
  6. The nightly's non-strict `swift package resolve` silently re-resolves a stale file before
     `update --dry-run`.
- **Fix (about 5 lines plus one adversarial case).**
  - LedgerKit is the project's only package root, so the two lockfiles must pin the same versions.
  - In `check-package-graph.sh`, which runs in `check.sh` step 2 locally and on CI, add:
    ```bash
    # The project's lockfile is enforced cold on CI; LedgerKit's is read only by `swift test` (F32).
    if ! diff <(jq -S .pins LedgerKit/Package.resolved) \
        <(jq -S .pins Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved); then
        echo "error: LedgerKit/Package.resolved pins differ from the project's; run swift package --package-path LedgerKit resolve" >&2
        exit 1
    fi
    ```
  - Compare `.pins`, not bytes. On `main`, Xcode 26.6 wrote different `originHash`es for the two files
    (`fe91…` and `20eb…`) over equal pins, so a byte comparison would break on the 26.6 fallback. I checked
    that the pins are equal on both `main` and HEAD.
  - Optional: make the nightly report run `resolve --only-use-versions-from-resolved-file`, so drift fails
    the report instead of disappearing.
  - Say in `ci-cd.md` that the pins check covers LedgerKit's file.

**S2. The fallback is written as a switch, but it only works as a revert.**
- **Where:**
  - `.github/workflows/pr.yml:57-58`;
  - `nightly.yml:20`;
  - `docs/ci-cd.md:11-12`;
  - `tasks/todo.md:157`;
  - the brief at `:14-15` and `:45`.
- **The comments say** "fall back to `macos-26` with `.xcode-version` 26.6 and check.sh's 26.5 destinations".
  Those three edits alone fail:
  - **Lockfiles.** Swift 6.3 reads swift-dependencies' `Package@swift-6.3.swift`, which requires
    `xctest-dynamic-overlay`. The strict flag then rejects F32's lockfiles. I reproduced the mirror case on
    27.0: main's lockfiles give exit 74 from xcodebuild and exit 1 from SwiftPM. 26.6 is not installed here,
    so the 26.6 direction is inferred.
  - **Snapshots.** 8 of the 16 references recorded on 27.0 fall outside tolerance against 26.5 renders.
    That is the notes' "fails" column; the pixel metric is symmetric.
  - **Locally.** Pete's Mac is on 27.0, so step 0 fails until 26.6 is reinstalled.
- **Still true today.** The macos-26 image (`20260907.0351.1`) keeps 26.6 as the default, with iPhone 17 and
  Series 11 (46mm) on 26.5. ADR-006's amendment is already right ("Rolling back means reverting F32").
- **It decays.** "Revert the PR" is clean only while nothing merged after F32 records snapshots or changes
  pins. Every later reference is a 27.0 render, and every later lockfile is written by 6.4.
- **Fix.**
  - Reword the four comments to: "fallback = revert F32 (the pin, the runner, the destinations, both
    lockfiles and the 16 references), per ADR-006's amendment".
  - Add one line to the brief's Rollback: "references recorded and pins resolved after F32 must be
    re-recorded and re-resolved on 26.6 as well".

**S3. `LedgerKit/Tests/LedgerDesignTests/TokenSnapshotTests.swift:8-9` is stale.**
- **Problem:** it still says the references are recorded on "iPhone 17 / Apple Watch Series 11 46 mm,
  OS 26.5". All 16 are now recorded on Series 12 (46mm) with 27.0. This is the one remaining Series 11 / 26.5
  claim about current artefacts, and it will mislead the next re-record.
- **Fix:** "(iPhone 17 / Apple Watch Series 12 46 mm, OS 27.0; F32)".
- `SnapshotConfig.swift:19`, "measured on the 26.5 simulator in F06", is historical and can stay. The
  re-record showed no layout shift, so `.xLarge` still holds.

### Nits

- **N1. `docs/testing-strategy.md:22-23`.** Goal 2 says "on any Mac and on `macos-26` runners". Change it to
  "on CI runners (`docs/ci-cd.md`)". Leaving §7 and the dated line 10 as the pre-F01 plan is fine.
- **N2. `tasks/features/F07-composition-di.md:76` is obsolete.**
  - It says: "swift-dependencies `Package@swift-6.3` resolution on Xcode 26.6 … verify first".
  - Under 6.4, the default manifest resolves, with `swift-issue-reporting` 2.1.1. It is a transitive major
    version, not a new direct dependency, so it needs no ADR. `LedgerDependencies` is still a placeholder,
    so nothing uses it yet.
  - Point F07 at IssueReporting 2.x (`reportIssue` and `unimplemented`) instead.
- **N3. `implementation-notes.md:3`.** "Nothing is committed or pushed" is stale: `950bba7` is committed,
  though not pushed.
- **N4. The Swift version is pinned twice:** in `.swiftformat:1` and as `--swift-version 6.4` in
  `check.sh:80`. Lefthook reads only `.swiftformat`, and no test asserts that the two agree. Either drop the
  CLI flag (SwiftFormat reads `.swiftformat` at the root) or add a check-wiring case. This predates F32.
- **N5. The fixture's simulator pairs are assumed** (`scripts/tests/adversarial/lib.sh:85`, and W24 at
  `check-wiring.adv.sh:201`). After the first CI run, replace them with the pairs the runner logs, as F01 did
  for macos-26. `sim-destination.sh` unpairs either way, so the risk is low.
- **N6. Put the snapshot table in the PR description.** Criterion 4 wants the justification "in the PR", so
  copy the notes' 16-row table there.
- **N7. The main checkout needs cleaning after the merge.**
  - `/Users/peterarevalo/Dev/workout-app` has the same two files modified by Xcode 27, byte-identical to this
    PR's copies.
  - After the squash-merge, `git pull` there will refuse with "would be overwritten".
  - First run `git -C /Users/peterarevalo/Dev/workout-app checkout -- Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Ledger.xcodeproj/xcshareddata/xcschemes/LedgerWatch.xcscheme`.

## Pin enforcement and cache key

I tested strict `xcodebuild -resolvePackageDependencies` (plus SwiftPM where noted) on a clean copy.
"Warm" is a copy of a package directory that a strict run of HEAD populated, which is what an exact-key hit
restores.

| Case | Warm | Cold |
|---|---|---|
| HEAD as committed | — | 0 |
| Main's two lockfiles (the F32 situation) | — | **74** (xcodebuild), **1** (SwiftPM: "swift-issue-reporting added") |
| Manifest edited so that the pins no longer satisfy it (`exact: "1.17.0"`) | **74** | **74** |
| Manifest edited but the pins still satisfy it | 0 | 0 (Xcode does not call this stale) |
| Only `LedgerKit/Package.resolved` stale | — | **0**: S1 |

- **The exact-key cache is safe.**
  - The key hashes `.xcode-version` and both lockfiles.
  - `actions/cache` saves only on a miss in a successful job, and with no `restore-keys` a miss always
    resolves cold and strictly. So a restored directory was always made by a strict run from identical pins
    and the same Xcode.
  - Adding the manifests to the key (code-review candidate 1) buys nothing, as rows 3 and 4 show.
- **Local caveat.** A warm `.derivedData` or `LedgerKit/.build` can still hide a stale file locally. The
  notes and `ci-cd.md` say so, and CI always runs on a lockfile change, which is never docs-only.

## Regenerated Xcode files

- **`project.pbxproj`:** unchanged against `main`, and identical to the main checkout.
- **The project's `Package.resolved`:**
  - It is byte-identical to the file Xcode 27 wrote in the main checkout (mtime 17:49:45).
  - A non-strict `xcodebuild` resolve on a clean copy leaves it unchanged.
  - Its `swift-issue-reporting` pin is 2.1.1 at `75b000cea2ca6d7527a57e1b9cc0bdf21a9abe9f`, which matches the
    checkout's `git log` (`75b000c Fix Windows build (#200)`).
- **`LedgerKit/Package.resolved`:**
  - A non-strict `swift package resolve` leaves it unchanged.
  - It is byte-identical to the project's file, including `originHash` `3d394519…`. That is expected:
    LedgerKit is the project's only package root, and the pbxproj has no remote package references. Its
    `.pins` equal the project's.
- **`LedgerWatch.xcscheme`:**
  - It is byte-identical to the Xcode 27 write in the main checkout (mtime 17:49:46, one second after the
    lockfile).
  - The only change drops `BlueprintName` from the two runnable references. `BlueprintIdentifier` is the
    key, and `LastUpgradeVersion` stays 2660.
  - Xcode did not rewrite `Ledger.xcscheme`. It may drop the same two lines when it next saves that scheme;
    commit that when it happens.
- None of these files is `project.pbxproj`, so ADR-003 allows committing tool-written changes.

## Snapshots (criterion 4)

The four pairs below were opened with Read and diffed pixel by pixel. For every pair, the size is unchanged
and the best shift is (0, 0).

| Reference | Differing pixels | Max Δ | Where |
|---|--:|--:|---|
| `phoneTypeRamp … dark-large` | 16,070 (5.45 %) | 21 | glyph edges, x 16–364 |
| `phonePalette_scheme … dark-large` | 3,696 (1.95 %) | 21 | labels only (x 60–134); the swatches (x < 50) are pixel-identical |
| `watchTypeRamp_46mm … mm46` | 264 (0.35 %) | 1 | glyph edges |
| `ArchivoFontTests … iOS` | 414 (0.48 %) | 1 | glyph edges |

Line breaks, baselines and positions are identical by eye. This is font rendering only, and the numbers
equal the notes' table. Re-recording all 16 from one runtime is justified.

## Scripts

- **`check-xcode-version.sh`:**
  - The check moved out of `bootstrap.sh` verbatim.
  - It reads `.xcode-version` relative to the script and does not depend on the working directory.
  - `awk` avoids the SIGPIPE issue that `head` had.
  - Quoting is correct, and it is compatible with bash 3.2.
- **`check.sh`:**
  - Step 0 runs before `mise install` in every mode (W40).
  - All 4 `xcodebuild` runs are pinned (W43).
  - `--fast` is pinned (W44).
  - Diagnostics are off on every test run, including record mode, since it uses the same `run_plan` path
    (W45).
- **`bootstrap.sh`:**
  - W41 exercises it in a sandbox, which stops at the fake `simctl list runtimes`, so it has no side effects.
  - The runtime builds match the notes: iOS 27.0 is 24A434 and watchOS 27.0 is 24R362.
- **Workflows:**
  - `nightly.yml` pins its `xcodebuild` runs (WF51) and turns diagnostics off (WF53).
  - WF14's filter changed from `startswith("macos")` to "not ubuntu", which closes the vacuous pass.
  - `actionlint.yaml` is the documented way to allow the label.

## Size

- By my count, 43 non-comment code lines were added and 33 removed, 76 in total. The notes say 77. With
  comments the diff is 103 lines.
- The two lockfiles and the scheme are generated: 20 lines added, 22 removed.
- Well under the 500-line target.

## Code-review candidates (level high): disposition

| # | Candidate | Disposition |
|---|---|---|
| 1 | The cache key omits the manifests | **Refuted by test** (pin table, rows 3–4). The real gap is S1. |
| 2 | IssueReporting 2.x changes runtime behaviour | No product code uses swift-dependencies yet. It is a transitive dependency, so it needs no ADR. Folded into N2. |
| 3 | `-collect-test-diagnostics never` loses crash evidence | Accepted tradeoff: `simctl diagnose` never finished in 600 s, and the result bundle keeps the failures and logs. Revisit when R4 closes. |
| 4 | Step 0 fails `--lint-only` and `--fast` on another Xcode | This is intended (notes, decision 2). The pre-commit hooks don't call `check.sh`. The Command Line Tools case prints a clear error, which I verified. |
| 5 | The nightly's non-strict `resolve` | Folded into S1 (optional part). |
| 6 | Dropping `restore-keys` costs a cold clone | Declined. `pr.yml` runs only on `pull_request`, so caches are per-PR anyway, and a cold run happens only when the pins or the Xcode version change. |
| 7 | The fixture pairs are invented | N5. |
| 8 | Destinations are hard-coded in 4 places | Predates F32 and is outside its scope. S2's wording makes the revert the fallback. |
| 9 | The Swift version is pinned twice | N4. |
| 10 | The hint suggests `/Applications/Xcode.app` | Declined. On the image and on Pete's Mac, `Xcode.app` is 27.0. The message moved verbatim, and W41 pins it. |
