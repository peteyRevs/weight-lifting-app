# CI efficiency notes (2026-09-30 to 2026-10-01)

Base: `main` 7740bd9, branch `chore/ci-efficiency`. Pete approved three changes on 2026-09-30, after the
free macOS minutes ran out and he set a $60 monthly limit. Each push to a code PR costs about $1–2.
`docs/ci-cd.md` ("CI efficiency") is the short form of this file.

## Where the minutes went

From the Actions API, for the six green `Check` jobs since PR CI went iOS-only (runs 36724955416,
36731346913, 36789015183, 36791318043 attempt 3, 36802178287, 36881427263):

- The job took 846–1,302 s, which bills as 15–22 minutes. `check.sh` was 805–1,262 s of that.
- Run 36791318043, attempt 3, by step: tools 1 s, format 4 s, lint and script tests 125 s, iOS build
  745 s, boot 2 s, iOS tests 363 s, coverage 4 s; 1,245 s in all.
- The same run's attempt 1 failed with exit 75 at 1,514 s. Its iOS build alone took 1,104 s, so the
  1,500 s deadline arrived before the tests could finish. Nothing was wrong with the code: attempt 3
  passed unchanged.

So the build is 60–73% of a run, the tests about 30%, and format, lint and the script tests about 10%.

## What changed

1. **Deadline.** `LEDGER_XCODEBUILD_DEADLINE` is 2,400 s (was 1,500). The step's timeout is 42 minutes
   (was 27) and the job's 47 (was 30). WF49 still requires the deadline to fall 1–5 minutes before the
   step's timeout; WF65 pins 2,400 and that the job outlasts the step.
2. **Compilation cache.** With `LEDGER_COMPILATION_CACHE=YES`, which only `pr.yml` sets, `check.sh`
   passes `COMPILATION_CACHE_ENABLE_CACHING=YES` to both `build-for-testing` calls and to nothing else
   (W65). `pr.yml` restores `.derivedData/CompilationCache.noindex` before `check.sh` and saves it after
   (WF64, WF11).
3. **Static checks on Linux.** A new `Static checks` job on `ubuntu-latest` runs `check.sh
   --static-only`. `Check` needs it and runs `check.sh --ios-only --skip-static` (WF04, WF05, WF07, WF08,
   WF63; W58–W69).

## Design decisions

### `restore-keys` for the compilation cache, but not for `SourcePackages`

The compilation cache's key is `compilation-<hash of .xcode-version and both lockfiles>-<commit>`, and
its `restore-keys` is the same without the commit. A run therefore starts from the newest cache its
branch, or `main`, has saved for the same Xcode and pins.

That is safe because of what the cache is. Each entry is one compilation's output, stored under a hash
of the compiler, its arguments and the contents of every input. A stale cache cannot supply a wrong
result: an entry either matches the inputs exactly or is not used. An old cache costs only misses.
"Measured" below shows a changed file compiling again, and a fresh checkout's mtimes changing nothing.

`SourcePackages` is the opposite. `xcodebuild` trusts the checkouts it finds over `Package.resolved`, so
another run's checkouts would let a stale lockfile build (F32 notes, "Package pins"). That cache keeps
its exact key, and WF52 now checks exactly that step.

The save step runs after a red run too, since the cache holds only finished compilations, so the push
that fixes a failure starts warm. It does not run when the run was cancelled, because a newer push is
already running, nor when the restore hit the exact key (a re-run of the same commit).

### No warm-up job on `main`

Superseded 2026-10-20: first runs reached the deadline on a cold build, and the repository went public (free
standard minutes), so `main-cache.yml` now saves `main`'s caches on each code push
(`tasks/chores/2026-10-17-main-cache.md`, `tasks/chores/ci-test-time.md`). The reasoning below was the cost side.

No job saves a cache on `main`, so a PR's first run has nothing to restore. A job that did would run a
cold build on every merge, which is the most expensive step there is (745–1,104 s on the runner). At
best it would save the same build once, on the next PR's first run. With about one PR per merge that
is a wash, and it is a loss whenever two merges land before the next PR opens. Later pushes to a PR
are already warm from the PR's own cache.

If first runs turn out to dominate, a manual `workflow_dispatch` of `PR` on `main` saves a cache in
`main`'s scope, which every PR can restore. This is how GitHub scopes caches; it has not been tried here.

### Which suites need macOS

`scripts/tests/adversarial/run.sh` reads `LEDGER_ADV_SUITES`: `portable` skips the suites whose header
has a `# needs macOS: <why>` line, `macos` runs only those, and unset or `all` runs every one. Four
suites carry the line (W68 pins the list):

| Suite | Case | Why |
|---|---|---|
| `catalog-version-attack` | V10 | Edits a file with BSD `sed -i ''`, which GNU sed reads as a script. |
| `ci-post-clone` | PC12 | Runs the real `xcodebuild -showBuildSettings`; it skips when there is no xcodebuild. |
| `coverage-gate` | C27 | Runs the real `xccov` through `xcrun`; it skips when there is none. |
| `xcode27` | XV12, XV13 | Go through Apple's `/usr/bin/xcodebuild` shim with `DEVELOPER_DIR`; they skip elsewhere. |

