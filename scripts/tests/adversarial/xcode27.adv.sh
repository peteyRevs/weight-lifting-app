#!/usr/bin/env bash
# F32 (Xcode 27 / Swift 6.4) adversarial cases, from the brief and docs/ci-cd.md; findings and repros in
# tasks/features/F32-xcode-27-migration/test-findings.md. The real check-xcode-version.sh runs against a
# stub xcodebuild, and once through Apple's /usr/bin shim with DEVELOPER_DIR. The real sim-destination.sh
# runs against variants of the xcode-27 fixture. The committed lockfiles, the workflows' cache key and
# Select step (run against the image's paths), and actionlint's label config are checked too.
# No network and no simulator, unless opted in:
#   ADV_REAL_SIMCTL=1  SD23 resolves check.sh's defaults on this Mac (simctl list only; unpair is faked)
#   ADV_COLD_PINS=1    PL02 resolves a stale lockfile from cold packages (network; ~650 MB under $TMPDIR)
set -uo pipefail
source "$(dirname "$0")/lib.sh"

T="$ADV_TMP"
WF="$ROOT/.github/workflows"

# ---- scripts/check-xcode-version.sh ------------------------------------------------------------
# It runs from a directory whose own .xcode-version says 26.6: only the repository's pin may count.
XV="$T/xv"
mkdir -p "$XV/repo/scripts" "$XV/bin" "$XV/elsewhere"
cp "${ADV_CHECK_XCODE:-$ROOT/scripts/check-xcode-version.sh}" "$XV/repo/scripts/check-xcode-version.sh" # override: mutants
echo 26.6 >"$XV/elsewhere/.xcode-version"
cat >"$XV/bin/xcodebuild" <<'SH'
#!/bin/sh
[ "$1" = -version ] || { echo "stub xcodebuild: unexpected $*" >&2; exit 64; }
printf 'Xcode %s\nBuild version %s\n' "$XCODE_REPORTS" "${XCODE_BUILD:-27A266a}"
exit "${XCODE_EXIT:-0}"
SH
chmod +x "$XV/bin/xcodebuild"
# xv <.xcode-version, a printf format, or MISSING> <version the stub reports> [VAR=value...]: sets $code, $out
xv() {
    local pin="$1" reported="$2"
    shift 2
    # shellcheck disable=SC2059 # the pin is a printf format on purpose ('27.0\n', '27.0')
    if [[ "$pin" == MISSING ]]; then rm -f "$XV/repo/.xcode-version"; else printf "$pin" >"$XV/repo/.xcode-version"; fi
    out="$(cd "$XV/elsewhere" && env PATH="$XV/bin:$PATH" XCODE_REPORTS="$reported" "$@" \
        "$XV/repo/scripts/check-xcode-version.sh" 2>&1)"
    code=$?
}
refused() { # exit 1, the message naming both versions, no ✓
    printf '%s %s %s' "$code" "$(grep -cF "pinned to Xcode $1 (.xcode-version)" <<<"$out")$(grep -cF "reports $2." <<<"$out")" \
        "$(grep -c '✓' <<<"$out")"
}

xv '27.0\n' 27.0
check "XV01 pinned 27.0 and xcodebuild says 27.0 -> exit 0 (run from a directory whose .xcode-version says 26.6)" \
    is "$code $out" "0 Xcode 27.0 ✓"
xv '27.0' 27.0
check "XV02 a pin without a trailing newline reads the same" is "$code" 0
xv '27.0\n' 27.0.1
check "XV03 pinned 27.0, Xcode 27.0.1 -> refused, naming both" is "$(refused 27.0 27.0.1)" "1 11 0"
xv '27.0.1\n' 27.0
check "XV04 pinned 27.0.1, Xcode 27.0 -> refused" is "$(refused 27.0.1 27.0)" "1 11 0"
xv '27.0.1\n' 27.0.1
check "XV05 pinned 27.0.1, Xcode 27.0.1 -> exit 0" is "$code" 0
for reported in 27.1 27 127.0 27.01 7.0 26.6; do
    xv '27.0\n' "$reported"
    check "XV06 pinned 27.0, Xcode $reported -> refused (no prefix, suffix or major-only match)" \
        is "$(refused 27.0 "$reported")" "1 11 0"
