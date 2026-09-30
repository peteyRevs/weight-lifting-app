#!/usr/bin/env bash
# scripts/sim-destination.sh against the runners' simulators (lib.sh: fixtures/simctl/xcode-27.json, the
# image CI uses, and macos-26.json, from PR #5's first run): a watch destination by name also matched the
# iPhones paired with same-named watches of any OS, and xcodebuild exited 70. By UDID it resolves; the
# resolved device is also unpaired, as defence in depth. xcrun is faked (lib.sh fake_simctl): simctl
# lists the fixture.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

RESOLVE="${ADV_SIM_DESTINATION:-$ROOT/scripts/sim-destination.sh}" # override: mutation-test this suite
T="$ADV_TMP"
fake_simctl "$T/bin"
export PATH="$T/bin:$PATH" XCRUN_LOG="$T/xcrun.log"

# resolve <destination>: sets $out (stdout), $err (stderr) and $code.
resolve() { out="$("$RESOLVE" "$1" 2>"$T/err")"; code=$?; err="$(cat "$T/err")"; }

# ---- the xcode-27 image: check.sh's and the nightly's defaults (check.sh:19-20, nightly.yml matrix) ----
resolve 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.0'
check "SD16 the default watch resolves on the xcode-27 image to its Series 12 (46mm) on 27.0, by UDID" \
    is "$code $out" "0 platform=watchOS Simulator,id=2416B270-8634-4D4A-9084-2B04B4498921"
resolve 'platform=iOS Simulator,name=iPhone 17,OS=27.0'
check "SD17 the default iPhone resolves on the xcode-27 image to its iPhone 17 on 27.0, by UDID" \
    is "$code $out" "0 platform=iOS Simulator,id=46F7C9EA-B38C-445A-BAD9-8A70A603E9E1"
for dest in 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=27.0' \
    'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
    'platform=iOS Simulator,name=iPhone 17,OS=26.5'; do
    resolve "$dest"
    check "SD18 the xcode-27 image has no Series 11 and no 26.x runtime -> exit 1: $dest" \
        is "$code [$out] $(grep -cF "$dest" <<<"$err")" "1 [] 1"
done

# ---- macos-26: F01's defaults, among same-named twins on 26.2, 26.4 and 26.5 ----
export SIMCTL_JSON="$SIMCTL_MACOS26"
WATCH='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'
IOS='platform=iOS Simulator,name=iPhone 17,OS=26.5'
resolve "$WATCH"
check "SD01 a watch by name and OS resolves to the one 26.5 Series 11 (46mm), by UDID (not its 26.2/26.4 twins)" \
    is "$code $out" "0 platform=watchOS Simulator,id=07C1BE1A-2EFF-4897-8A98-D6E7C104E516"
resolve "$IOS"
check "SD02 an iPhone by name and OS resolves to the available iPhone 17 on 26.5 (an unavailable twin is skipped)" \
    is "$code $out" "0 platform=iOS Simulator,id=88931AEA-62E6-447F-8697-DCE00A671384"
check "SD03 a resolved destination carries no name (xcodebuild then matches exactly one device)" \
    bash -c "! grep -q 'name=' <<<'$out'"

# Overrides (LEDGER_IOS_DEST / LEDGER_WATCH_DEST) keep working.
resolve 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm),OS=26.4'
check "SD04 an override by name and OS resolves the same way" \
    is "$code $out" "0 platform=watchOS Simulator,id=16F616F7-8578-4BBB-9C03-A193FFF485DE"
: >"$XCRUN_LOG"
resolve 'platform=watchOS Simulator,id=98D83340-55EC-4686-AE5E-5ABDF78767BF'
check "SD05 an override by id passes through unchanged, without a device lookup" \
    is "$code $out $(grep -c 'list devices' "$XCRUN_LOG")" \
    "0 platform=watchOS Simulator,id=98D83340-55EC-4686-AE5E-5ABDF78767BF 0"
resolve 'OS=26.5,name=iPhone Air,platform=iOS Simulator'
check "SD06 the key order does not matter" is "$code $out" "0 platform=iOS Simulator,id=CB15797E-6053-40B1-BB72-7F30D005A4F2"

# No match fails closed: nothing on stdout for xcodebuild, the destination named on stderr.
for dest in 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=27.0' \
    'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    'platform=iOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
    'platform=watchOS Simulator,name=Apple Watch Series 11,OS=26.5' \
    'platform=iOS Simulator,name=iPhone 17'; do
    resolve "$dest"
    check "SD07 no available device matches -> exit 1, empty stdout, stderr names it: $dest" \
        is "$code [$out] $(grep -cF "$dest" <<<"$err")" "1 [] 1"
done
XCRUN_FAIL='list devices' resolve "$WATCH"
check "SD08 simctl failing fails the resolution" is "$code [$out]" "1 []"

# Unpairing: the fixture pairs the Series 11 (46mm) with iPhone 17 Pro Max (as the run's log shows),
# and iPhone 17 with an Ultra 3 (confirmed by the first run's session logs, which pair their clones).
unpairs() { grep '^simctl unpair' "$XCRUN_LOG" | tr '\n' ';'; }
: >"$XCRUN_LOG"
resolve "$WATCH"
check "SD09 the resolved watch leaves its pair (only that pair, not its 26.2 twin's)" \
    is "$code $(unpairs)" "0 simctl unpair 00000001-FA1E-4A1E-8A1E-000000000001;"
check "SD10 ... and simctl's chatter stays off stdout (stdout is the destination)" \
    is "$(wc -l <<<"$out" | tr -d ' ')" 1
: >"$XCRUN_LOG"
resolve "$IOS"
check "SD11 the resolved iPhone leaves its pair too" is "$code $(unpairs)" "0 simctl unpair 00000003-FA1E-4A1E-8A1E-000000000003;"
: >"$XCRUN_LOG"
resolve 'platform=iOS Simulator,id=841190F6-F927-4F0D-B152-62A06B4040CA'
check "SD12 an override by id is unpaired as well" is "$code $(unpairs)" "0 simctl unpair 00000001-FA1E-4A1E-8A1E-000000000001;"
jq '.pairs["00000009-FA1E-4A1E-8A1E-000000000009"] = {watch: {udid: "98D83340-55EC-4686-AE5E-5ABDF78767BF"},
    phone: {udid: "88931AEA-62E6-447F-8697-DCE00A671384"}, state: "(inactive, disconnected)"}' "$SIMCTL_JSON" >"$T/two.json"
: >"$XCRUN_LOG"
SIMCTL_JSON="$T/two.json" resolve "$IOS"
check "SD13 an iPhone in two pairs (one inactive) leaves both" \
    is "$code $(unpairs)" "0 simctl unpair 00000003-FA1E-4A1E-8A1E-000000000003;simctl unpair 00000009-FA1E-4A1E-8A1E-000000000009;"
: >"$XCRUN_LOG"
resolve 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm),OS=26.4'
check "SD14 an unpaired device unpairs nothing" is "$code $(unpairs)" "0 "
for sub in 'list pairs' unpair; do
    XCRUN_FAIL="$sub" resolve "$WATCH"
    check "SD15 a failing 'simctl $sub' fails the resolution" is "$code [$out]" "1 []"
done

finish
