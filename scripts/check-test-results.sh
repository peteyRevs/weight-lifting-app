#!/usr/bin/env bash
# Asserts that a test run did what its plan asked: every enabled test target in
# the plan produced a test bundle in the result, and every bundle passed.
# A green `xcodebuild test` is not proof on its own — it has passed with the
# LedgerKit targets silently missing and with an empty bundle on a full disk
# (F00 implementation notes #17, #19).
#
#   scripts/check-test-results.sh <result.xcresult> <plan.xctestplan>
set -euo pipefail

cd "$(dirname "$0")/.."
RESULT="$1"
PLAN="$2"

if ! TESTS="$(xcrun xcresulttool get test-results tests --path "$RESULT" 2>/dev/null)"; then
    echo "error: no readable test results in $RESULT" >&2
    exit 1
fi

expected="$(jq -r '.testTargets[] | select(.enabled != false) | .target.name' "$PLAN" | sort)"
ran="$(jq -r '.testNodes[]?.children[]? | select(.nodeType | endswith("test bundle")) | "\(.name) \(.result)"' <<<"$TESTS" | sort)"

missing="$(comm -23 <(echo "$expected") <(awk '{ print $1 }' <<<"$ran"))"
failed="$(awk '$2 != "Passed"' <<<"$ran")"

if [[ -n "$missing" || -n "$failed" || -z "$ran" ]]; then
    echo "error: $RESULT does not match $PLAN" >&2
    [[ -z "$ran" ]] && echo "  no test bundles ran" >&2
    [[ -n "$missing" ]] && sed 's/^/  did not run: /' <<<"$missing" >&2
    [[ -n "$failed" ]] && sed 's/^/  not passed: /' <<<"$failed" >&2
    exit 1
fi

echo "$(wc -l <<<"$ran" | tr -d ' ') test targets ran and passed ($(basename "$PLAN" .xctestplan))"
