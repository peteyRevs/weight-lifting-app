#!/usr/bin/env bash
# Fixture test for scripts/coverage-gate.sh (F01 brief, test plan). Saved
# xccov reports stand in for result bundles, so this needs no simulator.
# Run by scripts/check.sh step 2.
set -euo pipefail
cd "$(dirname "$0")/../.."

FIXTURES=scripts/tests/fixtures/coverage
export LEDGER_COVERAGE_THRESHOLDS="$FIXTURES/thresholds.json"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
FAILED=0 OUT=""

fail() { echo "FAIL: $1" >&2; FAILED=1; }
expect() { grep -qF -- "$1" <<<"$OUT" || fail "missing: $1"; }
reject() { if grep -qF -- "$1" <<<"$OUT"; then fail "unexpected: $1"; fi; }

# gate <expected exit> [inputs...] — output lands in $OUT, the step summary in
# $SCRATCH/summary.md (never the real one when this runs on GitHub Actions).
gate() {
    local expected="$1" status=0
    shift
    : >"$SCRATCH/summary.md"
    GITHUB_STEP_SUMMARY="$SCRATCH/summary.md" scripts/coverage-gate.sh "$@" >"$SCRATCH/out" 2>&1 || status=$?
    OUT="$(<"$SCRATCH/out")"
    [[ $status -eq $expected ]] || fail "exit $status, expected $expected, for: ${*:-no arguments}"
}

# 1 · passing report: only LedgerKit/Sources counts; exclusions are honoured
gate 0 "$FIXTURES/ios.json"
expect "| LedgerDomain | 116 / 120 | 96.66 % | 95 % | ✓ |"
expect "| FeatureToday | 40 / 50 | 80.00 % | 70 % | ✓ |"
expect "| Overall | 156 / 170 | 91.76 % | 80 % | ✓ |"
expect "No executable lines measured yet: LedgerSync."
for excluded in LedgerAppKit Previews Generated LedgerApp.swift WeightTests; do reject "$excluded"; done

# 2 · two bundles: a file measured twice keeps its best measurement
gate 0 "$FIXTURES/ios.json" "$FIXTURES/watch.json"
expect "| LedgerDomain | 119 / 120 | 99.16 % | 95 % | ✓ |"

# 3 · LedgerDomain at 94 %: exit 1, ✗ row on stdout and in the step summary
gate 1 "$FIXTURES/domain-94.json"
expect "| LedgerDomain | 94 / 100 | 94.00 % | 95 % | ✗ |"
expect "error: coverage gate: LedgerDomain is at 94.00 %, below its 95 % threshold"
grep -qF "| LedgerDomain | 94 / 100 | 94.00 % | 95 % | ✗ |" "$SCRATCH/summary.md" || fail "step summary lacks the ✗ row"

# 4 · a measured module without a threshold fails
gate 1 "$FIXTURES/unknown-module.json"
expect "| LedgerDependencies | 10 / 10 | 100.00 % | none | ✗ |"
expect "LedgerDependencies has no threshold"

# 5 · unusable input
gate 2
gate 2 "$SCRATCH/missing.xcresult"

# 6 · a file that never ran still counts
echo '{"targets":[{"name":"T","files":[{"path":"/ci/LedgerKit/Sources/LedgerDomain/A.swift","coveredLines":0,"executableLines":1}]}]}' >"$SCRATCH/zero.json"
gate 1 "$SCRATCH/zero.json"
expect "| LedgerDomain | 0 / 1 | 0.00 % | 95 % | ✗ |"

# 7 · a report without LedgerKit sources (coverage off) fails loudly
echo '{"targets":[]}' >"$SCRATCH/empty.json"
gate 1 "$SCRATCH/empty.json"
expect "| LedgerDomain | 0 / 0 | 0.00 % | 95 % | ✗ |"
expect "Overall: no lines measured"

# 8 · a required module missing from the report fails (its test target was dropped)
gate 1 "$FIXTURES/domain-94.json"
expect "error: coverage gate: FeatureToday: no lines measured"

# 9 · a measured module that is not required fails until it is added
jq '.required = ["FeatureToday"]' "$LEDGER_COVERAGE_THRESHOLDS" >"$SCRATCH/not-required.json"
LEDGER_COVERAGE_THRESHOLDS="$SCRATCH/not-required.json" gate 1 "$FIXTURES/ios.json"
expect 'LedgerDomain has coverage now; add it to "required"'

# 10 · bundles that disagree on a file's lines: the larger measurement wins
echo '{"targets":[{"name":"T","files":[{"path":"/ci/LedgerKit/Sources/LedgerDomain/Units/Weight.swift","coveredLines":10,"executableLines":10}]}]}' >"$SCRATCH/small.json"
gate 0 "$FIXTURES/ios.json" "$SCRATCH/small.json"
expect "| LedgerDomain | 116 / 120 | 96.66 % | 95 % | ✓ |"

[[ $FAILED -eq 0 ]] || exit 1
echo "coverage-gate.test.sh: 10 cases passed"
