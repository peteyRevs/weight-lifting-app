#!/usr/bin/env bash
# scripts/check.sh step wiring: the real, unmodified check.sh runs in a sandbox whose
# tools (mise, xcodebuild, swift) and helper scripts are stubs. Each stub logs its
# call and fails when $FAIL_AT names it, so every step's failure is injected in turn
# and check.sh must exit non-zero without running a later step.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

SB="$ADV_TMP/sandbox"
mkdir -p "$SB/scripts/tests" "$SB/bin"
cp "${ADV_CHECK_SH:-$ROOT/scripts/check.sh}" "$SB/scripts/check.sh" # override: mutation-test this suite
cp "${ADV_SIM_DESTINATION:-$ROOT/scripts/sim-destination.sh}" "$SB/scripts/sim-destination.sh" # the real one
fake_simctl "$SB/bin" # ... against the runner's simulators; its calls go to $XCRUN_LOG, not $LOG
export LOG="$ADV_TMP/calls.log" XCRUN_LOG="$ADV_TMP/xcrun.log"

stub() { # <path> <body>: a /bin/sh stub with the log/fail helpers in front of <body>
    printf '#!/bin/sh\nlog() { printf "%%s\\n" "$*" >>"$LOG"; }\nfail_if() { [ "${FAIL_AT:-}" = "$1" ] && exit "${FAIL_CODE:-1}"; return 0; }\n%s\n' "$2" >"$1"
    chmod +x "$1"
}
stub "$SB/bin/mise" '
case "$1" in
    install) log mise-install; fail_if mise-install ;;
    exec)
        shift; [ "$1" = -- ] && shift
        tool="$1"; shift
        case "$tool $*" in
            "swiftformat --version") id=swiftformat-version ;;
            "swiftlint version") id=swiftlint-version ;;
            "swiftformat --lint"*) id=swiftformat-lint ;;
            "swiftlint lint"*) id=swiftlint-lint ;;
            xcbeautify*) id=xcbeautify; cat ;;
            *) id="unknown-$tool" ;;
        esac
        log "$id $*"; fail_if "$id" ;;
esac'
stub "$SB/bin/xcodebuild" '
scheme=""; bundle=""; dest=""
while [ $# -gt 0 ]; do
    case "$1" in -scheme) scheme="$2" ;; -resultBundlePath) bundle="$2" ;; -destination) dest="$2" ;; esac
    shift
done
log "xcodebuild-$scheme $dest"
mkdir -p "$bundle"
echo "Test Suite All tests passed"
fail_if "xcodebuild-$scheme"'
stub "$SB/bin/swift" 'log swift-test; fail_if swift-test'
stub "$SB/scripts/check-package-graph.sh" 'log package-graph; fail_if package-graph'
stub "$SB/scripts/check-test-results.sh" 'id="check-test-results-$(basename "$2" .xctestplan)"; log "$id $1"; fail_if "$id"'
stub "$SB/scripts/coverage-gate.sh" 'log "coverage-gate $*"; fail_if coverage-gate'
stub "$SB/scripts/tests/a.test.sh" 'log script-test-a; fail_if script-test-a'
stub "$SB/scripts/tests/b.test.sh" 'log script-test-b; fail_if script-test-b'

# run [flags...]: the sandboxed check.sh; sets $code, $out and $calls (ids only).
run() {
    : >"$LOG"; : >"$XCRUN_LOG"
    out="$(PATH="$SB/bin:$PATH" "$SB/scripts/check.sh" "$@" 2>&1)"
    code=$?
    calls="$(awk '{ print $1 }' "$LOG" | tr '\n' ' ')"
}

FULL="mise-install swiftformat-version swiftlint-version swiftformat-lint swiftlint-lint package-graph \
script-test-a script-test-b xcodebuild-Ledger xcbeautify check-test-results-PR xcodebuild-LedgerWatch \
xcbeautify check-test-results-PR-Watch coverage-gate"
FULL="$(echo $FULL) "

