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

finish() {
    printf '%s: %d passed, %d failed, %d skipped\n' "$(basename "$0")" "$ADV_PASS" "$ADV_FAIL" "$ADV_SKIP"
    [[ $ADV_FAIL -eq 0 ]]
}