done
# F32 fix round (T4): a pin saved with a CRLF, or padded, reads as 27.0 here and in the CI Select steps (WF57).
xv '27.0\r\n' 27.0
crlf="$code $out"
xv ' 27.0 \r\n' 27.0
check "XV14 a pin with a CRLF, or padded with spaces, reads as 27.0 -> exit 0 (the Select steps agree: WF57)" \
    is "$crlf|$code $out" "0 Xcode 27.0 ✓|0 Xcode 27.0 ✓"
xv MISSING 27.0
check "XV07 no .xcode-version -> non-zero, naming the file, no ✓" \
    is "$([[ $code -ne 0 ]] && echo nonzero) $(grep -c 'xcode-version' <<<"$out") $(grep -c '✓' <<<"$out")" "nonzero 1 0"
xv '' 27.0
check "XV08 an empty .xcode-version -> refused" is "$code $(grep -c '✓' <<<"$out")" "1 0"
xv '27.0\n' 27.0 XCODE_EXIT=69
check "XV09 xcodebuild -version failing (exit 69) after printing 27.0 -> non-zero, no ✓ (pipefail)" \
    is "$([[ $code -ne 0 ]] && echo nonzero) $(grep -c '✓' <<<"$out")" "nonzero 0"
cat >"$XV/bin/xcodebuild-cltools" <<'SH'
#!/bin/sh
echo "xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance" >&2
exit 1
SH
chmod +x "$XV/bin/xcodebuild-cltools"
mkdir -p "$XV/cltools" && ln -sf "$XV/bin/xcodebuild-cltools" "$XV/cltools/xcodebuild"
printf '27.0\n' >"$XV/repo/.xcode-version"
out="$(cd "$XV/elsewhere" && PATH="$XV/cltools:$PATH" "$XV/repo/scripts/check-xcode-version.sh" 2>&1)"; code=$?
check "XV10 only the Command Line Tools selected -> non-zero, xcode-select's error shown, no ✓" \
    is "$([[ $code -ne 0 ]] && echo nonzero) $(grep -c 'command line tools instance' <<<"$out") $(grep -c '✓' <<<"$out")" \
    "nonzero 1 0"
# A PATH with bash and the script's own tools, and no xcodebuild.
mkdir -p "$XV/bare"
for tool in bash tr dirname awk cat; do ln -sf "$(command -v "$tool")" "$XV/bare/$tool"; done
out="$(cd "$XV/elsewhere" && PATH="$XV/bare" "$XV/repo/scripts/check-xcode-version.sh" 2>&1)"; code=$?
check "XV11 no xcodebuild on PATH -> non-zero, no ✓" \
    is "$([[ $code -ne 0 ]] && echo nonzero) $(grep -c '✓' <<<"$out")" "nonzero 0"
# Apple's /usr/bin/xcodebuild shim runs $DEVELOPER_DIR/usr/bin/xcrun xcodebuild: a developer directory
# that is another Xcode (here a fake 26.6) is what every later xcodebuild, xcrun and swift would use too.
if [[ -x /usr/bin/xcodebuild && "$(uname)" == Darwin ]]; then
    dev="$XV/Xcode_26.6.app/Contents/Developer"
    mkdir -p "$dev/usr/bin"
    # shellcheck disable=SC2016 # expanded by the stub, not here
    printf '#!/bin/sh\ntool="$1"; shift\nexec "$(dirname "$0")/$tool" "$@"\n' >"$dev/usr/bin/xcrun"
    printf '#!/bin/sh\nprintf "Xcode 26.6\\nBuild version 17F42\\n"\n' >"$dev/usr/bin/xcodebuild"
    chmod +x "$dev/usr/bin/xcrun" "$dev/usr/bin/xcodebuild"
    out="$(cd "$XV/elsewhere" && DEVELOPER_DIR="$dev" PATH="/usr/bin:/bin" "$XV/repo/scripts/check-xcode-version.sh" 2>&1)"
    code=$?
    check "XV12 DEVELOPER_DIR at another Xcode (26.6), through Apple's shim -> refused, naming 26.6" \
        is "$(refused 27.0 26.6)" "1 11 0"
    out="$(cd "$XV/elsewhere" && DEVELOPER_DIR=/nonexistent PATH="/usr/bin:/bin" "$XV/repo/scripts/check-xcode-version.sh" 2>&1)"
    code=$?
    check "XV13 DEVELOPER_DIR at a missing directory -> non-zero, no ✓" \
        is "$([[ $code -ne 0 ]] && echo nonzero) $(grep -c '✓' <<<"$out")" "nonzero 0"
