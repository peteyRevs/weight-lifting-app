#!/usr/bin/env bash
# The local gate. Green check.sh is the minimum bar for a PR
# (docs/testing-strategy.md §7 — this script implements that contract).
#
#   scripts/check.sh                    full gate: format, lint, iOS, watchOS, coverage
#   scripts/check.sh --fast             host-side package tests only; no simulators
#   scripts/check.sh --lint-only        steps 0–2 only
#   scripts/check.sh --skip-lint        steps 3–5 only (no format, lint or script tests)
#   scripts/check.sh --record-snapshots re-record snapshot references on both
#                                       simulators, then fail; re-run to verify
#   scripts/check.sh --ios-only         steps 0–3 and 5: no watchOS step, and the coverage gate
#                                       reads the iOS bundle alone. PR CI runs this (Pete,
#                                       2026-09-30; docs/ci-cd.md); the full gate, before every
#                                       merge, runs both. Combines with --skip-lint and
#                                       --record-snapshots (iOS references only)
#   scripts/check.sh --static-only      step 2 without the script suites that need macOS, and step 0
#                                       without the Xcode check: PR CI's Linux job (docs/ci-cd.md)
#   scripts/check.sh --skip-static      steps 0, 1 and 3–5, plus the script suites that need macOS: PR
#                                       CI's macOS job, which runs after the Linux one. Combines with
#                                       --ios-only and --record-snapshots
#   scripts/check.sh --build-only       step 0 and step 3's iOS build alone, as step 3 runs it: no
#                                       simulator boot, string catalogs, tests or coverage. main-cache.yml
#                                       runs it on each push to main to save main's compilation cache
#                                       (docs/ci-cd.md, "Compilation cache"). Takes no other flag
#   scripts/check.sh --ios-only --shard <n>/<count>
#                                       step 3 tests shard <n>'s test targets alone (scripts/pr-shards.txt;
#                                       the others are skipped), and step 5 is left to
#                                       scripts/check-shards.sh, which checks and gates every shard's
#                                       bundle. PR CI's Check jobs, one per shard (docs/ci-cd.md,
#                                       "Shards"). Needs --ios-only or --watch-only; combines with
#                                       --skip-lint, --skip-static and --nightly
#   scripts/check.sh --watch-only       steps 0–2 and 4: the watchOS step alone, and no coverage gate (it
#                                       reads both platforms). Combines with --skip-lint, --skip-static,
#                                       --nightly and --shard
#   scripts/check.sh --nightly          steps 3 and 4 test the Nightly plans (Nightly, Nightly-Watch), and
#                                       step 5 is skipped: coverage is the PR lane's gate. The nightly's
#                                       legs run --nightly --skip-lint with --ios-only or --watch-only and
#                                       --shard (docs/ci-cd.md, "Nightly legs"). Takes no --fast,
#                                       --lint-only, --static-only or --record-snapshots
#
# Step 3 also checks every String Catalog against the keys its iOS build extracted
# (scripts/check-string-catalogs.sh), in every mode that builds iOS, --record-snapshots too.
#
# Destinations are overridable:
#   LEDGER_IOS_DEST, LEDGER_WATCH_DEST
# Also read: LEDGER_BOOT_TIMEOUT (scripts/sim-boot.sh), LEDGER_XCODEBUILD_DEADLINE and
# LEDGER_COMPILATION_CACHE (CI, below).
set -euo pipefail

cd "$(dirname "$0")/.."

IOS_DEST="${LEDGER_IOS_DEST:-platform=iOS Simulator,name=iPhone 17,OS=27.0}"
WATCH_DEST="${LEDGER_WATCH_DEST:-platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.0}"
RESULTS=".derivedData/Results"

