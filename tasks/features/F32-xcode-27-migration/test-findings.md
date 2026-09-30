# F32 test findings (Adversarial Tester)

I tested commit `950bba7` on `chore/F32-xcode-27` on 2026-09-29, with Xcode 27.0 (27A266a) and Swift 6.4.
I wrote the tests from these sources:
- the brief;
- `docs/ci-cd.md`;
- `git diff main...HEAD` of the scripts, workflows and `scripts/tests/`;
- the `xcode-27` image README (actions/runner-images `images/macos/xcode-27-arm64-Readme.md`, image
  20260921.0210.1), fetched today.

I read `implementation-notes.md` only after the tests were written, to cross-reference them.

## What was written

| File | Cases | What it attacks |
|---|---|---|
| `scripts/tests/adversarial/xcode27.adv.sh` (new) | XV01–XV13 | the real `check-xcode-version.sh` against a stub `xcodebuild` (patch, minor, major, prefix and suffix versions; missing or empty pin; `xcodebuild` failing or absent; run from another directory). XV12–XV13 go through Apple's `/usr/bin/xcodebuild` shim with `DEVELOPER_DIR` at a fake 26.6 developer directory, or at a missing one |
| | SD19–SD23 | the real `sim-destination.sh` on variants of the xcode-27 fixture: twin iPhone 17s on iOS 27.0 in either order; an override; both defaults paired with each other, against a stateful fake simctl whose `unpair` fails on a pair that no longer exists, as the real one does. SD23 (opt-in) resolves `check.sh`'s defaults against this Mac's real simulators |
| | PL01–PL02 | the two committed lockfiles (T1). PL02 (opt-in, network) resolves a stale project lockfile from cold packages, with and without `check.sh`'s flag |
| | WF54–WF58 | every job's runner; the cache key's inputs; the Select step's position; the Select steps run as the runner would, against the image's paths; actionlint's config (minimal, needed, and a mistyped label still fails) |
| `scripts/tests/adversarial/check-wiring.adv.sh` | W46–W47 | `--record-snapshots` (the other branch of `run_plan`) pins packages and skips diagnostics; `--fast`'s `swift test` gets neither `xcodebuild`-only flag |
| `scripts/tests/adversarial/workflows.adv.sh` | WF59 ×5 | the Scope step: a PR touching only `.xcode-version`, either lockfile, `.swiftformat` or `.github/actionlint.yaml` starts Check |

Run them:

```sh
scripts/tests/adversarial/run.sh xcode27                          # host only, ~2 s
ADV_REAL_SIMCTL=1 scripts/tests/adversarial/run.sh xcode27        # + SD23: simctl list only, unpair is faked
ADV_COLD_PINS=1 scripts/tests/adversarial/run.sh xcode27          # + PL02: network, ~650 MB under $TMPDIR, ~30 s
```

The suites are bash 3.2 (the image ships only 3.2.57) and pass shellcheck.

## Results

| Run | Result |
|---|---|
| Every `scripts/tests/*.test.sh` | all exit 0. Adversarial suites: **298 passed, 0 failed, 2 skipped** (SD23 and PL02, both opt-in); 262 passed before this round. lint-rules 55 / 39 / 44 and coverage-gate 10 also pass |
| `scripts/check.sh --lint-only` | **OK, 46 s**; step 0 printed `Xcode 27.0 ✓` |
| The opt-ins, run here | SD23 ok: iPhone 17 → `C67249F5…`, Series 12 (46mm) → `FA05ABC5…`. PL02 ok |
| Everything again under `/bin/bash` 3.2.57 | same results |
| Full gate | **not run**. Every new case is host-only, and none needs a simulator |

Real-tool experiments, on scratch copies of the repository (the worktree was not touched):