unset FAIL_AT GITHUB_ACTIONS
run
expect_exit "W01 full run with every step green exits 0" 0 "$code" "$out"
if [[ "$calls" == "$FULL" ]]; then pass "W02 full run calls every step in order"; else
    fail "W02 full run calls every step in order" "want: $FULL
got:  $calls"; fi
check "W03 coverage gate reads both bundles" \
    grep -q 'coverage-gate .derivedData/Results/PR-iOS.xcresult .derivedData/Results/PR-watchOS.xcresult' "$LOG"

# Inject a failure at every step: non-zero exit, and the calls are exactly the steps
# up to the failing one (xcodebuild's own xcbeautify shares its pipeline, so it runs).
for id in $FULL; do
    [[ "$id" == xcbeautify ]] && continue # covered below: it appears twice
    want=" $FULL"; want="${want%%" $id "*} $id "; want="${want# }"
    [[ "$id" == xcodebuild-* ]] && want="${want}xcbeautify "
    FAIL_AT="$id" run
    if [[ $code -ne 0 && "$calls" == "$want" ]]; then
        pass "W04 failure at $id stops check.sh (exit $code)"
    else
        fail "W04 failure at $id stops check.sh" "exit $code
want: $want
got:  $calls"
    fi
done
FAIL_AT=xcbeautify run
if [[ $code -ne 0 && "$calls" != *check-test-results-PR* ]]; then
    pass "W05 xcbeautify failing with xcodebuild green still fails the step"
else
    fail "W05 xcbeautify failing with xcodebuild green still fails the step" "exit $code, calls: $calls"
fi
FAIL_AT=xcodebuild-Ledger FAIL_CODE=65 run
expect_exit "W06 xcodebuild's exit code (65) reaches the caller through the pipe" 65 "$code" "$out"
FAIL_AT=coverage-gate FAIL_CODE=1 run
expect_exit "W07 coverage gate's exit 1 is check.sh's exit" 1 "$code" "$out"

# The trap's summary must not change the status, even when the first step fails.
FAIL_AT=mise-install FAIL_CODE=3 run
if [[ $code -eq 3 && "$out" != *"unbound variable"* ]]; then
    pass "W08 failure in step 0 keeps its exit code and prints the summary"
else
    fail "W08 [F6] failure in step 0 keeps its exit code and prints the summary" \
        "bash $BASH_VERSION: exit $code (want 3); $(grep -m1 'unbound' <<<"$out")"
fi

# ---- flags ----------------------------------------------------------------------
run --skip-lint
want="mise-install swiftformat-version swiftlint-version xcodebuild-Ledger xcbeautify check-test-results-PR \
xcodebuild-LedgerWatch xcbeautify check-test-results-PR-Watch coverage-gate "
if [[ $code -eq 0 && "$calls" == "$want" ]]; then pass "W09 --skip-lint runs tools, iOS, watchOS, coverage"; else
    fail "W09 --skip-lint runs tools, iOS, watchOS, coverage" "exit $code
want: $want
got:  $calls"; fi
for id in xcodebuild-Ledger check-test-results-PR xcodebuild-LedgerWatch check-test-results-PR-Watch coverage-gate; do
    FAIL_AT="$id" run --skip-lint
    expect_exit "W10 --skip-lint: failure at $id fails" nonzero "$code"
done

run --lint-only
if [[ $code -eq 0 && "$calls" != *xcodebuild* && "$calls" == *script-test-b* ]]; then
    pass "W11 --lint-only runs format, lint, graph, script tests and no simulator step"
else
    fail "W11 --lint-only runs format, lint, graph, script tests and no simulator step" "exit $code, calls: $calls"
fi
FAIL_AT=script-test-b run --lint-only
expect_exit "W12 --lint-only: a failing script test fails" nonzero "$code"

run --lint-only --skip-lint
if [[ $code -ne 0 ]]; then
    pass "W13 --lint-only --skip-lint (checks nothing) is rejected"
else
    fail "W13 [F7] --lint-only --skip-lint (checks nothing) is rejected" \
        "exit 0 after running only: $calls
$(tail -1 <<<"$out")"
fi

run --bogus
expect_exit "W14 unknown flag exits 2" 2 "$code"

