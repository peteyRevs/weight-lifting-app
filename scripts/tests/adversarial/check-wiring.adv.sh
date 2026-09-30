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
cp "${ADV_CHECK_XCODE:-$ROOT/scripts/check-xcode-version.sh}" "$SB/scripts/check-xcode-version.sh" # the real one
cp "${ADV_BOOTSTRAP:-$ROOT/scripts/bootstrap.sh}" "$SB/scripts/bootstrap.sh"                     # the real one (W41)
echo 27.0 >"$SB/.xcode-version" # the stub xcodebuild reports $XCODE_REPORTS, 27.0 by default
fake_simctl "$SB/bin" # ... against the runner's simulators, logging to $LOG too: one ordered log
export LOG="$ADV_TMP/calls.log" XCRUN_LOG="$ADV_TMP/calls.log"
# A hung xcodebuild, by process name: bash under a symlink named xcodebuild runs hang.sh. It tells W35's
# watchdog it has started, then waits 60 s on a fifo nobody writes. Only a wait that runs out is logged.
mkdir -p "$SB/hang" && ln -s /bin/bash "$SB/hang/xcodebuild" && mkfifo "$SB/hang/started" "$SB/hang/never"
cat >"$SB/hang/hang.sh" <<'SH'
exec 3<>"$(dirname "$0")/started" && echo started >&3 # fd 3 stays open, so the line waits for its reader
read -r -t 60 <>"$(dirname "$0")/never" # a builtin: SIGINT ends this process, not a child
echo "hang completed" >>"$LOG"
SH

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
if [ "$1" = -version ]; then
    log xcode-version; fail_if xcode-version
    printf "Xcode %s\\nBuild version 27A266a\\n" "${XCODE_REPORTS:-27.0}"; exit 0
fi
printf "%s\\n" "$*" >>"$LOG.args"
action="$1"; scheme=""; bundle=""; dest=""; diag=unset
while [ $# -gt 0 ]; do
    case "$1" in -scheme) scheme="$2" ;; -resultBundlePath) bundle="$2" ;; -destination) dest="$2" ;;
        -collect-test-diagnostics) diag="$2" ;; build-for-testing | test-without-building) action="$1" ;; esac
    shift
done
log "xcodebuild-$action-$scheme $dest"
printf "%s diagnostics=%s\\n" "$action" "$diag" >>"$LOG.diag"
printf "%s %s\\n" "$action-$scheme" "${TEST_RUNNER_SNAPSHOT_TESTING_RECORD-unset}" >>"$LOG.env"
mkdir -p "$bundle"
echo "Test Suite All tests passed"
[ "${HANG_AT:-}" != "xcodebuild-$action-$scheme" ] || exec "$(dirname "$0")/../hang/xcodebuild" "$(dirname "$0")/../hang/hang.sh"
fail_if "xcodebuild-$action-$scheme"'
stub "$SB/bin/swift" 'log "swift-test $*"; fail_if swift-test'
stub "$SB/bin/git" 'log "git $*"; fail_if git'
# W35's watchdog sleeps until the hang has started, whatever the load; at most 60 s if it never does.
mkdir -p "$SB/deadline" && cat >"$SB/deadline/sleep" <<'SH' && chmod +x "$SB/deadline/sleep"
#!/bin/bash
printf 'sleep %s\n' "$*" >>"$LOG"
read -r -t 60 _ <>"$(dirname "$0")/../hang/started"
SH
stub "$SB/scripts/check-package-graph.sh" 'log package-graph; fail_if package-graph'
stub "$SB/scripts/check-package-pins.sh" 'log package-pins; fail_if package-pins'
stub "$SB/scripts/check-test-results.sh" 'id="check-test-results-$(basename "$2" .xctestplan)"; log "$id $1"; fail_if "$id"'
stub "$SB/scripts/coverage-gate.sh" 'log "coverage-gate $*"; fail_if coverage-gate'
stub "$SB/scripts/tests/a.test.sh" 'log script-test-a; fail_if script-test-a'
stub "$SB/scripts/tests/b.test.sh" 'log script-test-b; fail_if script-test-b'

