#!/usr/bin/env bash
# Boots the simulator of a destination by UDID (F01 notes, "Second CI run"). A never-booted simulator,
# as on every fresh runner, spends minutes on its first boot (data migration, then SpringBoard), and an
# app-hosted test cannot launch before it ends. So check.sh and the nightly start the boot before the
# build and wait for it after, then test on that simulator alone.
#
#   scripts/sim-boot.sh <destination>         start booting it and return at once (booted is fine)
#   scripts/sim-boot.sh --wait <destination>  wait until it has booted, at most $LEDGER_BOOT_TIMEOUT s
#                                             (240); if not, erase it and wait once more, or exit 1
set -euo pipefail

wait=0
if [[ "${1:-}" == --wait ]]; then wait=1; shift; fi
[[ ",${1:-}" =~ ,id=([^,]+) ]] || { echo "error: no id= in the destination '${1:-}'" >&2; exit 2; }
udid="${BASH_REMATCH[1]}"
timeout="${LEDGER_BOOT_TIMEOUT:-240}"

if [[ $wait -eq 0 ]]; then
    # Any other error is left to --wait: `bootstatus -b` boots it too, and an erase may cure it.
    err="$(xcrun simctl boot "$udid" 2>&1)" || [[ "$err" == *"current state: Boot"* ]] || echo "$err" >&2
    exit 0
fi

log="$(mktemp "${TMPDIR:-/tmp}/sim-boot.XXXXXX")"
trap 'rm -f "$log"' EXIT
booted() { # bootstatus -b boots it if needed, then waits; perl's alarm (kept across exec) ends it
    perl -e 'alarm shift; exec @ARGV or die' "$timeout" xcrun simctl bootstatus "$udid" -b >"$log" 2>&1 && return
    tail -n 4 "$log" >&2 # the last boot state it reported
    return 1
}
if booted; then echo "sim-boot: $udid booted (waited ${SECONDS}s)"; exit 0; fi
echo "sim-boot: $udid did not boot within ${timeout}s; erasing it and booting it once more" >&2
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true # erase needs it shut down; it may be already
xcrun simctl erase "$udid"
if booted; then echo "sim-boot: $udid booted after an erase (waited ${SECONDS}s)"; exit 0; fi
echo "error: simulator $udid did not boot within ${timeout}s, even after an erase" >&2
exit 1