| Lockfile | Package directory | Command | Result |
|---|---|---|---|
| project lockfile from `main` (stale) | cold | `xcodebuild build-for-testing` with `check.sh`'s arguments | exit 74 in 12 s, "Could not resolve package dependencies"; file untouched |
| same | cold | `xcodebuild -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile` | exit 74, "an out-of-date resolved file was detected"; file untouched |
| same | cold | the same, without the flag | exit 0, **file rewritten** |
| same | warm (resolved from the committed file) | the same, with the flag | **exit 0** |
| `LedgerKit/Package.resolved` from `main` | cold / warm scratch path | `swift package resolve --only-use-versions-from-resolved-file` | exit 1 / **exit 0** |
| committed lockfiles; `Package.swift` requirement moved so it excludes the pin (GRDB `7.10.x`) | cold / warm | the same | exit 1 / exit 1 |
| committed; a new root dependency with no pin (swift-case-paths) | cold / warm | the same | exit 1 / exit 1 |
| committed; a root dependency already pinned transitively (swift-custom-dump) | cold / warm | the same | exit 0 / exit 0 (SwiftPM does not count this as stale) |
| **`LedgerKit/Package.resolved` from `main`**, project lockfile committed | **cold** | `xcodebuild -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile` (CI's path) | **exit 0**, LedgerKit's file ignored (T1) |

## Mutation check

Each mutant ran in a scratch clone against `check-wiring`, `sim-destination`, `workflows` and `xcode27`.
"Existing" means any case written before this round, including the implementer's W40–W45, SD16–SD18 and
WF50–WF53.

| Mutant | Caught by existing cases | Caught by new cases |
|---|---|---|
| X1 `check-xcode-version.sh` accepts a prefix (`!= "$PINNED"*`) | **none** | XV03, XV06, XV08 |
| X2 compares the major version only | **none** | XV03, XV04, XV06 |
| X3 reads `.xcode-version` from the working directory | **none** (`check.sh` and `bootstrap.sh` `cd` to the root first) | XV01–XV06, XV12 |
| X4 no `pipefail` (a failing `xcodebuild` that printed 27.0 passes) | **none** | XV09 |
| X5 warns and exits 0 | W40, W41 | XV03 and others |
| C1 Xcode check after `mise install` | W02, W04, W09, W40 | |
| C2 `check-xcode-version.sh \|\| true` | W04, W40 | |
| C3 pin flag on `build-for-testing` only | W43 | W46 |
| C4 `--fast` without the SwiftPM pin | W44 | |
| C5b diagnostics flag dropped in record mode only | **none** | W46 |
| C6b pin flag dropped in record mode only | **none** | W46 |
| C7 diagnostics flag moved to the end of the test command (a **correct** refactor) | W45 fails falsely (T2) | |
| S1 `sim-destination.sh` without `first(…)` (twins on one runtime give two UDIDs) | **none** (SD01–SD18, W23–W26 all pass) | SD19, SD20 |
| S2 unpairs only pairs where the device is the watch | SD11–SD13, W24 | SD20 |
| Y1 cache key without `.xcode-version` | **none** (WF12 checks a hard-coded file list, not the key; WF52 checks `restore-keys` only) | WF55 |
| Y2 cache key without the project lockfile | **none** | WF55 |
| Y3 `restore-keys: spm-` put back | WF52 | |
| Y4 Select step moved after `check.sh` | **none** (WF14 checks that the step exists, not its order) | WF56 |
| Y5 / Y6 nightly loses the pin flag / the diagnostics flag | WF51 / WF53 | |
| Y7 dependency report back on `macos-26` | WF50 | WF54 |
| Y8 `actionlint.yaml` also ignores every error (`paths: …: ignore: ['.*']`) | **none** (WF01 then passes) | WF58 |
| Y9 Scope counts root dotfiles as docs (`.*) ;;` after `*/*`) | **none** | WF59 |
| L1 `LedgerKit/Package.resolved` reverted to `main`'s (stale) | **none** | PL01 |

**Answer to the brief:** yes, plausible bugs slip past W40–W45, SD16–SD18 and WF50–WF53:
- the version comparison itself (X1–X4);
- twin simulators on one runtime (S1: this Mac's own case);
- the inputs of the cache key (Y1, Y2);
- the order of the Select step (Y4);
- the record-mode branch (C5b, C6b).

Each is now caught. The implementer's removal mutants (notes, "Mutation check") hold as they claimed.

---

## Findings

### T1: `LedgerKit/Package.resolved` is outside CI's pin enforcement (minor bug; guarded by PL01)

`docs/ci-cd.md` says a stale `Package.resolved` fails instead of being rewritten. For the project's lockfile
that is true in CI: the cache key is exact, and the package directory is cold on a key change. For
`LedgerKit/Package.resolved` it holds nowhere in practice:
- Xcode ignores a local package's own lockfile. CI's `xcodebuild` resolved **from cold** with `main`'s stale
  LedgerKit lockfile: exit 0.
- `check-package-graph.sh` runs `swift package describe`, which does not resolve. From a cold scratch path it
  wrote no checkouts and left the file untouched.
- The nightly's dependency report runs `swift package resolve` without the flag. It would rewrite the file on
  the runner, silently.
- Only `check.sh --fast` reads it with the flag. CI never runs `--fast`, and locally `LedgerKit/.build` is warm,
  where a stale file passes (the notes' own table shows exit 0).

So the file can drift from the graph CI proves. Nothing fails until someone runs `--fast` on a fresh clone
(`bootstrap.sh` step 5). The file is also in the PR cache key, which only costs a spurious cache miss, since
`xcodebuild` never reads it.

Repro:
```sh
git show main:LedgerKit/Package.resolved > LedgerKit/Package.resolved     # the Swift 6.3 pins
swift package --package-path LedgerKit resolve --only-use-versions-from-resolved-file   # warm: exit 0
# CI's path, from cold packages, on a copy of the repo:
xcodebuild -resolvePackageDependencies -project Ledger.xcodeproj -scheme Ledger \
  -clonedSourcePackagesDirPath /tmp/cold -onlyUsePackageVersionsFromResolvedFile        # exit 0
git checkout -- LedgerKit/Package.resolved
```

**Guard added:** PL01 requires the two lockfiles to pin the same packages. It compares identity, kind,
location, revision and version, and ignores `originHash`. Today they are byte-identical. With PL01 in
`check.sh` step 2, CI's cold proof of the project lockfile covers LedgerKit's too. The rule holds because the
app targets have no packages of their own (the pbxproj has no `XCRemoteSwiftPackageReference`), so both files
describe one graph. The implementer may prefer to enforce this another way, for example a strict
`swift package resolve` of LedgerKit in CI. PL01 then goes.

### T2: W45 fails a correct refactor (minor bug, test)

W45 greps `' -collect-test-diagnostics never '` with a trailing space. If the flag becomes the last argument
of the test command, which is still correct, both W45 cases fail (mutant C7). W43 already allows the flag at the
end of the line (`\( \|$\)`), and my W46 now does the same; W45 should too. It fails safe (a false red, not a
false green), so I left it as it is.

### T3: A 27.0 beta or RC passes step 0 (question)

`check-xcode-version.sh` compares only the marketing version. A 27.0 beta or RC reports `Xcode 27.0` with a
build like `27A5218g`, and it passes:
```sh
# stub xcodebuild printing "Xcode 27.0\nBuild version 27A5218g", .xcode-version 27.0
scripts/check-xcode-version.sh      # Xcode 27.0 ✓, exit 0
```
The image's 27.0 is 27A266a. `.xcode-version` cannot express a build, and the old bootstrap check behaved the
same, so this is not a regression. Should the gate also pin the build, for example on a second line that only
`check-xcode-version.sh` reads? Or is "27.0, any build" the intended pin?

### T4: CRLF or spaces in `.xcode-version` split local from CI (question)

The check strips all whitespace (`tr -d '[:space:]'`). The three Select steps use `$(cat .xcode-version)`,
which strips only trailing newlines:
- `27.0\r\n` passes `check.sh` locally, but the workflow selects `/Applications/Xcode_27.0\r.app`.
- ` 27.0` does the same with `/Applications/Xcode_ 27.0.app`.

CI fails closed at `xcode-select`, so nothing wrong ships. It is still a "local green, runner red" gap, and the
repo has no `.gitattributes` to prevent it. Should the Select steps trim the same way, or the check reject
anything but `27.0` and a newline?

### T5: The nightly never compares the selected Xcode with the pin (question)

In `pr.yml`, `check.sh` step 0 re-checks whatever the Select step chose. The nightly's test and
dependency-report jobs select `/Applications/Xcode_$(cat .xcode-version).app` and only print
`xcodebuild -version`. Today that path is a link to 27A266a, per the README. The images do relink versioned
names; this one already links `Xcode_27.0.0.app` and `Xcode.app`. If that happens, the PR goes red at step 0,
but the nightly runs quietly on the other Xcode. Adding `&& scripts/check-xcode-version.sh` to those two steps
would close it.

---

## Attacked and held

- **Exact version pin.**
  - 27.0.1 against 27.0, both ways, and 27.1, 27, 127.0, 27.01 and 7.0 against 27.0: all refused, with both
    versions named (XV03–XV06).
  - A pin without a trailing newline is fine (XV02).
  - A missing or empty `.xcode-version` fails (XV07, XV08).
  - `xcodebuild` failing, absent, or on the Command Line Tools only: fails, no ✓ (XV09–XV11).
  - Run from another directory, the repository's pin still counts (XV01).
- **`DEVELOPER_DIR`.** Apple's shim honours it (XV12, XV13), so the check reads the same Xcode that every later
  `xcodebuild`, `xcrun` and `swift` uses. A different Xcode fails; a missing directory fails.
- **Every mode checks.** `--fast`, `--lint-only`, `--skip-lint`, `--record-snapshots` and the full gate all
  check before any tool runs (W40). `bootstrap.sh` gives the same message (W41).
- **The CI-selected Xcode in the PR.** The Select step picks `Xcode_27.0.app`, and `check.sh` step 0 compares
  it again.
  - The README lists `/Applications/Xcode_27.app` (27.0, 27A266a, the default), linked as `Xcode_27.0.app`,
    `Xcode_27.0.0.app` and `Xcode.app`.
  - All three Select steps, run for real with fake `sudo` and `xcode-select`, pick a listed path (WF57).
- **Destinations.**
  - The defaults resolve on the fixture (SD16, SD17) and on this Mac (SD23).
  - The fixture's device list matches the README exactly: iPhone 17, 17e, 18 Pro, 18 Pro Max, Air, and five
    iPads on iOS 27.0; SE 3 40/44, Series 12 42/46 and Ultra 4 on watchOS 27.0. It has no Series 11 and no
    26.x (SD18).
  - Twin iPhone 17s on one runtime give exactly one destination, the first simctl lists, the same on every call.
    Only its own pair is left (SD19, SD20).
  - Overrides resolve and unpair (W25, SD21).
  - Both defaults paired with each other: the iPhone's lookup unpairs them, and the watch's lookup sees the pair
    gone and does not unpair twice (SD22).
- **Pins.**
  - Every `xcodebuild` in `check.sh` passes `-onlyUsePackageVersionsFromResolvedFile`, record mode included
    (W43, W46), and so does the nightly (WF51). `--fast` passes `--only-use-versions-from-resolved-file` (W44).
  - A stale lockfile fails from cold, and the file is kept. Without the flag it is rewritten (PL02 and the
    table above).
  - The exact-key cache is sound: `actions/cache` saves only after a green job (`post-if: success()`). So a
    restored `SourcePackages` is always a strict resolution of that key's pins, under that Xcode.
  - A manifest change with unchanged lockfiles behaves the same warm and cold (the table), so `Package.swift`
    need not be in the key.
  - The nightly caches nothing, so its matrix proves the project lockfile cold on every run.
  - `mise-action`'s cache holds tools, not packages.
  - The key covers `.xcode-version` and both lockfiles, and every pattern in it matches a tracked file (WF55).
- **`-collect-test-diagnostics never`.**
  - It is on every test run: failing, green and record mode (W45, W46), and on the nightly (WF53).
  - It is absent from `swift test`, which does not know it (W47).
  - `xcodebuild build-for-testing` accepts it and ignores it (checked), so its absence there matters to no one.
  - Not re-verified: that it removes the 600 s `simctl diagnose`. That needs a failing simulator run, and no
    test here needed the lock.
- **Workflows.**
  - Every job runs on `ubuntu-*` or `xcode-27`, including any job added later (WF54, WF07, WF50).
  - Each Mac job selects Xcode once, before anything builds, tests or resolves (WF56).
  - `actionlint.yaml` declares exactly the one label. Without it, actionlint 1.7.12 rejects `xcode-27`; with it,
    a mistyped label is still rejected (WF58, WF01).
  - Docs-only PRs still skip the Mac (WF18, WF39), and the toolchain pin files still start it (WF59).
- **`check-package-graph.sh`.** Its `swift package describe` resolves nothing, from a cold scratch path.
- **`.swiftformat` against `check.sh`.** Both use Swift 6.4, and `swift --version` here is 6.4 (6.4.0.34.1).

**Verdict: F32's tooling holds.** I found no bug that blocks the merge, and no new case fails. T1 is a real gap,
now closed by PL01 until the implementer confirms that guard or replaces it. T2 is a brittle test that fails
safe. T3–T5 are questions for Pete.