# run [flags...]: the sandboxed check.sh; sets $code, $out and $calls (ids only; simctl's simulator
# lookups, list and unpair, are sim-destination.sh's and pinned by W23-W27).
run() {
    : >"$LOG"; : >"$LOG.args"; : >"$LOG.env"; : >"$LOG.diag"
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
I=46F7C9EA-B38C-445A-BAD9-8A70A603E9E1 W=2416B270-8634-4D4A-9084-2B04B4498921 # the defaults, on the xcode-27 image

FULL="xcode-version mise-install swiftformat-version swiftlint-version swiftformat-lint swiftlint-lint package-graph \
package-pins script-test-a script-test-b \
simctl-boot xcodebuild-build-for-testing-Ledger xcbeautify \
simctl-bootstatus xcodebuild-test-without-building-Ledger xcbeautify check-test-results-PR \
simctl-boot xcodebuild-build-for-testing-LedgerWatch xcbeautify \
simctl-bootstatus xcodebuild-test-without-building-LedgerWatch xcbeautify check-test-results-PR-Watch coverage-gate"
FULL="$(echo $FULL) "

unset FAIL_AT GITHUB_ACTIONS SNAPSHOT_TESTING_RECORD TEST_RUNNER_SNAPSHOT_TESTING_RECORD
run
expect_exit "W01 full run with every step green exits 0" 0 "$code" "$out"
if [[ "$calls" == "$FULL" ]]; then pass "W02 full run calls every step in order"; else
    fail "W02 full run calls every step in order" "want: $FULL
got:  $calls"; fi
check "W03 coverage gate reads both bundles, in full mode (no --ios-only)" \
    is "$(grep '^coverage-gate' "$LOG")" 'coverage-gate .derivedData/Results/PR-iOS.xcresult .derivedData/Results/PR-watchOS.xcresult'

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
want="xcode-version mise-install swiftformat-version swiftlint-version ${FULL#*script-test-b }"
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
check "W23 xcodebuild gets each default simulator by UDID (the xcode-27 image's iPhone 17 and Series 12 on 27.0)" \
    is "$(grep '^xcodebuild' "$LOG" | tr '\n' ';')" \
    "xcodebuild-build-for-testing-Ledger platform=iOS Simulator,id=$I;xcodebuild-test-without-building-Ledger platform=iOS Simulator,id=$I;xcodebuild-build-for-testing-LedgerWatch platform=watchOS Simulator,id=$W;xcodebuild-test-without-building-LedgerWatch platform=watchOS Simulator,id=$W;"
check "W24 ... after unpairing both (the fixture pairs them as Xcode 27 does: iPhone 17 + Ultra 4, Series 12 + 18 Pro Max)" \
    is "$(grep '^simctl unpair' "$LOG" | tr '\n' ';')" \
    "simctl unpair 00002703-FA1E-4A1E-8A1E-000000002703;simctl unpair 00002701-FA1E-4A1E-8A1E-000000002701;"
LEDGER_IOS_DEST='platform=iOS Simulator,name=iPhone Air,OS=27.0' \
    LEDGER_WATCH_DEST='platform=watchOS Simulator,id=3A3B91C1-A67A-4F4E-9C2A-5DA1567C2D5F' run
air="platform=iOS Simulator,id=3F725D53-2EEF-470E-A724-90E5D09B0BF1"
s12="platform=watchOS Simulator,id=3A3B91C1-A67A-4F4E-9C2A-5DA1567C2D5F"
check "W25 LEDGER_*_DEST overrides by name and OS, or by id, reach xcodebuild as UDIDs" \
    is "$(grep '^xcodebuild' "$LOG" | cut -d ' ' -f 2- | tr '\n' ';')" "$air;$air;$s12;$s12;"
# The image has no Series 11 and no 26.x runtime: F01's 26.5 defaults, or a Series 11 on 27.0, match nothing.
for dest in 'Apple Watch Series 11 (46mm),OS=27.0' 'Apple Watch Series 11 (46mm),OS=26.5'; do
    LEDGER_WATCH_DEST="platform=watchOS Simulator,name=$dest" run
    if [[ $code -ne 0 && "$calls" != *xcodebuild* ]]; then
        pass "W26 a destination that matches no simulator ($dest) stops check.sh before any xcodebuild"
    else
        fail "W26 a destination that matches no simulator ($dest) stops check.sh before any xcodebuild" "exit $code, calls: $calls"
    fi
done
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
# The watchdog's sleep is the stub in $SB/deadline, which returns once the hang has started, so no
# load can fire it early or late; "hang completed" in the log means no SIGINT arrived.
: >"$LOG"
out="$(HANG_AT=xcodebuild-test-without-building-Ledger LEDGER_XCODEBUILD_DEADLINE=3 PATH="$SB/deadline:$SB/bin:$PATH" \
    perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV or die' "$SB/scripts/check.sh" --skip-lint 2>&1)"
code=$?
check "W35 LEDGER_XCODEBUILD_DEADLINE interrupts a hung xcodebuild (SIGINT, exit 130), failing check.sh" \
    is "$code $(grep -c '^sleep 3$' "$LOG") $(grep -c 'hang completed' "$LOG") $(grep -c check-test-results "$LOG") \
$(grep -c 'check.sh FAILED (exit 130)' <<<"$out")" "130 1 0 0 1"

# ---- F32: step 0 fails on any Xcode but the pinned one, in every mode, as bootstrap.sh does ----------
pinned_msg="error: this repo is pinned to Xcode 27.0 (.xcode-version) but
       xcodebuild reports 26.6.
       Select the right one:  sudo xcode-select -s /Applications/Xcode.app"
for flags in "" --fast --lint-only --skip-lint --record-snapshots --ios-only; do
    XCODE_REPORTS=26.6 run $flags
    check "W40 on Xcode 26.6 with 27.0 pinned, check.sh ${flags:-(full)} fails at step 0, before any tool, saying so" \
        is "$code $calls$(grep -c '^error: this repo is pinned' <<<"$out")" "1 xcode-version 1"
done
check "W41 ... with bootstrap.sh's message, word for word" is "$(grep -A2 '^error: this repo is pinned' <<<"$out")" "$pinned_msg"
: >"$LOG"
out="$(XCODE_REPORTS=26.6 PATH="$SB/bin:$PATH" "$SB/scripts/bootstrap.sh" 2>&1)"; code=$?
bootstrap_msg="$(grep -A2 '^error: this repo is pinned' <<<"$out")"; bootstrap_calls="$(tr '\n' ' ' <"$LOG")"
: >"$LOG"
PATH="$SB/bin:$PATH" "$SB/scripts/bootstrap.sh" >/dev/null 2>&1 # stops later, at the fake simctl
check "W41 bootstrap.sh stops at the same check with the same message, and passes the pinned Xcode on to mise" \
    is "$code $bootstrap_calls| $(head -2 "$LOG" | tr '\n' ' ')| $bootstrap_msg" "1 xcode-version | xcode-version mise-install | $pinned_msg"
check "W42 one copy of the check: check.sh step 0 and bootstrap.sh both run scripts/check-xcode-version.sh" \
    is "$(grep -c '^scripts/check-xcode-version\.sh' "$ROOT/scripts/check.sh" "$ROOT/scripts/bootstrap.sh" | tr '\n' ' ')$(grep -lF 'xcodebuild -version' "$ROOT"/scripts/*.sh | tr '\n' ' ')" \
    "$ROOT/scripts/check.sh:1 $ROOT/scripts/bootstrap.sh:1 $ROOT/scripts/check-xcode-version.sh "

# ---- F32: packages resolve only to the committed Package.resolved (Swift 6.4 rewrote a pin) --------
run
builds="$(grep -E '^(build-for-testing|test-without-building) ' "$LOG.args")"
check "W43 every xcodebuild build and test run passes -onlyUsePackageVersionsFromResolvedFile" \
    is "$(grep -c . <<<"$builds") $(grep -c -- ' -onlyUsePackageVersionsFromResolvedFile\( \|$\)' <<<"$builds")" "4 4"
run --fast
check "W44 --fast's swift test passes --only-use-versions-from-resolved-file" \
    is "$code $(grep -c '^swift-test .*--only-use-versions-from-resolved-file' "$LOG")" "0 1"
# Xcode 27 runs `simctl diagnose` after a failing test run; here it timed out after 600 s per platform.
# The stub reads the flag's value wherever it sits, so moving the flag is not a failure (F32 T2).
FAIL_AT=xcodebuild-test-without-building-Ledger run
check "W45 every test run, a failing one too, passes -collect-test-diagnostics never" \
    is "$code $(grep '^test-without-building ' "$LOG.diag" | tr '\n' ';')" "1 test-without-building diagnostics=never;"
run
check "W45 ... (both platforms on a green run)" \
    is "$(grep '^test-without-building ' "$LOG.diag" | tr '\n' ';')" \
    "test-without-building diagnostics=never;test-without-building diagnostics=never;"
# F32 adversarial (tasks/features/F32-xcode-27-migration/test-findings.md): record mode takes the other
# branch of run_plan, and swift test knows neither xcodebuild flag.
run --record-snapshots
builds="$(grep -E '^(build-for-testing|test-without-building) ' "$LOG.args")"
tests="$(grep '^test-without-building ' "$LOG.args")"
check "W46 --record-snapshots pins packages on all four xcodebuild calls and skips diagnostics on both test runs" \
    is "$(grep -c . <<<"$builds") $(grep -c -- ' -onlyUsePackageVersionsFromResolvedFile\( \|$\)' <<<"$builds") \
$(grep -c -- ' -collect-test-diagnostics never\( \|$\)' <<<"$tests")" "4 4 2"
run --fast
check "W47 --fast's swift test gets neither xcodebuild-only flag (swift test would reject it)" \
    is "$code $(grep -c '^swift-test .*\(-collect-test-diagnostics\|-onlyUsePackageVersionsFromResolvedFile\)' "$LOG")" "0 0"
# F32 fix round (T1): LedgerKit's lockfile is checked against the project's in step 2 of every mode that
# lints; W02 and W04 show the full gate runs it and stops on it.
FAIL_AT=package-pins run --lint-only
check "W48 --lint-only runs the package pins check after the graph check, and a mismatch fails it there" \
    is "$code $calls" "1 xcode-version mise-install swiftformat-version swiftlint-version swiftformat-lint swiftlint-lint \
package-graph package-pins "

# ---- --record-snapshots: F06's run_plan keeps going after a failing plan, if tests ran ----------
# The fake xcrun's `xcresulttool get test-results summary` reports $XCRUN_TEST_COUNT tests (1).
record_log() { # the lifecycle, plus each xcresulttool read of a bundle
    sed -nE -e 's/^simctl (boot|bootstatus) ([^ ]+).*/\1 \2/p' \
        -e 's/^xcodebuild-(build-for-testing|test-without-building)-[A-Za-z]+ .*id=([^,]+).*/\1 \2/p' \
        -e 's/^xcresulttool get test-results summary --path .*/xcresulttool/p' "$LOG" | tr '\n' ';'
}
recorded="boot $I;build-for-testing $I;bootstatus $I;test-without-building $I;xcresulttool;\
boot $W;build-for-testing $W;bootstatus $W;test-without-building $W;xcresulttool;"
FAIL_AT=xcodebuild-test-without-building-Ledger FAIL_CODE=65 run --record-snapshots
check "W36 record mode runs both platforms (boot, build, wait, test, read the bundle) though iOS's tests fail" \
    is "$code $(record_log) $(grep -c '^check-test-results\|^coverage-gate' "$LOG")" "1 $recorded 0"
run --record-snapshots; rec="$(grep '^test-without-building' "$LOG.env" | tr '\n' ';')"
run; norm="$(grep '^test-without-building' "$LOG.env" | tr '\n' ';')"
check "W37 record mode passes TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all to both test runs; a normal run does not" \
    is "$rec $norm" "test-without-building-Ledger all;test-without-building-LedgerWatch all; \
test-without-building-Ledger unset;test-without-building-LedgerWatch unset;"
stopped() { # exit code, calls, then how often it said why / that references were recorded
    printf '%s %s %s/%s' "$code" "$(record_log)" \
        "$(grep -cxF 'error: the record run failed before any test ran (.derivedData/Results/PR-iOS.xcresult)' <<<"$out")" \
        "$(grep -c 'references recorded' <<<"$out")"
}
ios_only="boot $I;build-for-testing $I;bootstatus $I;test-without-building $I;xcresulttool;"
XCRUN_TEST_COUNT=0 run --record-snapshots; zero="$(stopped)"
XCRUN_FAIL='get test-results' run --record-snapshots
check "W38 a record run whose bundle reports no test (or cannot be read) fails there, before the watch" \
    is "$zero; $(stopped)" "1 $ios_only 1/0; 1 $ios_only 1/0"
run --record-snapshots
check "W39 a green record run lists the changed references, then exits 1 with no results or coverage check" \
    is "$code $(grep '^git' "$LOG") $(grep -c '^check-test-results\|^coverage-gate' "$LOG") \
$(grep -cxF 'snapshot references recorded; re-run check.sh (without the flag) to verify them' <<<"$out")" \
    "1 git status --short -- :(glob)**/__Snapshots__/** 0 1"

# ---- F32: PR CI runs --ios-only (Pete, 2026-09-30); without the flag both platforms run (W01-W03) ------
# The first xcode-27 run reached LEDGER_XCODEBUILD_DEADLINE in the watchOS tests (F32 notes, "CI trial").
IOS_CALLS="${FULL%%simctl-boot xcodebuild-build-for-testing-LedgerWatch *}coverage-gate "
run --ios-only
check "W49 --ios-only runs steps 0-3 and 5 in order: tools, format, lint, script tests, iOS, its results, coverage" \
    is "$code $calls" "0 $IOS_CALLS"
check "W50 ... and the coverage gate gets --ios-only and the iOS bundle alone" \
    is "$(grep '^coverage-gate' "$LOG")" "coverage-gate --ios-only .derivedData/Results/PR-iOS.xcresult"
check "W51 ... and it looks up, unpairs, boots, builds and tests the iPhone only: no call names the watch" \
    is "$(lifecycle) $(grep -c '^simctl list devices' "$LOG") $(grep '^simctl unpair' "$LOG" | tr '\n' ';') \
$(cat "$LOG" "$LOG.args" | grep -c -e "$W" -e LedgerWatch -e PR-watchOS)" \
    "boot $I;build-for-testing $I;bootstatus $I;test-without-building $I; 1 simctl unpair 00002703-FA1E-4A1E-8A1E-000000002703; 0"
check "W52 ... and it says step 4 is skipped, in the output and the summary, and ends \"check.sh (--ios-only) OK\"" \
    is "$(grep -c '==> 4 · watchOS skipped (--ios-only)' <<<"$out") $(grep -cE '^ +[0-9]+s  watchOS skipped \(--ios-only\)$' <<<"$out") \
$(grep -c 'check\.sh (--ios-only) OK' <<<"$out") $(grep -c 'check\.sh OK' <<<"$out")" "1 1 1 0"
for id in $IOS_CALLS; do
    [[ "$id" == xcbeautify || "$id" == simctl-* ]] && continue # as W04
    want=" $IOS_CALLS"; want="${want%%" $id "*} $id "; want="${want# }"
    [[ "$id" == xcodebuild-* ]] && want="${want}xcbeautify "
    FAIL_AT="$id" run --ios-only
    check "W53 --ios-only: failure at $id stops check.sh there" is "$([[ $code -ne 0 ]] && echo failed) $calls" "failed $want"
done
want="xcode-version mise-install swiftformat-version swiftlint-version ${IOS_CALLS#*script-test-b }"
run --skip-lint --ios-only; either="$code $calls"
run --ios-only --skip-lint
check "W54 --ios-only --skip-lint, in either order, runs tools, iOS, its results and coverage" \
    is "$either|$code $calls" "0 $want|0 $want"
run --lint-only --skip-lint; w13="$code $calls|$(grep -c '^error: contradictory flags' <<<"$out")"
for flags in "--ios-only --lint-only" "--lint-only --ios-only" "--ios-only --fast" "--fast --ios-only"; do
    run $flags
    check "W55 $flags is rejected as --lint-only --skip-lint is (W13): exit 2, before any step" \
        is "$w13 $code $calls|$(grep -c '^error: contradictory flags' <<<"$out")" "2 |1 2 |1"
done
run --ios-only --record-snapshots
check "W56 --ios-only --record-snapshots records on the iPhone alone, lists the references, exits 1 unchecked" \
    is "$code $(record_log) $(grep '^test-without-building' "$LOG.env" | tr '\n' ';') $(grep -c '^git status' "$LOG") \
$(grep -c '^check-test-results\|^coverage-gate' "$LOG")" "1 $ios_only test-without-building-Ledger all; 1 0"

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