else
    skip "XV12 DEVELOPER_DIR at another Xcode, through Apple's shim" "no /usr/bin/xcodebuild"
    skip "XV13 DEVELOPER_DIR at a missing directory" "no /usr/bin/xcodebuild"
fi

# ---- scripts/sim-destination.sh on the xcode-27 image, and its variants --------------------------
SD="$T/sd"
fake_simctl "$SD/bin"
RESOLVE="${ADV_SIM_DESTINATION:-$ROOT/scripts/sim-destination.sh}" # override: mutants
export XCRUN_LOG="$SD/xcrun.log"
resolve() { # <destination> [fixture]: sets $out and $code
    out="$(SIMCTL_JSON="${2:-$SIMCTL_JSON}" PATH="$SD/bin:$PATH" "$RESOLVE" "$1" 2>/dev/null)"
    code=$?
}
unpairs() { grep '^simctl unpair' "$XCRUN_LOG" | sed 's/^simctl unpair //' | tr '\n' ' '; }
IOS27='platform=iOS Simulator,name=iPhone 17,OS=27.0'
WATCH27='platform=watchOS Simulator,name=Apple Watch Series 12 (46mm),OS=27.0'
I=46F7C9EA-B38C-445A-BAD9-8A70A603E9E1 W=2416B270-8634-4D4A-9084-2B04B4498921 # the image's defaults
TWIN=17171717-2700-4000-8000-000000000017                                    # a second iPhone 17 on 27.0
# shellcheck disable=SC2016 # $twin is jq's, not the shell's
twin_json='{lastBootedAt: null, udid: $twin, isAvailable: true, deviceTypeIdentifier:
    "com.apple.CoreSimulator.SimDeviceType.iPhone-17", state: "Shutdown", name: "iPhone 17"}'
jq --arg twin "$TWIN" ".devices[\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\"] += [$twin_json]
    | .pairs[\"00002799-FA1E-4A1E-8A1E-000000002799\"] = {watch: {name: \"Apple Watch SE 3 (44mm)\",
      udid: \"F0B169D0-9CC9-40F6-A335-0F9240C09B9F\"}, phone: {name: \"iPhone 17\", udid: \$twin}, state: \"(active, disconnected)\"}" \
    "$SIMCTL_JSON" >"$SD/twin-after.json"
jq --arg twin "$TWIN" ".devices[\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\"] |= [$twin_json] + ." \
    "$SIMCTL_JSON" >"$SD/twin-first.json"

# This Mac has had two iPhone 17s on iOS 27.0 (Xcode made a second default set): exactly one, by UDID.
resolve "$IOS27" "$SD/twin-after.json"; after="$code $out"
resolve "$IOS27" "$SD/twin-after.json"; again="$code $out"
resolve "$IOS27" "$SD/twin-first.json"; first="$code $out"
check "SD19 two available iPhone 17s on iOS 27.0 -> one destination, the first simctl lists, the same on every call" \
    is "$after|$again|$first" "0 platform=iOS Simulator,id=$I|0 platform=iOS Simulator,id=$I|0 platform=iOS Simulator,id=$TWIN"
: >"$XCRUN_LOG"
resolve "$IOS27" "$SD/twin-after.json"
check "SD20 ... and only the chosen twin leaves its pair (the other's pair with an SE 3 stays)" \
    is "$code $(unpairs)" "0 00002703-FA1E-4A1E-8A1E-000000002703 "
: >"$XCRUN_LOG"
resolve 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0'
check "SD21 an override on the image (Series 12 (42mm)) resolves by UDID and leaves its pair with the iPhone Air" \
    is "$code $out $(unpairs)" \
    "0 platform=watchOS Simulator,id=3A3B91C1-A67A-4F4E-9C2A-5DA1567C2D5F 00002702-FA1E-4A1E-8A1E-000000002702 "

# The image's pairs are unknown (lib.sh). If Xcode pairs the two defaults with each other, check.sh
# resolves the iPhone (unpairing them), then the watch: a stateful simctl, where unpairing a pair that
# is gone fails as the real one does, shows the second lookup sees the pair gone.
mkdir -p "$SD/stateful"
cat >"$SD/stateful/xcrun" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$XCRUN_LOG"
case "$1 $2 $3" in
    "simctl list pairs") jq '{pairs}' "$STATE" ;;
    "simctl list devices") jq '{devices: (.devices | map_values(map(select(.isAvailable))))}' "$STATE" ;;
    "simctl unpair "*)
        jq -e --arg p "$3" '.pairs | has($p)' "$STATE" >/dev/null || { echo "Invalid device pair: $3" >&2; exit 148; }
        jq --arg p "$3" 'del(.pairs[$p])' "$STATE" >"$STATE.new" && mv "$STATE.new" "$STATE" ;;
    *) echo "fake xcrun: unexpected: $*" >&2; exit 64 ;;
