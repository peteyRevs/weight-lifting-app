#!/usr/bin/env bash
# Asserts that a test run did what its plan asked: every enabled test target in
# the plan produced a test bundle in the result, and every bundle passed.
# A green `xcodebuild test` is not proof on its own — it has passed with the
# LedgerKit targets silently missing and with an empty bundle on a full disk
# (F00 implementation notes #17, #19).
#
#   scripts/check-test-results.sh <result.xcresult> <plan.xctestplan> [test target...]
#
# With test targets (check.sh --shard), the run was one shard of the plan: exactly those targets must
# have run, each one the plan enables, and no other target may have run.
set -euo pipefail

cd "$(dirname "$0")/.."
RESULT="$1"
PLAN="$2"
shift 2

if ! TESTS="$(xcrun xcresulttool get test-results tests --path "$RESULT" 2>/dev/null)"; then
    echo "error: no readable test results in $RESULT" >&2
    exit 1
fi

expected="$(jq -r '.testTargets[] | select(.enabled != false) | .target.name' "$PLAN" | sort)"
ran="$(jq -r '.testNodes[]?.children[]? | select(.nodeType | endswith("test bundle")) | "\(.name) \(.result)"' <<<"$TESTS" | sort)"

shard="" unexpected=""
if [[ $# -gt 0 ]]; then
    shard="$(printf '%s\n' "$@" | sort)"
    unknown="$(comm -23 <(echo "$shard") <(echo "$expected"))"
    if [[ -n "$unknown" ]]; then
        echo "error: not a test target that $PLAN enables: $(tr '\n' ' ' <<<"$unknown")" >&2
        exit 1
    fi
    expected="$shard"
    unexpected="$(comm -13 <(echo "$expected") <(awk '{ print $1 }' <<<"$ran"))"
fi

missing="$(comm -23 <(echo "$expected") <(awk '{ print $1 }' <<<"$ran"))"
failed="$(awk '$2 != "Passed"' <<<"$ran")"

if [[ -n "$missing" || -n "$failed" || -n "$unexpected" || -z "$ran" ]]; then
    echo "error: $RESULT does not match $PLAN${shard:+ (its shard: $(tr '\n' ' ' <<<"$shard"))}" >&2
    [[ -z "$ran" ]] && echo "  no test bundles ran" >&2
    [[ -n "$missing" ]] && sed 's/^/  did not run: /' <<<"$missing" >&2
    [[ -n "$failed" ]] && sed 's/^/  not passed: /' <<<"$failed" >&2
    [[ -n "$unexpected" ]] && sed 's/^/  ran outside its shard: /' <<<"$unexpected" >&2
    exit 1
fi

echo "$(wc -l <<<"$ran" | tr -d ' ') test targets ran and passed ($(basename "$PLAN" .xctestplan)${shard:+, one shard})"
