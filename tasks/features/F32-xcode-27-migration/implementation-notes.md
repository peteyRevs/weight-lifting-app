# F32 implementation notes

Base: `main` e94b501, branch `chore/F32-xcode-27`. Committed as `950bba7` (not pushed); the fix round is
uncommitted. No GitHub or Xcode Cloud setting was changed.

Toolchain: Xcode 27.0 (27A266a), Apple Swift 6.4 (swiftlang-6.4.0.34.1). Simulator runtimes: iOS 27.0 (24A434)
and watchOS 27.0 (24R362). The 26.5 runtimes are still installed.

## Decisions

1. **Pin.**
   - `.xcode-version` is 27.0.
   - SwiftFormat's compiler version is 6.4, in both `.swiftformat` and `check.sh` step 1 (they must agree).
     Formatting is unchanged: 0 of 253 files.
   - `SWIFT_VERSION` stays 6.0 and the minimum stays iOS 26.0 / watchOS 26.0. `Config/*.xcconfig` is untouched.
   - `mise.toml` is unchanged. SwiftLint 0.65.1 and SwiftFormat 0.63.0 are the newest releases
     (`mise ls-remote`), and both run clean under Swift 6.4. The `xcode-27` image ships the same SwiftFormat
     0.63.0 and xcbeautify 3.2.1.
2. **The gate hole.**
   - `scripts/check-xcode-version.sh` now holds bootstrap.sh's check, message included, moved rather than
     copied.
   - `bootstrap.sh` step 1 and `check.sh` step 0 both call it, before `mise install`.
   - Step 0 runs in every mode, so `--fast`, `--lint-only`, `--skip-lint` and `--record-snapshots` check the
     pin too.
3. **Destinations.**
   - `check.sh` defaults to `iPhone 17, OS=27.0` and `Apple Watch Series 12 (46mm), OS=27.0`, and so does the
     nightly matrix.
   - `bootstrap.sh` downloads the 27.0 runtimes and names the Series 12 in its hint.
   - New fixture `scripts/tests/fixtures/simctl/xcode-27.json`, from the image README (image 20260921.0210.1).
     It holds the iOS 27.0 phones and iPads and the watchOS 27.0 watches, with `deviceTypeIdentifier`s checked
     against Xcode 27's `simctl list devicetypes`. The UDIDs are made up.
   - **Pairs: the README lists none, so the runner's pairs are unknown** (lib.sh says so). The fixture assumes
     the pairs Xcode 27 created locally for its default set when the 27.0 runtimes installed today:
     - Series 12 (46mm) + iPhone 18 Pro Max;
     - Series 12 (42mm) + iPhone Air;
     - Ultra 4 (49mm) + iPhone 17.

     macos-26's logged pairs had the same shape. `sim-destination.sh` unpairs either way.
   - `lib.sh`: `SIMCTL_JSON` is now the xcode-27 fixture, and `SIMCTL_MACOS26` keeps macos-26.json for the
     resolution cases the 27 image cannot show (same-named twins on three runtimes, an unavailable twin).
