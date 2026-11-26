#!/usr/bin/env bash
# Waits, at most <seconds> (default 120), until nothing that writes Xcode's compilation cache is still
# running, so the cache's save does not tar a CAS mid-write (issue #153; docs/ci-cd.md, "Compilation
# cache"). The writers are xcodebuild, the build service it starts (SWBBuildService; XCBBuildService
# before Swift Build), the compilers and llvm-cas, which loads the CAS for ValidateCAS. xcodebuild has no
# command that stops the service, so this waits on those exact process names and kills nothing.
#
#   scripts/ci-cas-idle.sh [<seconds>]
#
# Prints idle=true when none is left, idle=false when one outlasts the wait or pgrep cannot tell, and
# appends the same line to $GITHUB_OUTPUT, where the save step reads it: a missed save costs the next run
# a colder build, a torn one every PR that restores it. Exits 0 either way.
set -uo pipefail

WRITERS=(xcodebuild SWBBuildService XCBBuildService swift-driver swift-frontend clang llvm-cas)

answer() { # <true|false> <message>
    if [[ $1 == false ]]; then
        printf '%s%s\n' "${GITHUB_ACTIONS:+::warning title=Compilation cache::}" "$2"
    else
        printf '%s\n' "$2"
    fi
    echo "idle=$1"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "idle=$1" >>"$GITHUB_OUTPUT"; fi
    exit 0
}

limit="${1:-120}"
if [[ ! "$limit" =~ ^[0-9]+$ ]]; then answer false "ci-cas-idle.sh: '$limit' is not a number of seconds; not saving"; fi
if ! command -v pgrep >/dev/null; then answer false "ci-cas-idle.sh: no pgrep, so the cache writers cannot be seen; not saving"; fi

# running: the writers' names still running, space-separated; status 2 when pgrep fails (exit 2 or more).
running() {
    local name found="" status
    for name in "${WRITERS[@]}"; do
        pgrep -x "$name" >/dev/null 2>&1
        status=$?
        case $status in
            0) found="$found $name" ;;
            1) ;;
            *) return 2 ;;
        esac
    done
    printf '%s' "${found# }"
}

waited=0
while true; do
    busy="$(running)" || answer false "ci-cas-idle.sh: pgrep failed, so the cache writers cannot be seen; not saving"
    if [[ -z "$busy" ]]; then answer true "No compilation cache writer is running (waited ${waited} s)."; fi
    if [[ $waited -ge $limit ]]; then
        answer false "Still running after ${limit} s: $busy. The compilation cache is not saved this run."
    fi
    if [[ $waited -eq 0 ]]; then echo "Waiting up to ${limit} s for: $busy"; fi
    sleep 1
    waited=$((waited + 1))
done
