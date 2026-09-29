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
cp "${ADV_SIM_BOOT:-$ROOT/scripts/sim-boot.sh}" "$SB/scripts/sim-boot.sh"                         # the real one
fake_simctl "$SB/bin" # ... against the runner's simulators, logging to $LOG too: one ordered log
export LOG="$ADV_TMP/calls.log" XCRUN_LOG="$ADV_TMP/calls.log"
mkdir -p "$SB/hang" && ln -s /bin/sleep "$SB/hang/xcodebuild" # a hung xcodebuild, by process name

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
printf "%s\\n" "$*" >>"$LOG.args"
action="$1"; scheme=""; bundle=""; dest=""
while [ $# -gt 0 ]; do
    case "$1" in -scheme) scheme="$2" ;; -resultBundlePath) bundle="$2" ;; -destination) dest="$2" ;; esac
    shift
done
log "xcodebuild-$action-$scheme $dest"
mkdir -p "$bundle"
echo "Test Suite All tests passed"
[ "${HANG_AT:-}" != "xcodebuild-$action-$scheme" ] || exec "$(dirname "$0")/../hang/xcodebuild" 60
fail_if "xcodebuild-$action-$scheme"'
stub "$SB/bin/swift" 'log swift-test; fail_if swift-test'
stub "$SB/scripts/check-package-graph.sh" 'log package-graph; fail_if package-graph'
stub "$SB/scripts/check-test-results.sh" 'id="check-test-results-$(basename "$2" .xctestplan)"; log "$id $1"; fail_if "$id"'
stub "$SB/scripts/coverage-gate.sh" 'log "coverage-gate $*"; fail_if coverage-gate'
stub "$SB/scripts/tests/a.test.sh" 'log script-test-a; fail_if script-test-a'
stub "$SB/scripts/tests/b.test.sh" 'log script-test-b; fail_if script-test-b'

# run [flags...]: the sandboxed check.sh; sets $code, $out and $calls (ids only; simctl's simulator
# lookups, list and unpair, are sim-destination.sh's and pinned by W23-W27).
run() {
    : >"$LOG"; : >"$LOG.args"
    out="$(PATH="$SB/bin:$PATH" "$SB/scripts/check.sh" "$@" 2>&1)"
    code=$?
    calls="$(awk '$1 == "simctl" { if ($2 != "list" && $2 != "unpair") print "simctl-" $2; next } { print $1 }' "$LOG" |
        tr '\n' ' ')"
}
# lifecycle: the simulator steps in order, "<step> <udid>;" (boot, bootstatus, shutdown, erase, xcodebuild)
lifecycle() {
    sed -nE -e 's/^simctl (boot|bootstatus|shutdown|erase) ([^ ]+).*/\1 \2/p' \
        -e 's/^xcodebuild-(build-for-testing|test-without-building)-[A-Za-z]+ .*id=([^,]+).*/\1 \2/p' "$LOG" | tr '\n' ';'
}
I=88931AEA-62E6-447F-8697-DCE00A671384 W=07C1BE1A-2EFF-4897-8A98-D6E7C104E516 # the runner's defaults

FULL="mise-install swiftformat-version swiftlint-version swiftformat-lint swiftlint-lint package-graph \
script-test-a script-test-b \
simctl-boot xcodebuild-build-for-testing-Ledger xcbeautify \
simctl-bootstatus xcodebuild-test-without-building-Ledger xcbeautify check-test-results-PR \
simctl-boot xcodebuild-build-for-testing-LedgerWatch xcbeautify \
simctl-bootstatus xcodebuild-test-without-building-LedgerWatch xcbeautify check-test-results-PR-Watch coverage-gate"
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
    [[ "$id" == xcbeautify || "$id" == simctl-* ]] && continue # covered below: each appears more than once
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
FAIL_AT=xcodebuild-test-without-building-Ledger FAIL_CODE=65 run
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
want="mise-install swiftformat-version swiftlint-version ${FULL#*script-test-b }"
if [[ $code -eq 0 && "$calls" == "$want" ]]; then pass "W09 --skip-lint runs tools, iOS, watchOS, coverage"; else
    fail "W09 --skip-lint runs tools, iOS, watchOS, coverage" "exit $code
want: $want
got:  $calls"; fi
for id in xcodebuild-build-for-testing-Ledger xcodebuild-test-without-building-Ledger check-test-results-PR \
    xcodebuild-build-for-testing-LedgerWatch xcodebuild-test-without-building-LedgerWatch check-test-results-PR-Watch coverage-gate; do
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
    "xcodebuild-build-for-testing-Ledger platform=iOS Simulator,id=$I;xcodebuild-test-without-building-Ledger platform=iOS Simulator,id=$I;xcodebuild-build-for-testing-LedgerWatch platform=watchOS Simulator,id=$W;xcodebuild-test-without-building-LedgerWatch platform=watchOS Simulator,id=$W;"
