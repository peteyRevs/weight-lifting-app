#!/usr/bin/env bash
# F01 adversarial suite (docs/subagent-workflow.md, Adversarial Tester). Every case
# encodes a property the gate must have; a FAIL is a hole, recorded with its repro
# in tasks/features/F01-ci-gates/test-findings.md. No network, no simulator.
#
#   scripts/tests/adversarial/run.sh            all suites
#   scripts/tests/adversarial/run.sh coverage   suites whose name contains "coverage"
#
# Exit 0 only when every case in every suite passed.
set -uo pipefail

cd "$(dirname "$0")"
failed=()
for suite in ./*.adv.sh; do
    [[ -z "${1:-}" || "$suite" == *"$1"* ]] || continue
    printf '\n== %s\n' "${suite#./}"
    bash "$suite" || failed+=("${suite#./}")
done

printf '\n'
if [[ ${#failed[@]} -gt 0 ]]; then
    printf 'adversarial: FAILED suites: %s\n' "${failed[*]}"
    exit 1
fi
echo "adversarial: all suites passed"