esac
SH
chmod +x "$SD/stateful/xcrun"
jq --arg i "$I" --arg w "$W" '.pairs = {"000027AA-FA1E-4A1E-8A1E-0000000027AA": {watch: {name: "Apple Watch Series 12 (46mm)",
    udid: $w}, phone: {name: "iPhone 17", udid: $i}, state: "(active, disconnected)"}}' "$SIMCTL_JSON" >"$SD/state.json"
: >"$XCRUN_LOG"
ios="$(STATE="$SD/state.json" PATH="$SD/stateful:$PATH" "$RESOLVE" "$IOS27" 2>/dev/null)"; ios_code=$?
watch="$(STATE="$SD/state.json" PATH="$SD/stateful:$PATH" "$RESOLVE" "$WATCH27" 2>/dev/null)"; watch_code=$?
check "SD22 the two defaults paired with each other: iPhone then watch resolve, and the pair is left once" \
    is "$ios_code $ios|$watch_code $watch|$(unpairs)" \
    "0 platform=iOS Simulator,id=$I|0 platform=watchOS Simulator,id=$W|000027AA-FA1E-4A1E-8A1E-0000000027AA "

# check.sh's defaults against this Mac's own simulators: simctl list is real, unpair only logged.
if [[ "${ADV_REAL_SIMCTL:-}" == 1 ]]; then
    mkdir -p "$SD/real"
    cat >"$SD/real/xcrun" <<'SH'
#!/bin/sh
case "$1 $2" in
    "simctl list") exec /usr/bin/xcrun "$@" ;;
    "simctl unpair") printf '%s\n' "$*" >>"$XCRUN_LOG"; exit 0 ;;
esac
echo "read-only xcrun: refused: $*" >&2
exit 64
SH
    chmod +x "$SD/real/xcrun"
    /usr/bin/xcrun simctl list devices available --json >"$SD/real.json"
    for var in IOS_DEST WATCH_DEST; do
        dest="$(sed -nE "s/^$var=\"\\\$\{LEDGER_${var}:-(.*)\}\"$/\1/p" "$ROOT/scripts/check.sh")"
        name="$(sed -E 's/.*name=([^,]*).*/\1/' <<<"$dest")"
        runtime="com.apple.CoreSimulator.SimRuntime.$(sed -E 's/.*platform=([A-Za-z]+) Simulator.*OS=([0-9.]+).*/\1-\2/' <<<"$dest" | tr . -)"
        : >"$XCRUN_LOG"
        out="$(PATH="$SD/real:$PATH" "$RESOLVE" "$dest" 2>/dev/null)"; code=$?
        udid="${out##*id=}"
        named="$(jq -r --arg r "$runtime" --arg u "$udid" '.devices[$r][]? | select(.udid == $u) | .name' "$SD/real.json")"
        check "SD23 this Mac: check.sh's $var ($dest) resolves to one available $name, by UDID" \
            is "$code $(wc -l <<<"$out" | tr -d ' ') $named" "0 1 $name"
    done
else
    skip "SD23 check.sh's defaults resolve on this Mac" "set ADV_REAL_SIMCTL=1"
fi

# ---- package pins --------------------------------------------------------------------------------
# [T1] Only the project's lockfile is proven in CI (cold, with -onlyUsePackageVersionsFromResolvedFile).
# LedgerKit/Package.resolved is read only by check.sh --fast, locally and warm. The two describe one
# graph (the app targets have no package of their own), so they must pin the same packages.
PROJECT_RESOLVED="$ROOT/Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
pins() { jq -S '[.pins[] | {identity, kind, location, state}] | sort_by(.identity)' "$1"; }
pins "$ROOT/LedgerKit/Package.resolved" >"$T/pins-ledgerkit.json"
pins "$PROJECT_RESOLVED" >"$T/pins-project.json"
check "PL01 [T1] LedgerKit/Package.resolved pins exactly what the project's (CI-proven) Package.resolved pins" \
    diff "$T/pins-project.json" "$T/pins-ledgerkit.json"

