#!/usr/bin/env bash
# #153's two CI scripts around the compilation cache, against build logs and process tables that lie:
#   scripts/ci-cache-report.sh  reports the hit rate and ValidateCAS's outcome, and never fails the job;
#   scripts/ci-cas-idle.sh      waits, bounded, for the cache's writers by exact name, and says idle=true
#                               only when none is left (the save step reads it), never killing anything;
# and #161's scripts/ci-cas-validate.sh, which validates a restored cache in-process before the build, and
# never fails the job. xcrun (xcresulttool get log, --find), llvm-cas and pgrep are faked, so this runs anywhere.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

REPORT="$ROOT/scripts/ci-cache-report.sh"
IDLE="$ROOT/scripts/ci-cas-idle.sh"
T="$ADV_TMP"
mkdir -p "$T/bin"

# Fake xcrun: `xcresulttool get log --type build --compact --path <bundle>` prints <bundle>/log.json; a bundle
# without one fails as xcresulttool does for a test bundle ("No build log available").
# `xcrun --find llvm-cas` prints $FAKE_LLVM_CAS, or fails as xcrun does when that is empty.
cat >"$T/bin/xcrun" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${XCRUN_LOG:-/dev/null}"
if [ "$1" = --find ]; then
    [ -n "${FAKE_LLVM_CAS:-}" ] || { echo "xcrun: error: unable to find utility \"$2\", not a developer tool or in PATH" >&2; exit 72; }
    echo "$FAKE_LLVM_CAS"; exit 0
fi
while [ $# -gt 0 ]; do [ "$1" = --path ] && { bundle="$2"; break; }; shift; done
[ -f "$bundle/log.json" ] || { echo "Error: No build log available" >&2; exit 1; }
cat "$bundle/log.json"
SH
# Fake pgrep: `pgrep -x <name>` matches $FAKE_RUNNING's names exactly, anything else by substring, as pgrep
# does. FAKE_RUNNING_FOR=<n> keeps them running for the first n calls only; FAKE_PGREP_STATUS forces an exit.
cat >"$T/bin/pgrep" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${PGREP_LOG:-/dev/null}"
[ -z "${FAKE_PGREP_STATUS:-}" ] || exit "$FAKE_PGREP_STATUS"
if [ -n "${FAKE_RUNNING_FOR:-}" ]; then
    n=$(($(cat "$PGREP_COUNT" 2>/dev/null || echo 0) + 1)); echo "$n" >"$PGREP_COUNT"
    [ "$n" -le "$FAKE_RUNNING_FOR" ] || exit 1
fi
exact=no; [ "$1" = -x ] && { exact=yes; shift; }
for name in ${FAKE_RUNNING:-}; do
    if [ $exact = yes ]; then [ "$name" = "$1" ] && exit 0; else case "$name" in *"$1"*) exit 0 ;; esac; fi
done
exit 1
SH
chmod +x "$T/bin/xcrun" "$T/bin/pgrep"
export PATH="$T/bin:$PATH" XCRUN_LOG="$T/xcrun.log" PGREP_LOG="$T/pgrep.log" PGREP_COUNT="$T/pgrep.count"
unset GITHUB_ACTIONS GITHUB_OUTPUT

