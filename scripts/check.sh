#!/usr/bin/env bash
# The local gate. Green check.sh is the minimum bar for a PR
# (docs/testing-strategy.md §7 — this script implements that contract).
#
#   scripts/check.sh                    full gate: format, lint, iOS, watchOS, coverage
#   scripts/check.sh --fast             host-side package tests only; no simulators
#   scripts/check.sh --lint-only        steps 0–2 only
#   scripts/check.sh --skip-lint        steps 3–5 only (no format, lint or script tests)
#   scripts/check.sh --record-snapshots re-record snapshot references, then fail
#
# Destinations are overridable:
#   LEDGER_IOS_DEST, LEDGER_WATCH_DEST
set -euo pipefail

cd "$(dirname "$0")/.."

IOS_DEST="${LEDGER_IOS_DEST:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
WATCH_DEST="${LEDGER_WATCH_DEST:-platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5}"
RESULTS=".derivedData/Results"

FAST=0 LINT_ONLY=0 SKIP_LINT=0 RECORD_SNAPSHOTS=0
for arg in "$@"; do
    case "$arg" in
        --fast) FAST=1 ;;
        --lint-only) LINT_ONLY=1 ;;
        --skip-lint) SKIP_LINT=1 ;;
        --record-snapshots) RECORD_SNAPSHOTS=1 ;;
        *) echo "error: unknown flag $arg" >&2; exit 2 ;;
    esac
done
# --lint-only excludes every other flag, and --fast runs no snapshot tests to record.
if (( LINT_ONLY && (SKIP_LINT || FAST || RECORD_SNAPSHOTS) || FAST && RECORD_SNAPSHOTS )); then
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
trap 'status=$?; if [[ $status -ne 0 ]]; then printf "\n\033[31mcheck.sh FAILED (exit %s)\033[0m\n" "$status"; summary; fi' EXIT

# On GitHub Actions, tools print workflow commands so findings annotate the PR diff.
beautify() { mise exec -- xcbeautify ${GITHUB_ACTIONS:+--renderer github-actions}; }

# ---- 0. tools ---------------------------------------------------------------
step "0 · tools"
mise install --quiet
mise exec -- swiftformat --version
mise exec -- swiftlint version
done_step "tools"

if [[ $SKIP_LINT -eq 0 ]]; then
    # ---- 1. format ----------------------------------------------------------
    step "1 · format (swiftformat --lint)"
    mise exec -- swiftformat --lint --swift-version 6.3 ${GITHUB_ACTIONS:+--reporter github-actions-log} LedgerKit Apps
    done_step "format"

    # ---- 2. lint + package graph --------------------------------------------
    step "2 · lint (swiftlint --strict) + package graph + script tests"
    mise exec -- swiftlint lint --strict --quiet --config .swiftlint.yml ${GITHUB_ACTIONS:+--reporter github-actions-logging}
    scripts/check-package-graph.sh
    for test in scripts/tests/*.test.sh; do "$test"; done
    done_step "lint"
fi

if [[ $LINT_ONLY -eq 1 ]]; then
    summary
    printf '\n\033[32mcheck.sh (--lint-only) OK\033[0m\n'
    exit 0
fi

if [[ $RECORD_SNAPSHOTS -eq 1 ]]; then
    # swift-snapshot-testing always fails the run that writes references.
    export SNAPSHOT_TESTING_RECORD=all
    echo "recording snapshot references — this run is expected to fail"
fi

# ---- fast tier: host-side package tests, no simulator -----------------------
if [[ $FAST -eq 1 ]]; then
    step "3 · swift test (host, pure targets)"
    swift test --package-path LedgerKit --filter 'LedgerDomainTests|LedgerPersistenceTests'
    done_step "swift test"
    summary
    printf '\n\033[32mcheck.sh (--fast) OK\033[0m\n'
    exit 0
fi

mkdir -p "$RESULTS"

# ---- 3. iOS build + PR plan -------------------------------------------------
step "3 · iOS build + PR test plan"
rm -rf "$RESULTS/PR-iOS.xcresult"
set -o pipefail
xcodebuild test -project Ledger.xcodeproj -scheme Ledger -testPlan PR \
    -destination "$IOS_DEST" \
    -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages \
    -resultBundlePath "$RESULTS/PR-iOS.xcresult" \
    -parallel-testing-enabled YES -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 60 -quiet | beautify
scripts/check-test-results.sh "$RESULTS/PR-iOS.xcresult" TestPlans/PR.xctestplan
done_step "iOS"

# ---- 4. watchOS build + PR-Watch plan ---------------------------------------
step "4 · watchOS build + PR-Watch test plan"
rm -rf "$RESULTS/PR-watchOS.xcresult"
# One worker = one watch clone. A second clone intermittently fails to launch
# the host app or UI runner ("Unknown application display identifier").
xcodebuild test -project Ledger.xcodeproj -scheme LedgerWatch -testPlan PR-Watch \
    -destination "$WATCH_DEST" \
    -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages \
    -resultBundlePath "$RESULTS/PR-watchOS.xcresult" \
    -parallel-testing-enabled YES -parallel-testing-worker-count 1 -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 60 -quiet | beautify
scripts/check-test-results.sh "$RESULTS/PR-watchOS.xcresult" TestPlans/PR-Watch.xctestplan
done_step "watchOS"

# ---- 5. coverage gate -------------------------------------------------------
step "5 · coverage gate"
scripts/coverage-gate.sh "$RESULTS/PR-iOS.xcresult" "$RESULTS/PR-watchOS.xcresult"
done_step "coverage"

summary
printf '\n\033[32mcheck.sh OK\033[0m\n'
