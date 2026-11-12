#!/usr/bin/env bash
# Performance verdicts (docs/testing-strategy.md §2.2, "Budgets and the runner"): every test that times code against
# a budget reaches its verdict through PerformanceRunner.verdict, the one place the hosted nightly's runner factor
# swaps the statistic (median × factor) and scales the budget. A test that compared a timing itself would hold the
# runner to the reference machine's budget, or its own statistic, and nothing would say so.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

T="$ADV_TMP"
# Files that time code but hold no budget: a bound that only proves a loop ends (seconds, not a performance claim).
EXEMPT="ExercisePickerModelAdversarialTests.swift WrapLayoutAdversarialTests.swift"

# faults <tests dir>: each file that measures a time with no verdict through PerformanceRunner, or that also compares
# a timing to a budget in an #expect of its own; one "<file>: <why>" per line, nothing when every file holds.
faults() {
    grep -rlE 'clock\.measure|\.measure \{' "$1" --include='*.swift' | sort | while read -r file; do
        name="$(basename "$file")"
        [[ " $EXEMPT " == *" $name "* ]] && continue
        grep -q 'PerformanceRunner\.verdict' "$file" || echo "$name: times code with no PerformanceRunner.verdict"
        if grep -qE '#expect\([^"]*<=? *(PerformanceBudget\.|Self\.[a-zA-Z]+\)|budget\b|\.(milli|micro)?seconds\()' "$file"; then
            echo "$name: compares a timing to a budget itself"
        fi
    done
}

measured="$(grep -rlE 'clock\.measure|\.measure \{' "$ROOT/LedgerKit/Tests" --include='*.swift' | wc -l | tr -d ' ')"
check "V01 every test that times code against a budget reaches its verdict through PerformanceRunner ($measured files time code)" \
    is "$(faults "$ROOT/LedgerKit/Tests")" ""
check "V02 ... and no budget is scaled anywhere else (the verdict scales it once)" \
    is "$(grep -rlE 'PerformanceRunner\.factor *\*|\* *PerformanceRunner\.factor|PerformanceRunner\.budget' "$ROOT/LedgerKit/Tests" \
        --include='*.swift' | grep -v '/PerformanceRunnerTests.swift$' || true)" ""
for name in $EXEMPT; do
    file="$(find "$ROOT/LedgerKit/Tests" -name "$name")"
    check "V03 the exempt $name still bounds a loop in seconds, with no budget" \
        is "$([[ -n "$file" ]] && grep -cE 'PerformanceBudget|budget' "$file")" "0"
done

# The rule itself, against tests that break it as a later edit could.
mkdir -p "$T/Tests/A"
cat >"$T/Tests/A/OwnMedianTests.swift" <<'SWIFT'
let timings = (0 ..< 5).map { _ in clock.measure { work() } }.sorted()
#expect(timings[2] < PerformanceBudget.statsQuery, "median")
SWIFT
cat >"$T/Tests/A/InlineTests.swift" <<'SWIFT'
let timings = (0 ..< 5).map { _ in clock.measure { work() } }
let verdict = PerformanceRunner.verdict(timings, budget: .milliseconds(5))
#expect(verdict.isWithinBudget, "\(verdict)")
#expect(timings[2] < .milliseconds(5), "median \(timings[2])")
SWIFT
cat >"$T/Tests/A/GoodTests.swift" <<'SWIFT'
let timings = (0 ..< 5).map { _ in clock.measure { work() } }
let verdict = PerformanceRunner.verdict(timings, budget: Self.budget, statistic: .median)
#expect(verdict.isWithinBudget, "\(verdict)")
SWIFT
check "V04 a test that times code and compares its own statistic, or an inline budget, is named; a verdict passes" \
    is "$(faults "$T/Tests")" "InlineTests.swift: compares a timing to a budget itself
OwnMedianTests.swift: times code with no PerformanceRunner.verdict
OwnMedianTests.swift: compares a timing to a budget itself"

finish
