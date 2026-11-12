#!/usr/bin/env bash
# Step 5 of a sharded run (docs/ci-cd.md, "Shards"): PR CI's Coverage job, after every Check shard passed.
# Each `check.sh --ios-only --shard <n>/<count>` leaves .derivedData/Results/PR-iOS-shard<n>.xcresult.
# This checks them together as an unsharded `check.sh --ios-only` checks its one bundle:
#   1. each bundle ran exactly its shard's test targets, and they passed (check-test-results.sh);
#   2. the shards' targets together are exactly the targets the PR plan enables, none twice;
#   3. the coverage gate over every shard's bundle, at the same thresholds (coverage-gate.sh --ios-only).
#
# Coverage, 3: in one run every test target's copy of a source file reports the same lines covered, those
# any test of the run executed (coverage is plan-wide, docs/testing-strategy.md §4). A shard's bundle
# reports those its own tests executed, and the gate keeps each file's best measurement. So a file counts
# as covered by the shard that covers it most, never more than an unsharded run would count it: the gate
# is at least as strict. `xcresulttool merge` was tried and keeps only the first bundle's coverage, and
# `xccov merge` of a report with itself changed its numbers (docs/ci-cd.md, "Shards").
#
#   scripts/check-shards.sh
#
# Locally: `check.sh --ios-only --shard 1/2`, then `--shard 2/2`, then this.
set -euo pipefail

cd "$(dirname "$0")/.."
RESULTS=".derivedData/Results"
SHARDS_FILE="scripts/pr-shards.txt"
PLAN="TestPlans/PR.xctestplan"

shard_count="$(awk '$1 !~ /^#/ && NF { print $1 }' "$SHARDS_FILE" | sort -u | wc -l | tr -d ' ')"
bundles=()
for ((n = 1; n <= shard_count; n++)); do
    bundle="$RESULTS/PR-iOS-shard$n.xcresult"
    if [[ ! -d "$bundle" ]]; then
        echo "error: $bundle is missing: run check.sh --ios-only --shard $n/$shard_count first" >&2
        exit 1
    fi
    # shellcheck disable=SC2046 # one word per test target
    scripts/check-test-results.sh "$bundle" "$PLAN" $(awk -v n="$n" '$1 == n { print $2 }' "$SHARDS_FILE")
    bundles+=("$bundle")
done

sharded="$(awk '$1 !~ /^#/ && NF { print $2 }' "$SHARDS_FILE" | sort)"
planned="$(jq -r '.testTargets[] | select(.enabled != false) | .target.name' "$PLAN" | sort)"
if [[ "$sharded" != "$planned" ]]; then
    echo "error: the shards in $SHARDS_FILE do not test exactly the targets $PLAN enables, each once:" >&2
    diff <(echo "$planned") <(echo "$sharded") | sed -n 's/^< /  in no shard: /p; s/^> /  sharded but not in the plan, or twice: /p' >&2
    exit 1
fi
echo "the $shard_count shards together tested every target of $(basename "$PLAN" .xctestplan), each once"

scripts/coverage-gate.sh --ios-only "${bundles[@]}"