check "W24 ... after unpairing both (the fixture pairs them: iPhone 17 + Ultra 3, Series 11 + 17 Pro Max)" \
    is "$(grep '^simctl unpair' "$LOG" | tr '\n' ';')" \
    "simctl unpair 00000003-FA1E-4A1E-8A1E-000000000003;simctl unpair 00000001-FA1E-4A1E-8A1E-000000000001;"
LEDGER_IOS_DEST='platform=iOS Simulator,name=iPhone Air,OS=26.5' \
    LEDGER_WATCH_DEST='platform=watchOS Simulator,id=98D83340-55EC-4686-AE5E-5ABDF78767BF' run
air="platform=iOS Simulator,id=CB15797E-6053-40B1-BB72-7F30D005A4F2"
s11="platform=watchOS Simulator,id=98D83340-55EC-4686-AE5E-5ABDF78767BF"
check "W25 LEDGER_*_DEST overrides by name and OS, or by id, reach xcodebuild as UDIDs" \
    is "$(grep '^xcodebuild' "$LOG" | cut -d ' ' -f 2- | tr '\n' ';')" "$air;$air;$s11;$s11;"
LEDGER_WATCH_DEST='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=27.0' run
if [[ $code -ne 0 && "$calls" != *xcodebuild* ]]; then
    pass "W26 a destination that matches no simulator stops check.sh before any xcodebuild"
else
    fail "W26 a destination that matches no simulator stops check.sh before any xcodebuild" "exit $code, calls: $calls"
fi
run --lint-only; lint_calls="$(grep -c '^simctl' "$LOG")"
run --fast
check "W27 --lint-only and --fast look up, boot or wait for no simulator" is "$lint_calls $(grep -c '^simctl' "$LOG")" "0 0"

# ---- F01's second CI run: parallel-testing clones each paid a first boot, and the step timed out ----
green="boot $I;build-for-testing $I;bootstatus $I;test-without-building $I;\
boot $W;build-for-testing $W;bootstatus $W;test-without-building $W;"
run
check "W28 per platform: boot, build-for-testing, wait for the boot, test-without-building, by UDID" \
    is "$code $(lifecycle)" "0 $green"
tests="$(grep '^test' "$LOG.args")"
check "W29 every test run passes -parallel-testing-enabled NO (no clones, no worker count)" \
    is "$(grep -c . <<<"$tests") $(grep -c -- ' -parallel-testing-enabled NO ' <<<"$tests") $(grep -c 'parallel-testing-enabled YES\|worker-count' <<<"$tests")" "2 2 0"
XCRUN_HANG=unerased LEDGER_BOOT_TIMEOUT=1 run
check "W30 a boot that times out is erased and waited for once more, then the tests run" \
    is "$code $(lifecycle)" "0 boot $I;build-for-testing $I;bootstatus $I;shutdown $I;erase $I;bootstatus $I;\
test-without-building $I;boot $W;build-for-testing $W;bootstatus $W;shutdown $W;erase $W;bootstatus $W;test-without-building $W;"
XCRUN_HANG=always LEDGER_BOOT_TIMEOUT=1 run
check "W31 a boot that times out again after the erase stops check.sh before any test run" \
    is "$code $(lifecycle) $(grep -c "simulator $I did not boot within 1s, even after an erase" <<<"$out")" \
    "1 boot $I;build-for-testing $I;bootstatus $I;shutdown $I;erase $I;bootstatus $I; 1"
XCRUN_FAIL=bootstatus run
check "W32 a bootstatus that fails (rather than hangs) takes the same path: one erase, then stop" \
    is "$code $(lifecycle)" "1 boot $I;build-for-testing $I;bootstatus $I;shutdown $I;erase $I;bootstatus $I;"
XCRUN_BOOTED=1 run
check "W33 a simulator already booted is fine, and says nothing" \
    is "$code $(grep -c 'current state' <<<"$out") $(lifecycle)" "0 0 $green"
XCRUN_FAIL='boot ' run
check "W34 any other boot error is shown and left to the wait (bootstatus -b boots it too)" \
    is "$code $(grep -c "simctl: boot $I failed" <<<"$out") $(lifecycle)" "0 1 $green"

# A CI step's timeout kills check.sh but not xcodebuild, so check.sh interrupts xcodebuild first. The
# stub hangs 60 s as a process named xcodebuild; perl resets SIGINT, which a background caller ignores.
SECONDS=0
: >"$LOG"
out="$(HANG_AT=xcodebuild-test-without-building-Ledger LEDGER_XCODEBUILD_DEADLINE=3 PATH="$SB/bin:$PATH" \
    perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV or die' "$SB/scripts/check.sh" --skip-lint 2>&1)"
code=$?
check "W35 LEDGER_XCODEBUILD_DEADLINE interrupts a hung xcodebuild (SIGINT, exit 130), failing check.sh" \
    is "$code $((SECONDS < 30)) $(grep -c check-test-results "$LOG") $(grep -c 'check.sh FAILED (exit 130)' <<<"$out")" \
    "130 1 0 1"

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