4. **Workflows.**
   - `runs-on: xcode-27` for Check, the nightly test matrix and the dependency report. A comment says it is a
     preview image and that the fallback is `macos-26` with 26.6.
   - The "Select Xcode" step keeps working: the README lists `/Applications/Xcode_27.0.app` as a link to the
     default `Xcode_27.app`.
   - actionlint 1.7.12, the newest release, rejects the unknown label, so `.github/actionlint.yaml` names it
     (rhysd/actionlint#739 asks for it upstream).
5. **Swift 6.4 / Xcode 27: no product code changed** (criterion 5).
   - A clean build of both schemes gives no new compiler warning or error, and no deprecation.
   - The only warning, pre-existing since Xcode 26.6, is fixed (see "Warnings").
   - Xcode 27 regenerated three files, now included as written (orchestrator's decision). ADR-003 reserves only
     `project.pbxproj`, and **the pbxproj did not change.** See "Package pins".
6. **Package pins (orchestrator).**
   - Every xcodebuild in `check.sh` and the nightly passes `-onlyUsePackageVersionsFromResolvedFile`.
   - `--fast` passes `swift test --only-use-versions-from-resolved-file`, a SwiftPM 6.4 spelling (verified with
     `swift test --help`).
   - The PR cache restores on an exact key only; see "Stale-pin proof".
7. **Test diagnostics.**
   - On a failure, Xcode 27 runs `simctl diagnose --timeout=600`. Here it never finished and timed out after
     600 s per platform: "Failure collecting diagnostics from simulator: Timed out after 600.0 seconds".
   - The first record run spent 725 s in iOS tests instead of about 100 s. The Xcode 26.6 logs show no such
     step.
   - Record mode always fails, and a red CI run would burn about 20 macOS minutes and could hit
     `LEDGER_XCODEBUILD_DEADLINE`. So `check.sh` and the nightly test runs now pass
     `-collect-test-diagnostics never`.
   - The result bundle still holds every failure, log and attachment.

## Package pins: the swift-issue-reporting switch

- Xcode 27 rewrote the project's `Package.resolved`. Its pins are unchanged except that `xctest-dynamic-overlay`
  1.13.1 became **`swift-issue-reporting` 2.1.1**, and its `originHash` changed.
- **Cause: version-specific manifests.** swift-dependencies 1.17.1 and three of its Point-Free dependencies
  (combine-schedulers, swift-clocks and swift-custom-dump) declare `// swift-tools-version: 6.4` in their default
  `Package.swift`, which requires `swift-issue-reporting` (the renamed repository) from 2.1.0.
  - Swift 6.3 could not read that manifest, so it fell back to the newest `Package@swift-6.x.swift` (6.3, 6.1 or
    6.0). Those require `xctest-dynamic-overlay` from 1.13.0.
  - Swift 6.4 reads the default manifest.
- Any Swift 6.4 toolchain forces this; our requirements are unchanged. It is a new major version of
  IssueReporting, used only inside swift-dependencies. The full PR and PR-Watch plans pass on it.
- Regenerated files, none hand-edited:

  | File | By | Change |
  |---|---|---|
  | `Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | xcodebuild (package resolution) | the pin switch above |
  | `LedgerKit/Package.resolved` | `swift package resolve` | the same pins; the file is now byte-identical to the one above |
  | `Ledger.xcodeproj/xcshareddata/xcschemes/LedgerWatch.xcscheme` | Xcode 27 opening the project (in the main checkout, 17:49; copied byte for byte) | drops 2 `BlueprintName = "LedgerWatch"` lines |
  | `Ledger.xcodeproj/project.pbxproj` | none | **unchanged** |

### Stale-pin proof

Each step temporarily reverted a lockfile to main's version, then restored it (logs `f32-stale-*.log`):

| Lockfile state | Package directory | Command | Result |
|---|---|---|---|
| xcodeproj `Package.resolved` from main | **cold** (empty `-clonedSourcePackagesDirPath`) | `xcodebuild -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile` | **exit 74**: "an out-of-date resolved file was detected … swift-issue-reporting added" |
| same | warm (`.derivedData/SourcePackages` already on 2.1.1) | `build-for-testing … -onlyUsePackageVersionsFromResolvedFile` | exit 0, stale file untouched |
| `LedgerKit/Package.resolved` from main | warm `LedgerKit/.build` | `swift package resolve --only-use-versions-from-resolved-file` | exit 0; also checks out xctest-dynamic-overlay 1.13.1 next to 2.1.1 |

- Both tools trust existing checkouts over the file, and they never prune them. Comparing the workspace state
  with the lockfile would therefore fail falsely after any branch switch.
- So `pr.yml`'s package cache lost `restore-keys: spm-`. It restores only on an exact hash of `.xcode-version`
  and both lockfiles. CI then uses checkouts that a strict run made from those exact pins, or resolves cold and
  fails on a stale file. WF52 guards it.
- **Local caveat:** a warm `.derivedData` can still hide a stale lockfile. Verify a PR that changes pins after
  `rm -rf .derivedData/SourcePackages`. `docs/ci-cd.md` says so.
- **This PR changes the pins, so its gates ran cold.** Each resolved strictly and was green:
  - `LedgerKit/.build` was deleted before the first `--fast`;
  - `.derivedData` was deleted before the final full gate and before the fresh-device pass.

## Warnings

- **Fixed:** `LedgerKit/Tests/LedgerDomainTests/Engine/Adversarial/Round4StoreAdversarialTests.swift:57`, "no
  calls to throwing functions occur within 'try' expression".
  - It was not new: F04's 26.6 close-out run and a Swift 6.3 build had it. Swift 6.4 adds the
    `[#UnnecessaryEffectMarker]` tag.
  - `Since1970StampStore.highestSeq` does not throw, so the `try` is dropped. There is no behaviour change
    (orchestrator's decision), and criterion 1's zero warnings now holds.
- **New with Xcode 27: none** from the compiler, the linker or the asset tools, on either platform.
- **Tool noise, not diagnostics.** Non-quiet builds print `appintentsmetadataprocessor … warning: Metadata
  extraction skipped, no AppIntents.framework dependency found`, 19 per iOS build. `xcodebuild` logs
  `IDELaunchParametersSnapshot: debugger version lookup failed`. The gate builds with `-quiet`, and neither
  line reaches its log or the PR annotations.
- **Environment, not the project:** the first iOS build (`f32-ios-build.log`, 17:44) ran through `sim-lock.py`
  before its SDKROOT fix at 17:45:43. The leaked macOS SDKROOT caused `-Wincompatible-sysroot` on the package
  test products. **That run is not evidence.** Every later run was made after the fix, or with
  `env -u SDKROOT`.
- **Follow-up (not done here):** warnings in package targets do not fail `check.sh`, because
  `SWIFT_TREAT_WARNINGS_AS_ERRORS` in `Config/Base.xcconfig` reaches only the app targets. A small future PR
  should make LedgerKit's own targets, not third-party packages, treat warnings as errors.

## Snapshots (criterion 4)

- `scripts/check.sh --record-snapshots` ran through the lock on the 27.0 simulators and rewrote all 16
  references.
- Every PNG was opened with its main version; the phone ones were also compared as 6× crops and an 8×-amplified
  difference heatmap.
- `f32-snapdiff` compared each pair: dimensions, pixels that differ, maximum channel delta, and summed error at
  every whole-pixel shift from -2 to 2 on each axis. A layout delta shows as a non-zero best shift; every pair
  is best at (0, 0).
- A separate run of the snapshot suites against **main's** references on 27.0 records which would fail without
  the re-record.

| Reference | Pixels differing | Max Δ (of 255) | Best shift | Fails on 27.0 with main's | Class |
|---|--:|--:|:-:|:-:|---|
| phonePalette_scheme dark-large | 3,696 (1.95 %) | 21 | 0,0 | **yes** (0.9916 / 0.901) | font rendering |
| phonePalette_scheme light-large | 3,607 (1.90 %) | 20 | 0,0 | no | font rendering |
| phonePalette_increasedContrast dark-large | 3,696 (1.95 %) | 21 | 0,0 | **yes** (0.9916 / 0.901) | font rendering |
| phonePalette_increasedContrast light-large | 3,607 (1.90 %) | 20 | 0,0 | no | font rendering |
| phoneTypeRamp_appearance dark-large | 16,070 (5.45 %) | 21 | 0,0 | **yes** (0.9896 / 0.906) | font rendering |
| phoneTypeRamp_appearance dark-xLarge | 18,149 (5.68 %) | 20 | 0,0 | **yes** (0.9910 / 0.931) | font rendering |
| phoneTypeRamp_appearance dark-accessibility3 | 33,499 (5.73 %) | 16 | 0,0 | **yes** (0.9935 / 0.931) | font rendering |
| phoneTypeRamp_appearance light-large | 14,107 (4.79 %) | 20 | 0,0 | **yes** (0.9949 / 0.943) | font rendering |
| phoneTypeRamp_appearance light-xLarge | 15,680 (4.91 %) | 19 | 0,0 | **yes** (0.9945 / 0.943) | font rendering |
| phoneTypeRamp_appearance light-accessibility3 | 28,826 (4.93 %) | 15 | 0,0 | no | font rendering |
| phoneTypeRamp_boldText bold-dark-large | 16,749 (5.68 %) | 21 | 0,0 | **yes** (0.9902 / 0.912) | font rendering |
| watchPalette_46mm mm46 | 189 (0.32 %) | 1 | 0,0 | no | font rendering, ±1 |
| watchTypeRamp_46mm mm46 | 264 (0.35 %) | 1 | 0,0 | no | font rendering, ±1 |
| watchTypeRamp_boldText46mm bold-mm46 | 343 (0.46 %) | 1 | 0,0 | no | font rendering, ±1 |
| ArchivoFontTests widthAxis 88 vs 112, iOS | 414 (0.48 %) | 1 | 0,0 | no | font rendering, ±1 |
| ArchivoFontTests widthAxis 88 vs 112, watchOS | 414 (0.48 %) | 1 | 0,0 | no | font rendering, ±1 |

"Fails" gives the pixel match and the lowest perceptual precision against the required 0.995 / 0.98.

- **No layout delta; none unchanged.** Sizes, line breaks, baselines and glyph positions are identical. Only
  anti-aliased glyph edges moved.
  - On the phone, edge pixels move both ways in equal numbers: the mean signed luminance change per changed
    pixel is at most 0.5 of 255. The weight did not change; the edge coverage was redistributed.
  - Colour swatches are pixel-identical; only their labels differ.
- **All 16 are committed as recorded on 27.0.**
  - 8 would fail the gate otherwise.
  - The other 8 differ only within tolerance, but re-recording them keeps every reference from one runtime.
    A future diff then shows only the code change, not iOS 26.5's rasterisation mixed in.

## Tests

- **check-wiring:**
  - W40: step 0 fails on Xcode 26.6 with 27.0 pinned, in all five modes, before any tool, with the message.
  - W41: bootstrap.sh stops at the same check with the same words, and passes a matching Xcode on to mise.
  - W42: there is one copy of the check.
  - W43: `-onlyUsePackageVersionsFromResolvedFile` on all four xcodebuild runs.
  - W44: `--fast` pins SwiftPM.
  - W45: `-collect-test-diagnostics never` on every test run, a failing one included.
  - W23–W26 and W28–W39 now run on the xcode-27 fixture.
  - W24 asserts Xcode 27's pairs.
  - W26 also rejects Series 11 on 27.0 and F01's 26.5 default.
- **sim-destination:**
  - SD16 and SD17: the defaults resolve on the xcode-27 image.
  - SD18: Series 11, and the 26.x destinations, match nothing there.
  - SD01–SD15 stay on macos-26 for the twin and unavailable-device logic.
- **workflows:**
  - WF07 and WF50: `xcode-27` for every macOS job.
  - WF14's filter was `startswith("macos")`, which would have passed vacuously on `xcode-27`. It is now
    "not ubuntu".
  - WF15: the pin is 27.0.
  - WF48: the nightly matrix resolves on the xcode-27 fixture.
  - WF51: the nightly pins packages.
  - WF52: exact-key cache.
  - WF53: the nightly turns off test diagnostics.
- **Mutation check.**
  - Against main, in a scratch worktree of main with only the new tests copied in:
    - check-wiring fails W23 and W40–W44, plus everything downstream of the unresolved defaults;
    - workflows fails WF07, WF15, WF48, WF50, WF51 and WF52;
    - sim-destination passes, as expected, because `sim-destination.sh` is unchanged.
  - Single-property mutants of the new check.sh (`ADV_CHECK_SH`), each failing exactly its cases:
    - no Xcode check: W40 and W41 fail;
    - no xcodebuild pin: W43 alone;
    - no SwiftPM pin: W44 alone;
    - diagnostics left on: W45 alone;
    - 26.5 destinations: W23, W24, W28 and more.
- **All `scripts/tests/*.test.sh` pass:**

  | Suite | Cases |
  |---|--:|
  | check-wiring | 73 |
  | sim-destination | 25 |
  | workflows | 56 |
  | check-test-results | 18 |
  | ci-post-clone | 14 |
  | coverage-gate | 60 |
  | release-please | 16 |
  | lint-rules rounds | 55, 39, 44 |

## Gates

All ran through `sim-lock.py`, on iPhone 17 (C67249F5, iOS 27.0) and Apple Watch Series 12 (46mm) (FA05ABC5,
watchOS 27.0), from Xcode 27's default set. Logs are in the session scratchpad.

| Run | Log | State | Result |
|---|---|---|---|
| `--fast` | `f32-fast-1-before-try-fix.log` | `LedgerKit/.build` deleted: strict SwiftPM resolution from cold | OK, 118 s; 687 tests |
| `--record-snapshots`, diagnostics on | `f32-record-1-diagnose-timeout.log` | warm | stopped: iOS tests took 725 s (the 600 s `simctl diagnose`) |
| `--record-snapshots` | `f32-record.log` | warm | recorded all 16, exit 1 by design, 266 s |
| main's references on 27.0 | `f32-oldref.log` | warm | 4 iOS snapshot tests (8 references) fail; watchOS passes |
| full gate | `f32-check-1-before-try-fix.log` | `.derivedData` deleted | OK, 324 s; one warning (the `try`, once per platform) |
| `--fast`, after the `try` fix | `f32-fast.log` | warm | OK, 72 s; 687 tests, 0 warnings |
| **final full gate** | **`f32-check.log`** | **`.derivedData` deleted: cold packages, cold build** | **OK, 394 s, 0 warnings** |
| **`CI=true` runner shape** | `f32-ci-fresh.log` | `.derivedData` deleted; details below | **OK, 421 s** |

The runner-shaped pass:
- It used fresh, never-booted `f32-runner-iphone17` (iPhone 17, iOS 27.0) and `f32-runner-series12` (Series 12
  46mm, watchOS 27.0), paired to each other as the runner's are, and passed by id as F01 did.
- `LEDGER_XCODEBUILD_DEADLINE=1500`, as `pr.yml` sets it.
- Both devices were deleted afterwards.

Steps, in seconds:

| Step | Final full gate | `CI=true` fresh devices |
|---|--:|--:|
| tools, format | 1 | 1 |
| lint + script tests | 48 | 50 |
| iOS build (boot running) | 87 | 105 |
| iOS boot wait | 0 | 0 |
| iOS tests | 130 | 130 |
| watchOS build (boot running) | 37 | 44 |
| watchOS boot wait | 0 | 1 |
| watchOS tests | 89 | 88 |
| coverage | 2 | 2 |
| **total** | **394** | **421** |

Both runs:
- PR: 17 test bundles, 837 tests, 835 passed and 2 skipped, both nightly-only by design
  (`ReplayPerformanceTests`, one `.slow` test).
- PR-Watch: 8 bundles, 814 tests, 812 passed and 2 skipped (the same two).
- `check-test-results.sh` confirmed that every planned target ran.
- Coverage: LedgerDomain 98.97 % (threshold 95), LedgerDesign 95.52 % (threshold 60), overall 98.61 %
  (threshold 80).

Even from cold, the never-booted first boots were hidden behind the builds.

## Docs

- The F32 brief:
  - status in progress;
  - milestone M0, with Pete's reason;
  - runner, destinations and fallback;
  - criterion 3 deferred to Pete's Xcode Cloud setup;
  - rollback.
- `docs/ci-cd.md`:
  - the header now covers the Xcode 27 runner, the fallback, the pins and diagnostics;
  - `.xcode-version` is 27.0;
  - §5 Xcode Cloud selects 27.0;
  - §10 bootstrap names the shared check and the 27.0 runtimes.
- ADR-006: a dated amendment with Pete's decision, and a header marker.
- `docs/architecture.md`: §1 Language, Toolchain and CI/CD rows, the tree comment, and §17 risk 4.
- `docs/engineering-standards.md`: §1 Language and Xcode rows.
- `docs/xcode-cloud/README.md`:
  - Xcode 27.0 in §3–§5;
  - F32's criterion 3 added to §6's checklist.
- `tasks/todo.md`: R4 names the `xcode-27` preview, the fallback and when to close it.
- **Left alone:** `docs/testing-strategy.md` §7 and the plan YAML in `docs/ci-cd.md` §2–§3, §10 still show
  26.6, 6.3 and Series 11. They are the pre-F01 plan, which ci-cd.md's header marks as superseded by
  `scripts/`. ADR-001's "Swift 6.3" is a dated decision record.

## Size (standards §10)

Code, excluding tests, snapshots, docs and comments:

| Group | Added | Removed | Lines |
|---|--:|--:|--:|
| Code: `check.sh`, `check-xcode-version.sh`, `bootstrap.sh`, both workflows, `actionlint.yaml`, `.swiftformat`, `.xcode-version` | 43 | 34 | **77** |
| Generated by Xcode 27 / SwiftPM: two `Package.resolved`, `LedgerWatch.xcscheme` | 20 | 22 | 42 |
| Test code: one line in `Round4StoreAdversarialTests.swift`; suites and fixture under `scripts/tests/` | 280 | 31 | not counted |

The total is well under the 500-line target.

## Fix round (review S1–S3, test findings T1–T5, nits)

The orchestrator's decisions, each with its change and the test that holds it. Uncommitted; `project.pbxproj`
is untouched, and no pin changed.

| Item | Change | Test |
|---|---|---|
| **S1 = T1** both lockfiles agree | New `scripts/check-package-pins.sh`: `jq -S -c '.pins \| sort_by(.identity) \| .[]'` over each file, compared whole (identity, kind, location, version, revision, branch); `originHash`, order and layout are ignored. On a mismatch it prints a per-pin `diff -u` and how to re-resolve. `check.sh` step 2 runs it after `check-package-graph.sh`, so `--lint-only`, the full gate, `--fast` and `--record-snapshots` all run it, locally and on CI. `docs/ci-cd.md` says that the pins check covers LedgerKit's file. | PL01 unchanged and green. New in `xcode27.adv.sh`: **PL03** committed files agree; **PL04** the real regression, `LedgerKit/Package.resolved` from `e94b501` (Swift 6.3), fails and names both pins and the fix; **PL05** the reverse; **PL06** ×7 one pin differs (revision, version, location, kind, branch, one short, one extra), each failing from either file; **PL07** another `originHash`, reversed pins and keys, compact JSON still agree; **PL08** a missing, pin-less or truncated file never passes, both missing included. `check-wiring`: **W48** `--lint-only` runs it after the graph check and stops on it; W02 and W04 cover the full gate. |
| **S2** rollback wording | Reworded in `pr.yml`, `nightly.yml`, ADR-006's amendment, `docs/ci-cd.md`, `docs/architecture.md` (§1 Toolchain and §17 risk 4), `tasks/todo.md` R4 and the brief (runner section and Rollback). Each now says: rolling back to 26.6 means reverting F32 as a whole, lockfiles and snapshots included; a label-and-pin switch alone fails; it gets harder with every merge on top; `macos-26` still carries 26.6. | Docs and comments. No "fall back to macos-26" wording is left (`git grep`). |
| **S3** snapshot comment | `TokenSnapshotTests.swift:8-9` now says Series 12 46 mm, OS 27.0 (F32). | Comment only. Format and lint are clean. |
| **T2** W45 | The `check-wiring` stub `xcodebuild` now records each run's action and the value of `-collect-test-diagnostics` wherever they appear in the arguments. W45 asserts every `test-without-building` run has `diagnostics=never`, on a failing run and on both platforms. | Mutants: the flag moved to the end (C7) **passes**, and so does the flag placed before the action; the flag dropped, or set to `on-failure`, fails W45 (and W46). |
| **T3** a 27.0 beta passes | Accepted. `check-xcode-version.sh`'s header says it compares the version only: a 27.0 beta or RC reports 27.0 and passes, and the build number is not pinned. | none (documented behaviour) |
| **T4** CRLF | The three Select steps now read the pin with `$(tr -d '[:space:]' < .xcode-version)`, the expression `check-xcode-version.sh` uses. Before, `cat` kept a `\r` or a space in the path. | **XV14**: `27.0\r\n` and ` 27.0 \r\n` pass the check. **WF57** (second case): with either pin, all three Select steps select `/Applications/Xcode_27.0.app`. **WF14** now requires the shared expression in every Mac job and in the script. |
| **T5** nightly | Both nightly Mac jobs (the test matrix and the dependency report) gain a step "Check the selected Xcode against .xcode-version", `scripts/check-xcode-version.sh`, right after Select. `pr.yml` already has `check.sh` step 0. | **WF60**: in every Mac job the next `run` step after Select is `check-xcode-version.sh`, or `check.sh`, whose step 0 is the check (W40). WF56 still holds. |

**Can the project's lockfile hold extras? Not today.**
- The pbxproj has no `XCRemoteSwiftPackageReference` and no `XCLocalSwiftPackageReference`. LedgerKit is a
  folder reference, the one package root, and the app targets depend only on its two umbrella products.
- The two files are byte-identical (`cmp`), test-only packages included, so Xcode resolves LedgerKit's whole
  graph, as `swift package resolve` does.
- Extras would appear only if someone added a package to an app target in Xcode, which
  engineering-standards §1 forbids. The check then fails (PL06 extra-pin), and its message says so.
- **Does the suggested fix work?** On a scratch copy with the stale `e94b501` LedgerKit lockfile,
  `swift package --package-path <copy> resolve` exited 0 in 15 s. It rewrote the file byte-identical to the
  committed one, and the check then passed.

**Mutation check.** Each mutant ran in a scratch copy of the tree with its own `--shared` clone, so the real
index was never touched.

| Mutant | Caught by |
|---|---|
| P1 pins compared by identity only | PL04, PL06 ×5 |
| P2 identity and version only | PL04, PL06 (revision, location, kind, branch) |
| P3 prints the diff but exits 0 | PL04, PL05, PL06 ×7 |
| P4 whole files compared (`cat`: `originHash` counts) | PL04, PL07, PL08 |
| P5 `jq` errors ignored (`\|\| true`) | PL08 |
| P6 subset: only the project's extras fail | PL06 (extra-pin, one-pin-short) |
| P7 pins not sorted | PL07. The first version compared two files in the same order and missed it, so PL07 now reverses one side only. |
| C1 `check.sh` no longer runs the pins check | W02, W04, W48 |
| C2 `check-package-pins.sh \|\| true` | W04 (package-pins), W48 |
| X1 `check-xcode-version.sh` reads the pin with `head -1` (keeps `\r`) | XV14 |
| Y1 Select steps back to `$(cat .xcode-version)` | WF14, WF57 (CRLF) |
| Y2 / Y3 nightly check step dropped from the test job / the dependency report | WF60 |
| Y4 nightly check step `\|\| true` | WF60 |

WF01 (actionlint) also failed in every workflow mutant. That is an artefact of the scratch copy: mise does
not trust its `mise.toml`, so WF01 fails on the unmutated copy too. It is not counted above.

**Found, not changed (outside W45's scope):** W29, W43 and W46 select the stub's argument lines that
*start* with the action. So a correct refactor that puts a flag before the action fails them falsely. They
fail safe.

**Nits.**
- **Fixed (docs only):**
  - N1: `testing-strategy.md` goal 2 now says "CI runners (`docs/ci-cd.md`)".
  - N2: F07's risk now points at IssueReporting 2.x (`reportIssue`, `unimplemented`).
  - N3: this file's header.
- **Skipped:**
  - N4 (the Swift version in both `.swiftformat` and `check.sh`). The fix is code or a new test, not docs,
    and it predates F32.
  - N5 (the fixture's assumed simulator pairs). It needs the pairs the first `xcode-27` CI run logs, which
    do not exist yet.
  - N6 (the snapshot table in the PR description). The PR is opened later. The 16-row table is ready in
    "Snapshots" above.
  - N7 (clean the main checkout after the merge). This is a post-merge step outside this worktree. The
    command is in review.md N7.
  - Not done: S1's optional strict `resolve` in the nightly report, which was not in the orchestrator's
    list. With the pins check on every PR, LedgerKit's lockfile cannot drift from the CI-proven one.

**Size of this round.**
- Non-comment code: 19 lines in the new `check-package-pins.sh` and 17 changed lines in `check.sh`,
  `check-xcode-version.sh` and the two workflows. About 36 lines, so F32 totals about 113.
- Tests: +135 / -21 in three suites.

**Verification.**
- Every `scripts/tests/*.test.sh` exits 0.
  - The adversarial suites pass **315, fail 0 and skip 2** (SD23 and PL02, both opt-in): check-wiring 77,
    workflows 61, xcode27 44, sim-destination 25, check-test-results 18, ci-post-clone 14, coverage-gate 60,
    release-please 16.
  - coverage-gate 10 and the lint-rules suites also pass.
- `scripts/check.sh --lint-only` is **OK in 43 s** (`f32-fix-lint.log`). Step 0 printed `Xcode 27.0 ✓` and
  step 2 printed `package pins agree … (9 pins)`.
- shellcheck 0.11.0 is clean, except for the known `check.sh:55` SC2154 and the suites' SC1091 info, both
  also on HEAD.
- **Full gate:** `sim-lock.py scripts/check.sh` (`f32-fix-check.log`), run warm because no pin changed.
  - Result: **OK, exit 0, 365 s, 0 warnings.**
  - Steps, in seconds: lint 47, iOS build 46, iOS boot 3, iOS tests 149, watchOS build 26, watchOS boot 0,
    watchOS tests 91, coverage 2.
  - Step 2 printed `package pins agree … (9 pins)`.
  - `check-test-results.sh` saw 17 targets ran and passed for PR, and 8 for PR-Watch.
  - Coverage: LedgerDomain 98.97 %, LedgerDesign 95.52 %, overall 98.61 %.