A suite is marked as a whole when one case needs macOS. On Linux, PC12, C27, XV12 and XV13 would skip
without failing, and CI would then test less than it did. The other six suites (`catalog-version`,
`check-test-results`, `check-wiring`, `release-please`, `sim-destination`, `workflows`) fake `xcrun`,
`xcodebuild` and `simctl`, and passed in a Linux container (below). The four `lint-rules*.test.sh`
files and `coverage-gate.test.sh` passed there too.

`check.sh` alone picks the half. It drops any `LEDGER_ADV_SUITES` it inherits, then sets `portable` for
`--static-only`, and passes `macos` to the one call `--skip-static` makes. See "What was wrong".

## What was wrong in the half-finished change

1. **`--static-only` failed its own suite.** `check.sh --static-only` exported
   `LEDGER_ADV_SUITES=portable`, and `check-wiring.adv.sh`, which runs in that half, starts sandboxed
   `check.sh` runs that inherited it. W61 ("the full gate and `--lint-only` run every suite") then saw
   `portable` and failed. `scripts/check.sh --static-only` exited 1 on the Mac, and would have on the
   runner. It was a real hole as well as a test artefact: a shell that exported the variable would have
   narrowed the full gate without a word. `check.sh` now unsets it before choosing, and W69 runs the
   full gate and `--lint-only` with the variable exported.
2. **No `restore-keys`.** The restore step's comment, `docs/ci-cd.md` and WF64 all described one;
   `pr.yml` had none, so WF64 failed and no run could ever have started warm except a re-run of the same
   commit. Added.
3. **Numbers without evidence.** `docs/ci-cd.md` gave a hit build as 20–22 s against 62–82 s cold, and
   the stored cache as about 200 MB. The measurements were lost; they are redone below, and the document
   now carries those figures (17–18 s, 57–59 s, 343 MB). Its "805–1,290 s" mixed a step's time with a
   job's; it now gives both ranges from the API.
4. **Two claims that were not quite true.** The workflow comment said SwiftLint would skip the custom
   rules without SourceKit; version 0.65.1 stops with a fatal error instead. The document said Xcode
   validates a restored cache; it validates once per boot, which comes to the same thing on a runner
   but not on a developer's Mac ("Measured", 4).

## Verified locally

All on this Mac (Xcode 27.0, 27A266a), 2026-10-01, on the uncommitted tree.

- `scripts/check.sh --lint-only`: exit 0 in 61 s. All 10 adversarial suites (442 cases, 2 skipped: the
  opt-in SD23 and PL02), `coverage-gate.test.sh` and the four lint-rules files.
- `scripts/check.sh --static-only`: exit 0 in 31 s. 6 suites (`portable`), 272 cases.
- `LEDGER_ADV_SUITES=macos scripts/tests/adversarial.test.sh`: exit 0 in 33 s. 4 suites, 170 cases and
  the same 2 skipped. This is what `Check` still pays for on macOS, where step 2 took 108–125 s before.
- `actionlint` 1.7.12 (mise) on `pr.yml`: no findings. WF01 also runs it in the suite.
- Mutations (`scratchpad/ci-eff/mutate.sh`), each failing the case named and then reverted: no
  `restore-keys` (WF64); no `unset LEDGER_ADV_SUITES` (W61 and W69, with and without `portable`
  exported); the deadline back at 1,500 (WF49, WF65); `Check` not needing `Static checks` (WF05); a
  `# needs macOS:` line removed (W68); the cache on for any value of the variable (W65); the save step
  without `!cancelled()` (WF64); `--static-only` keeping the Xcode check (W58, W59); `--skip-static`
  running every suite (W62, W63); `run.sh` ignoring the half (W66, W67).
- Not run: `check.sh --ios-only --skip-static` against real simulators. W62 and W63 cover its order of
  steps with stubs; the iOS build and tests themselves are unchanged apart from the cache setting,
  which the measurements below exercise.

### The Linux job, in a container

Docker Desktop, image `swift:6.4-noble` (Ubuntu 24.04, Swift 6.4, as the runner image's README lists
for 20260920.314.1). A clone of the tree with the changes committed and `HEAD` detached was mounted at
`/home/runner/work/workout-app/workout-app`. `/usr/share/swift/usr` was linked to `/usr`, so that
`LINUX_SOURCEKIT_LIB_PATH=/usr/share/swift/usr/lib` resolves as it should on the runner. Tools came
from `mise install`; `GITHUB_ACTIONS=true`.

- **arm64, native: `check.sh --static-only` exit 0 in 22 s** (format 10 s, lint and every portable suite
  12 s). SwiftFormat checked 355 files; the package graph, pins and catalog version passed; 6 suites
  passed, with no skipped case; the lint-rules fixtures fired. xcbeautify has no Linux arm64 build, so
  it was left out there (`MISE_DISABLE_TOOLS=xcbeautify`); `--static-only` never calls it.