# section <commandDetails> <emittedOutput> [duration]: one build-log section that ran a command.
section() {
    jq -cn --arg c "$1" --arg o "$2" --argjson d "${3:-0.01}" '{title: $c, duration: $d, result: "succeeded",
        commandInvocationDetails: {commandDetails: $c, emittedOutput: $o, exitCode: 0}, messages: [], subsections: []}'
}
# bundle <name> <section json>...: a build bundle whose log nests the sections as xcresulttool prints them
# (#153's runs: ValidateCAS at subsections[8], the metrics at [2710]), the last one a level deeper.
bundle() {
    local dir="$T/$1"; shift
    mkdir -p "$dir"
    printf '%s\n' "$@" | jq -s '{domainType: "Xcode.IDEActivityLogDomainType.BuildLog", title: "Build", duration: 1215.4,
        subsections: ((.[:-1] // []) + (if length > 0 then [{title: "Target", subsections: [.[-1]]}] else [] end))}' \
        >"$dir/log.json"
}
report() { out="$("$REPORT" "$@" 2>&1)"; code=$?; }

validate_cmd="ValidateCAS /Users/runner/work/r/r/.derivedData/CompilationCache.noindex/builtin /Applications/Xcode_27.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cas"
# ---- ci-cache-report.sh -------------------------------------------------------------------------------------
bundle cold.xcresult "$(section "$validate_cmd" $'recovered from invalid data\n' 150.26)" \
    "$(section CompilationCacheMetrics $'note: 0 hits / 765 cacheable tasks (0%)\n')"
report "$T/cold.xcresult"
expect_exit "C01 #153's cold build: reported, and exit 0" 0 "$code" "$out"
check "C01b ... the hit rate and ValidateCAS's outcome with its time, one line each" \
    is "$out" "compilation cache: 0 hits / 765 cacheable tasks (0%)
compilation cache: ValidateCAS: recovered from invalid data, 150 s
compilation cache: warning: ValidateCAS recovered after 150 s, at or past the 120 s llvm-cas gives its out-of-process check: a timeout, not a corrupt cache, yet the cache was dropped (#161)"
check "C01c ... read as the build log, compact, from the bundle named" \
    is "$(tail -1 "$T/xcrun.log")" "xcresulttool get log --type build --compact --path $T/cold.xcresult"

bundle warm.xcresult "$(section CompilationCacheMetrics $'note: 741 hits / 765 cacheable tasks (97%)\n')" \
    "$(section "$validate_cmd" $'validated successfully\n' 31.9)"
GITHUB_ACTIONS=true report "$T/warm.xcresult"
check "C02 on GitHub Actions each line is a notice annotation, whatever order the log holds them in" \
    is "$out" "::notice title=Compilation cache::741 hits / 765 cacheable tasks (97%)
::notice title=Compilation cache::ValidateCAS: validated successfully, 31 s"

bundle bare.xcresult "$(section "CompileSwift normal arm64 A.swift" 'note: 5 hits / 9 cacheable tasks (55%) ValidateCAS')"
report "$T/bare.xcresult"
check "C03 a log with neither section says so, and another task's output naming them is not taken for them" \
    is "$code|$out" "0|compilation cache: no hit rate in the build log (caching off, or the build stopped before its end)
compilation cache: ValidateCAS did not run (no cache restored, or this boot already validated it)"

bundle quiet.xcresult "$(section "$validate_cmd" '')"
report "$T/quiet.xcresult"
check "C04 a ValidateCAS without output is named as such" grep -qx 'compilation cache: ValidateCAS: no output, 0 s' <<<"$out"

mkdir -p "$T/test.xcresult"
report "$T/test.xcresult"
expect_exit "C05 a bundle without a build log (xcresulttool fails): exit 0" 0 "$code" "$out"
check "C05b ... with a warning that quotes xcresulttool" \
    grep -qx "compilation cache: warning: xcresulttool could not read the build log in $T/test.xcresult: Error: No build log available" <<<"$out"

mkdir -p "$T/torn.xcresult" && printf '{"subsections": [' >"$T/torn.xcresult/log.json"
GITHUB_ACTIONS=true report "$T/torn.xcresult"
check "C06 a log that is not JSON: exit 0 and a warning annotation" \
    is "$code|${out%%: *}" "0|::warning title=Compilation cache::the build log in $T/torn.xcresult is not the JSON expected"

report "$T/never-built.xcresult"
check "C07 no bundle at the path (the build never started): exit 0, a warning, xcresulttool not run" \
    is "$code|$out|$(grep -c never-built "$T/xcrun.log")" \
    "0|compilation cache: warning: no build result bundle at $T/never-built.xcresult (did the build start?)|0"
report
check "C08 no argument: exit 0 and a warning" is "$code|$out" "0|compilation cache: warning: no build result bundle named"

mkdir -p "$T/a cache/builtin" && head -c 300000 /dev/zero >"$T/a cache/builtin/data"
bundle "with space.xcresult" "$(section CompilationCacheMetrics 'note: 1 hits / 2 cacheable tasks (50%)')"
report "$T/with space.xcresult" "$T/a cache"
check "C09 paths with spaces, and the cache directory's size as du gives it" \
    is "$(sed -n 1p <<<"$out")|$(sed -n 3p <<<"$out" | sed -E 's/^compilation cache: [0-9.]+[BKMGT]? in /SIZE in /')" \
    "compilation cache: 1 hits / 2 cacheable tasks (50%)|SIZE in $T/a cache"
report "$T/cold.xcresult" "$T/no-cache"
check "C09b ... and a missing cache directory is named, still exit 0" \
    is "$code|$(tail -1 <<<"$out")" "0|compilation cache: no cache directory at $T/no-cache"

# #161: a recovery at llvm-cas's 120 s cap is a timeout; one well under it is real invalid data.
for case in "114.99 0" "115 1" "119.6 1"; do
    bundle "t$case.xcresult" "$(section "$validate_cmd" $'recovered from invalid data\n' "${case% *}")"
    GITHUB_ACTIONS=true report "$T/t$case.xcresult"
    check "C10 a recovery after ${case% *} s: ${case#* } timeout warning(s), exit 0" \
        is "$code|$(grep -c '^::warning title=Compilation cache::ValidateCAS recovered after .* (#161)$' <<<"$out")" "0|${case#* }"
done
bundle "skipped.xcresult" "$(section "$validate_cmd" $'validation skipped\n' 130)"
report "$T/skipped.xcresult"
check "C10b ... and a slow ValidateCAS that recovered nothing warns of nothing" is "$(grep -c warning <<<"$out")" 0

# ---- ci-cas-validate.sh -------------------------------------------------------------------------------------
# Fake llvm-cas: logs its arguments, prints $FAKE_CAS_OUT and exits $FAKE_CAS_STATUS (default 0).
VALIDATE="$ROOT/scripts/ci-cas-validate.sh"
cat >"$T/bin/llvm-cas" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${CAS_LOG:-/dev/null}"
[ -z "${FAKE_CAS_OUT:-}" ] || printf '%s\n' "$FAKE_CAS_OUT"
exit "${FAKE_CAS_STATUS:-0}"
SH
chmod +x "$T/bin/llvm-cas"
export CAS_LOG="$T/cas.log"
mkdir -p "$T/restored/builtin"
validate() { : >"$CAS_LOG"; out="$(FAKE_LLVM_CAS="${FAKE_LLVM_CAS-$T/bin/llvm-cas}" "$VALIDATE" "$@" 2>&1)"; code=$?; }

FAKE_CAS_OUT="validated successfully" GITHUB_ACTIONS=true validate "$T/restored/builtin"
check "V01 validated: a notice with the outcome and its time, exit 0" \
    is "$code|$out" "0|::notice title=Compilation cache::pre-validation: validated successfully, 0 s"
check "V01b ... running llvm-cas in-process, on the CAS named, with Xcode's own flags" \
    is "$(cat "$CAS_LOG")" "--cas $T/restored/builtin --validate-if-needed --check-hash --allow-recovery --in-process"
FAKE_CAS_OUT="validation skipped" validate "$T/restored/builtin"
check "V02 skipped (already validated this boot): a notice, exit 0" \
    is "$code|$out" "0|compilation cache: pre-validation: validation skipped, 0 s"
FAKE_CAS_OUT="recovered from invalid data" GITHUB_ACTIONS=true validate "$T/restored/builtin"
check "V03 recovered: a warning that the cache was dropped and the build is cold, exit 0" \
    is "$code|$out" "0|::warning title=Compilation cache::pre-validation: recovered from invalid data, 0 s: the restored cache was invalid and is dropped, so this build is cold"
validate "$T/never-restored/builtin"
check "V04 no cache directory: says so, exit 0, and never runs llvm-cas (it would create one)" \
    is "$code|$out|$(wc -l <"$CAS_LOG" | tr -d ' ')|$([[ -e "$T/never-restored" ]] && echo created)" \
    "0|compilation cache: no compilation cache at $T/never-restored/builtin, nothing to validate|0|"
FAKE_CAS_OUT="llvm-cas: validate-if-needed: bad data for digest 'AB': data record span passed the end of the data pool" \
    FAKE_CAS_STATUS=1 GITHUB_ACTIONS=true validate "$T/restored/builtin"
check "V05 llvm-cas failing: a warning quoting it, exit 0" \
    is "$code|$out" "0|::warning title=Compilation cache::llvm-cas could not validate $T/restored/builtin (exit 1, 0 s): llvm-cas: validate-if-needed: bad data for digest 'AB': data record span passed the end of the data pool; Xcode validates it itself"
FAKE_LLVM_CAS="" validate "$T/restored/builtin"
check "V06 no llvm-cas in the Xcode: a warning, exit 0" \
    is "$code|${out%%(*}|$(wc -l <"$CAS_LOG" | tr -d ' ')" "0|compilation cache: warning: no llvm-cas in the selected Xcode |0"
mkdir -p "$T/cwd/.derivedData/CompilationCache.noindex/builtin"
: >"$CAS_LOG" && (cd "$T/cwd" && FAKE_LLVM_CAS="$T/bin/llvm-cas" FAKE_CAS_OUT="validated successfully" "$VALIDATE" >/dev/null)
check "V07 no argument: the CAS check.sh's builds use, under .derivedData" \
    is "$(cut -d' ' -f1-2 "$CAS_LOG")" "--cas .derivedData/CompilationCache.noindex/builtin"

# ---- ci-cas-idle.sh --------------------------------------------------------------------------------------------
# idle [<seconds>]: runs it, stopped (exit 143) by a 20 s watchdog should a wait ever be unbounded.
idle() {
    local pid dog
    : >"$PGREP_LOG" && rm -f "$PGREP_COUNT" && : >"$T/out" && started=$SECONDS
    GITHUB_OUTPUT="$T/out" "$IDLE" "$@" >"$T/idle.log" 2>&1 &
    pid=$!
    (sleep 20 && kill "$pid") 2>/dev/null &
    dog=$!
    wait "$pid"; code=$?
    kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
    out="$(cat "$T/idle.log")" took=$((SECONDS - started))
}

FAKE_RUNNING="" idle 5
check "I01 nothing running: idle=true at once, in the log and \$GITHUB_OUTPUT, exit 0" \
    is "$code|$(tail -1 <<<"$out")|$(cat "$T/out")|$took" "0|idle=true|idle=true|0"
check "I01b ... asking pgrep for each writer by exact name, never a pattern" \
    is "$(paste -sd , "$PGREP_LOG")" \
    "-x xcodebuild,-x SWBBuildService,-x XCBBuildService,-x swift-driver,-x swift-frontend,-x clang,-x llvm-cas"

FAKE_RUNNING="SWBBuildService swift-frontend" FAKE_RUNNING_FOR=14 idle 30
check "I02 the build service and a compiler exit after a couple of polls: it waits for them, then idle=true" \
    is "$code|$(sed -n 1p <<<"$out")|$(cat "$T/out")" "0|Waiting up to 30 s for: SWBBuildService swift-frontend|idle=true"

FAKE_RUNNING="SWBBuildService" idle 2
check "I03 a writer that never exits: idle=false after the bound (not much later), exit 0" \
    is "$code|$(cat "$T/out")|$([[ $took -ge 2 && $took -le 6 ]] && echo bounded || echo "took $took s")" "0|idle=false|bounded"
check "I03b ... saying which one is left and that the cache is not saved" \
    grep -qx 'Still running after 2 s: SWBBuildService. The compilation cache is not saved this run.' <<<"$out"
FAKE_RUNNING="llvm-cas" GITHUB_ACTIONS=true idle 0
check "I03c ... as a warning annotation on GitHub Actions; a 0 s bound checks once" \
    is "$(sed -n 1p <<<"$out")|$(cat "$T/out")" \
    "::warning title=Compilation cache::Still running after 0 s: llvm-cas. The compilation cache is not saved this run.|idle=false"

FAKE_RUNNING="clangd sourcekit-lsp swift-frontend-helper Xcode" idle 2
check "I04 processes whose names only contain a writer's are not writers: idle=true at once" \
    is "$(cat "$T/out")|$took" "idle=true|0"

FAKE_PGREP_STATUS=3 idle 2
check "I05 pgrep failing cannot be read as 'none running': idle=false" is "$code|$(cat "$T/out")" "0|idle=false"
for bound in abc -1 1.5 " 3"; do
    FAKE_RUNNING="" idle "$bound"
    check "I06 a bound of '$bound' is not a number of seconds: idle=false, exit 0" is "$code|$(cat "$T/out")" "0|idle=false"
done
mkdir -p "$T/nopgrep" && ln -s "$(command -v sleep)" "$T/nopgrep/sleep"
: >"$T/out" && out="$(PATH="$T/nopgrep" GITHUB_OUTPUT="$T/out" "$BASH" "$IDLE" 2>&1)"; code=$?
check "I07 no pgrep at all: idle=false, exit 0" is "$code|$(cat "$T/out")" "0|idle=false"
check "I08 it kills nothing: no script runs kill, pkill or killall" \
    is "$(grep -nE '(^|[^[:alnum:]_-])(kill|pkill|killall)([^[:alnum:]_-]|$)' "$IDLE" "$REPORT" "$VALIDATE" | grep -v '^[^:]*:[0-9]*: *#' || true)" ""

finish
