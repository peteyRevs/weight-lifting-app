#!/usr/bin/env bash
# F01 adversarial suite (docs/subagent-workflow.md, Adversarial Tester). Every case
# encodes a property the gate must have; a FAIL is a hole, recorded with its repro
# in tasks/features/F01-ci-gates/test-findings.md. No network, no simulator.
#
#   scripts/tests/adversarial/run.sh            all suites
#   scripts/tests/adversarial/run.sh coverage   suites whose name contains "coverage"
#
# PR CI runs the suites in two halves (check.sh --static-only on Linux, --skip-static on macOS):
#   LEDGER_ADV_SUITES=portable   every suite but those with a "# needs macOS: <why>" header line
#   LEDGER_ADV_SUITES=macos      only those
# A suite needs macOS when one of its cases does (xcodebuild, xcrun, Apple's /usr/bin shims, BSD sed):
# on Linux that case would skip or break, and CI would test less. Unset or "all": every suite.
#
# Exit 0 only when every case in every suite passed, and at least one suite ran.
set -uo pipefail

cd "$(dirname "$0")" || exit 1
case "${LEDGER_ADV_SUITES:=all}" in
    all | portable | macos) ;;
    *) echo "error: LEDGER_ADV_SUITES must be all, portable or macos, not '$LEDGER_ADV_SUITES'" >&2; exit 2 ;;
esac
failed=() ran=0
for suite in ./*.adv.sh; do
    [[ -z "${1:-}" || "$suite" == *"$1"* ]] || continue
    needs_macos=no
    if grep -q '^# needs macOS: ' "$suite"; then needs_macos=yes; fi
    case "$LEDGER_ADV_SUITES:$needs_macos" in portable:yes | macos:no) continue ;; esac
    printf '\n== %s\n' "${suite#./}"
    ran=$((ran + 1))
    bash "$suite" || failed+=("${suite#./}")
done

printf '\n'
if [[ $ran -eq 0 ]]; then
    echo "adversarial: no suite matched (LEDGER_ADV_SUITES=$LEDGER_ADV_SUITES${1:+, filter $1})"
    exit 1
fi
if [[ ${#failed[@]} -gt 0 ]]; then
    printf 'adversarial: FAILED suites: %s\n' "${failed[*]}"
    exit 1
fi
echo "adversarial: all $ran suites passed ($LEDGER_ADV_SUITES)"
