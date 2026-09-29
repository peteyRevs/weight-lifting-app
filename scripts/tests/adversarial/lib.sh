# shellcheck shell=bash
# Shared helpers for the F01 adversarial suites. Sourced, never executed.
# Each case prints "ok", "FAIL" or "skip"; a suite exits 1 when any case failed.
# Bash 3.2 compatible (the macOS /bin/bash), no network.

# shellcheck disable=SC2034 # ROOT is read by the suites that source this file
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ADV_PASS=0
ADV_FAIL=0
ADV_SKIP=0

ADV_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ledger-adv.XXXXXX")"
trap 'rm -rf "$ADV_TMP"' EXIT

pass() { ADV_PASS=$((ADV_PASS + 1)); printf 'ok    %s\n' "$1"; }
fail() {
    ADV_FAIL=$((ADV_FAIL + 1))
    printf 'FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/        /'; fi
}
skip() { ADV_SKIP=$((ADV_SKIP + 1)); printf 'skip  %s (%s)\n' "$1" "$2"; }

# check <name> <condition-command...>: pass when the command succeeds; its output
# is shown only on failure. The command runs in a subshell, so it sets no globals.
check() {
    local name="$1" detail; shift
    if detail="$("$@" 2>&1)"; then pass "$name"; else fail "$name" "$detail"; fi
}

# expect_exit <name> <expected> <actual> [detail]; expected "nonzero" matches any failure.
expect_exit() {
    local name="$1" expected="$2" actual="$3" detail="${4:-}"
    if [[ "$expected" == nonzero && "$actual" -ne 0 ]] || [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name" "expected exit $expected, got $actual${detail:+
$detail}"
    fi
}

# is <actual> <expected>: for `check`; prints both on a mismatch.
is() { [[ "$1" == "$2" ]] || { printf 'got:  %s\nwant: %s\n' "$1" "$2"; return 1; }; }

# fake_simctl <bin dir>: puts an xcrun there whose `simctl list devices [available] --json` and
# `simctl list pairs --json` print $SIMCTL_JSON (devices filtered like simctl), and whose `simctl
# unpair` chatters on stdout. Each call is appended to $XCRUN_LOG; $XCRUN_FAIL names a failing one.
# `simctl boot`, `bootstatus`, `shutdown` and `erase` succeed at once, except that:
#   XCRUN_BOOTED=1         boot answers as simctl does for a booted simulator (exit 149);
#   XCRUN_HANG=always      bootstatus never finishes (it sleeps until killed);
#   XCRUN_HANG=unerased    bootstatus finishes only once $XCRUN_LOG shows that simulator erased.
# `xcresulttool get test-results summary` reports $XCRUN_TEST_COUNT tests (default 1) for any bundle.
fake_simctl() {
    mkdir -p "$1"
    cat >"$1/xcrun" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${XCRUN_LOG:-/dev/null}"
case "$2 $3" in "${XCRUN_FAIL:-none}"*) echo "simctl: $2 $3 failed" >&2; exit 1 ;; esac
case "$1 $2 $3" in
    "simctl unpair "*) echo "Unpaired $3." ;;
    "simctl list pairs") jq '{pairs}' "$SIMCTL_JSON" ;;
    "simctl list devices")
        case " $* " in
            *" available "*) jq '{devices: (.devices | map_values(map(select(.isAvailable))))}' "$SIMCTL_JSON" ;;
            *) jq '{devices}' "$SIMCTL_JSON" ;;
        esac ;;
    "simctl boot "*)
        if [ -n "${XCRUN_BOOTED:-}" ]; then echo "Unable to boot device in current state: Booted" >&2; exit 149; fi ;;
    "simctl bootstatus "*)
        case "${XCRUN_HANG:-}" in
            always) exec sleep 60 ;;
            unerased) grep -qx "simctl erase $3" "${XCRUN_LOG:-/dev/null}" || exec sleep 60 ;;
        esac
        echo "Finished" ;;
    "simctl shutdown "* | "simctl erase "*) ;;
    "xcresulttool get test-results")
        [ "$4" = summary ] || { echo "fake xcrun: unexpected: $*" >&2; exit 64; }
        echo "{\"totalTestCount\": ${XCRUN_TEST_COUNT:-1}}" ;;
    *) echo "fake xcrun: unexpected: $*" >&2; exit 64 ;;
esac
SH
    chmod +x "$1/xcrun"
}
# SIMCTL_JSON, the runner CI uses (F32): the xcode-27 image's iOS and watchOS 27.0 simulators, as its
# README lists them (actions/runner-images images/macos/xcode-27-arm64-Readme.md, image 20260921.0210.1);
# the UDIDs are made up. Its pairs are UNKNOWN: the README lists none, and no run has logged them yet.
# The fixture assumes the pairs Xcode 27 made for the default set here when the 27.0 runtimes installed
# (2026-09-29): Series 12 (46mm) + iPhone 18 Pro Max, Series 12 (42mm) + iPhone Air, Ultra 4 (49mm) +
# iPhone 17. macos-26's pairs had the same shape. sim-destination.sh unpairs either way.
SIMCTL_JSON="$ROOT/scripts/tests/fixtures/simctl/xcode-27.json"
# SIMCTL_MACOS26, for the resolution cases the 27 image cannot show (same-named watches on three
# runtimes, an unavailable twin): the macos-26 runner's simulators and the pairs PR #5's first-run log
# names, plus iPhone 17 + Ultra 3 (49mm) on 26.5, which the first run's session logs confirm (their
# clones were paired); fake pair ids.
SIMCTL_MACOS26="$ROOT/scripts/tests/fixtures/simctl/macos-26.json"
export SIMCTL_JSON SIMCTL_MACOS26

finish() {
    printf '%s: %d passed, %d failed, %d skipped\n' "$(basename "$0")" "$ADV_PASS" "$ADV_FAIL" "$ADV_SKIP"
    [[ $ADV_FAIL -eq 0 ]]
}
