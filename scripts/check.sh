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
#
# Destinations are overridable:
#   LEDGER_IOS_DEST, LEDGER_WATCH_DEST
# Also read: LEDGER_BOOT_TIMEOUT (scripts/sim-boot.sh), LEDGER_XCODEBUILD_DEADLINE (CI, below).
set -euo pipefail

cd "$(dirname "$0")/.."

IOS_DEST="${LEDGER_IOS_DEST:-platform=iOS Simulator,name=iPhone 17,OS=27.0}"
WATCH_DEST="${LEDGER_WATCH_DEST:-platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.0}"
RESULTS=".derivedData/Results"

FAST=0 LINT_ONLY=0 SKIP_LINT=0 RECORD_SNAPSHOTS=0 IOS_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --fast) FAST=1 ;;
        --lint-only) LINT_ONLY=1 ;;
        --skip-lint) SKIP_LINT=1 ;;
        --record-snapshots) RECORD_SNAPSHOTS=1 ;;
        --ios-only) IOS_ONLY=1 ;;
        *) echo "error: unknown flag $arg" >&2; exit 2 ;;
    esac
done
# --lint-only excludes every other flag, and --fast runs no simulator: no snapshots to record, no platform to pick.
if (( LINT_ONLY && (SKIP_LINT || FAST || RECORD_SNAPSHOTS || IOS_ONLY) || FAST && (RECORD_SNAPSHOTS || IOS_ONLY) )); then
    echo "error: contradictory flags: $*" >&2
    exit 2
fi

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

# On GitHub Actions, tools print workflow commands so findings annotate the PR diff.
beautify() { mise exec -- xcbeautify ${GITHUB_ACTIONS:+--renderer github-actions}; }

# ---- 0. Xcode and tools -----------------------------------------------------
step "0 · Xcode and tools"
scripts/check-xcode-version.sh # the pin in .xcode-version, as bootstrap.sh checks it
mise install --quiet
mise exec -- swiftformat --version
mise exec -- swiftlint version
done_step "tools"

if [[ $SKIP_LINT -eq 0 ]]; then
    # ---- 1. format ----------------------------------------------------------
    step "1 · format (swiftformat --lint)"
    mise exec -- swiftformat --lint --swift-version 6.4 ${GITHUB_ACTIONS:+--reporter github-actions-log} LedgerKit Apps
    done_step "format"

    # ---- 2. lint + package graph and pins -----------------------------------
    step "2 · lint (swiftlint --strict) + package graph and pins + script tests"
    mise exec -- swiftlint lint --strict --quiet --config .swiftlint.yml ${GITHUB_ACTIONS:+--reporter github-actions-logging}
    scripts/check-package-graph.sh
    scripts/check-package-pins.sh # LedgerKit's lockfile pins what the project's (CI-proven) one pins
    for test in scripts/tests/*.test.sh; do "$test"; done
    done_step "lint"
fi

if [[ $LINT_ONLY -eq 1 ]]; then
    summary
    printf '\n\033[32mcheck.sh (--lint-only) OK\033[0m\n'
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
        xcodebuild "$@" | beautify
        scripts/check-test-results.sh "$result" "$plan"
    fi
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
IOS_DEST="$(scripts/sim-destination.sh "$IOS_DEST")" # resolve each to one simulator by UDID and unpair it
if [[ $IOS_ONLY -eq 0 ]]; then WATCH_DEST="$(scripts/sim-destination.sh "$WATCH_DEST")"; fi

# ---- 3. iOS, 4. watchOS: build while the simulator boots, then test on it alone ----------
# A fresh runner's simulators have never booted. Each parallel-testing clone paid that first boot
# before an app-hosted test could launch, which ran out the CI step (F01 notes, "Second CI run").
# Packages resolve only to the committed Package.resolved: a stale one fails the build rather than
# being rewritten, as Swift 6.4 rewrote it (F32 notes, "Package pins").
test_platform() { # <step> <platform> <scheme> <plan> <destination> <result bundle name>
    local xcargs=(-project Ledger.xcodeproj -scheme "$3" -testPlan "$4" -destination "$5"
        -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages
        -onlyUsePackageVersionsFromResolvedFile)
    step "$1 · $2 build (the simulator boots meanwhile)"
    scripts/sim-boot.sh "$5"
    rm -rf "$RESULTS/$6-build.xcresult" "$RESULTS/$6.xcresult"
    xcodebuild build-for-testing "${xcargs[@]}" -resultBundlePath "$RESULTS/$6-build.xcresult" -quiet | beautify
    done_step "$2 build"
    step "$1 · $2 simulator boot"
    scripts/sim-boot.sh --wait "$5"
    done_step "$2 boot"
    step "$1 · $2 $4 test plan"
    # On a failure Xcode 27 runs `simctl diagnose`, which times out after 600 s here (F32 notes); the
    # result bundle still holds every failure, log and attachment.
    run_plan "$RESULTS/$6.xcresult" "TestPlans/$4.xctestplan" \
        test-without-building "${xcargs[@]}" -resultBundlePath "$RESULTS/$6.xcresult" -collect-test-diagnostics never \
        -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -quiet
    done_step "$2 tests"
}
test_platform 3 iOS Ledger PR "$IOS_DEST" PR-iOS
if [[ $IOS_ONLY -eq 1 ]]; then
    step "4 · watchOS skipped (--ios-only): the full gate and the nightly test it"
    done_step "watchOS skipped (--ios-only)"
    coverage=(--ios-only "$RESULTS/PR-iOS.xcresult")
else
    test_platform 4 watchOS LedgerWatch PR-Watch "$WATCH_DEST" PR-watchOS
    coverage=("$RESULTS/PR-iOS.xcresult" "$RESULTS/PR-watchOS.xcresult")
fi

if [[ $RECORD_SNAPSHOTS -eq 1 ]]; then
    git status --short -- ':(glob)**/__Snapshots__/**'
    echo "snapshot references recorded; re-run check.sh (without the flag) to verify them" >&2
    exit 1
fi

# ---- 5. coverage gate -------------------------------------------------------
step "5 · coverage gate"
scripts/coverage-gate.sh "${coverage[@]}"
done_step "coverage"

summary
if [[ $IOS_ONLY -eq 1 ]]; then
    printf '\n\033[32mcheck.sh (--ios-only) OK\033[0m\n' # not the full gate: that one tests watchOS too
else
    printf '\n\033[32mcheck.sh OK\033[0m\n'
fi
