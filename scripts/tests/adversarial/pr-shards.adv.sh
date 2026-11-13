#!/usr/bin/env bash
# PR CI's iOS test shards (docs/ci-cd.md, "Shards"): scripts/pr-shards.txt must place every test target the
# PR plan enables in exactly one shard (and each nightly leg list every target of its plan, P12), so a target
# added to the plan later cannot go untested in CI, and
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
        <(awk '$1 !~ /^#/ && NF && $2 !~ /\// { print $2 }' "$2" | sort) | sed -n 's/^< /plan /p; s/^> /shards /p'
}
# suite_faults <shards file>: each "<target>/<suite>" entry whose target is not whole in another shard of the
# file, which is listed twice, or whose suite no type or class of that target's sources declares (check.sh
# --shard runs it with -only-testing, and the shard holding the target skips it). Nothing when all hold.
suite_faults() {
    awk '$1 !~ /^#/ && NF { print $1, $2 }' "$1" | while read -r shard entry; do
        [[ "$entry" == */* ]] || continue
        target="${entry%%/*}" suite="${entry#*/}"
        whole="$(awk -v t="$target" '$1 !~ /^#/ && $2 == t { print $1 }' "$1")"
        if [[ -z "$whole" ]]; then echo "$entry: $target is in no shard whole"
        elif [[ "$whole" == "$shard" ]]; then echo "$entry: in the shard that holds $target whole"; fi
        if [[ "$(awk -v e="$entry" '$1 !~ /^#/ && $2 == e' "$1" | wc -l)" -ne 1 ]]; then echo "$entry: listed twice"; fi
        if ! grep -rqsE "^ *(final )?(struct|class) $suite\b" "$ROOT/LedgerKit/Tests/$target" "$ROOT/Apps/$target"; then
            echo "$entry: no suite $suite in $target"
        fi
    done
}
shard_numbers() { awk '$1 !~ /^#/ && NF { print $1 }' "$1" | sort -u | tr '\n' ' '; }

check "P01 every test target the PR plan enables is in exactly one shard, and every shard's target is in the plan" \
    is "$(mismatch "$PLAN" "$SHARDS")" ""
check "P02 two shards, numbered 1 and 2, each with targets" is "$(shard_numbers "$SHARDS")" "1 2 "
bad="$(awk '$1 !~ /^#/ && NF && ($1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[A-Za-z]+Tests$/ || (NF > 2 && $3 !~ /^#/))' "$SHARDS")"
check "P03 each line is \"<shard> <test target>\", with an optional # comment" is "$bad" ""

# Every shards file, the nightly's legs too (docs/ci-cd.md, "Nightly legs"): check.sh --shard reads
# scripts/<plan, lowercase>-shards.txt for the plan it tests, so each file must place every target of its plan.
for file in "$ROOT"/scripts/*-shards.txt; do
    name="$(basename "$file" -shards.txt)" plan=""
    for candidate in "$ROOT"/TestPlans/*.xctestplan; do
        if [[ "$(basename "$candidate" .xctestplan | tr '[:upper:]' '[:lower:]')" == "$name" ]]; then plan="$candidate"; fi
    done
    check "P12 $(basename "$file") is a test plan's (check.sh --shard reads it for that plan)" is "${plan:+found}" found
    [[ -n "$plan" ]] || continue
    check "P12 ... every test target $(basename "$plan") enables is in exactly one of its shards, and no other" \
        is "$(mismatch "$plan" "$file")" ""
    check "P12 ... its shards are numbered 1 to their count" \
        is "$(shard_numbers "$file")" "$(seq "$(awk '$1 !~ /^#/ && NF { print $1 }' "$file" | sort -u | wc -l)" | tr '\n' ' ')"
    check "P12 ... each line is \"<shard> <test target>[/<suite>]\", with an optional # comment" \
        is "$(awk '$1 !~ /^#/ && NF && ($1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[A-Za-z]+Tests(\/[A-Za-z0-9]+)?$/ || (NF > 2 && $3 !~ /^#/))' "$file")" ""
    check "P12 ... each suite entry names a suite of a target whole in another shard, once" is "$(suite_faults "$file")" ""
done
check "P13 the PR shards hold whole targets only (check-shards.sh reads each entry as a target)" \
    is "$(awk '$1 !~ /^#/ && $2 ~ /\//' "$SHARDS")" ""

# The suite rule itself, against shards files that break it as a later edit could.
leg() { printf '%s\n' "$@" >"$T/legs.txt"; suite_faults "$T/legs.txt"; }
check "P14 a suite whose target is whole in no shard is named" \
    is "$(leg "1 FeatureWorkoutTests/WorkoutSaveAdversarialTests")" "FeatureWorkoutTests/WorkoutSaveAdversarialTests: FeatureWorkoutTests is in no shard whole"
check "P14 ... a suite in the shard that holds its target whole" \
    is "$(leg "1 FeatureWorkoutTests" "1 FeatureWorkoutTests/WorkoutSaveAdversarialTests")" \
    "FeatureWorkoutTests/WorkoutSaveAdversarialTests: in the shard that holds FeatureWorkoutTests whole"
check "P14 ... a suite listed twice" \
    is "$(leg "1 FeatureWorkoutTests" "2 FeatureWorkoutTests/WorkoutSaveAdversarialTests" "3 FeatureWorkoutTests/WorkoutSaveAdversarialTests" | sort -u)" \
    "FeatureWorkoutTests/WorkoutSaveAdversarialTests: listed twice"
check "P14 ... a suite the target does not declare (a typo, or a suite renamed since)" \
    is "$(leg "1 FeatureWorkoutTests" "2 FeatureWorkoutTests/WorkoutSaveAdversarialTest" "3 LedgerUITests" "4 LedgerUITests/Tabs")" \
    "FeatureWorkoutTests/WorkoutSaveAdversarialTest: no suite WorkoutSaveAdversarialTest in FeatureWorkoutTests"

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