- **amd64, emulated: all six tools installed**, xcbeautify included
  (`xcbeautify-3.2.1-x86_64-unknown-linux-gnu.tar.xz`), so `mise install` should pass on the runner,
  which is x86-64. SwiftFormat then crashed (segmentation fault) under the emulation, so nothing after
  step 0 ran on amd64. The same binary's arm64 build ran clean, which points at the emulator, but that
  is an inference.
- **Without SourceKit** (library hidden, variable unset): SwiftLint died with `Fatal error: Loading
  libsourcekitdInProc.so failed`, exit 133. The job cannot go green with the custom rules silently off.
- Not shown: that the variable is what finds the library. In this image the library is also in
  `/usr/lib`, where SwiftLint looks anyway.

### Measured: the compilation cache

Method: `scratchpad/ci-eff/measure.sh`, run alone under the simulator lock. It runs the
`build-for-testing` that `check.sh` runs for iOS (scheme `Ledger`, plan `PR`, the iPhone 17 simulator
by UDID, the same DerivedData and package paths, packages already resolved), without `-quiet` so the
log shows each `Cache hit` and `Cache miss`. Between builds it deletes everything under `.derivedData`
except `SourcePackages` and, for a warm build, `CompilationCache.noindex`. Before a warm build it also
touches every tracked file under `Apps` and `LedgerKit`, as a fresh checkout would.

1. **Times.**

   | Build | Time | Hits | Misses |
   |---|---|---|---|
   | Cache off | 59 s, 58 s | – | – |
   | Cache on, empty | 57 s | 0 | 1,113 |
   | Cache on, full, mtimes moved | 18 s, 17 s | 1,003; 1,018 | 0 |

   A first attempt gave 95, 69, 23–29 and 89 s. It ran while the script suites and a container were
   also running, and its first build fetched the packages, so it is discarded.
2. **Size.** 1.0 GB in 1,851 files after one build, and the same after the warm one. 343 MB through
   `tar | zstd`, which is how `actions/cache` stores a path on the runner.
3. **A changed input compiles.** With a full cache, a comment appended to
   `LedgerKit/Sources/LedgerDomain/Units/Weight.swift` gave 974 hits and 33 misses in 19 s.
4. **A corrupt cache** (`corrupt.sh`, `corrupt2.sh`: 1 MB in the middle and 1 MB near the start of the
   largest file, `builtin/v1.1/v9.data`, overwritten with random bytes):
   - Xcode's `ValidateCAS` step validates once per boot. `builtin/v1.validation` holds the boot time of
     the last validation, and the step prints `validation skipped` when that equals this boot.
   - With the marker set to another boot time, as a restored cache has on a new runner, the step
     printed `recovered from invalid data`, and the build filled the cache again: exit 0, 1,113 misses,
     58 s. The next build had 1,012 hits.
   - With the marker left at this boot, the build failed: exit 65, `CAS-based dependency scan failed:
     not a IncludeTreeRoot node kind`. A runner cannot be in that state for a cache it restored, unless
     the cache is damaged during the job.
   - Validating a sound cache from another boot cost nothing measurable: 19 s, `validated successfully`.

The Mac built in 58 s what the runner takes 745–1,104 s to build, so none of these times carry over.
The ratio (a full cache took about 30% of the cold time here) may not either.

## Only the first CI runs can show

1. **The Linux job on the real runner.** That `jdx/mise-action` installs the six tools on
   `ubuntu-latest`; that SwiftLint finds SourceKit through `LINUX_SOURCEKIT_LIB_PATH=/usr/share/swift/usr/lib`
   (the path comes from the image's install script, not from a run); that the image's Swift still reads
   `LedgerKit/Package.swift` for `check-package-graph.sh`; that SwiftFormat does not crash on x86-64.
   A failure here is cheap: the job is on Linux, and `Check` does not start.
2. **Cache save and restore.** That the save step stores the directory after green and red runs; that a
   PR's second push restores it through `restore-keys`; that `ValidateCAS` accepts it; and that the
   build then reports hits. The keys are taken to include absolute paths, and the runner's checkout path
   is fixed, but no build here ran from a second path.
3. **Real timings.** The build's time on a PR's second run, against 745–1,104 s cold; what restoring and
   saving a cache of this size cost in macOS seconds; how long `Static checks` takes, and how much
   later `Check` therefore starts; how long the four macOS suites take in `Check`.
4. **Cache storage.** Each push saves a new cache of about 340 MB or more, since a save includes what it
   restored. A repository's caches are capped at 10 GB and evicted least recently used first, so about
   30 pushes fill it. The package cache is read by every run and should survive; watch for a run that
   resolves packages cold after a busy week.

## If it goes wrong

- A build fails with a `CAS` error: delete the `compilation-` caches (`gh cache list`, `gh cache
  delete`) and re-run. Removing `LEDGER_COMPILATION_CACHE` from `pr.yml` turns the feature off; the
  restore and save steps are then harmless.
- `Static checks` fails for a reason that is the runner's and not the code's: `Check` will not start.
  The full local gate still runs everything, and is the merge evidence (`docs/ci-cd.md` §4).
