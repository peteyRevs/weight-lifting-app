#!/usr/bin/env bash
# PR CI's iOS test shards (docs/ci-cd.md, "Shards"): scripts/pr-shards.txt must place every test target the
# PR plan enables in exactly one shard, so a target added to the plan later cannot go untested in CI, and
# scripts/check-shards.sh (the Coverage job) must check every shard's bundle before it gates their coverage.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

SHARDS="$ROOT/scripts/pr-shards.txt"
PLAN="$ROOT/TestPlans/PR.xctestplan"
T="$ADV_TMP"

# mismatch <plan> <shards file>: what differs between the plan's enabled targets and the shards' targets,
# one "<plan|shards> <target>" per line; nothing when each enabled target is in exactly one shard.
mismatch() {
    diff <(jq -r '.testTargets[] | select(.enabled != false) | .target.name' "$1" | sort) \
        <(awk '$1 !~ /^#/ && NF { print $2 }' "$2" | sort) | sed -n 's/^< /plan /p; s/^> /shards /p'
}
shard_numbers() { awk '$1 !~ /^#/ && NF { print $1 }' "$1" | sort -u | tr '\n' ' '; }

check "P01 every test target the PR plan enables is in exactly one shard, and every shard's target is in the plan" \
    is "$(mismatch "$PLAN" "$SHARDS")" ""
check "P02 two shards, numbered 1 and 2, each with targets" is "$(shard_numbers "$SHARDS")" "1 2 "
bad="$(awk '$1 !~ /^#/ && NF && ($1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[A-Za-z]+Tests$/ || (NF > 2 && $3 !~ /^#/))' "$SHARDS")"
check "P03 each line is \"<shard> <test target>\", with an optional # comment" is "$bad" ""

# The comparison itself, against a plan and a shards file that drift apart as a later PR could make them.
jq '.testTargets += [{"target": {"containerPath": "container:LedgerKit", "identifier": "FeatureNewTests", "name": "FeatureNewTests"}}]' \
    "$PLAN" >"$T/new-target.xctestplan"
check "P04 a target added to the plan but to no shard is named" is "$(mismatch "$T/new-target.xctestplan" "$SHARDS")" "plan FeatureNewTests"
{ cat "$SHARDS"; echo "1 FeatureWorkoutTests"; } >"$T/twice.txt"
check "P05 a target placed in both shards is named" is "$(mismatch "$PLAN" "$T/twice.txt")" "shards FeatureWorkoutTests"
grep -v ' LedgerHealthTests ' "$SHARDS" >"$T/dropped.txt"
check "P06 a target dropped from the shards is named" is "$(mismatch "$PLAN" "$T/dropped.txt")" "plan LedgerHealthTests"
jq '(.testTargets[] | select(.target.name == "LedgerHealthTests")) += {"enabled": false}' "$PLAN" >"$T/disabled.xctestplan"
check "P07 a target the plan disables but a shard lists is named" is "$(mismatch "$T/disabled.xctestplan" "$SHARDS")" "shards LedgerHealthTests"

# ---- scripts/check-shards.sh, the Coverage job, in a sandbox: its two checks are stubs that log ----------
SB="$T/sandbox"
mkdir -p "$SB/scripts" "$SB/TestPlans" "$SB/.derivedData/Results"
cp "$ROOT/scripts/check-shards.sh" "$SB/scripts/"
cp "$PLAN" "$SB/TestPlans/PR.xctestplan"
export LOG="$T/calls.log"
printf '#!/bin/sh\nr="$1"; shift 2; echo "check-test-results $r $*" >>"$LOG"; [ "${FAIL_AT:-}" != "$r" ]\n' >"$SB/scripts/check-test-results.sh"
printf '#!/bin/sh\necho "coverage-gate $*" >>"$LOG"\n' >"$SB/scripts/coverage-gate.sh"
chmod +x "$SB/scripts/"*.sh
shard_targets() { awk -v n="$1" '$1 == n { print $2 }' "$SHARDS" | tr '\n' ' ' | sed 's/ $//'; }
run_shards() { # [shards file]: runs check-shards.sh; sets $code and $out
    cp "${1:-$SHARDS}" "$SB/scripts/pr-shards.txt"
    : >"$LOG"
    out="$(cd "$SB" && scripts/check-shards.sh 2>&1)"
    code=$?
}
R=".derivedData/Results"
mkdir -p "$SB/$R/PR-iOS-shard1.xcresult" "$SB/$R/PR-iOS-shard2.xcresult"
run_shards
check "P08 check-shards.sh checks each shard's bundle against its own targets, then gates coverage over both bundles" \
    is "$code $(tr '\n' ';' <"$LOG")" "0 check-test-results $R/PR-iOS-shard1.xcresult $(shard_targets 1);\
check-test-results $R/PR-iOS-shard2.xcresult $(shard_targets 2);coverage-gate --ios-only $R/PR-iOS-shard1.xcresult $R/PR-iOS-shard2.xcresult;"
FAIL_AT="$R/PR-iOS-shard2.xcresult" run_shards
check "P09 ... and a shard's bundle that does not match its targets fails it before the coverage gate" \
    is "$([[ $code -ne 0 ]] && echo failed) $(grep -c '^coverage-gate' "$LOG")" "failed 0"
run_shards "$T/dropped.txt"
check "P10 ... and shards that do not test the plan's targets, each once, fail it before the gate, naming the target" \
    is "$([[ $code -ne 0 ]] && echo failed) $(grep -c '^coverage-gate' "$LOG") $(grep -c 'in no shard: LedgerHealthTests' <<<"$out")" "failed 0 1"
rm -rf "$SB/$R/PR-iOS-shard2.xcresult"
run_shards
check "P11 ... and a missing shard bundle fails it at once, naming the --shard to run" \
    is "$([[ $code -ne 0 ]] && echo failed) $(grep -c . "$LOG") $(grep -c 'run check.sh --ios-only --shard 2/2 first' <<<"$out")" "failed 1 1"

finish