# [T1, fix round] check.sh step 2 now enforces PL01 on every run that lints (--lint-only and the full gate,
# locally and on CI: W02, W04, W48) with scripts/check-package-pins.sh. It runs here on copies of the lockfiles.
PP="$T/pins"
PROJECT_REL="Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$PP/repo/scripts" "$PP/repo/LedgerKit" "$PP/repo/$(dirname "$PROJECT_REL")" "$PP/files"
cp "${ADV_CHECK_PINS:-$ROOT/scripts/check-package-pins.sh}" "$PP/repo/scripts/check-package-pins.sh" # override: mutants
place() { if [[ "$1" == MISSING ]]; then rm -f "$2"; else cp "$1" "$2"; fi; }
pinscheck() { # <LedgerKit's lockfile> <the project's lockfile>, either may be MISSING: sets $code, $out
    place "$1" "$PP/repo/LedgerKit/Package.resolved"
    place "$2" "$PP/repo/$PROJECT_REL"
    out="$(cd "$T" && "$PP/repo/scripts/check-package-pins.sh" 2>&1)"
    code=$?
}
committed="$ROOT/LedgerKit/Package.resolved"
edit() { jq "$2" "$committed" >"$PP/files/$1.resolved" && echo "$PP/files/$1.resolved"; } # <name> <jq filter>

pinscheck "$committed" "$PROJECT_RESOLVED"
check "PL03 the committed lockfiles agree -> exit 0 (run from another directory)" \
    is "$code $(grep -c '^package pins agree' <<<"$out")" "0 1"
# The regression itself: main's LedgerKit/Package.resolved before F32, which Swift 6.3 wrote
# (xctest-dynamic-overlay 1.13.1 where 6.4 pins swift-issue-reporting 2.1.1). check.sh needs full history.
PRE_F32=e94b50131be8fc8042caa7314c998122862eb8fd
if git -C "$ROOT" show "$PRE_F32:LedgerKit/Package.resolved" >"$PP/files/swift63.resolved" 2>/dev/null; then
    pinscheck "$PP/files/swift63.resolved" "$PROJECT_RESOLVED"
    check "PL04 [T1] a stale LedgerKit lockfile (main's before F32) -> exit 1, the diff naming both pins, and the fix" \
        is "$code $(grep -c '^-{.*"identity":"swift-issue-reporting"' <<<"$out") \
$(grep -c '^+{.*"identity":"xctest-dynamic-overlay"' <<<"$out") $(grep -c 'swift package --package-path LedgerKit resolve' <<<"$out")" \
        "1 1 1 1"
    pinscheck "$committed" "$PP/files/swift63.resolved"
    check "PL05 ... and a stale project lockfile against a current LedgerKit one -> exit 1" is "$code" 1
else
    fail "PL04 a stale LedgerKit lockfile fails" "no $PRE_F32 here: check.sh needs full history (fetch-depth: 0)"