FAIL_AT=swift-test run --fast
expect_exit "W15 --fast: failing swift test fails" nonzero "$code"

# ---- GitHub annotations (criterion 2) ------------------------------------------
GITHUB_ACTIONS=true run
check "W16 on Actions swiftformat reports as github-actions-log" \
    grep -q '^swiftformat-lint .*--reporter github-actions-log' "$LOG"
check "W17 on Actions swiftlint reports as github-actions-logging" \
    grep -q '^swiftlint-lint .*--reporter github-actions-logging' "$LOG"
check "W18 on Actions xcbeautify renders github-actions" \
    grep -q '^xcbeautify --renderer github-actions' "$LOG"
run
check "W19 locally no Actions reporter is passed" bash -c "! grep -q 'github-actions' '$LOG'"

# ---- F01's first CI run: xcodebuild exited 70 on the watch by name (paired with iPhones) -------
unset LEDGER_IOS_DEST LEDGER_WATCH_DEST
run
check "W23 xcodebuild gets each default simulator by UDID (the runner's iPhone 17 and Series 11 on 26.5)" \
    is "$(grep '^xcodebuild' "$LOG" | tr '\n' ';')" \
    "xcodebuild-Ledger platform=iOS Simulator,id=88931AEA-62E6-447F-8697-DCE00A671384;xcodebuild-LedgerWatch platform=watchOS Simulator,id=07C1BE1A-2EFF-4897-8A98-D6E7C104E516;"
check "W24 ... after unpairing both (the fixture pairs them: iPhone 17 + Ultra 3, Series 11 + 17 Pro Max)" \
    is "$(grep '^simctl unpair' "$XCRUN_LOG" | tr '\n' ';')" \
    "simctl unpair 00000003-FA1E-4A1E-8A1E-000000000003;simctl unpair 00000001-FA1E-4A1E-8A1E-000000000001;"
LEDGER_IOS_DEST='platform=iOS Simulator,name=iPhone Air,OS=26.5' \
    LEDGER_WATCH_DEST='platform=watchOS Simulator,id=98D83340-55EC-4686-AE5E-5ABDF78767BF' run
check "W25 LEDGER_*_DEST overrides by name and OS, or by id, reach xcodebuild as UDIDs" \
    is "$(grep '^xcodebuild' "$LOG" | tr '\n' ';')" \
    "xcodebuild-Ledger platform=iOS Simulator,id=CB15797E-6053-40B1-BB72-7F30D005A4F2;xcodebuild-LedgerWatch platform=watchOS Simulator,id=98D83340-55EC-4686-AE5E-5ABDF78767BF;"
LEDGER_WATCH_DEST='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=27.0' run
if [[ $code -ne 0 && "$calls" != *xcodebuild* ]]; then
    pass "W26 a destination that matches no simulator stops check.sh before any xcodebuild"
else
    fail "W26 a destination that matches no simulator stops check.sh before any xcodebuild" "exit $code, calls: $calls"
fi
run --lint-only; lint_calls="$(wc -l <"$XCRUN_LOG" | tr -d ' ')"
run --fast
check "W27 --lint-only and --fast look up no simulator" is "$lint_calls $(wc -l <"$XCRUN_LOG" | tr -d ' ')" "0 0"

# ---- round 2: this suite is part of the gate ---------------------------------------
# check.sh step 2 runs scripts/tests/*.test.sh; one of them must run this runner, be
# committed executable, and propagate its failure (exec, or an unguarded call).
entry="$ROOT/scripts/tests/adversarial.test.sh"
check "W20 check.sh step 2 runs every scripts/tests/*.test.sh" \
    grep -qF 'for test in scripts/tests/*.test.sh; do "$test"; done' "$ROOT/scripts/check.sh"
check "W21 scripts/tests/adversarial.test.sh is committed executable" \
    is "$(git -C "$ROOT" ls-files -s scripts/tests/adversarial.test.sh | awk '{ print $1 }')" 100755
check "W22 ... and it execs adversarial/run.sh (a failing suite fails step 2)" \
    grep -qE '^exec "\$\(dirname "\$0"\)/adversarial/run\.sh"$' "$entry"

finish
