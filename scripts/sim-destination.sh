#!/usr/bin/env bash
# Prints an xcodebuild destination by UDID for one given by name and OS (an id= passes as is), and
# unpairs that simulator (F01 notes, "First CI run"). By name, xcodebuild also matches every iPhone
# paired with a watch of that name, whatever its OS; the macos-26 runner pairs same-named watches on
# two runtimes, so the watch by name was ambiguous (exit 70). By UDID it is not; unpairing is defence
# in depth.
#
#   scripts/sim-destination.sh [--fresh] <destination>
#
# --fresh (the nightly's watch legs; docs/ci-cd.md, "Nightly legs"): prints a new simulator instead, of the device
# type and runtime of the one named, never paired and never booted, for the caller to delete. The image pairs its
# Series 12 (46mm) with an iPhone 18 Pro Max, and after the unpair below xcodebuild still sent the watch's
# app-hosted tests to that phone (run 43170933804). Needs a destination by name and OS, on a runtime simctl lists
# as available with an architecture (else it fails, with a GitHub ::error:: naming the runtime).
set -euo pipefail

fresh=0
if [[ "${1:-}" == --fresh ]]; then fresh=1; shift; fi
destination="$1" platform="" name="" os="" udid=""
IFS=, read -ra fields <<<"$1"
for field in "${fields[@]}"; do
    case "$field" in
        id=*) udid="${field#*=}" ;; platform=*) platform="${field#*=}" ;;
        name=*) name="${field#*=}" ;; OS=*) os="${field#*=}" ;;
    esac
done
if [[ $fresh -eq 1 && -n "$udid" ]]; then echo "error: --fresh needs a destination by name and OS, not $1" >&2; exit 2; fi
if [[ -z "$udid" ]]; then
    runtime="com.apple.CoreSimulator.SimRuntime.${platform% Simulator}-${os//./-}"
    found="$(xcrun simctl list devices available --json | jq -r --arg name "$name" --arg runtime "$runtime" \
        'first(.devices[$runtime][]? | select(.name == $name) | "\(.udid) \(.deviceTypeIdentifier)") // empty')"
    read -r udid type <<<"$found" || true # an empty line: no such simulator, named below
    [[ -n "$udid" ]] || { echo "error: no available simulator matches '$1' (name and OS, or id)" >&2; exit 1; }
    if [[ $fresh -eq 1 ]]; then
        # Its runtime must be usable: available, with an architecture. On one runner (run 43250355937, watch
        # leg 2) the watchOS 27.0 devices were listed as available, yet xcodebuild logged "SimDevice native
        # architecture is nil" for them (a runtime of "(null)", no supported architectures), listed only the
        # 27.2 watches and exited 70 after the build. That runtime's devices cannot run tests, so a new one
        # cannot either. Fail here, naming it; the OS is pinned, so never fall back to another.
        runtimes="$(xcrun simctl list runtimes --json)"
        if ! jq -e --arg runtime "$runtime" \
            'any(.runtimes[]?; .identifier == $runtime and .isAvailable == true and (.supportedArchitectures // [] | length > 0))' \
            <<<"$runtimes" >/dev/null; then
            state="$(jq -c --arg runtime "$runtime" 'first(.runtimes[]? | select(.identifier == $runtime)
                | {isAvailable, availabilityError, supportedArchitectures}) // "not listed"' <<<"$runtimes")"
            echo "::error::sim-destination: the $platform runtime $os ($runtime) is not usable here: $state. Its" \
                "simulators cannot run tests; the OS is pinned, so no other is tried." >&2
            exit 1
        fi
        udid="$(xcrun simctl create "Ledger $name" "$type" "$runtime")"
        echo "sim-destination: created $udid, a new $name" >&2
        echo "platform=$platform,id=$udid"
        exit 0 # a new simulator has no pair to undo
    fi
    destination="platform=$platform,id=$udid"
fi
pairs="$(xcrun simctl list pairs --json |
    jq -r --arg udid "$udid" '.pairs | to_entries[] | select(.value.watch.udid == $udid or .value.phone.udid == $udid) | .key')"
for pair in $pairs; do echo "sim-destination: unpairing $udid" >&2; xcrun simctl unpair "$pair" >&2; done
echo "$destination"