ALL_FLAGS="$*" FLAG_COUNT=$#
FAST=0 LINT_ONLY=0 SKIP_LINT=0 RECORD_SNAPSHOTS=0 IOS_ONLY=0 STATIC_ONLY=0 SKIP_STATIC=0 BUILD_ONLY=0 SHARD=""
WATCH_ONLY=0 NIGHTLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast) FAST=1 ;;
        --lint-only) LINT_ONLY=1 ;;
        --skip-lint) SKIP_LINT=1 ;;
        --record-snapshots) RECORD_SNAPSHOTS=1 ;;
        --ios-only) IOS_ONLY=1 ;;
        --watch-only) WATCH_ONLY=1 ;;
        --nightly) NIGHTLY=1 ;;
        --static-only) STATIC_ONLY=1 ;;
        --skip-static) SKIP_STATIC=1 ;;
        --build-only) BUILD_ONLY=1 ;;
        --shard)
            if [[ $# -lt 2 ]]; then echo "error: --shard needs <n>/<count>, as in --shard 1/2" >&2; exit 2; fi
            SHARD="$2"
            shift ;;
        *) echo "error: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done
# --lint-only and --static-only exclude every other flag, and --fast runs no simulator: no snapshots to
# record, no platform to pick. --skip-static runs part of what --skip-lint skips, and none of --lint-only.
# --watch-only is --ios-only's other half; --nightly picks the plans that steps 3 and 4 test.
if (( (LINT_ONLY || STATIC_ONLY) && (SKIP_LINT || FAST || RECORD_SNAPSHOTS || IOS_ONLY || SKIP_STATIC || WATCH_ONLY || NIGHTLY)
    || LINT_ONLY && STATIC_ONLY || FAST && (RECORD_SNAPSHOTS || IOS_ONLY || WATCH_ONLY || NIGHTLY) || SKIP_STATIC && SKIP_LINT
    || IOS_ONLY && WATCH_ONLY || NIGHTLY && RECORD_SNAPSHOTS )); then
    echo "error: contradictory flags: $ALL_FLAGS" >&2
    exit 2
fi
if (( BUILD_ONLY && FLAG_COUNT > 1 )); then
    echo "error: --build-only takes no other flag: $ALL_FLAGS" >&2
    exit 2
fi

# The lane's plans and result bundles: the PR plans by default, the Nightly plans with --nightly. A test
# that has no time allowance of its own gets the plan's maximum (check-wiring W88).
LANE=PR IOS_PLAN=PR WATCH_PLAN=PR-Watch TEST_ALLOWANCE=60
if [[ $NIGHTLY -eq 1 ]]; then LANE=Nightly IOS_PLAN=Nightly WATCH_PLAN=Nightly-Watch TEST_ALLOWANCE=600; fi

# --shard <n>/<count> (PR CI's Check jobs, the nightly's legs): the tests of shard <n> in the tested plan's
# shards file, scripts/<plan, lowercase>-shards.txt (pr-shards.txt, nightly-shards.txt, nightly-watch-shards.txt),
# every other shard's targets skipped. An entry may be one suite of a target, "<target>/<suite>", when the target
# is too long for one shard (the nightly's FeatureWorkoutTests): the shard holding the target whole skips those
# suites, and a shard that holds suites runs exactly its entries (-only-testing). The build passes the unsharded build's arguments (its result bundle's
# name aside), so every shard and main-cache.yml share compilation cache keys (check-wiring W84). A shard
# measures only part of the coverage, so step 5 is scripts/check-shards.sh's, over every shard's bundle. Only a
# run that tests one platform can be sharded.
SHARD_TARGETS=() TEST_SELECTION=()
if [[ -n "$SHARD" ]]; then
    if (( !(IOS_ONLY || WATCH_ONLY) || FAST || LINT_ONLY || STATIC_ONLY || RECORD_SNAPSHOTS )); then
        echo "error: --shard needs --ios-only or --watch-only, and takes no --fast, --lint-only, --static-only or --record-snapshots: $ALL_FLAGS" >&2
        exit 2
    fi
    SHARDS_FILE="scripts/$(tr '[:upper:]' '[:lower:]' <<<"$([[ $IOS_ONLY -eq 1 ]] && echo "$IOS_PLAN" || echo "$WATCH_PLAN")")-shards.txt"
    if [[ ! -f "$SHARDS_FILE" ]]; then
        echo "error: --shard: this plan has no shards ($SHARDS_FILE is missing): $ALL_FLAGS" >&2
        exit 2
    fi
    shard_count="$(awk '$1 !~ /^#/ && NF { print $1 }' "$SHARDS_FILE" | sort -u | wc -l | tr -d ' ')"
    if [[ ! "$SHARD" =~ ^[1-9][0-9]*/[1-9][0-9]*$ || "${SHARD#*/}" -ne "$shard_count" || "${SHARD%/*}" -gt "$shard_count" ]]; then
        echo "error: --shard takes <n>/$shard_count, <n> from 1 to $shard_count ($SHARDS_FILE has $shard_count shards), not $SHARD" >&2
        exit 2
    fi
    only=()
    while read -r shard entry _; do
        if [[ -z "$shard" || "$shard" == \#* ]]; then continue; fi
        if [[ "$shard" != "${SHARD%/*}" ]]; then TEST_SELECTION+=("-skip-testing:$entry"); continue; fi
        only+=("-only-testing:$entry")
        if [[ " ${SHARD_TARGETS[*]-} " != *" ${entry%%/*} "* ]]; then SHARD_TARGETS+=("${entry%%/*}"); fi
    done <"$SHARDS_FILE"
    if [[ "${only[*]}" == */* ]]; then TEST_SELECTION=("${only[@]}"); fi # this shard holds suites
fi
# --build-only is the iOS half of the gate without its static steps; the rest of the script reads these.
if [[ $BUILD_ONLY -eq 1 ]]; then IOS_ONLY=1 SKIP_LINT=1; fi

TIMINGS=()
STEP_STARTED_AT=0

step() {
    STEP_STARTED_AT=$SECONDS
    printf '\n\033[1m==> %s\033[0m\n' "$1"
}
done_step() {
    TIMINGS+=("$(printf '%6ss  %s' "$((SECONDS - STEP_STARTED_AT))" "$1")")
}
summary() {
    printf '\n\033[1m==> Summary\033[0m\n'
    printf '%s\n' ${TIMINGS[@]+"${TIMINGS[@]}"} # bash 3.2: an empty array is unbound under set -u
    printf '%6ss  total\n' "$SECONDS"
}
WATCHDOG=""
trap 'status=$?; [[ -z $WATCHDOG ]] || kill "$WATCHDOG" 2>/dev/null || true
if [[ $status -ne 0 ]]; then printf "\n\033[31mcheck.sh FAILED (exit %s)\033[0m\n" "$status"; summary; fi' EXIT

# A CI step's timeout kills check.sh but not xcodebuild, whose result bundle then stays unfinished. So
# pr.yml sets LEDGER_XCODEBUILD_DEADLINE, in seconds, short of that timeout: there check.sh interrupts
# its xcodebuild, which finalizes the bundle and exits, failing the step before the timeout does.
if [[ -n "${LEDGER_XCODEBUILD_DEADLINE:-}" ]]; then
    (sleep "$LEDGER_XCODEBUILD_DEADLINE" && pkill -INT -P $$ -x xcodebuild) </dev/null >/dev/null 2>&1 &
    WATCHDOG=$!
fi

# PR CI sets LEDGER_COMPILATION_CACHE=YES: xcodebuild then keeps each compilation's result in a
# content-addressed cache, .derivedData/CompilationCache.noindex, which pr.yml restores and saves, and
# main-cache.yml (--build-only) saves on main. A cache key hashes the compiler, its arguments and every
# input's contents, never a file's mtime, so a fresh checkout reuses it and a changed input misses it
# (docs/ci-cd.md). Locally it stays off.
CACHE_SETTINGS=()
if [[ "${LEDGER_COMPILATION_CACHE:-}" == YES ]]; then CACHE_SETTINGS=(COMPILATION_CACHE_ENABLE_CACHING=YES); fi

# On GitHub Actions, tools print workflow commands so findings annotate the PR diff.
beautify() { mise exec -- xcbeautify ${GITHUB_ACTIONS:+--renderer github-actions}; }

# ---- 0. Xcode and tools -----------------------------------------------------
step "0 · Xcode and tools"
if [[ $STATIC_ONLY -eq 0 ]]; then
    scripts/check-xcode-version.sh # the pin in .xcode-version, as bootstrap.sh checks it
fi # --static-only runs on Linux, which has no Xcode: the macOS job's step 0 checks it
mise install --quiet
mise exec -- swiftformat --version
mise exec -- swiftlint version
done_step "tools"

# PR CI splits the script suites: --static-only runs those that run anywhere, on Linux, and --skip-static
# the adversarial suites whose header says "# needs macOS:" (scripts/tests/adversarial/run.sh). Only the
# flag picks the half: a LEDGER_ADV_SUITES from the caller's environment is dropped, so the full gate and
# --lint-only run every suite whatever the shell exports. It also keeps --static-only's choice out of the
# check.sh runs inside check-wiring.adv.sh, which that suite's own cases start.
unset LEDGER_ADV_SUITES
if [[ $STATIC_ONLY -eq 1 ]]; then export LEDGER_ADV_SUITES=portable; fi

# ---- 1. format --------------------------------------------------------------
# Not in --static-only: SwiftFormat 0.63.0's Linux binary segfaults at random (exit 139) on the
# ubuntu-24.04 image from 2026-10-21, so PR CI formats in the macOS job (--skip-static) instead.
if [[ $SKIP_LINT -eq 0 && $STATIC_ONLY -eq 0 ]]; then
    step "1 · format (swiftformat --lint)"
    mise exec -- swiftformat --lint --swift-version 6.4 ${GITHUB_ACTIONS:+--reporter github-actions-log} LedgerKit Apps
    done_step "format"
fi

if [[ $SKIP_LINT -eq 0 && $SKIP_STATIC -eq 0 ]]; then
    # ---- 2. lint + package graph and pins -----------------------------------
    step "2 · lint (swiftlint --strict) + package graph and pins + script tests"
    mise exec -- swiftlint lint --strict --quiet --config .swiftlint.yml ${GITHUB_ACTIONS:+--reporter github-actions-logging}
    scripts/check-package-graph.sh
    scripts/check-package-pins.sh # LedgerKit's lockfile pins what the project's (CI-proven) one pins
    scripts/check-catalog-version.sh # a changed exercise catalog raises ExerciseCatalog.version (F03)
    for test in scripts/tests/*.test.sh; do "$test"; done
    done_step "lint"
elif [[ $SKIP_STATIC -eq 1 ]]; then
    step "2 · script tests that need macOS (--skip-static: the rest ran on Linux)"
    LEDGER_ADV_SUITES=macos scripts/tests/adversarial.test.sh
    done_step "macOS script tests"
fi

if [[ $LINT_ONLY -eq 1 || $STATIC_ONLY -eq 1 ]]; then
    summary
    printf '\n\033[32mcheck.sh (%s) OK\033[0m\n' "$([[ $LINT_ONLY -eq 1 ]] && echo --lint-only || echo --static-only)"
    exit 0
fi

if [[ $RECORD_SNAPSHOTS -eq 1 ]]; then
    # swift-snapshot-testing always fails the run that writes references. xcodebuild
    # forwards only TEST_RUNNER_-prefixed variables to the simulator's test runner.
    export SNAPSHOT_TESTING_RECORD=all TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all
    echo "recording snapshot references — this run is expected to fail"
fi

# In record mode a plan run fails by design; keep going so both simulators record.
run_plan() { # <result bundle> <plan file> <xcodebuild args…>
    local result="$1" plan="$2"
    shift 2
    if [[ $RECORD_SNAPSHOTS -eq 1 ]]; then
        xcodebuild "$@" | beautify || true
        # A failed build or simulator boot also fails the run: it is a recording only if tests ran.
        local ran
        ran="$(xcrun xcresulttool get test-results summary --path "$result" 2>/dev/null |
            jq -r '.totalTestCount // 0' || true)"
        if [[ "${ran:-0}" -eq 0 ]]; then
            echo "error: the record run failed before any test ran ($result)" >&2
            exit 1
        fi
    else
        local status=0
        xcodebuild "$@" | beautify || status=$?
        if [[ $status -ne 0 ]]; then
            # Once, and only for the simulator's own failure: the test runner never connected, so no test ran
            # (the nightly's watch leg 1, run 43170933804). Inside the same deadline; the first bundle is kept.
            if ! runner_never_connected "$result"; then return "$status"; fi
            echo "warning: the test runner hung before it connected, and no test ran: testing again, once" >&2
            rm -rf "${result%.xcresult}-runner-hung.xcresult"
            mv "$result" "${result%.xcresult}-runner-hung.xcresult"
            xcodebuild "$@" | beautify
        fi
        scripts/check-test-results.sh "$result" "$plan" ${SHARD_TARGETS[@]+"${SHARD_TARGETS[@]}"}
    fi
}
# <result bundle>: whether its run failed only because the test runner never connected: no test passed or was
# skipped, and every failure is xcodebuild's "The test runner hung before establishing connection."
runner_never_connected() {
    xcrun xcresulttool get test-results summary --path "$1" 2>/dev/null | jq -e '.passedTests == 0
        and .skippedTests == 0 and (.testFailures | length) > 0
        and all(.testFailures[]; .failureText == "The test runner hung before establishing connection.")' >/dev/null
}

# ---- fast tier: host-side package tests, no simulator -----------------------
if [[ $FAST -eq 1 ]]; then
    step "3 · swift test (host, pure targets)"
    swift test --package-path LedgerKit --only-use-versions-from-resolved-file \
        --filter 'LedgerDomainTests|LedgerPersistenceTests' # committed pins only, as steps 3-4
    done_step "swift test"
    summary
    printf '\n\033[32mcheck.sh (--fast) OK\033[0m\n'
    exit 0
fi

mkdir -p "$RESULTS"
# resolve each tested platform's to one simulator by UDID, and unpair it
if [[ $WATCH_ONLY -eq 0 ]]; then IOS_DEST="$(scripts/sim-destination.sh "$IOS_DEST")"; fi
if [[ $IOS_ONLY -eq 0 ]]; then WATCH_DEST="$(scripts/sim-destination.sh "$WATCH_DEST")"; fi

# ---- 3. iOS, 4. watchOS: build while the simulator boots, then test on it alone ----------
# A fresh runner's simulators have never booted. Each parallel-testing clone paid that first boot
# before an app-hosted test could launch, which ran out the CI step (F01 notes, "Second CI run").
# Packages resolve only to the committed Package.resolved: a stale one fails the build rather than
# being rewritten, as Swift 6.4 rewrote it (F32 notes, "Package pins").
# The iOS build leaves the keys the compiler extracted from each module's code. Before any iOS test runs,
# every String Catalog is compared with them (F09; scripts/check-string-catalogs.sh). The watch build's
# keys are not read. A record run stops there too: a screen recorded from a catalog that does not match
# the code would have to be recorded again.
# ARCHS=arm64: every simulator here (a developer Mac, the xcode-27 image) runs on Apple silicon. Without it
# the iOS build also builds the embedded watch app and its package modules for x86_64, since the active-arch
# rule covers only the destination's own platform (tasks/chores/2026-10-18-arm64-only.md). Both actions
# get it, so the tests run what was built.
test_platform() { # <step> <platform> <scheme> <plan> <destination> <result bundle name>
    local xcargs=(-project Ledger.xcodeproj -scheme "$3" -testPlan "$4" -destination "$5"
        -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages
        -onlyUsePackageVersionsFromResolvedFile ARCHS=arm64)
    if [[ $BUILD_ONLY -eq 1 ]]; then
        step "$1 · $2 build (--build-only: no simulator boots, nothing is tested)"
    else
        step "$1 · $2 build (the simulator boots meanwhile)"
        scripts/sim-boot.sh "$5"
    fi
    rm -rf "$RESULTS/$6-build.xcresult" "$RESULTS/$6.xcresult"
    xcodebuild build-for-testing "${xcargs[@]}" ${CACHE_SETTINGS[@]+"${CACHE_SETTINGS[@]}"} \
        -resultBundlePath "$RESULTS/$6-build.xcresult" -quiet | beautify
    done_step "$2 build"
    if [[ $BUILD_ONLY -eq 1 ]]; then return; fi
    if [[ "$2" == iOS ]]; then
        step "$1 · string catalogs (each against the keys the $2 build extracted)"
        scripts/check-string-catalogs.sh
        done_step "string catalogs"
    fi
    step "$1 · $2 simulator boot"
    scripts/sim-boot.sh --wait "$5"
    done_step "$2 boot"
    step "$1 · $2 $4 test plan${SHARD:+, shard $SHARD (${#SHARD_TARGETS[@]} test targets)}"
    # On a failure Xcode 27 runs `simctl diagnose`, which times out after 600 s here (F32 notes); the
    # result bundle still holds every failure, log and attachment.
    run_plan "$RESULTS/$6.xcresult" "TestPlans/$4.xctestplan" \
        test-without-building "${xcargs[@]}" -resultBundlePath "$RESULTS/$6.xcresult" -collect-test-diagnostics never \
        -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance "$TEST_ALLOWANCE" -quiet \
        ${TEST_SELECTION[@]+"${TEST_SELECTION[@]}"}
    done_step "$2 tests"
}
if [[ $WATCH_ONLY -eq 1 ]]; then
    step "3 · iOS skipped (--watch-only)"
    done_step "iOS skipped (--watch-only)"
else
    test_platform 3 iOS Ledger "$IOS_PLAN" "$IOS_DEST" "$LANE-iOS${SHARD:+-shard${SHARD%/*}}"
fi
if [[ $BUILD_ONLY -eq 1 ]]; then
    summary
    printf '\n\033[32mcheck.sh (--build-only) OK\033[0m\n' # built, not tested
    exit 0
fi
if [[ $IOS_ONLY -eq 1 ]]; then
    step "4 · watchOS skipped (--ios-only): the full gate and the nightly test it"
    done_step "watchOS skipped (--ios-only)"
    coverage=(--ios-only "$RESULTS/PR-iOS.xcresult")
else
    test_platform 4 watchOS LedgerWatch "$WATCH_PLAN" "$WATCH_DEST" "$LANE-watchOS${SHARD:+-shard${SHARD%/*}}"
    coverage=("$RESULTS/PR-iOS.xcresult" "$RESULTS/PR-watchOS.xcresult")
fi

if [[ $RECORD_SNAPSHOTS -eq 1 ]]; then
    git status --short -- ':(glob)**/__Snapshots__/**'
    echo "snapshot references recorded; re-run check.sh (without the flag) to verify them" >&2
    exit 1
fi

# ---- 5. coverage gate -------------------------------------------------------
if [[ $NIGHTLY -eq 1 ]]; then
    step "5 · coverage gate skipped (--nightly): coverage is the PR lane's gate"
    done_step "coverage skipped (--nightly)"
elif [[ -n "$SHARD" ]]; then
    step "5 · coverage gate skipped (--shard): scripts/check-shards.sh gates every shard's bundle"
    done_step "coverage skipped (--shard)"
elif [[ $WATCH_ONLY -eq 1 ]]; then
    step "5 · coverage gate skipped (--watch-only): the gate reads both platforms"
    done_step "coverage skipped (--watch-only)"
else
    step "5 · coverage gate"
    scripts/coverage-gate.sh "${coverage[@]}"
    done_step "coverage"
fi

summary
# Only the plain run is the full gate; any other names what it left out: a platform, the PR plans, shards.
mode=""
if [[ $NIGHTLY -eq 1 ]]; then mode+=" --nightly"; fi
if [[ $IOS_ONLY -eq 1 ]]; then mode+=" --ios-only"; fi # not the full gate: that one tests watchOS too
if [[ $WATCH_ONLY -eq 1 ]]; then mode+=" --watch-only"; fi
if [[ -n "$SHARD" ]]; then mode+=" --shard $SHARD"; fi # one shard's tests, no coverage
printf '\n\033[32mcheck.sh%s OK\033[0m\n' "${mode:+ (${mode# })}"