fi
# Any one pin that differs fails, whichever file holds it. The project's may not hold a package LedgerKit's
# graph lacks either (an app-level package: engineering-standards §1).
grdb='.pins[] | select(.identity == "grdb.swift")'
for mutant in \
    "revision:($grdb | .state.revision) = \"0000000000000000000000000000000000000000\"" \
    "version:($grdb | .state.version) = \"7.11.0\"" \
    "location:($grdb | .location) = \"https://github.com/someone/grdb.swift\"" \
    "kind:($grdb | .kind) = \"localSourceControl\"" \
    "branch:($grdb | .state) += {branch: \"master\"}" \
    "one-pin-short:.pins |= .[1:]" \
    "extra-pin:.pins += [{identity: \"swift-case-paths\", kind: \"remoteSourceControl\",
        location: \"https://github.com/pointfreeco/swift-case-paths\",
        state: {revision: \"1111111111111111111111111111111111111111\", version: \"1.7.2\"}}]"; do
    mutated="$(edit "${mutant%%:*}" "${mutant#*:}")" || { fail "PL06 (${mutant%%:*})" "jq could not apply it"; continue; }
    pinscheck "$mutated" "$PROJECT_RESOLVED"; ledgerkit_side="$code"
    pinscheck "$committed" "$mutated"; project_side="$code"
    check "PL06 one pin differs (${mutant%%:*}), in LedgerKit's lockfile or in the project's -> exit 1 both ways" \
        is "$ledgerkit_side $project_side" "1 1"
done
# SwiftPM writes an originHash per root manifest (Xcode 26.6 wrote two over equal pins); order and layout
# are not pins either.
reshaped="$(edit reshaped '.originHash = "20eb7c62c8798f501f39bee916360b8758851e803db14d7500540cbf164a0a8d"
    | .pins |= (reverse | map(to_entries | reverse | from_entries))')"
jq -c . "$PROJECT_RESOLVED" >"$PP/files/compact.resolved"
pinscheck "$reshaped" "$PP/files/compact.resolved"
check "PL07 another originHash, pins and keys in another order, compact JSON -> still agree, exit 0" is "$code" 0
printf '{"pins": [' >"$PP/files/truncated.resolved"
echo '{"originHash": "x", "version": 3}' >"$PP/files/no-pins.resolved"
unreadable=""
tally() { unreadable="$unreadable$([[ $code -ne 0 ]] && echo nonzero || echo 0)$(grep -c '^package pins agree' <<<"$out") "; }
pinscheck MISSING "$PROJECT_RESOLVED"; tally
pinscheck "$committed" MISSING; tally
pinscheck MISSING MISSING; tally
pinscheck "$PP/files/no-pins.resolved" "$PP/files/no-pins.resolved"; tally
pinscheck "$PP/files/truncated.resolved" "$PROJECT_RESOLVED"; tally
check "PL08 a missing lockfile (either or both), neither with pins, or truncated JSON -> non-zero, never 'agree'" \
    is "$unreadable" "nonzero0 nonzero0 nonzero0 nonzero0 nonzero0 "

# A stale lockfile fails from cold packages. Opt-in: it clones every package (the local SwiftPM cache helps).
if [[ "${ADV_COLD_PINS:-}" == 1 ]]; then
    CP="$T/cold"
    mkdir -p "$CP"
    rsync -a --exclude .derivedData --exclude .build --exclude .swiftpm --exclude .git "$ROOT/" "$CP/repo/"
    P="Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    jq '.pins |= .[1:]' "$PROJECT_RESOLVED" >"$CP/stale.resolved" # one pin short: out of date
    xresolve() { # <SourcePackages dir> [flag]: exit code, whether it says so, whether it rewrote the file
        cp "$CP/stale.resolved" "$CP/repo/$P"
        local status=0
        (cd "$CP/repo" && xcodebuild -resolvePackageDependencies -project Ledger.xcodeproj -scheme Ledger \
            -derivedDataPath "$CP/dd" -clonedSourcePackagesDirPath "$CP/$1" ${2:+"$2"}) >"$CP/log" 2>&1 || status=$?
        printf '%s %s %s' "$([[ $status -ne 0 ]] && echo failed || echo passed)" \
            "$(grep -q 'out-of-date resolved file' "$CP/log" && echo says-so || echo silent)" "$(cmp -s "$CP/stale.resolved" "$CP/repo/$P" && echo kept || echo rewritten)"
    }
    pinned="$(xresolve cold-pinned -onlyUsePackageVersionsFromResolvedFile)"
    unpinned="$(xresolve cold-unpinned)"
    check "PL02 a stale project lockfile, cold: with check.sh's flag xcodebuild fails and keeps it; without, it rewrites it" \
        is "$pinned | $unpinned" "failed says-so kept | passed silent rewritten"
    rm -rf "$CP"
else
    skip "PL02 a stale lockfile fails from cold packages" "set ADV_COLD_PINS=1 (network)"
fi

# ---- workflows ---------------------------------------------------------------------------------------
if ! command -v ruby >/dev/null || ! ruby -ryaml -rjson -e '' 2>/dev/null; then
    fail "workflow cases" "no ruby with yaml/json (macOS and the runner both ship one)"
    finish
    exit
fi
json() { ruby -ryaml -rjson -e 'y = YAML.load_file(ARGV[0]); y["on"] = y.delete(true) if y.key?(true); puts JSON.generate(y)' "$1"; }
for w in "$WF"/*.yml; do json "$w" >"$T/$(basename "$w" .yml).json"; done

# Every Mac job runs on the xcode-27 image, including any a later change adds.
jobs="$(for w in "$WF"/*.yml; do
    jq -r --arg w "$(basename "$w")" '.jobs | to_entries[] | "\($w):\(.key)=\(.value."runs-on" | tostring)"' "$T/$(basename "$w" .yml).json"
done)"
check "WF54 every job in every workflow runs on ubuntu-* or on xcode-27 (Check, and the nightly's tests and dependency report)" \
    is "$(grep -vE '=(ubuntu-[a-z0-9.-]+|xcode-27)$' <<<"$jobs" | tr '\n' ' ')|$(grep -c '=xcode-27$' <<<"$jobs")" "|3"

# The package cache: its key must change with the Xcode and with either lockfile, and name only live files.
key="$(jq -r '.jobs[].steps[] | select(.uses // "" | test("actions/cache")) | .with.key' "$T/pr.json")"
patterns="$(grep -o "hashFiles([^)]*)" <<<"$key" | grep -o "'[^']*'" | tr -d "'")"
tracked="$(git -C "$ROOT" ls-files)"
covered="" dead=""
for f in .xcode-version LedgerKit/Package.resolved Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; do
    hit=no
    # shellcheck disable=SC2053 # $p is a hashFiles pattern: glob matching is the point
    while IFS= read -r p; do [[ -n "$p" && "$f" == $p ]] && hit=yes; done <<<"$patterns"
    covered="$covered$f=$hit "
done
while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    live=no
    # shellcheck disable=SC2053 # as above
    while IFS= read -r t; do [[ "$t" == $p ]] && { live=yes; break; }; done <<<"$tracked"
    [[ $live == yes ]] || dead="$dead$p "
done <<<"$patterns"
check "WF55 the package cache key hashes .xcode-version and both lockfiles, and no pattern that matches nothing" \
    is "$covered|$dead" ".xcode-version=yes LedgerKit/Package.resolved=yes Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved=yes |"

# In a Mac job, nothing may build, test or resolve before Xcode is selected.
order="$(for w in pr nightly; do
    jq -r '.jobs | to_entries[] | select(.value."runs-on" | startswith("ubuntu") | not) | .key as $job
        | [.value.steps | to_entries[] | select(.value.run // "" | test("xcode-select -s")) | .key] as $sel
        | [.value.steps | to_entries[] | select((.value.run // "" | test("xcodebuild|swift |scripts/"))
            and (.value.run | test("xcode-select -s") | not)) | .key] as $uses
        | "\($job):\(if ($sel | length) == 1 and ($uses | length) > 0 and $sel[0] < ($uses | min) then "ok" else "sel=\($sel) uses=\($uses)" end)"' \
        "$T/$w.json"
done | tr '\n' ' ')"
check "WF56 each Mac job selects Xcode once, before any step that runs xcodebuild, swift or a script" \
    is "$order" "check:ok test:ok dependencies:ok "

# Each Select step, run as the runner runs it, with the committed .xcode-version, must pick a path the
# xcode-27 image has (its README: Xcode 27.0 at /Applications/Xcode_27.app, linked as Xcode_27.0.app).
SEL="$T/select"
mkdir -p "$SEL/bin" "$SEL/repo"
cp "$ROOT/.xcode-version" "$SEL/repo/.xcode-version"
printf '#!/bin/sh\nexec "$@"\n' >"$SEL/bin/sudo"
cat >"$SEL/bin/xcode-select" <<'SH'
#!/bin/sh
[ "$1" = -s ] || exit 64
case "$2" in
    /Applications/Xcode_27.app | /Applications/Xcode_27.0.app) printf '%s\n' "$2" >>"$SELECTED"; exit 0 ;;
esac
echo "xcode-select: error: invalid developer directory '$2'" >&2
exit 1
SH
printf '#!/bin/sh\nprintf "Xcode 27.0\\nBuild version 27A266a\\n"\n' >"$SEL/bin/xcodebuild"
chmod +x "$SEL/bin/sudo" "$SEL/bin/xcode-select" "$SEL/bin/xcodebuild"
export SELECTED="$SEL/selected"
select_steps() { # runs every Mac job's Select step against $SEL/repo/.xcode-version: "ok|failed ...", then the paths
    : >"$SELECTED"
    local w step ran=""
    for w in pr nightly; do
        while IFS= read -r step; do
            [[ -z "$step" ]] && continue
            (cd "$SEL/repo" && PATH="$SEL/bin:$PATH" bash -eo pipefail -c "$(jq -r '.' <<<"$step")") >/dev/null 2>&1 &&
                ran="${ran}ok " || ran="${ran}failed "
        done < <(jq -c '.jobs[] | select(."runs-on" | startswith("ubuntu") | not) | .steps[] | select(.run // "" | test("xcode-select -s")) | .run' \
            "$T/$w.json")
    done
    printf '%s%s' "$ran" "$(sort -u "$SELECTED" | tr '\n' ' ')"
}
check "WF57 every Select step, run with the committed pin, selects an Xcode the xcode-27 image has" \
    is "$(select_steps)" "ok ok ok /Applications/Xcode_27.0.app "
# F32 fix round (T4): a pin saved with a CRLF, or padded, reads as check-xcode-version.sh reads it (XV14).
printf '27.0\r\n' >"$SEL/repo/.xcode-version"
crlf="$(select_steps)"
printf ' 27.0 \r\n' >"$SEL/repo/.xcode-version"
check "WF57 ... and with a CRLF, or padded with spaces, the same Xcode (no Xcode_27.0\\r.app)" \
    is "$crlf|$(select_steps)" "ok ok ok /Applications/Xcode_27.0.app |ok ok ok /Applications/Xcode_27.0.app "
cp "$ROOT/.xcode-version" "$SEL/repo/.xcode-version"

# F32 fix round (T5): every Mac job checks the selected Xcode against the pin before it builds: the nightly's
# jobs in the run step right after Select, and Check by running check.sh, whose step 0 is that check in every
# mode, --ios-only included (W40).
checked="$(for w in pr nightly; do
    jq -r '.jobs | to_entries[] | select(.value."runs-on" | startswith("ubuntu") | not) | .key as $job
        | [.value.steps[] | select(.run) | .run] as $runs
        | ($runs | map(test("xcode-select -s")) | index(true)) as $sel
        | "\($job):\($runs[$sel + 1] // "none" | if test("^scripts/check-xcode-version\\.sh$|^scripts/check\\.sh( --[a-z-]+)*$")
            then "checked" else "unchecked" end)"' \
        "$T/$w.json"
done | tr '\n' ' ')"
check "WF60 each Mac job's next run step after Select checks the Xcode against .xcode-version (the nightly too)" \
    is "$checked" "check:checked test:checked dependencies:checked "

# actionlint: the config only teaches it the preview label; a mistyped label still fails.
check "WF58 .github/actionlint.yaml declares the xcode-27 label and nothing else" \
    is "$(ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$ROOT/.github/actionlint.yaml")" \
    '{"self-hosted-runner":{"labels":["xcode-27"]}}'
al="$(cd "$ROOT" && mise which actionlint 2>/dev/null || true)"
if [[ -x "$al" ]]; then
    AL="$T/actionlint"
    mkdir -p "$AL/.github/workflows" && git -C "$AL" init -q
    cp "$WF"/*.yml "$AL/.github/workflows/"
    bare="$(cd "$AL" && "$al" -no-color -shellcheck= .github/workflows/*.yml 2>&1)"; bare_code=$?
    cp "$ROOT/.github/actionlint.yaml" "$AL/.github/actionlint.yaml"
    for w in "$AL"/.github/workflows/*.yml; do sed -i.bak -E 's/runs-on: xcode-27( |$)/runs-on: xcode-72\1/' "$w" && rm -f "$w.bak"; done
    typo="$(cd "$AL" && "$al" -no-color -shellcheck= .github/workflows/*.yml 2>&1)"; typo_code=$?
    check "WF58 ... without it actionlint rejects xcode-27; with it, a mistyped label (xcode-72) is still rejected" \
        is "$bare_code $([[ $(grep -c 'label "xcode-27" is unknown' <<<"$bare") -ge 1 ]] && echo named) $typo_code \
$([[ $(grep -c 'label "xcode-72" is unknown' <<<"$typo") -ge 1 ]] && echo named)" "1 named 1 named"
else
    skip "WF58 actionlint without the config, and with a mistyped label" "actionlint missing (WF01 fails too); run: mise install"
fi

finish
